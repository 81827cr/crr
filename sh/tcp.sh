#!/usr/bin/env bash
# 简化版 BBR 安装 + 启用 + 状态检测 + 卸载

set -e
sh_ver="1.0"
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Suffix="\033[0m"

info() { echo -e "${Green}[信息]${Suffix} $1"; }
warn() { echo -e "${Yellow}[提示]${Suffix} $1"; }
error() { echo -e "${Red}[错误]${Suffix} $1" >&2; }

# 检查系统和架构
detect_sys() {
    [[ -f /etc/os-release ]] && source /etc/os-release
    case "$ID" in
        debian|ubuntu) release=$ID ;;
        centos|rhel) release="centos" ;;
        *) error "不支持的系统: $ID"; exit 1 ;;
    esac
    bit=$(uname -m)
    [[ "$bit" = "x86_64" ]] && bit="x64" || bit="x32"
}

# 检查当前内核和BBR状态
check_status() {
    kernel=$(uname -r)
    bbr_enabled=$(sysctl net.ipv4.tcp_congestion_control | grep -q "bbr" && lsmod | grep -q "bbr" && echo "BBR启动成功" || echo "BBR未启动")
    
    if [[ "$kernel" =~ ^5\.[0-9]+ ]]; then
        kernel_status="已安装 BBR 加速内核"
    elif [[ "$kernel" =~ ^4\.9 ]]; then
        kernel_status="可能支持BBR的内核"
    else
        kernel_status="未安装BBR支持内核"
    fi
}

# 安装 BBR 正常内核（推荐5.4或更高）
install_bbr_kernel() {
    detect_sys
    info "开始安装 BBR 支持内核（推荐版本 5.4+）..."
    if [[ "$release" = "debian" || "$release" = "ubuntu" ]]; then
        apt update
        apt install -y wget curl
        # 添加受支持的新内核源（以Debian为例）
        wget -qO- https://kernel.ubuntu.com/~kernel-ppa/mainline/v5.15.148/amd64/ | grep 'generic.*deb' | grep -v lowlatency | awk -F'"' '{print $2}' | while read url; do
            wget -c https://kernel.ubuntu.com$url
        done
        dpkg -i *.deb
        rm -f *.deb
        update-grub
    else
        error "暂不支持此系统安装内核，请手动升级到 5.x"
        exit 1
    fi
    warn "内核安装完成，请重启后重新运行脚本启用BBR"
    read -p "现在是否重启系统？[Y/n]: " yn
    [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]] && reboot
}

# 启用 BBR
enable_bbr() {
    info "正在启用 BBR..."
    modprobe tcp_bbr 2>/dev/null || true
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    info "BBR 启用完成。"
}

# 卸载所有加速配置
remove_all_accel() {
    info "正在移除所有加速配置..."
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sysctl -p
    info "加速配置已清除。"
}

# 主菜单
start_menu() {
    clear
    check_status
    echo -e "
BBR 简化管理脚本 [v${sh_ver}]
-------------------------------
当前状态: ${Green}${kernel_status}${Suffix} ，${Yellow}${bbr_enabled}${Suffix}
-------------------------------
 1. 安装 BBR 支持内核
 2. 启用 BBR
 3. 卸载所有加速配置
 0. 退出脚本
"
    read -p "请输入选项 [0-3]: " opt
    case "$opt" in
        1) install_bbr_kernel ;;
        2) enable_bbr ;;
        3) remove_all_accel ;;
        0) exit 0 ;;
        *) error "请输入有效选项 [0-3]" && sleep 2 && start_menu ;;
    esac
}

detect_sys
start_menu
