#!/bin/bash

# 自动设置 alias（清除旧路径，添加当前路径）
sed -i "/alias p=.*panel\.sh.*/d" ~/.bashrc
echo "alias p='$(realpath "$0")'" >> ~/.bashrc
echo -e "\033[1;33m已自动更新 p 快捷命令，执行 source ~/.bashrc 生效\033[0m"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

function pause_and_back() {
  echo -e "${GREEN}\n操作完成，按回车键返回菜单...${NC}"
  read
  show_menu
}

function install_packages() {
  echo -e "${BLUE}默认安装的包如下：${NC}"
  echo -e "${YELLOW}curl socat wget iproute2 quota at bc jq zip vim screen git net-tools cron ufw${NC}"
  echo -ne "${YELLOW}请输入你不想安装的包（用空格分隔，可留空）：${NC}"
  read exclude

  EXCLUDE_ARRAY=($exclude)
  ALL_PACKAGES=(curl socat wget iproute2 quota at bc jq zip vim screen git net-tools cron ufw)

  INSTALL_LIST=()
  for pkg in "${ALL_PACKAGES[@]}"; do
    skip=false
    for ex in "${EXCLUDE_ARRAY[@]}"; do
      if [[ "$pkg" == "$ex" ]]; then
        skip=true
        break
      fi
    done
    $skip || INSTALL_LIST+=("$pkg")
  done

  echo -e "${GREEN}开始安装：${INSTALL_LIST[*]}${NC}"
  apt update -y && apt install -y "${INSTALL_LIST[@]}"
  pause_and_back
}

function set_timezone() {
  timedatectl set-timezone Asia/Shanghai
  echo -e "${GREEN}时区已设置为 Asia/Shanghai${NC}"
  pause_and_back
}

