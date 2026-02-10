#!/usr/bin/env bash
set -e

SCRIPT_NAME="$(basename "$0")"

IPV4=$(
  curl -4 -fsS --connect-timeout 2 --max-time 4 ip.sb 2>/dev/null \
  || ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' \
  || hostname -I 2>/dev/null | awk '{print $1}'
)
IPV4="${IPV4:-127.0.0.1}"



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
    wget -qO qb-static https://a.dps.dpdns.org/app/x86_64-qbittorrent-nox
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
    echo "🧹 开始功能0：卸载并清理所有 qBittorrent 相关内容..."
    # 停止并移除服务
    systemctl stop qb 2>/dev/null || true
    systemctl disable qb 2>/dev/null || true
    rm -f /etc/systemd/system/qb.service
    systemctl daemon-reload

    # 卸载 apt 包
    apt remove -y qbittorrent-nox qbittorrent || true
    apt purge -y qbittorrent-nox qbittorrent || true

    # ---- 清理 qbuser 的目录和用户 ----
    # 移除 qbuser 的主目录 (包含配置和缓存)
    rm -rf /home/qbuser
    
    # 移除 qbuser 用户
    userdel qbuser 2>/dev/null || true
    # ----------------------------------

    # 清理静态二进制与配置
    rm -f /opt/qb-static
    rm -rf /root/.config/qBittorrent
    rm -f ~/.local/share/qBittorrent
    rm -rf ~/.cache/qBittorrent

    echo
    echo "✅ 功能0 完成，已彻底卸载并清理所有配置。"
}


function setup_qb_safe_service() {
    systemctl stop qb
    # 1. 创建低权限不能登录的用户
    #    先判断用户是否存在，如果不存在才创建
    if ! id -u qbuser &>/dev/null; then
        useradd -r -s /sbin/nologin qbuser
    else
        echo "用户 'qbuser' 已存在，跳过创建。"
    fi

    # 2. 设置下载目录所有权为 qbuser
    mkdir -p /opt/Downloads
    chown -R qbuser:qbuser /opt/Downloads
    chmod -R 750 /opt/Downloads

    # 3. 创建 qbuser 用户目录和配置目录，并设置权限
    mkdir -p /home/qbuser
    mkdir -p /home/qbuser/.config/qBittorrent
    mkdir -p /home/qbuser/.cache/qBittorrent

    # 移动旧的配置文件到新目录
    if [ -d "/root/.config/qBittorrent" ]; then
        echo "正在移动旧配置文件..."
        mv /root/.config/qBittorrent/* /home/qbuser/.config/qBittorrent/
    else
        echo "未找到旧配置文件，跳过移动。"
    fi

    # 赋予 qbuser 对其 home 目录的完整权限
    chown -R qbuser:qbuser /home/qbuser
    chmod 700 /home/qbuser
    
    # 确保 qb-static 可执行文件权限正确
    # 你这里写的是 chown，但通常只需要确保执行权限
    chown -R qbuser:qbuser /opt/qb-static
    chmod +x /opt/qb-static


    # 4. 清理旧的 qb 配置
    rm -rf /root/.config/qBittorrent
    rm -rf /root/.cache/qBittorrent

    # 5. 删除并重新创建 /etc/systemd/system/qb.service 文件
    cat > /etc/systemd/system/qb.service <<EOF
[Unit]
Description=qBittorrent Daemon Service (Static v4.3.9)
After=network.target

[Service]
LimitNOFILE=512000
User=qbuser
Environment=XDG_CONFIG_HOME=/home/qbuser/.config
ExecStart=/opt/qb-static
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    # 6. 重启服务
    systemctl daemon-reload
    systemctl restart qb

    echo "所有配置已完成，请使用 'systemctl status qb' 命令检查服务状态。"
}

function show_menu() {
    cat <<-EOF
===========================
   qBittorrent 一键管理脚本
===========================
  1) 安装静态版 v4.3.9
  2) apt 安装系统版
  11) 一键设置低权限用户运行(仅限v4.3.9)
  0) 卸载并清理
  q) 退出
===========================
EOF
    read -rp "请选择功能： " choice
    case "$choice" in
        1)  install_static ;;
        2)  install_apt ;;
        11) setup_qb_safe_service ;;
        0)  uninstall_all ;;
        q|Q|"") echo "退出脚本。" ; exit 0 ;;
        *) echo "无效选项！" ; show_menu ;;
    esac
}

# ---------- 脚本入口 ----------
ensure_root
show_menu
