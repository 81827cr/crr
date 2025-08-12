#!/bin/bash
set -e

# —— 公共基础函数 —— #
# 下载并解压到 ~/frp，并生成全局的 PORT/TOKEN 变量
function frp_base() {
  # 如果已经有 ~/frp，就跳过下载
  if [ -d "$HOME/frp" ]; then
    cd "$HOME/frp/"
    return
  fi

  cd "$HOME"
  wget -q https://github.com/fatedier/frp/releases/download/v0.63.0/frp_0.63.0_linux_amd64.tar.gz
  tar -zxf frp_0.63.0_linux_amd64.tar.gz && rm frp_0.63.0_linux_amd64.tar.gz
  mv frp_0.63.0_linux_amd64/ frp/
  cd frp/
}

# —— 检查并安装 PM2 —— #
function ensure_pm2_installed() {
  # 检查 node
  if command -v node >/dev/null 2>&1; then
    echo "✅ Node.js 已安装，跳过 nvm 安装"
  else
    echo "⏳ 未检测到 Node.js，正在通过 nvm 安装..."
    bash <(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh)
    source ~/.bashrc
    nvm install node
  fi

  # 检查 pm2
  if command -v pm2 >/dev/null 2>&1; then
    echo "✅ pm2 已安装，跳过安装"
  else
    echo "🔧 安装 pm2..."
    npm install -g pm2
  fi
}

# —— 功能 1：安装 & 启动 frps —— #
function install_frps() {
  frp_base
  # 随机端口 & token
  PORT=7000
  TOKEN=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c16)

  # 放行端口（有 ufw 则生效，无 ufw 则忽略错误）
  echo "设置 UFW：放行端口 $PORT"
  ufw allow "$PORT" 2>/dev/null || true

  # 写 frps.toml（每次重写）
  cat > frps.toml <<EOF
bindAddr = "0.0.0.0"
bindPort = $PORT

auth.method = "token"
auth.token = "$TOKEN"
EOF

  echo
  echo "请选择保活方式：1) PM2    2) systemd    3) openrc"
  read -p "> " opt
  case "$opt" in
    1)
      # 安装 nvm/node + pm2
      ensure_pm2_installed

      # 启动并保活
      pm2 start ~/frp/frps --name frps -- -c ~/frp/frps.toml
      pm2 startup
      pm2 save
      ;;
    2)
      cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=frps Daemon Service
After=network.target

[Service]
User=root
ExecStart=$HOME/frp/frps -c $HOME/frp/frps.toml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      systemctl enable frps
      systemctl restart frps
      ;;
    3)
      install_frps_openrc
      ;;
    *)
      echo "无效选项，已取消。"; return
      ;;
  esac

  echo -e "\n✅ frps 安装并启动完成！bindPort=$PORT  token=$TOKEN\n"
  echo "—— frpc 客户端示例 ——"
  cat <<EOF
serverAddr = "YOUR_FRPS_SERVER_IP"
serverPort = $PORT
auth.method = "token"
auth.token = "$TOKEN"
EOF
  echo
}

# 极简：用 OpenRC + wrapper 做保活（不产生日志，输出重定向到 /dev/null）
function install_frps_openrc() {
  frp_base            # 确保 $HOME/frp 存在

  WRAPPER=/usr/local/bin/frps-supervisor.sh

  # 写 wrapper（不写日志）
  cat > "$WRAPPER" <<'EOF'
#!/bin/sh
# 简单重启循环：frps 退出后 5s 重启，且不产生日志
while true; do
  "$HOME"/frp/frps -c "$HOME"/frp/frps.toml >/dev/null 2>&1
  sleep 5
done
EOF
  chmod +x "$WRAPPER"

  # 极简 OpenRC 脚本（只要能启动 wrapper 即可）
  cat > /etc/init.d/frps <<'EOF'
#!/sbin/openrc-run
command="/usr/local/bin/frps-supervisor.sh"
command_user="root"
depend() { need net }
EOF
  chmod +x /etc/init.d/frps

  # 加开机并启动
  rc-update add frps default
  rc-service frps start

  echo "✅ frps 已用 OpenRC（无日志模式）部署并启动"
}


