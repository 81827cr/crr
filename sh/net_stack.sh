#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# IPv4/IPv6 Stack Detector + Network Priority Switcher
# Extracted from your script (with safer input/commands)
# ============================================================

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="${CONFIG_FILE:-/opt/xray/config.json}"
GAI_CONF="${GAI_CONF:-/etc/gai.conf}"

# This line is commonly used to prefer IPv4 on glibc systems
GAI_V4_LINE="precedence ::ffff:0:0/96  100"

# ---------- Basic logging ----------
log_info(){ echo -e "${BLUE}[INFO]${PLAIN} $*"; }
log_ok(){   echo -e "${GREEN}[OK]${PLAIN}  $*"; }
log_warn(){ echo -e "${YELLOW}[WARN]${PLAIN} $*"; }
log_err(){  echo -e "${RED}[ERR]${PLAIN}  $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_err "请使用 sudo/root 运行。"
    exit 1
  fi
}

# ---------- 1) Detect IPv4/IPv6 connectivity ----------
detect_net_stack() {
  HAS_V4=false
  HAS_V6=false
  CURL_OPT=""
  NET_TYPE="Unknown"
  DOMAIN_STRATEGY="IPIfNonMatch"

  # Use short timeouts, fail fast
  if curl -fsS4m 2 https://1.1.1.1 >/dev/null 2>&1; then HAS_V4=true; fi
  if curl -fsS6m 2 https://2606:4700:4700::1111 >/dev/null 2>&1; then HAS_V6=true; fi

  if $HAS_V4 && $HAS_V6; then
    NET_TYPE="Dual-Stack (双栈)"
    CURL_OPT="-4"                 # keep consistent with original behavior
    DOMAIN_STRATEGY="IPIfNonMatch"
  elif $HAS_V4; then
    NET_TYPE="IPv4 Only"
    CURL_OPT="-4"
    DOMAIN_STRATEGY="UseIPv4"
  elif $HAS_V6; then
    NET_TYPE="IPv6 Only"
    CURL_OPT="-6"
    DOMAIN_STRATEGY="UseIPv6"
  else
    log_err "无法连接互联网（IPv4/IPv6 都不可用），请检查网络。"
    exit 1
  fi
}

print_detect_result() {
  echo -e "${BLUE}===================================================${PLAIN}"
  echo -e "${BLUE}          网络栈检测 (IPv4/IPv6 Check)            ${PLAIN}"
  echo -e "${BLUE}===================================================${PLAIN}"
  echo -e "  IPv4 可用: $($HAS_V4 && echo -e "${GREEN}YES${PLAIN}" || echo -e "${RED}NO${PLAIN}")"
  echo -e "  IPv6 可用: $($HAS_V6 && echo -e "${GREEN}YES${PLAIN}" || echo -e "${RED}NO${PLAIN}")"
  echo -e "  结果类型: ${YELLOW}${NET_TYPE}${PLAIN}"
  echo -e "  CURL_OPT: ${YELLOW}${CURL_OPT}${PLAIN}"
  echo -e "  建议 Xray domainStrategy: ${YELLOW}${DOMAIN_STRATEGY}${PLAIN}"
  echo -e "${BLUE}===================================================${PLAIN}"
}

# ---------- 2) System-level preference (glibc gai.conf) ----------
set_system_prio() {
  local mode="$1" # v4 or v6
  [[ -f "$GAI_CONF" ]] || touch "$GAI_CONF"

  if [[ "$mode" == "v4" ]]; then
    # Add v4 precedence line if not exists
    if ! grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100([[:space:]]*)$' "$GAI_CONF" 2>/dev/null; then
      echo "$GAI_V4_LINE" >> "$GAI_CONF"
    fi
  else
    # Remove v4 precedence line to prefer v6
    sed -i "\|^${GAI_V4_LINE}$|d" "$GAI_CONF" 2>/dev/null || true
  fi
}

# ---------- 3) Xray domainStrategy switch ----------
require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    log_err "缺少 jq，请先安装：apt-get update && apt-get install -y jq"
    exit 1
  fi
}

require_xray_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_err "找不到 Xray 配置文件：$CONFIG_FILE"
    log_warn "你可以导出 CONFIG_FILE=/path/to/config.json 再运行"
    exit 1
  fi
}

