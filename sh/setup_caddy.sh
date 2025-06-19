#!/bin/bash

set -e

# 确保以 root 身份运行
if [[ $EUID -ne 0 ]]; then
  echo "请以 root 用户运行此脚本"
  exit 1
fi

CADDY_FILE="/etc/caddy/Caddyfile"
DEFAULT_EMAIL="4399@gmail.com"

# 功能菜单
function menu() {
  echo "=== Caddy 管理工具 ==="
  echo "1) 安装并配置 Caddy 反向代理"
  echo "2) 查看完整配置文件"
  echo "0) 退出"
  read -rp "请输入操作编号: " choice

  case "$choice" in
    1) install_and_config ;;
    2) view_full_config ;;
    0) exit 0 ;;
    *) echo "无效输入，请重新运行脚本。"; exit 1 ;;
  esac
}

# 检查并安装 Caddy（如果未安装）
function check_and_install_caddy() {
  if command -v caddy &>/dev/null; then
    echo ">>> 已检测到 Caddy，无需重复安装。"
    return
  fi

  echo ">>> 开始安装 Caddy..."
  apt update
  apt install -y curl vim wget gnupg lsb-release apt-transport-https ca-certificates

  echo ">>> 添加 Caddy GPG 密钥和源..."
  curl -sSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor > /usr/share/keyrings/caddy.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" > /etc/apt/sources.list.d/caddy.list

  echo ">>> 安装 Caddy 本体..."
  apt update
  apt install -y caddy
}

# 安装并配置反代
function install_and_config() {
  check_and_install_caddy

  read -rp "请输入你的邮箱（默认: $DEFAULT_EMAIL）: " email
  email="${email:-$DEFAULT_EMAIL}"

  read -rp "请输入你要反代的域名（如 git.example.com）: " domain
  read -rp "请输入本地反代端口（如 3000）: " port

  echo ">>> 正在写入配置到 $CADDY_FILE..."
  {
    echo ""
    echo "$domain {"
    echo "    tls $email"
    echo "    encode gzip"
    echo "    reverse_proxy localhost:$port"
    echo "}"
  } >> "$CADDY_FILE"

  echo ">>> 重启 Caddy 并设置开机自启..."
  systemctl daemon-reexec
  systemctl restart caddy
  systemctl enable caddy

  echo ">>> 配置成功！请确保 $domain 的 DNS 已指向当前服务器 IP。"
}

# 查看完整配置文件
function view_full_config() {
  echo ">>> 当前 Caddyfile 配置如下："
  echo "==============================="
  cat "$CADDY_FILE"
  echo "==============================="
}

# 启动菜单
menu