function set_ssh() {
  tmp_script="./set_ssh.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/set_ssh.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function linux_clean() {
  tmp_script="./linux_clean.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/linux_clean.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function set_swap() {
  tmp_script="./set_swap.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/set_swap.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function enable_bbr() {
  tmp_script="./enable_bbr.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/enable_bbr.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function security_check() {
  tmp_script="./linux_security_check.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/linux_security_check.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function port_forward() {
  tmp_script="./port_forward.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/port_forward.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function setup_caddy() {
  tmp_script="./setup_caddy.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/setup_caddy.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function set_dns() {
  tmp_script="./set_dns.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/set_dns.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function backup() {
  tmp_script="./backup.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/backup.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function recover() {
  tmp_script="./recover.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/recover.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}

function test() {
  tmp_script="./test.sh"
  curl -sSL https://raw.githubusercontent.com/81827cr/crr/refs/heads/main/sh/test.sh -o "$tmp_script" && bash "$tmp_script"
  rm -f "$tmp_script"
  pause_and_back
}


function show_sysinfo() {
  CYAN='\033[1;36m'

  echo -e "${BLUE}========= 系统信息 =========${NC}"

  CPU_MODEL=$(lscpu | grep "Model name" | sed 's/.*:\s*//')
  CPU_CORES=$(nproc)

  CPU_FREQ_RAW=$(lscpu | grep "CPU MHz" | awk '{print $3}')
  CPU_FREQ=${CPU_FREQ_RAW:-"不可用"}

  CACHE_L1=$(lscpu | grep "L1d cache" | awk '{print $3}')
  CACHE_L2=$(lscpu | grep "L2 cache" | awk '{print $3}')
  CACHE_L3=$(lscpu | grep "L3 cache" | awk '{print $3}')
  CACHE_L1=${CACHE_L1:-"N/A"}
  CACHE_L2=${CACHE_L2:-"N/A"}
  CACHE_L3=${CACHE_L3:-"N/A"}

  AES=$(lscpu | grep -q aes && echo -e "${CYAN}✔ Enabled${NC}" || echo -e "${RED}✘ Disabled${NC}")
  VMX=$(lscpu | grep -Eq 'vmx|svm' && echo -e "${CYAN}✔ Enabled${NC}" || echo -e "${RED}✘ Disabled${NC}")

  MEM_USED=$(free -h | awk '/Mem:/ {print $3}')
  MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
  SWAP_USED=$(free -h | awk '/Swap:/ {print $3}')
  SWAP_TOTAL=$(free -h | awk '/Swap:/ {print $2}')

  DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
  DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
  DISK_PATH=$(df -h / | awk 'NR==2 {print $1}')

  UPTIME=$(uptime -p)
  LOAD_AVG=$(uptime | awk -F'load average:' '{ print $2 }')

  OS=$(lsb_release -d | awk -F"\t" '{print $2}')
  ARCH=$(uname -m)
  KERNEL=$(uname -r)

  TCP_CONG=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
  VIRT=$(systemd-detect-virt)

  IPINFO=$(curl -s ipinfo.io)
  IPV4_ASN=$(echo "$IPINFO" | jq -r .org)
  IPV4_LOC=$(echo "$IPINFO" | jq -r '.city + " / " + .region + " / " + .country')

  echo -e "CPU 型号          : ${CYAN}$CPU_MODEL${NC}"
  echo -e "CPU 核心数        : ${CYAN}$CPU_CORES${NC}"
  echo -e "CPU 频率          : ${CYAN}$CPU_FREQ MHz${NC}"
  echo -e "CPU 缓存          : ${CYAN}L1: $CACHE_L1 / L2: $CACHE_L2 / L3: $CACHE_L3${NC}"
  echo -e "AES-NI指令集      : $AES"
  echo -e "VM-x/AMD-V支持    : $VMX"
  echo -e "内存              : ${CYAN}$MEM_USED / $MEM_TOTAL${NC}"
  echo -e "Swap              : ${CYAN}$SWAP_USED / $SWAP_TOTAL${NC}"
  echo -e "硬盘空间          : ${CYAN}$DISK_USED / $DISK_TOTAL${NC}"
  echo -e "启动盘路径        : ${CYAN}$DISK_PATH${NC}"
  echo -e "系统在线时间      : ${CYAN}$UPTIME${NC}"
  echo -e "负载              : ${CYAN}$LOAD_AVG${NC}"
  echo -e "系统              : ${CYAN}$OS${NC}"
  echo -e "架构              : ${CYAN}$ARCH (64 Bit)${NC}"
  echo -e "内核              : ${CYAN}$KERNEL${NC}"
  echo -e "TCP加速方式       : ${CYAN}$TCP_CONG${NC}"
  echo -e "虚拟化架构        : ${CYAN}$VIRT${NC}"
  echo -e "IPV4 ASN          : ${CYAN}$IPV4_ASN${NC}"
  echo -e "IPV4 位置         : ${CYAN}$IPV4_LOC${NC}"

  pause_and_back
}

function show_menu() {
  clear
  echo -e "${BLUE}========= Linux 管理控制面板 =========${NC}"
  echo -e "${YELLOW}[1] 系统信息${NC}"
  echo -e "${YELLOW}[2] 系统清理${NC}"
  echo -e "${YELLOW}[3] 安装常用软件包（可选择排除）${NC}"
  echo -e "${YELLOW}[4] 设置时区为 Asia/Shanghai${NC}"
  echo -e "${YELLOW}[5] 开启ssh密钥登录${NC}"
  echo -e "${YELLOW}[6] 设置虚拟内存 Swap${NC}"
  echo -e "${YELLOW}[7] 开启 BBR 加速${NC}"
  echo -e "${YELLOW}[8] 运行一键安全检查脚本${NC}"
  echo -e "${YELLOW}[9] 端口转发脚本${NC}"
  echo -e "${YELLOW}[10] caddy反代脚本${NC}"
  echo -e "${YELLOW}[11] 修改 DNS 配置${NC}"
  echo -e "${YELLOW}[12] 备份vps${NC}"
  echo -e "${YELLOW}[13] 还原vps${NC}"
  echo -e "${YELLOW}[14] test测试${NC}"
  echo -e "${YELLOW}[0] 退出脚本${NC}"
  echo
  read -p "请输入操作编号: " choice

  case $choice in
    1) show_sysinfo ;;
    2) linux_clean ;;
    3) install_packages ;;
    4) set_timezone ;;
    5) set_ssh ;;
    6) set_swap ;;
    7) enable_bbr ;;
    8) security_check ;;
    9) port_forward ;;
    10) setup_caddy ;;
    11) set_dns ;;
    12) backup ;;
    13) recover ;;
    14) test ;;
    0) echo -e "${GREEN}退出成功，再见！${NC}" && exit 0 ;;
    *) echo -e "${RED}无效输入，脚本已退出！${NC}" && exit 1 ;;
  esac
}

show_menu
