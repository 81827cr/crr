#!/usr/bin/env bash
set -euo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "请用 root 运行"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export NEEDRESTART_MODE=a

TAG="IPWL"
DEFAULT_PROTO="tcp"

V4_IN="IPWL-IN"
V4_DU="IPWL-DU"
V6_IN="IPWL6-IN"
V6_DU="IPWL6-DU"

CONF_DIR="/etc/ipwl"
CONF_FILE="${CONF_DIR}/policies.conf"
SERVICE_FILE="/etc/systemd/system/ipwl-apply.service"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"

have(){ command -v "$1" >/dev/null 2>&1; }
log(){ echo "[ipwl] $*"; }

ensure_conf(){
  mkdir -p "$CONF_DIR"
  touch "$CONF_FILE"
  chmod 600 "$CONF_FILE"
}

apt_install(){
  dpkg --configure -a >/dev/null 2>&1 || true
  local n=0
  until apt-get update -y; do n=$((n+1)); [[ "$n" -ge 3 ]] && return 1; sleep 2; done
  n=0
  until apt-get install -y -q -o Dpkg::Options::=--force-confnew -o Dpkg::Options::=--force-confdef "$@"; do
    n=$((n+1)); [[ "$n" -ge 3 ]] && return 1; sleep 2
  done
}

ensure_deps_and_persist(){
  log "检查依赖与持久化组件..."

  if ! have iptables; then
    log "安装 iptables..."
    apt_install iptables
  fi

  if have debconf-set-selections; then
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections || true
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections || true
  fi

  if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
    log "安装 iptables-persistent（提供 netfilter-persistent）..."
    apt_install iptables-persistent
  fi

  systemctl enable netfilter-persistent >/dev/null 2>&1 || true
  systemctl start  netfilter-persistent >/dev/null 2>&1 || true

  # ip6tables 可能不存在（极简系统）
  if ! have ip6tables; then
    log "提示：未检测到 ip6tables，IPv6 不会被限制（可安装 iptables 套件或禁用IPv6避免绕过）"
  fi

  log "持久化组件 OK"
}

save_rules(){
  if have netfilter-persistent; then
    netfilter-persistent save >/dev/null 2>&1 || true
  else
    mkdir -p /etc/iptables || true
    have iptables-save && iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    have ip6tables-save && ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  fi
}

chain_exists(){ local tool="$1" chain="$2"; "$tool" -S "$chain" >/dev/null 2>&1; }
rule_exists(){ local tool="$1"; shift; "$tool" -C "$@" >/dev/null 2>&1; }
ensure_chain(){ local tool="$1" chain="$2"; "$tool" -N "$chain" 2>/dev/null || true; }
flush_chain(){
  local tool="$1" ch="$2"
  "$tool" -F "$ch" >/dev/null 2>&1 || true
}

ensure_jump_first(){
  local tool="$1" from="$2" to="$3"
  chain_exists "$tool" "$from" || return 0
  rule_exists "$tool" "$from" -j "$to" || "$tool" -I "$from" 1 -j "$to"
}

ensure_anchor_basics(){
  local tool="$1" anchor="$2"
  rule_exists "$tool" "$anchor" -i lo -j RETURN || "$tool" -I "$anchor" 1 -i lo -j RETURN
  rule_exists "$tool" "$anchor" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN \
    || "$tool" -I "$anchor" 2 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
}

allow_docker_internal(){
  local tool="$1" anchor="$2"

  # 只放行 docker bridge 的转发流量（容器互通/bridge 网络）
  rule_exists "$tool" "$anchor" -i docker0 -j RETURN || "$tool" -A "$anchor" -i docker0 -j RETURN
  rule_exists "$tool" "$anchor" -o docker0 -j RETURN || "$tool" -A "$anchor" -o docker0 -j RETURN

  # 覆盖 br-xxxx 的自定义 bridge 网络（容错：没有 physdev 模块也不报错）
  "$tool" -C "$anchor" -m physdev --physdev-is-bridged -j RETURN >/dev/null 2>&1 \
    || "$tool" -A "$anchor" -m physdev --physdev-is-bridged -j RETURN 2>/dev/null || true
}

ensure_docker_user_v6_hook(){
  ip6tables -N DOCKER-USER 2>/dev/null || true
  rule_exists ip6tables DOCKER-USER -j RETURN || ip6tables -A DOCKER-USER -j RETURN
  rule_exists ip6tables FORWARD -j DOCKER-USER || ip6tables -I FORWARD 1 -j DOCKER-USER
}

