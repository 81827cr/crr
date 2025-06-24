#!/usr/bin/env bash
# BBR 简化管理脚本 v1.1
# 支持 Debian/Ubuntu amd64 系统，内核安装版本为 5.15.148

set -e
sh_ver="1.1"
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Suffix="\033[0m"

info() { echo -e "${Green}[信息]${Suffix} $1"; }
warn() { echo -e "${Yellow}[提示]${Suffix} $1"; }
error() { echo -e "${Red}[错误]${Suffix} $1" >&2; }

TARGET_KERNEL_VERSION="5.15.148-0515148-generic"

detect_sys() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
    else
        error "无法检测系统版本，退出。"
        exit 1
    fi

    case "$ID" in
        debian|ubuntu) release=$ID ;;
        *) error "不支持的系统: $ID"; exit 1 ;;
    esac

    arch=$(uname -m)
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        error "仅支持 amd64/x86_64 架构，目前系统架构为：$arch"
        exit 1
    fi
}

check_status() {
    kernel=$(uname -r)
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    bbr_loaded=$(lsmod | grep -w "tcp_bbr" || true)

    if [[ "$available_cc" == *bbr* ]]; then
        kernel_status="BBR支持内核已安装"
    else
        kernel_status="未安装BBR支持内核"
    fi

    if [[ "$current_cc" == "bbr" && -n "$bbr_loaded" ]]; then
        bbr_enabled="BBR启动成功"
    elif [[ "$current_cc" == "bbr" ]]; then
        bbr_enabled="BBR已启用（模块未加载）"
    else
        bbr_enabled="BBR未启用"
    fi
}

install_bbr_kernel() {
    detect_sys
    info "开始安装 BBR 支持内核（版本 5.15.148）..."

    apt update
    apt install -y wget curl gnupg2 software-properties-common

    tmpdir=$(mktemp -d)
    cd "$tmpdir"

    base_url="https://kernel.ubuntu.com/~kernel-ppa/mainline/v5.15.148/amd64/"

    # 下载所有 generic 内核包，排除 lowlatency 和 signed
    wget -qO- "$base_url" | \
    grep -Eo 'href="[^"]+generic[^"]+\.deb"' | \
    grep -vE 'lowlatency|signed' | \
    sed 's/href="//;s/"//' | \
    while read -r deb; do
        wget -c "${base_url}${deb}"
    done

    dpkg -i ./*.deb

    cd -
    rm -rf "$tmpdir"

    update-grub

    warn "内核安装完成，请重启系统后重新运行本脚本启用 BBR。"
    read -rp "是否立即重启？[Y/n]: " yn
    if [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]]; then
        reboot
    else
        info "请手动重启以使用新内核。"
    fi
}

enable_bbr() {
    info "正在启用 BBR..."

    modprobe tcp_bbr 2>/dev/null || true

    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

    sysctl -w net.core.default_qdisc=fq
    sysctl -w net.ipv4.tcp_congestion_control=bbr

    sysctl -p

    info "BBR 启用完成，重启后仍应保持 bbr。"
}

remove_all_accel() {
    info "正在移除所有加速配置..."

    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

    sysctl -w net.ipv4.tcp_congestion_control=reno

    modprobe -r tcp_bbr 2>/dev/null || true

    sysctl -p

    info "加速配置已清除，拥塞控制已恢复为 reno。"
}

remove_old_kernels() {
    info "检测并准备卸载旧内核..."

    # 当前运行内核
    local current_kernel=$(uname -r)

    # 列出所有已安装内核，排除当前内核和目标内核
    local kernels=$(dpkg --list | grep linux-image | awk '{print $2}' | grep -v "$current_kernel" | grep -v "$TARGET_KERNEL_VERSION" || true)

    if [[ -z "$kernels" ]]; then
        info "没有检测到可卸载的旧内核。"
        return
    fi

    echo "检测到以下旧内核："
    echo "$kernels"
    read -rp "确认卸载这些旧内核？此操作不可逆 [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        apt purge -y $kernels
        info "旧内核卸载完成。"
        update-grub
    else
        info "取消卸载旧内核。"
    fi
}

check_and_prompt_old_kernel_removal() {
    detect_sys
    local kernel=$(uname -r)

    if [[ "$kernel" == "$TARGET_KERNEL_VERSION" ]]; then
        warn "当前系统运行在目标内核版本 $TARGET_KERNEL_VERSION"
        echo
        remove_old_kernels
    else
        info "当前系统内核版本为 $kernel，未检测到目标内核。"
    fi
}

start_menu() {
    clear
    check_status
    echo -e "
BBR 简化管理脚本 v${sh_ver}
-------------------------------
当前状态: ${Green}${kernel_status}${Suffix} ，${Yellow}${bbr_enabled}${Suffix}
-------------------------------
 1. 安装 BBR 支持内核（5.15.148）
 2. 卸载旧内核（仅当运行目标内核时可用）
 3. 启用 BBR
 4. 卸载所有加速配置

 0. 退出脚本
"
    read -rp "请输入选项 [0-4]: " opt
    case "$opt" in
        1) install_bbr_kernel ;;
        2) check_and_prompt_old_kernel_removal ;;
        3) enable_bbr ;;
        4) remove_all_accel ;;

        0) exit 0 ;;
        *) error "请输入有效选项 [0-4]" && sleep 2 && start_menu ;;
    esac
}

detect_sys
start_menu
