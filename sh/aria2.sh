#!/usr/bin/env bash
# one-click-aria2-install.sh — 最终版（含下载目录存在为文件的自动备份处理）
# 用法: sudo bash one-click-aria2-install.sh

set -euo pipefail

CONF_DIR="/etc/aria2"
CONF_FILE="$CONF_DIR/aria2.conf"
SERVICE_FILE="/etc/systemd/system/aria2.service"

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "请以 root 或使用 sudo 运行此脚本。"
    exit 1
  fi
}

gen_rand_key() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c16 || echo "$(date +%s)"
}

get_run_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    echo "$SUDO_USER"
  else
    id -un
  fi
}

backup_if_exists() {
  local f="$1"
  if [ -e "$f" ]; then
    cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" || true
  fi
}

install_aria2() {
  local RUN_USER HOME_DIR SESSION_DIR DOWNLOAD_DIR INPUT_PORT INPUT_KEY
  RUN_USER=$(get_run_user)
  HOME_DIR=$(eval echo "~${RUN_USER}" 2>/dev/null || echo "/root")
  SESSION_DIR="/opt/aria2-session"

  echo "将以用户: ${RUN_USER} 安装 aria2，会话目录: ${SESSION_DIR}"

  apt-get update
  apt-get install -y aria2 || { echo "aria2 安装失败，请检查 apt 源"; exit 1; }

  mkdir -p "$CONF_DIR"
  backup_if_exists "$CONF_FILE"
  backup_if_exists "$SERVICE_FILE"

  # 修复 session 被误建为目录的情况
  if [ -d "${SESSION_DIR}/aria2.session" ]; then
    echo "注意: ${SESSION_DIR}/aria2.session 是目录 -> 备份并替换为文件"
    mv "${SESSION_DIR}/aria2.session" "${SESSION_DIR}/aria2.session.dir.bak.$(date +%s)" || true
  fi
  mkdir -p "$SESSION_DIR"
  chown -R "${RUN_USER}:" "$SESSION_DIR" 2>/dev/null || chown -R "${RUN_USER}:${RUN_USER}" "$SESSION_DIR" || true
  chmod 700 "$SESSION_DIR"
  if [ ! -f "${SESSION_DIR}/aria2.session" ]; then
    touch "${SESSION_DIR}/aria2.session"
    chown "${RUN_USER}:" "${SESSION_DIR}/aria2.session" 2>/dev/null || chown "${RUN_USER}:${RUN_USER}" "${SESSION_DIR}/aria2.session" || true
    chmod 600 "${SESSION_DIR}/aria2.session"
  fi

  # RPC 交互
  read -rp "是否开启 RPC？(回车默认开启，输入 n/N 表示不开启): " enable_rpc_input
  if [[ "${enable_rpc_input}" =~ ^[Nn]$ ]]; then
    ENABLE_RPC=false
  else
    ENABLE_RPC=true
  fi

  RPC_PORT=6800
  RPC_SECRET=""
  if [ "$ENABLE_RPC" = true ]; then
    read -rp "RPC 端口 (回车默认 6800): " INPUT_PORT
    if [ -n "$INPUT_PORT" ]; then RPC_PORT="$INPUT_PORT"; fi
    read -rp "RPC 密钥 (回车自动生成 16 位随机密钥): " INPUT_KEY
    if [ -n "$INPUT_KEY" ]; then RPC_SECRET="$INPUT_KEY"; else RPC_SECRET=$(gen_rand_key); fi
  fi

  # 新增：下载目录询问（默认 /opt/download）
  read -rp "下载目录 (回车默认 /opt/download): " INPUT_DOWNLOAD
  if [ -n "$INPUT_DOWNLOAD" ]; then
    DOWNLOAD_DIR="$INPUT_DOWNLOAD"
  else
    DOWNLOAD_DIR="/opt/download"
  fi

  # 如果目标存在且不是目录（例如为文件），自动备份该文件后创建目录
  if [ -e "$DOWNLOAD_DIR" ] && [ ! -d "$DOWNLOAD_DIR" ]; then
    ts=$(date +%s)
    echo "注意：$DOWNLOAD_DIR 已存在且不是目录，已备份为 ${DOWNLOAD_DIR}.file.bak.$ts"
    mv "$DOWNLOAD_DIR" "${DOWNLOAD_DIR}.file.bak.$ts" || { echo "无法备份 $DOWNLOAD_DIR，请检查权限或磁盘"; exit 1; }
  fi

  # 创建下载目录并设置权限
  mkdir -p "$DOWNLOAD_DIR" || { echo "无法创建目录 $DOWNLOAD_DIR（可能为只读文件系统或权限问题）"; exit 1; }
  chown -R "${RUN_USER}:" "$DOWNLOAD_DIR" 2>/dev/null || chown -R "${RUN_USER}:${RUN_USER}" "$DOWNLOAD_DIR" || true
  chmod 755 "$DOWNLOAD_DIR"

  # 写配置（dir 指向下载目录）
  cat >"$CONF_FILE" <<EOF
# aria2 配置（生成时间: $(date -u +"%Y-%m-%dT%H:%M:%SZ")）
dir=${DOWNLOAD_DIR}
continue=true
input-file=${SESSION_DIR}/aria2.session
save-session=${SESSION_DIR}/aria2.session
save-session-interval=60
max-concurrent-downloads=5
max-connection-per-server=4
enable-dht=true
enable-dht6=true
dht-listen-port=6881-6999
listen-port=6881-6999
enable-peer-exchange=true
bt-enable-lpd=true
bt-max-peers=80
bt-tracker=udp://tracker.opentrackr.org:1337/announce,udp://open.demonii.com:1337/announce,udp://tracker.openbittorrent.com:6969/announce,udp://tracker.internetwarriors.net:1337/announce,udp://exodus.desync.com:6969/announce,udp://tracker.tiny-vps.com:6969/announce,udp://tracker.moeking.me:6969/announce,udp://tracker.cyberia.is:6969/announce,udp://tracker3.itzmx.com:6961/announce,http://tracker.opentrackr.org:1337/announce,http://tracker.opentrackr.org:80/announce
# 不写独立日志，使用 systemd journal
EOF

  if [ "$ENABLE_RPC" = true ]; then
    cat >>"$CONF_FILE" <<EOF
# RPC
enable-rpc=true
rpc-listen-port=${RPC_PORT}
rpc-listen-all=true
rpc-allow-origin-all=true
rpc-secret=${RPC_SECRET}
EOF
  else
    echo "enable-rpc=false" >>"$CONF_FILE"
  fi

  chown root:root "$CONF_FILE"
  chmod 644 "$CONF_FILE"

  # systemd unit
  cat >"$SERVICE_FILE" <<UNIT
[Unit]
Description=Aria2c download manager (simple)
After=network.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${SESSION_DIR}
ExecStart=/usr/bin/aria2c --conf-path=${CONF_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable aria2.service
  systemctl restart aria2.service || true

  sleep 0.4
  if systemctl is-active --quiet aria2.service; then
    echo "aria2 已启动（User=${RUN_USER}）。"
  else
    echo "aria2 未能成功启动，请查看 journal 以获取详细错误："
    echo "  sudo journalctl -u aria2.service -n 120 --no-pager"
  fi

  if [ "$ENABLE_RPC" = true ]; then
    echo "端口: ${RPC_PORT}"
    echo "密钥: ${RPC_SECRET}"
  else
    echo "RPC 未启用"
  fi
  echo "下载目录: ${DOWNLOAD_DIR}"
  echo "配置文件: ${CONF_FILE}"
}

view_config() {
  if [ ! -f "$CONF_FILE" ]; then
    echo "找不到 $CONF_FILE，请先运行功能 1 安装。"
    return 1
  fi

  DIR_VAL=$(grep -E '^dir=' "$CONF_FILE" | cut -d= -f2- || true)
  PORT_VAL=$(grep -E '^rpc-listen-port=' "$CONF_FILE" | cut -d= -f2- || true)
  SECRET_VAL=$(grep -E '^rpc-secret=' "$CONF_FILE" | cut -d= -f2- || true)

  if [ -n "$PORT_VAL" ]; then
    echo "端口: $PORT_VAL"
  else
    echo "端口: 未设置 (默认 6800)"
  fi

  if [ -n "$SECRET_VAL" ]; then
    echo "密钥: $SECRET_VAL"
  else
    echo "密钥: 未设置"
  fi

  if [ -n "$DIR_VAL" ]; then
    echo "下载目录: $DIR_VAL"
  else
    echo "下载目录: 未设置"
  fi
}

purge_all() {
  echo "!!! 将彻底删除 aria2 及其配置/会话/服务 单元 (不可恢复) !!!"
  read -rp "确认删除并卸载 aria2 吗？输入 y 确认: " yn
  if [[ ! "$yn" =~ ^[Yy]$ ]]; then
    echo "已取消。"
    return 0
  fi

  systemctl stop aria2.service 2>/dev/null || true
  systemctl disable aria2.service 2>/dev/null || true

  if [ -f "$SERVICE_FILE" ]; then
    rm -f "$SERVICE_FILE"
  fi
  systemctl daemon-reload
  systemctl reset-failed || true

  if [ -f "$CONF_FILE" ]; then rm -f "$CONF_FILE"; fi

  RUN_USER=$(get_run_user)
  HOME_DIR=$(eval echo "~${RUN_USER}" 2>/dev/null || echo "/root")
  SESSION_DIR="/opt/aria2-session"

  if [ -d "$SESSION_DIR" ]; then
    rm -rf "$SESSION_DIR"
  fi

  if dpkg -l aria2 >/dev/null 2>&1; then
    apt-get remove --purge -y aria2 || true
    apt-get autoremove -y || true
  fi

  echo "清理完成。注意：下载目录不会被自动删除，以免误删你的文件。"
}

main_menu() {
  cat <<'MENU'
请选择功能：
1) 安装并配置 aria2
2) 查看 aria2 配置
3) 卸载并彻底清理
q) 退出
MENU
  while true; do
    read -rp "请输入 1/2/3 或 q: " choice
    case "$choice" in
      1) install_aria2; break ;;
      2) view_config; break ;;
      3) purge_all; break ;;
      q|Q) echo "退出"; exit 0 ;;
      *) echo "无效输入，请重试。" ;;
    esac
  done
}

require_root
main_menu