init_firewall(){
  log "初始化锚链..."

  ensure_chain iptables "$V4_IN"
  flush_chain iptables "$V4_IN"
  ensure_jump_first iptables INPUT "$V4_IN"
  ensure_anchor_basics iptables "$V4_IN"

  ensure_chain iptables "$V4_DU"
  flush_chain iptables "$V4_DU"
  if chain_exists iptables DOCKER-USER; then
    ensure_jump_first iptables DOCKER-USER "$V4_DU"
    ensure_anchor_basics iptables "$V4_DU"
    allow_docker_internal iptables "$V4_DU"
  fi

  if have ip6tables; then
    ensure_chain ip6tables "$V6_IN"
    ensure_jump_first ip6tables INPUT "$V6_IN"
    ensure_anchor_basics ip6tables "$V6_IN"

    ensure_docker_user_v6_hook
    ensure_chain ip6tables "$V6_DU"
    ensure_jump_first ip6tables DOCKER-USER "$V6_DU"
    ensure_anchor_basics ip6tables "$V6_DU"
  fi

  log "锚链 OK"
}

normalize_csv(){
  local s="${1:-}"
  s="$(echo "$s" | tr -d ' ' | sed 's/^,*//;s/,*$//')"
  echo "$s"
}

policy_chain_name(){
  local proto="$1" port="$2"
  echo "${TAG}-P-${port}-${proto^^}"
}

# ✅ 修复点：不要 -I 10，直接 append，避免 index too big
ensure_policy_jump(){
  local tool="$1" anchor="$2" proto="$3" port="$4" pchain="$5"
  chain_exists "$tool" "$anchor" || return 0
  ensure_chain "$tool" "$pchain"
  rule_exists "$tool" "$anchor" -p "$proto" -m "$proto" --dport "$port" -j "$pchain" \
    || "$tool" -A "$anchor" -p "$proto" -m "$proto" --dport "$port" -j "$pchain"
}

rebuild_policy_chain(){
  local tool="$1" pchain="$2" proto="$3" port="$4" csv="$5"
  ensure_chain "$tool" "$pchain"
  "$tool" -F "$pchain" >/dev/null 2>&1 || true

  if [[ -n "${csv:-}" && "${csv:-}" != "-" ]]; then
    IFS=',' read -r -a ips <<< "$csv"
    local ip
    for ip in "${ips[@]}"; do
      [[ -z "$ip" ]] && continue
      "$tool" -A "$pchain" -s "$ip" -p "$proto" -m "$proto" --dport "$port" -j RETURN
    done
  fi

  # 端口最终拦截：不是白名单的一律 DROP
  "$tool" -A "$pchain" -p "$proto" -m "$proto" --dport "$port" -j DROP
}

parse_policy_line(){
  local line="$1"
  line="${line%%#*}"
  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$line" ]] && return 1

  local proto port
  proto="$(echo "$line" | awk '{print $1}')"
  port="$(echo "$line" | awk '{print $2}')"
  [[ "$proto" == "tcp" || "$proto" == "udp" ]] || return 1
  [[ "$port" =~ ^[0-9]+$ ]] || return 1

  local rest v4 v6
  rest="$(echo "$line" | cut -d' ' -f3- 2>/dev/null || true)"
  v4=""; v6=""
  [[ "$rest" == *"v4="* ]] && v4="$(echo "$rest" | sed -n 's/.*v4=\([^ ]*\).*/\1/p')"
  [[ "$rest" == *"v6="* ]] && v6="$(echo "$rest" | sed -n 's/.*v6=\([^ ]*\).*/\1/p')"
  v4="$(normalize_csv "${v4:-}")"; v6="$(normalize_csv "${v6:-}")"
  [[ -z "$v4" ]] && v4="-"
  [[ -z "$v6" ]] && v6="-"
  echo "$proto" "$port" "$v4" "$v6"
}

apply_one(){
  local proto="$1" port="$2" v4csv="$3" v6csv="$4"
  local pchain; pchain="$(policy_chain_name "$proto" "$port")"

  ensure_policy_jump iptables "$V4_IN" "$proto" "$port" "$pchain"
  ensure_policy_jump iptables "$V4_DU" "$proto" "$port" "$pchain"
  rebuild_policy_chain iptables "$pchain" "$proto" "$port" "${v4csv:-"-"}"

  if have ip6tables; then
    local pchain6="${pchain}6"
    ensure_policy_jump ip6tables "$V6_IN" "$proto" "$port" "$pchain6"
    ensure_policy_jump ip6tables "$V6_DU" "$proto" "$port" "$pchain6"
    rebuild_policy_chain ip6tables "$pchain6" "$proto" "$port" "${v6csv:-"-"}"
  fi
}

ensure_service_auto(){
  # 你要“脚本运行就自动装开机自启”：这里做“创建+enable”，不 start，避免卡住
  if ! have systemctl; then return 0; fi

  if [[ ! -f "$SERVICE_FILE" ]]; then
    cat > "$SERVICE_FILE" <<SVC
[Unit]
Description=Apply IPWL policies after boot (after docker)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH} apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  systemctl enable ipwl-apply.service >/dev/null 2>&1 || true
}

