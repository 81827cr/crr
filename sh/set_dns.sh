#!/bin/bash

# 颜色变量定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[1;36m'  # 亮青色
NC='\033[0m'

# DNS设置函数
set_dns() {
  echo -e "${CYAN}当前 DNS 配置：${NC}"
  grep '^nameserver' /etc/resolv.conf || echo "无 DNS 配置"

  # 直接清空现有配置并写入新的 DNS 地址
  echo -e "${GREEN}写入新的 DNS 配置：${new_dns}${NC}"
  echo "" > /etc/resolv.conf
  for ip in $new_dns; do
    echo "nameserver $ip" >> /etc/resolv.conf
  done

  echo -e "${GREEN}DNS 已设置完成！${NC}"
  pause_and_back
}

# DNS优化设置函数
set_dns_ui() {
  root_use
  send_stats "优化DNS"
  
  while true; do
    clear
    echo "优化DNS地址"
    echo "------------------------"
    echo -e "当前DNS地址"
    # 使用awk给输出的每一行加上亮青色
    awk '{print "'$CYAN'" $0 "'$NC'"}' /etc/resolv.conf
    echo "------------------------"
    echo ""
    echo -e "1. 国外DNS优化:"
    echo -e "v4: ${CYAN} 1.1.1.1 8.8.8.8${NC}"
    echo -e "v6: ${CYAN} 2606:4700:4700::1111 2001:4860:4860::8888${NC}"
    echo -e "2. 国内DNS优化:"
    echo -e "v4: ${CYAN} 223.5.5.5 114.114.114.114${NC}"
    echo -e "v6: ${CYAN} 2400:3200::1 2400:da00::6666${NC}"
    echo -e "3. 手动编辑DNS配置"
    echo "------------------------"
    echo "0. 返回上一级选单"
    echo "------------------------"
    read -e -p "请输入你的选择: " Limiting
    case "$Limiting" in
      1)
        # 设置国外 DNS 优化
        new_dns="1.1.1.1 8.8.8.8 2606:4700:4700::1111 2001:4860:4860::8888"
        set_dns
        send_stats "国外DNS优化"
        ;;
      2)
        # 设置国内 DNS 优化
        new_dns="223.5.5.5 114.114.114.114 2400:3200::1 2400:da00::6666"
        set_dns
        send_stats "国内DNS优化"
        ;;
      3)
        # 手动编辑DNS配置，允许用户输入新的 DNS
        echo -ne "${YELLOW}请输入新的 DNS（支持多个，空格分隔，留空取消）：${NC}"
        read new_dns
        if [[ -z "$new_dns" ]]; then
          echo -e "${GREEN}未输入，取消设置 DNS。${NC}"
          pause_and_back
          continue
        fi
        set_dns
        send_stats "手动编辑DNS配置"
        ;;
      *)
        break
        ;;
    esac
  done
}

# 提示函数，等待用户继续
pause_and_back() {
  read -p "按任意键返回..." -n 1 -s
  clear
}

# 权限提升函数
root_use() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}需要管理员权限，请使用 root 用户执行！${NC}"
    exit 1
  fi
}

# 发送统计信息的函数 (可根据实际需求修改)
send_stats() {
  local action=$1
  # 这里可以添加实际的统计上传或日志记录操作
  echo "发送统计信息：$action"
}

# 主执行逻辑
set_dns_ui
