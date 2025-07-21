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
  echo "3) 卸载 Caddy 及其所有配置"
  echo "0) 退出"
  read -rp "请输入操作编号: " choice

  case "$choice" in
    1) install_and_config ;;
    2) view_full_config ;;
    3) uninstall_caddy ;;
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

  # 1. 邮箱
  read -rp "请输入你的邮箱（默认: $DEFAULT_EMAIL）: " email
  email="${email:-$DEFAULT_EMAIL}"

  # 2. 域名
  read -rp "请输入你反代的域名（如 git.example.com）: " domain
  [[ -z "$domain" ]] && { echo "未输入域名，已取消操作。"; exit 1; }

  # 3. 目标地址（IP/域名 或 完整 URL）
  read -rp "请输入要反代的落地机 IP 或域名/URL（默认: 127.0.0.1）: " target
  target="${target:-127.0.0.1}"

  # 4. 如果没带协议，再询问端口并决定 scheme
  if [[ "$target" =~ ^https?:// ]]; then
    upstream="$target"
  else
    read -rp "请输入落地机的端口（如 80/443/3000）: " port
    [[ -z "$port" ]] && { echo "未输入端口，已取消操作。"; exit 1; }

    # 443 默认 https，其它默认 http
    if [[ "$port" -eq 443 ]]; then
      scheme="https"
    else
      scheme="http"
    fi
    upstream="${scheme}://${target}:${port}"
  fi

  echo ">>> 写入配置到 $CADDY_FILE..."

  # 初始化 Caddyfile
  if [[ ! -f "$CADDY_FILE" ]]; then
    echo "# Caddy 配置文件自动创建于 $(date)" > "$CADDY_FILE"
  fi

  # 追加反代配置
  {
    echo ""
    echo "$domain {"
    echo "    tls $email"
    echo "    encode gzip"
    echo "    reverse_proxy $upstream"
    echo "}"
  } >> "$CADDY_FILE"

  # 重启并启用 Caddy
  echo ">>> 重启 Caddy 并设置开机自启..."
  systemctl daemon-reexec
  if ! systemctl restart caddy; then
    echo "❌ Caddy 启动失败，请查看：journalctl -u caddy.service -n 30"
    exit 1
  fi
  systemctl enable caddy

  echo "✅ 配置成功！请确保 $domain 的 DNS 已正确解析到当前服务器 IP。"
}


# 查看完整配置文件
function view_full_config() {
  if [[ -f "$CADDY_FILE" ]]; then
    cat "$CADDY_FILE"
  else
    echo "（尚未创建任何配置）"
  fi
}

# 卸载 Caddy 和配置
function uninstall_caddy() {
  echo ">>> 正在卸载 Caddy..."
  systemctl stop caddy || true
  systemctl disable caddy || true

  apt purge -y caddy
  apt autoremove -y

  echo ">>> 正在删除 Caddy 源和 GPG 密钥..."
  rm -f /etc/apt/sources.list.d/caddy.list
  rm -f /usr/share/keyrings/caddy.gpg

  echo ">>> 正在删除配置文件目录 /etc/caddy/"
  rm -rf /etc/caddy/

  echo ">>> Caddy 已完整卸载并清理。"
}

# 启动菜单
menu