apply_all(){
  ensure_deps_and_persist
  ensure_conf
  init_firewall

  local line parsed proto port v4 v6
  while IFS= read -r line; do
    parsed="$(parse_policy_line "$line" || true)"
    [[ -z "$parsed" ]] && continue
    proto="$(echo "$parsed" | awk '{print $1}')"
    port="$(echo "$parsed" | awk '{print $2}')"
    v4="$(echo "$parsed" | awk '{print $3}')"
    v6="$(echo "$parsed" | awk '{print $4}')"
    apply_one "$proto" "$port" "$v4" "$v6"
  done < "$CONF_FILE"

  save_rules
  ensure_service_auto
  log "apply 完成（已持久化 + 已确保开机自启）"
}

list_policies(){
  ensure_conf
  local idx=0 any=0 line parsed proto port v4 v6
  echo "当前策略："
  echo "--------------------------------------------------------------------------------"
  while IFS= read -r line; do
    parsed="$(parse_policy_line "$line" || true)"
    [[ -z "$parsed" ]] && continue
    proto="$(echo "$parsed" | awk '{print $1}')"
    port="$(echo "$parsed" | awk '{print $2}')"
    v4="$(echo "$parsed" | awk '{print $3}')"
    v6="$(echo "$parsed" | awk '{print $4}')"
    idx=$((idx+1)); any=1
    printf "[%d] proto=%s port=%s allow_v4=%s allow_v6=%s\n" "$idx" "$proto" "$port" "$v4" "$v6"
  done < "$CONF_FILE"
  [[ "$any" -eq 1 ]] || echo "（无策略）"
  echo "--------------------------------------------------------------------------------"
}

split_ips(){
  local -n all=$1; local -n v4=$2; local -n v6=$3
  v4=(); v6=()
  local ip
  for ip in "${all[@]}"; do
    [[ -z "$ip" ]] && continue
    if [[ "$ip" == *:* ]]; then v6+=("$ip"); else v4+=("$ip"); fi
  done
}

upsert_policy(){
  local proto="$1" port="$2"; shift 2
  local ips=("$@")
  ensure_conf

  local v4_ips=() v6_ips=()
  split_ips ips v4_ips v6_ips

  local v4csv v6csv
  v4csv="$(IFS=,; echo "${v4_ips[*]:-}")"; v4csv="$(normalize_csv "$v4csv")"; [[ -z "$v4csv" ]] && v4csv="-"
  v6csv="$(IFS=,; echo "${v6_ips[*]:-}")"; v6csv="$(normalize_csv "$v6csv")"; [[ -z "$v6csv" ]] && v6csv="-"

  if grep -qE "^${proto}[[:space:]]+${port}[[:space:]]" "$CONF_FILE"; then
    local tmp; tmp="$(mktemp)"
    awk -v p="$proto" -v pt="$port" -v nv4="$v4csv" -v nv6="$v6csv" '
      BEGIN{OFS=" "}
      $1==p && $2==pt {print p, pt, "v4="nv4, "v6="nv6; next}
      {print}
    ' "$CONF_FILE" > "$tmp"
    mv "$tmp" "$CONF_FILE"
  else
    echo "$proto $port v4=$v4csv v6=$v6csv" >> "$CONF_FILE"
  fi

  apply_all
}

delete_policy_idx(){
  ensure_conf
  local sel="$1"
  [[ "$sel" =~ ^[0-9]+$ ]] || { echo "输入无效"; return 1; }

  local tmp; tmp="$(mktemp)"
  local idx=0 found=0 line parsed
  while IFS= read -r line; do
    parsed="$(parse_policy_line "$line" || true)"
    if [[ -z "$parsed" ]]; then
      echo "$line" >> "$tmp"
      continue
    fi
    idx=$((idx+1))
    if [[ "$idx" -eq "$sel" ]]; then found=1; continue; fi
    echo "$line" >> "$tmp"
  done < "$CONF_FILE"

  [[ "$found" -eq 1 ]] || { rm -f "$tmp"; echo "编号不存在"; return 1; }
  mv "$tmp" "$CONF_FILE"
  apply_all
}

flush_del_chain(){
  local tool="$1" ch="$2"
  chain_exists "$tool" "$ch" || return 0
  "$tool" -F "$ch" 2>/dev/null || true
  "$tool" -X "$ch" 2>/dev/null || true
}

