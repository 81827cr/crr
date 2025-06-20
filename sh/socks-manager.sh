#!/bin/bash
set -euo pipefail

# ==============================
# Socks5 出口 管理脚本
# 交互式菜单：创建 / 查看 / 删除
# 基于 Dante (danted)，配置目录：/root/sh/socks-manager
# ==============================

# 根目录，可按需修改\ nBASE_DIR="/root/sh/socks-manager"
CONF_DIR="$BASE_DIR/conf.d"
MAIN_CONF="$BASE_DIR/danted.conf"
SERVICE_FILE="/etc/systemd/system/socks-manager.service"
SERVICE_NAME="socks-manager"

ensure_root() {
  [[ $EUID -ne 0 ]] && { echo "请以 root 用户运行此脚本" >&2; exit 1; }
}

check_danted() {
  if ! command -v danted &>/dev/null; then
    echo "[WARN] danted 未安装。"
    read -rp "是否现在安装 dante-server? (Y/n): " yn
    yn=${yn:-Y}
    if [[ "$yn" =~ ^[Yy] ]]; then
      apt update && apt install -y dante-server
      echo "[INFO] danted 已安装。"
    else
      echo "[ERROR] 未安装 danted，脚本无法继续。" >&2
      exit 1
    fi
  fi
}

install_dependencies() {
  mkdir -p "$CONF_DIR"

  cat > "$MAIN_CONF" <<EOF
logoutput: syslog
internal: 0.0.0.0 port = 0
internal: :: port = 0
external: *

method: none
user.privileged: root
user.notprivileged: nobody

## 引入所有子配置
include "$CONF_DIR/*.conf"
EOF

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Socks 出口 管理 (Dante) Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$(which danted) -f $MAIN_CONF
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}

# 校验端口
read_port() {
  local prompt="$1" port
  while :; do
    read -rp "$prompt" port
    if [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && (( port<=65535 )); then
      echo "$port"; return
    else
      echo "❌ 端口需在 1–65535 之间，请重新输入。" >&2
    fi
  done
}

# 创建新 Socks 出口
create_socks() {
  echo "--- 创建新的 Socks 出口 ---"
  read -rp "请输入监听地址 (IPv4 或 IPv6, 留空取消): " BIND_ADDR
  [[ -z "$BIND_ADDR" ]] && { echo "已取消。"; return; }

  SOCKS_PORT=$(read_port "请输入 Socks 监听端口: ")
  NODE_PORT=$(read_port "请输入节点服务本地端口: ")

  read -rp "请输入用户名 (留空则不启用认证): " AUTH_USER
  if [[ -n "$AUTH_USER" ]]; then
    read -rp "请输入该用户密码: " AUTH_PASS
    id "$AUTH_USER" &>/dev/null || useradd -M -s /usr/sbin/nologin "$AUTH_USER"
    echo "$AUTH_USER:$AUTH_PASS" | chpasswd
    METHOD="username"
  else
    METHOD="none"
  fi

  SAFE_ADDR=$(echo "$BIND_ADDR" | sed 's/[:\/]/_/g')
  CONF_FILE="$CONF_DIR/${SAFE_ADDR}_${SOCKS_PORT}.conf"

  if [[ -f "$CONF_FILE" ]]; then
    echo "⚠️ 配置已存在，跳过：$CONF_FILE" >&2
    return
  fi

  cat > "$CONF_FILE" <<EOF
# 自动生成：$BIND_ADDR:$SOCKS_PORT → 本机 $NODE_PORT
logoutput: syslog
internal: $BIND_ADDR port = $SOCKS_PORT
external: *

method: $METHOD
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
client pass {
    from: ::/0 to: ::/0
    log: connect disconnect error
}

pass {
    from: 0.0.0.0/0 to: 127.0.0.1 port = $NODE_PORT
    protocol: tcp udp
    method: $METHOD
    log: connect disconnect error
}
pass {
    from: ::/0 to: ::1 port = $NODE_PORT
    protocol: tcp udp
    method: $METHOD
    log: connect disconnect error
}
EOF

  echo "✅ 写入配置：$CONF_FILE"
  systemctl restart "$SERVICE_NAME"
  echo "👉 已启动：$BIND_ADDR:$SOCKS_PORT (method=$METHOD)"
}

# 列出配置
list_socks() {
  echo "--- 列出所有配置 ---"
  mapfile -t files < <(ls "$CONF_DIR"/*.conf 2>/dev/null || true)
  if (( ${#files[@]} == 0 )); then echo "（无任何配置）"; return; fi
  for i in "${!files[@]}"; do
    printf "%2d) %s\n" $((i+1)) "$(basename "${files[i]}")"
  done
}

# 删除配置
delete_socks() {
  echo "--- 删除配置 ---"
  mapfile -t files < <(ls "$CONF_DIR"/*.conf 2>/dev/null || true)
  if (( ${#files[@]} == 0 )); then echo "（无可删除配置）"; return; fi
  list_socks
  read -rp "请输入要删除的序号 (留空取消): " idx
  [[ -z "$idx" ]] && { echo "已取消。"; return; }
  if ! [[ "$idx" =~ ^[1-9][0-9]*$ ]] || (( idx<1 || idx>${#files[@]} )); then echo "❌ 无效序号" >&2; return; fi
  rm -f "${files[idx-1]}"
  echo "✔️ 已删除 $(basename "${files[idx-1]}")"
  systemctl restart "$SERVICE_NAME"
}

# 交互式主菜单
main() {
  ensure_root
  check_danted
  install_dependencies

  while true; do
    echo
    echo "======= Socks 管理菜单 ======="
    echo "1) 创建新的 Socks 出口"
    echo "2) 查看所有配置"
    echo "3) 删除某个配置"
    echo "0) 退出"
    echo "==============================="
    read -rp "请输入选项: " choice
    case "$choice" in
      1) create_socks ;; 2) list_socks ;; 3) delete_socks ;; 0) echo "退出"; exit 0 ;; * ) echo "❌ 无效选择" ;;
    esac
  done
}

main
