#!/bin/bash

# 自动设置 alias（清除旧路径，添加当前路径）
sed -i "/alias p=.*panel\.sh.*/d" ~/.bashrc
echo "alias p='$(realpath "$0")'" >> ~/.bashrc
echo -e "\033[1;33m已自动更新 p 快捷命令，执行 source ~/.bashrc 生效\033[0m"

# 如果 ~/.profile 不存在，则创建并写入内容；存在则跳过
if [ ! -f ~/.profile ]; then
  cat > ~/.profile <<'EOF'
if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi
EOF
fi


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'
CYAN='\033[1;36m'

# 通用远程脚本执行函数：下载并执行，然后返回菜单
run_remote() {
  bash <(curl -fsSL "$1")
  pause_and_back
}

function pause_and_back() {
  echo -e "${GREEN}\n操作完成，按回车键返回菜单...${NC}"
  read
  show_menu
}

function install_packages() {
  echo -e "${BLUE}默认安装的包如下：${NC}"
  echo -e "${YELLOW}curl socat wget iproute2 quota at bc jq zip vim screen git net-tools cron sudo ufw${NC}"
  echo -ne "${YELLOW}请输入你不想安装的包（用空格分隔，可留空）：${NC}"
  read exclude

  EXCLUDE_ARRAY=($exclude)
  ALL_PACKAGES=(curl socat wget iproute2 quota at bc jq zip vim screen git net-tools cron sudo ufw)

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

function set_ssh()        { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/set_ssh.sh"; }
function linux_clean()    { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/linux_clean.sh"; }
function set_swap()       { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/set_swap.sh"; }
function enable_bbr()     { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/enable_bbr.sh"; }
function security_check() { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/linux_security_check.sh"; }
function port_forward()   { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/port_forward.sh"; }
function setup_caddy()    { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/setup_caddy.sh"; }
function set_dns()        { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/set_dns.sh"; }
function backup()         { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/backup.sh"; }
function recover()        { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/recover.sh"; }
function install_qb()     { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/install_qb.sh"; }
function set_frp()        { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/set_frp.sh"; }
function test()           { run_remote "https://raw.githubusercontent.com/81827cr/crr/main/sh/test.sh"; }

# 安装 rclone
function install_rclone() {
  # 1. 下载并执行官方安装脚本
  run_remote "https://rclone.org/install.sh"

  # 2. 确保配置目录存在，并创建一个空的 rclone.conf
  mkdir -p ~/.config/rclone
  touch ~/.config/rclone/rclone.conf
}

# 安装 node
function install_node() {
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  source ~/.bashrc
  nvm install node
  pause_and_back
}


function show_sysinfo() {

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

function show_sys_settings() {
  clear
  echo -e "系统设置"
  echo "------------------------"
  echo "1.   开启 ssh 密钥登录        2.   安装常用软件包"
  echo "3.   设置虚拟内存 Swap        4.   设置时区为 Asia/Shanghai"
  echo "5.   开启 BBR 加速            6.   运行安全检查脚本"
  echo "7.   端口转发                 8.   修改 DNS 配置"
  echo "------------------------"
  echo "9.   test 测试               10.  一键调优"
  read -p "请输入操作编号: " sub
  case $sub in
    1) set_ssh ;;
    2) install_packages ;;
    3) set_swap ;;
    4) set_timezone ;;
    5) enable_bbr ;;
    6) security_check ;;
    7) port_forward ;;
    8) set_dns ;;
    9) test ;;
    10) run_remote "https://…/one_click_tune.sh" ;;  # 一键调优脚本 URL
    *) echo -e "${RED}无效输入，返回主菜单${NC}"; sleep 1; show_menu ;;
  esac
}

function show_software_mgmt() {
  clear
  echo -e "软件管理"
  echo "------------------------"
  echo "1.   安装 qBittorrent       2.   frp 管理"
  echo "3.   安装 rclone            4.   caddy 反代"
  echo "5.   安装 node"
  echo "------------------------"
  read -p "请输入操作编号: " sub
  case $sub in
    1) install_qb ;;
    2) set_frp ;;
    3) install_rclone ;;
    4) setup_caddy ;;
    5) install_node ;;
    *) echo -e "${RED}无效输入，返回主菜单${NC}"; sleep 1; show_menu ;;
  esac
}



function show_menu() {
  clear
  echo -e "${CYAN}Linux 管理控制面板${NC}"
  echo -e "${CYAN}输入${YELLOW}p${CYAN}可快速启动脚本${NC}"
  echo "------------------------"
  echo -e "${CYAN}1.${NC}  系统信息"
  echo -e "${CYAN}2.${NC}  系统清理"
  echo -e "${CYAN}3.${NC}  系统设置"
  echo -e "${CYAN}4.${NC}  软件管理"
  echo "------------------------"
  echo -e "${CYAN}5.${NC}  备份vps"
  echo -e "${CYAN}6.${NC}  还原vps"
  echo "------------------------"
  echo -e "${CYAN}0.${NC}  退出脚本"
  echo "------------------------"
  echo
  read -p "请输入操作编号: " choice

  case $choice in
    1) show_sysinfo ;;
    2) linux_clean ;;
    3) show_sys_settings ;;
    4) show_software_mgmt ;;
    5) backup ;;
    6) recover ;;
    0) echo -e "${GREEN}退出成功，再见！${NC}" && exit 0 ;;
    *) echo -e "${RED}无效输入，脚本已退出！${NC}" && exit 1 ;;
  esac
}

show_menu