apply_xray_domain_strategy() {
  local strategy="$1" # IPIfNonMatch, UseIPv4, UseIPv6
  require_jq
  require_xray_config

  # Write to temp then move (atomic-ish)
  jq --arg s "$strategy" '.routing.domainStrategy = $s' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

  if systemctl is-enabled xray >/dev/null 2>&1 || systemctl status xray >/dev/null 2>&1; then
    systemctl restart xray || true
  fi
}

get_current_status() {
  require_jq
  require_xray_config

  CURRENT_STRATEGY="$(jq -r '.routing.domainStrategy // "Unknown"' "$CONFIG_FILE")"

  if grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100([[:space:]]*)$' "$GAI_CONF" 2>/dev/null; then
    SYS_PRIO="IPv4 优先"
  else
    SYS_PRIO="IPv6 优先"
  fi

  # UI markers
  MARK_1=" "; MARK_2=" "; MARK_3=" "; MARK_4=" "
  if [[ "$CURRENT_STRATEGY" == "UseIPv4" ]]; then
    STATUS_TEXT="${YELLOW}仅 IPv4 (IPv4 Only)${PLAIN}"
    MARK_3="${GREEN}●${PLAIN}"
  elif [[ "$CURRENT_STRATEGY" == "UseIPv6" ]]; then
    STATUS_TEXT="${YELLOW}仅 IPv6 (IPv6 Only)${PLAIN}"
    MARK_4="${GREEN}●${PLAIN}"
  else
    # Dual-stack behavior depends on gai.conf preference
    if [[ "$SYS_PRIO" == "IPv4 优先" ]]; then
      STATUS_TEXT="${GREEN}双栈 - IPv4 优先${PLAIN}"
      MARK_1="${GREEN}●${PLAIN}"
    else
      STATUS_TEXT="${GREEN}双栈 - IPv6 优先${PLAIN}"
      MARK_2="${GREEN}●${PLAIN}"
    fi
  fi
}

apply_strategy() {
  local sys_prio="$1"      # v4 or v6
  local xray_strategy="$2" # IPIfNonMatch, UseIPv4, UseIPv6
  local desc="$3"

  echo -e "${BLUE}正在配置: ${desc}...${PLAIN}"
  set_system_prio "$sys_prio"
  apply_xray_domain_strategy "$xray_strategy"
  log_ok "设置成功：${desc}"
  read -n 1 -s -r -p "按任意键继续..."
}

network_menu() {
  while true; do
    get_current_status
    clear
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          网络优先级切换 (Network Priority)       ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "配置文件: ${GRAY}${CONFIG_FILE}${PLAIN}"
    echo -e "当前状态: ${STATUS_TEXT}"
    echo -e "---------------------------------------------------"
    echo -e "  ${MARK_1} 1. IPv4 优先 (推荐)   ${GRAY}- 双栈环境，v4 流量优先${PLAIN}"
    echo -e "  ${MARK_2} 2. IPv6 优先          ${GRAY}- 双栈环境，v6 流量优先${PLAIN}"
    echo -e "  ${MARK_3} 3. 仅 IPv4            ${GRAY}- 强制 Xray 只用 IPv4${PLAIN}"
    echo -e "  ${MARK_4} 4. 仅 IPv6            ${GRAY}- 强制 Xray 只用 IPv6${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e "  9. 运行一次网络栈检测 (v4/v6 可用性 + 建议策略)"
    echo -e "  0. 退出 (Exit)"
    echo -e ""
    read -r -p "请输入选项 [0-4,9]: " choice

    case "$choice" in
      1) apply_strategy "v4" "IPIfNonMatch" "IPv4 优先 (双栈)" ;;
      2) apply_strategy "v6" "IPIfNonMatch" "IPv6 优先 (双栈)" ;;
      3) apply_strategy "v4" "UseIPv4"      "仅 IPv4 (Disable v6)" ;;
      4) apply_strategy "v6" "UseIPv6"      "仅 IPv6 (Disable v4)" ;;
      9)
        clear
        detect_net_stack
        print_detect_result
        echo ""
        read -n 1 -s -r -p "按任意键继续..."
        ;;
      0) exit 0 ;;
      *) log_warn "输入无效"; sleep 1 ;;
    esac
  done
}

main() {
  require_root
  # If you only want detection without xray config changes:
  # detect_net_stack; print_detect_result; exit 0

  # Full interactive menu:
  network_menu
}

main "$@"

