#!/bin/bash
set -e

# —— 公共基础函数 —— #
# 下载并解压到 ~/frp，并生成全局的 PORT/TOKEN 变量
function frp_base() {
  # 如果已经有 ~/frp，就跳过下载
  if [ -d "$HOME/frp" ]; then
    cd "$HOME/frp"
    return
  fi

  cd "$HOME"
  wget -q https://github.com/fatedier/frp/releases/download/v0.63.0/frp_0.63.0_linux_amd64.tar.gz
  tar -zxf frp_0.63.0_linux_amd64.tar.gz && rm frp_0.63.0_linux_amd64.tar.gz
  mv frp_0.63.0_linux_amd64 frp
  cd frp
}

# —— 功能 1：安装 & 启动 frps —— #
function install_frps() {
  frp_base
  # 随机端口 & token
  PORT=$(( RANDOM % 55536 + 10000 ))
  TOKEN=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c16)

  # 放行端口（有 ufw 则生效，无 ufw 则忽略错误）
  echo "设置 UFW：放行端口 $PORT"
  ufw allow "$PORT" 2>/dev/null || true

  # 写 frps.toml（每次重写）
  cat > frp/frps.toml <<EOF
bindAddr = "0.0.0.0"
bindPort = $PORT

auth.method = "token"
auth.token = "$TOKEN"
EOF

  echo
  echo "请选择保活方式：1) PM2    2) systemd"
  read -p "> " opt
  case "$opt" in
    1)
      # 安装 nvm/node + pm2
      bash <(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh)
      source ~/.bashrc
      nvm install node
      npm install -g pm2

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
ExecStart=$(which frps) -c ~/frp/frps.toml

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      systemctl enable frps
      systemctl restart frps
      ;;
    *)
      echo "无效选项，已取消。"; return
      ;;
  esac

  echo -e "\n✅ frps 安装并启动完成！bindPort=$PORT  token=$TOKEN\n"
  echo "—— frpc 客户端示例 ——"
  cat <<EOF

[common]
serverAddr = \"YOUR_FRPS_SERVER_IP\"
serverPort = $PORT

auth.method = \"token\"
auth.token = \"$TOKEN\"
EOF
  echo
}

# —— 功能 2：管理 & 追加 frpc —— #
function manage_frpc() {
  frp_base

  # 检查已有保活任务
  pm2 info frpc >/dev/null 2>&1 && U_PM2=true || U_PM2=false
  systemctl is-active frpc >/dev/null 2>&1 && U_SD=true || U_SD=false

  if ! $U_PM2 && ! $U_SD; then
    echo "请选择 frpc 保活方式：1) PM2    2) systemd"
    read -p "> " opt
    case "$opt" in
      1)
        bash <(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh)
        source ~/.bashrc; nvm install node; npm install -g pm2
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
ExecStart=$(which frpc) -c ~/frp/frpc.toml

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable frpc; systemctl restart frpc
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
  read -p "请输入穿透服务名字（回车退出）: " NAME || return
  [ -z "$NAME" ] && return
  read -p "请输入内网端口（回车退出）: " LPORT || return
  [ -z "$LPORT" ] && return
  read -p "请输入外网端口（回车退出）: " RPORT || return
  [ -z "$RPORT" ] && return
  read -p "请输入内网 IP（回车退出）: " LIP || return
  [ -z "$LIP" ] && return

  cat >> frpc.toml <<EOF

[[proxies]]
name = "$NAME"
type = "tcp"
local_ip = "$LIP"
local_port = $LPORT
remote_port = $RPORT
EOF

  echo "设置 UFW：放行端口 $RPORT"
  ufw allow "$RPORT" 2>/dev/null || true

  # 重启保活
  $U_PM2   && pm2 restart frpc
  $U_SD    && systemctl restart frpc

  echo -e "\n✅ 已追加代理 \"$NAME\" (remote_port=$RPORT)"
  echo "请确保 frps 服务器已放行相同端口。"
  echo
}

# —— 菜单入口 —— #
function show_menu() {
  clear
  echo "1) 安装 frps 服务端"
  echo "2) 管理 frpc 客户端"
  echo "0) 退出"
  read -p "请选择: " num
  case "$num" in
    1) install_frps ;;
    2) manage_frpc ;;
    0) exit 0 ;;
    *) echo "无效输入"; sleep 1; show_menu ;;
  esac
}

show_menu
