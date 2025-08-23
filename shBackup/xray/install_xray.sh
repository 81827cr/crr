#!/usr/bin/env bash
# 简易 Xray 安装/卸载面板（中文注释）
set -euo pipefail

# --------- 配置区（把你给的链接放这里） ------------
DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/v25.8.3/Xray-linux-64.zip"
XDIR="/opt/xray"
SERVICE_NAME="xray"
SYSTEMD_UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_INIT_PATH="/etc/init.d/${SERVICE_NAME}"
TMP_DIR="/tmp/xray_install_$$"
# ----------------------------------------------------

# 通用远程脚本执行函数：下载并执行，然后返回菜单
run_remote() {
  bash <(curl -fsSL "$1")
  pause_and_back
}

# 检测 init 系统：返回 systemd / openrc / unknown
detect_init_system() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    echo "systemd" && return
  fi
  # 如果有 rc-service 或 openrc-run，判定为 openrc
  if command -v rc-service >/dev/null 2>&1 || [ -f /sbin/openrc-run ]; then
    echo "openrc" && return
  fi
  echo "unknown"
}

# 创建默认配置文件
setup_xray_config() {
  mkdir -p "$XDIR"
  cat > "$XDIR/config.json" <<'EOF'
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 10808,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
}

# 安装 OpenRC 服务脚本
install_openrc_service() {
  cat > "$OPENRC_INIT_PATH" <<'EOF'
#!/sbin/openrc-run

name="xray"
description="Xray Service"

command="/opt/xray/xray"
command_args="-config /opt/xray/config.json"

pidfile="/var/run/${name}.pid"
command_background="yes"

depend() {
    need net
    after firewall
}

start_pre() {
    # 如果需要，检查配置文件是否存在
    if [ ! -f /opt/xray/config.json ]; then
        eerror "Config file /opt/xray/config.json not found!"
        return 1
    fi
}
EOF
  chmod +x "$OPENRC_INIT_PATH" || true
  # 添加到默认运行级并启动（若可用）
  command -v rc-update >/dev/null 2>&1 && rc-update add "$SERVICE_NAME" default || true
  command -v rc-service >/dev/null 2>&1 && rc-service "$SERVICE_NAME" start || true
}

# 卸载 OpenRC 服务
remove_openrc_service() {
  command -v rc-service >/dev/null 2>&1 && rc-service "$SERVICE_NAME" stop || true
  command -v rc-update >/dev/null 2>&1 && rc-update del "$SERVICE_NAME" default || true
  [ -f "$OPENRC_INIT_PATH" ] && rm -f "$OPENRC_INIT_PATH"
}

# 安装 systemd 单元
install_systemd_service() {
  cat > "$SYSTEMD_UNIT_PATH" <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/xray/xray -config /opt/xray/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload || true
  systemctl enable --now "$SERVICE_NAME" || true
}

# 卸载 systemd 单元
remove_systemd_service() {
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    systemctl stop "$SERVICE_NAME" || true
    systemctl disable "$SERVICE_NAME" || true
  fi
  [ -f "$SYSTEMD_UNIT_PATH" ] && rm -f "$SYSTEMD_UNIT_PATH"
  systemctl daemon-reload || true
}

# 安装主流程（不做包检测，假设 unzip/wget 已就绪）
install_xray() {
  echo "开始安装 Xray..."
  rm -rf "$TMP_DIR" || true
  mkdir -p "$TMP_DIR"
  # 下载到临时目录
  echo "下载: $DOWNLOAD_URL"
  wget -q --show-progress -O "$TMP_DIR/Xray.zip" "$DOWNLOAD_URL"
  mkdir -p "$XDIR"
  unzip -o "$TMP_DIR/Xray.zip" -d "$TMP_DIR" >/dev/null 2>&1 || true
  # 尝试移动解压出的可执行文件到 /opt/xray/xray
  if [ -f "$TMP_DIR/xray" ]; then
    mv -f "$TMP_DIR/xray" "$XDIR/xray"
  else
    # 有些 release 会在子目录，尝试查找
    found=$(find "$TMP_DIR" -type f -name xray -perm /a+x | head -n1 || true)
    if [ -n "$found" ]; then
      mv -f "$found" "$XDIR/xray"
    else
      echo "未找到 xray 可执行文件，安装失败。" >&2
      rm -rf "$TMP_DIR" || true
      return 1
    fi
  fi
  chmod +x "$XDIR/xray"
  # 写默认配置（如果已存在则覆盖）
  setup_xray_config
  # 根据 init 系统选择保活方式
  init_sys=$(detect_init_system)
  echo "检测到 init 系统: $init_sys"
  if [ "$init_sys" = "systemd" ]; then
    install_systemd_service
  elif [ "$init_sys" = "openrc" ]; then
    install_openrc_service
  else
    echo "未识别 init 系统，已安装二进制与配置，请手动创建服务（systemd 或 openrc）。"
  fi
  rm -rf "$TMP_DIR"
  echo "安装完成：$XDIR/xray"
}

# 卸载主流程
uninstall_xray() {
  echo "开始卸载 Xray..."
  init_sys=$(detect_init_system)
  echo "检测到 init 系统: $init_sys"
  if [ "$init_sys" = "systemd" ]; then
    remove_systemd_service
  elif [ "$init_sys" = "openrc" ]; then
    remove_openrc_service
  fi
  # 删除程序目录
  rm -rf "$XDIR"
  echo "卸载完成。"
}

function reality()   { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/xray/reality.sh"; }


# --------- 交互面板 ---------
# 必须以 root 运行（写 /opt 和 /etc）
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 身份运行此脚本。"
  exit 1
fi

cat <<'EOF'
请选择操作：
1) 安装 xray
2) 生成 reality
9) 卸载 xray
0) 退出
EOF

read -rp "输入选项: " choice
# 如果直接回车或空则退出
if [ -z "${choice:-}" ]; then
  echo "退出。" && exit 0
fi

case "$choice" in
  1) install_xray ;;
  2) reality ;;
  9) uninstall_xray ;;
  0)
    echo "退出。" && exit 0
    ;;
  *)
    echo "未知选项，退出。" && exit 1
    ;;
esac

exit 0

