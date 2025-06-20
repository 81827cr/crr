#!/bin/bash
set -euo pipefail

# ======================
# Socks 出口 管理脚本
# 支持：创建 / 列表 / 删除 Socks5 出口配置
# 基于 Dante (danted)，配置目录放在 /root/sh/socks-manager
# ======================

# 根目录，可按需修改
BASE_DIR="/root/sh/socks-manager"
CONF_DIR="$BASE_DIR/conf.d"
MAIN_CONF="$BASE_DIR/danted.conf"
SERVICE_FILE="/etc/systemd/system/socks-manager.service"
SERVICE_NAME="socks-manager"

ensure_root() {
  [[ $EUID -ne 0 ]] && { echo "请以 root 用户运行此脚本" >&2; exit 1; }
}

install_dependencies() {
  # 安装 Dante 服务
  if ! command -v danted &>/dev/null; then
    echo ">>> 安装 dante-server..."
    apt update && apt install -y dante-server
  fi

  # 创建基础目录
  mkdir -p "$CONF_DIR"

  # 写主配置文件
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

  # 写自定义 systemd 单元，指向 MAIN_CONF
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

  # 启用/重载/启动
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}

# 读取并校验端口
read_port() {
  local prompt="$1" port
  while :; do
    read -rp "$prompt" port
    if [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && (( port<=65535 )); then
      echo "$port"
      return
    else
      echo "❌ 端口需在 1–65535 之间，请重新输入。" >&2
    fi
  done
}

# 功能 1：创建新 Socks 出口
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

  # 生成文件名，替换特殊字符
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

# 功能 2：列出所有配置
list_socks() {
  echo "--- 列出所有配置 ---"
  mapfile -t files < <(ls "$CONF_DIR"/*.conf 2>/dev/null || true)
  if (( ${#files[@]} == 0 )); then
    echo "（无任何配置）"
    return
  fi
  for i in "${!files[@]}"; do
    printf "%2d) %s\n" $((i+1)) "$(basename "${files[i]}")"
  done
}

# 功能 2：删除指定配置
delete_socks() {
  echo "--- 删除配置 ---"
  mapfile -t files < <(ls "$CONF_DIR"/*.conf 2>/dev/null || true)
  if (( ${#files[@]} == 0 )); then
    echo "（无可删除配置）"
    return
  fi
  list_socks
  read -rp "请输入要删除的序号 (留空取消): " idx
  [[ -z "$idx" ]] && { echo "已取消。"; return; }
  if ! [[ "$idx" =~ ^[1-9][0-9]*$ ]] || (( idx<1 || idx>${#files[@]} )); then
    echo "❌ 无效序号" >&2
    return
  fi
  rm -f "${files[idx-1]}"
  echo "✔️ 已删除 $(basename "${files[idx-1]}")"
  systemctl restart "$SERVICE_NAME"
}

show_help() {
  cat <<EOF
Usage: $0 [选项]
  -i, --install    创建新的 Socks 出口
  -l, --list       列出所有配置
  -d, --delete     删除指定配置
  -h, --help       显示帮助
EOF
}

main() {
  ensure_root
  install_dependencies

  [[ $# -eq 0 ]] && { show_help; exit 0; }

  case "$1" in
    -i|--install) create_socks ;;
    -l|--list)    list_socks   ;;
    -d|--delete)  delete_socks ;;
    -h|--help)    show_help    ;;
    *) echo "❌ 未知选项：$1" >&2; show_help; exit 1 ;;
  esac
}

main "$@"