# —— 功能 2：管理 & 追加 frpc —— #
function manage_frpc() {
  frp_base

  # 检查已有保活任务
  pm2 info frpc >/dev/null 2>&1 && U_PM2=true || U_PM2=false
  [[ -f /etc/systemd/system/frpc.service ]] && U_SD=true || U_SD=false

  if ! $U_PM2 && ! $U_SD; then
    echo "请选择 frpc 保活方式：1) PM2    2) systemd"
    read -p "> " opt
    case "$opt" in
      1)
        # 安装 nvm/node + pm2
        ensure_pm2_installed

        pm2 start ~/frp/frpc --name frpc -- -c ~/frp/frpc.toml
        pm2 startup; pm2 save
        ;;
      2)
        cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=frpc Daemon Service
After=network.target

[Service]
User=root
ExecStart=$HOME/frp/frpc -c $HOME/frp/frpc.toml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable frpc
        ;;
      *)
        echo "无效选项，已取消。"; return
        ;;
    esac
  else
    echo "检测到已有 frpc 保活，跳过保活设置。"
  fi

  # 追加代理配置
  echo
  read -p "请输入穿透服务名字: " NAME || return
  [ -z "$NAME" ] && return
  read -p "请输入内网端口: " LPORT || return
  [ -z "$LPORT" ] && return
  read -p "请输入外网端口: " RPORT || return
  [ -z "$RPORT" ] && return
  read -p "请输入内网 IP（默认127.0.0.1）: " LIP
  LIP=${LIP:-127.0.0.1}

  cat >> frpc.toml <<EOF

[[proxies]]
name = "$NAME"
type = "tcp"
localIP = "$LIP"
localPort = $LPORT
remotePort = $RPORT
EOF

  echo "设置 UFW：放行端口 $LPORT"
  ufw allow "$LPORT" 2>/dev/null || true

  # 重启保活
  $U_PM2   && pm2 restart frpc
  $U_SD    && systemctl restart frpc

  echo "请确保 frps 服务器已放行相同端口。"
  echo -e "配置名: $NAME  外网端口: $RPORT"
  echo
}

# —— 功能 3：卸载 frp —— #
function uninstall_frp() {
  echo ">> 停止并删除 PM2 进程"
  pm2 delete frps >/dev/null 2>&1 || true
  pm2 delete frpc >/dev/null 2>&1 || true

  echo ">> 删除 frp 目录"
  rm -rf ~/frp

  echo ">> 停止并移除 systemd 服务"
  systemctl stop frps.service frpc.service >/dev/null 2>&1 || true
  systemctl disable frps.service frpc.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/frps.service /etc/systemd/system/frpc.service
  systemctl daemon-reload

  echo ">> 停止并移除 OpenRC 服务 与 wrapper"
  rc-service frps stop >/dev/null 2>&1 || true
  rc-update del frps default >/dev/null 2>&1 || true
  rm -f /etc/init.d/frps /usr/local/bin/frps-supervisor.sh

  echo ">> 更新 PM2 启动项并保存"
  pm2 startup >/dev/null 2>&1 || true
  pm2 save >/dev/null 2>&1 || true

  echo -e "\n✅ frp 已彻底卸载完成！\n"
}

# —— 菜单入口 —— #
function show_menu() {
  clear
  echo "1) 安装 frps 服务端"
  echo "2) 管理 frpc 客户端"
  echo "3) 卸载 frp"
  echo "0) 退出"
  read -p "请选择: " num

  # 如果直接按回车，退出脚本
  if [[ -z "$num" ]]; then
    echo "已退出"
    exit 0
  fi

  case "$num" in
    1) install_frps ;;
    2) manage_frpc ;;
    3) uninstall_frp ;;
    0) exit 0 ;;
    *) echo "无效输入"; sleep 1; show_menu ;;
  esac
}


while true; do
  show_menu
done