clear_all(){
  ensure_conf
  : > "$CONF_FILE"

  while rule_exists iptables INPUT -j "$V4_IN"; do iptables -D INPUT -j "$V4_IN" || break; done
  if chain_exists iptables DOCKER-USER; then
    while rule_exists iptables DOCKER-USER -j "$V4_DU"; do iptables -D DOCKER-USER -j "$V4_DU" || break; done
  fi
  iptables -S | awk '/^-N IPWL-P-/{print $2}' | while read -r ch; do flush_del_chain iptables "$ch"; done
  flush_del_chain iptables "$V4_IN"
  flush_del_chain iptables "$V4_DU"

  if have ip6tables; then
    while rule_exists ip6tables INPUT -j "$V6_IN"; do ip6tables -D INPUT -j "$V6_IN" || break; done
    if chain_exists ip6tables DOCKER-USER; then
      while rule_exists ip6tables DOCKER-USER -j "$V6_DU"; do ip6tables -D DOCKER-USER -j "$V6_DU" || break; done
    fi
    ip6tables -S | awk '/^-N IPWL-P-/{print $2}' | while read -r ch; do flush_del_chain ip6tables "$ch"; done
    flush_del_chain ip6tables "$V6_IN"
    flush_del_chain ip6tables "$V6_DU"
  fi

  save_rules
  log "已清空全部策略（并持久化）"
}

debug_hits(){
  echo "=== IPv4 anchors ==="
  iptables -nvL IPWL-IN --line-numbers || true
  iptables -nvL IPWL-DU --line-numbers || true
  echo "=== DOCKER-USER (v4) ==="
  iptables -nvL DOCKER-USER --line-numbers 2>/dev/null || true
  echo
  if have ip6tables; then
    echo "=== IPv6 anchors ==="
    ip6tables -nvL IPWL6-IN --line-numbers || true
    ip6tables -nvL IPWL6-DU --line-numbers || true
    echo "=== DOCKER-USER (v6) ==="
    ip6tables -nvL DOCKER-USER --line-numbers 2>/dev/null || true
  else
    echo "NO ip6tables, IPv6 not filtered."
  fi
}

menu_add(){
  read -r -p "协议 tcp/udp（默认 tcp）: " proto
  proto="${proto:-$DEFAULT_PROTO}"
  [[ "$proto" == "tcp" || "$proto" == "udp" ]] || { echo "只支持 tcp/udp"; return 1; }

  # ✅ 支持多个端口：空格分隔
  read -r -p "端口（可输入多个，空格分隔）: " portline
  read -r -a ports <<< "$portline"
  [[ "${#ports[@]}" -gt 0 ]] || { echo "未输入端口"; return 1; }

  # 校验端口并去重（不影响单端口）
  local uniq_ports=() seen=" "
  local p
  for p in "${ports[@]}"; do
    [[ "$p" =~ ^[0-9]+$ ]] || { echo "端口必须是数字：$p"; return 1; }
    [[ "$p" -ge 1 && "$p" -le 65535 ]] || { echo "端口范围 1-65535：$p"; return 1; }
    if [[ "$seen" != *" $p "* ]]; then
      uniq_ports+=("$p")
      seen+=" $p "
    fi
  done

  echo "允许IP（空格分隔，可混IPv4/IPv6）:"
  read -r -p "IP列表: " ipline
  read -r -a ips <<< "$ipline"
  [[ "${#ips[@]}" -gt 0 ]] || { echo "未输入 IP"; return 1; }

  # ✅ 对每个端口执行 upsert：重复端口即更新
  for p in "${uniq_ports[@]}"; do
    upsert_policy "$proto" "$p" "${ips[@]}"
  done
}

menu_del(){
  list_policies
  read -r -p "删除编号(或q取消): " sel
  [[ "${sel,,}" == "q" ]] && return 0
  delete_policy_idx "$sel"
}

main_menu(){
  ensure_service_auto || true
  while true; do
    echo
    echo "========= IPWL 端口白名单（重启自动恢复）========="
    echo "1) 查询策略"
    echo "2) 新增/更新策略"
    echo "3) 删除策略"
    echo "4) 一键清空全部策略"
    echo "5) 立即 apply（重建规则并持久化）"
    echo "6) Debug：查看命中计数（排查为何未拦截）"
    echo "0) 退出"
    read -r -p "选择: " c
    case "$c" in
      1) list_policies ;;
      2) menu_add ;;
      3) menu_del ;;
      4) read -r -p "确认清空？(yes/no): " yn; [[ "${yn,,}" == "yes" ]] && clear_all ;;
      5) apply_all ;;
      6) debug_hits ;;
      0) exit 0 ;;
      *) echo "无效选择" ;;
    esac
  done
}

ensure_conf
ensure_service_auto || true

case "${1:-}" in
  apply) apply_all ;;
  list) list_policies ;;
  clear) clear_all ;;
  debug) debug_hits ;;
  "" ) main_menu ;;
  * ) echo "用法: $0 [apply|list|clear|debug]"; exit 1 ;;
esac
