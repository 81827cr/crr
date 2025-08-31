#!/usr/bin/env bash
set -e

SCRIPT_NAME="$(basename "$0")"
IPV4=$(curl -4 -s ip.sb || echo "<你的服务器IP>")

function ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "⚠️  请使用 root 权限运行：sudo bash $SCRIPT_NAME"
        exit 1
    fi
}

function install_static() {
    echo "🔧 开始功能1：安装 qBittorrent v4.3.9 静态版..."
    mkdir -p /opt
    cd /opt

    # 下载并授权
    wget -qO qb-static https://github.com/userdocs/qbittorrent-nox-static/releases/download/release-4.3.9_v1.2.15/x86_64-qbittorrent-nox
    chmod +x qb-static

    # 首次初始化：自动同意许可并启动，10 秒后杀掉
    echo "⏳ 初始化 qBittorrent（自动同意许可）..."
    yes | timeout 10s /opt/qb-static || true

    # 创建 systemd 服务
    cat > /etc/systemd/system/qb.service <<-EOF
[Unit]
Description=qBittorrent Daemon Service (Static v4.3.9)
After=network.target

[Service]
LimitNOFILE=512000
User=root
ExecStart=/opt/qb-static

[Install]
WantedBy=multi-user.target
EOF

    # 启动并开机自启
    systemctl daemon-reload
    systemctl restart qb
    systemctl enable qb

    # 无论是否安装 ufw，都执行放行命令，不报错中止
    echo "设置ufw防火墙规则：允许 8080 端口"
    ufw allow 8080 2>/dev/null || true

    echo
    echo "✅ 功能1 完成！"
    echo "   Web UI: http://$IPV4:8080"
    echo "   默认用户: admin"
    echo "   默认密码: adminadmin"
}

function install_apt() {
    echo "🔧 开始功能2：通过 apt 安装系统版 qBittorrent..."
    apt update -y
    apt install -y qbittorrent-nox

    # 首次初始化
    echo "⏳ 初始化系统版 qBittorrent..."
    yes | timeout 10s /usr/bin/qbittorrent-nox || true

    # 创建/覆盖同名 systemd 服务
    cat > /etc/systemd/system/qb.service <<-EOF
[Unit]
Description=qBittorrent Daemon Service (APT)
After=network.target

[Service]
LimitNOFILE=512000
User=root
ExecStart=/usr/bin/qbittorrent-nox

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl restart qb
    systemctl enable qb

    # 无论是否安装 ufw，都执行放行命令，不报错中止
    echo "设置ufw防火墙规则：允许 8080 端口"
    ufw allow 8080 2>/dev/null || true

    echo
    echo "✅ 功能2 完成！"
    echo "   Web UI: http://$IPV4:8080"
    echo "   默认用户: admin"
    echo "   默认密码: adminadmin"
}

function uninstall_all() {
    echo "🧹 开始功能3：卸载并清理所有 qBittorrent 相关内容..."
    # 停止并移除服务
    systemctl stop qb 2>/dev/null || true
    systemctl disable qb 2>/dev/null || true
    rm -f /etc/systemd/system/qb.service
    systemctl daemon-reload

    # 卸载 apt 包
    apt remove -y qbittorrent-nox qbittorrent || true
    apt purge -y qbittorrent-nox qbittorrent || true

    # 清理静态二进制与配置
    rm -f /opt/qb-static
    rm -rf /root/.config/qBittorrent

    echo
    echo "✅ 功能3 完成，已彻底卸载并清理所有配置。"
}

function show_menu() {
    cat <<-EOF
===========================
   qBittorrent 一键管理脚本
===========================
  1) 安装静态版 v4.3.9
  2) apt 安装系统版
  3) 卸载并清理
  q) 退出
===========================
EOF
    read -rp "请选择功能： " choice
    case "$choice" in
        1) install_static ;;
        2) install_apt ;;
        3) uninstall_all ;;
        q|Q|"") echo "退出脚本。" ; exit 0 ;;
        *) echo "无效选项！" ; show_menu ;;
    esac
}

# ---------- 脚本入口 ----------
ensure_root
show_menu
