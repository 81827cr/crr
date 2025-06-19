#!/bin/bash

# 确保以 root 身份运行
if [[ $EUID -ne 0 ]]; then
  echo "请以 root 用户运行此脚本" >&2
  exit 1
fi

# 持久化脚本路径
IPTABLES_SCRIPT="/root/sh/iptables.sh"
mkdir -p "$(dirname "$IPTABLES_SCRIPT")"

# 如果脚本不存在，创建并写入 shebang，然后赋可执行权限
if [[ ! -f "$IPTABLES_SCRIPT" ]]; then
  cat > "$IPTABLES_SCRIPT" <<'EOF'
#!/bin/bash
# 本脚本用于重启时恢复 iptables 转发规则
EOF
  chmod +x "$IPTABLES_SCRIPT"
fi

# 功能菜单
echo "请选择操作："
echo "1) 创建端口转发"
echo "2) 查看 iptables NAT 规则"
read -rp "请输入选项 (1 或 2): " choice

case "$choice" in
  1)
    # 1. 输入中转机监听端口
    read -rp "请输入中转机监听端口 (1-65535): " forward_port
    if [[ -z "$forward_port" || ! "$forward_port" =~ ^[0-9]+$ || "$forward_port" -lt 1 || "$forward_port" -gt 65535 ]]; then
      echo "❌ 无效端口，脚本退出"
      exit 1
    fi

    # 2. 输入落地机 IP
    read -rp "请输入落地机的 IP 地址: " target_ip
    if [[ -z "$target_ip" ]]; then
      echo "❌ IP 地址不能为空，脚本退出"
      exit 1
    fi

    # 3. 输入落地机端口
    read -rp "请输入落地机的端口 (1-65535): " target_port
    if [[ -z "$target_port" || ! "$target_port" =~ ^[0-9]+$ || "$target_port" -lt 1 || "$target_port" -gt 65535 ]]; then
      echo "❌ 无效端口，脚本退出"
      exit 1
    fi

    echo "✅ 开始配置..."

    # 步骤1：开启 IP 转发并保存配置
    echo ">>> 开启 IP 转发..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    # 步骤4：设置 UFW 允许 FORWARD
    echo ">>> 设置 UFW 允许 FORWARD..."
    ufw default allow FORWARD

    # 步骤2：实时添加 iptables 规则
    echo ">>> 添加实时 iptables 规则..."
    iptables -t nat -A PREROUTING -p tcp --dport "$forward_port" -j DNAT --to-destination "$target_ip":"$target_port"
    iptables -t nat -A POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j MASQUERADE

    # 构造规则文本
    RULE1="iptables -t nat -A PREROUTING -p tcp --dport $forward_port -j DNAT --to-destination $target_ip:$target_port"
    RULE2="iptables -t nat -A POSTROUTING -p tcp -d $target_ip --dport $target_port -j MASQUERADE"

    # 步骤3：追加到持久化脚本（去重）
    echo ">>> 写入持久化脚本 $IPTABLES_SCRIPT ..."
    grep -Fxq "$RULE1" "$IPTABLES_SCRIPT" || echo "$RULE1" >> "$IPTABLES_SCRIPT"
    grep -Fxq "$RULE2" "$IPTABLES_SCRIPT" || echo "$RULE2" >> "$IPTABLES_SCRIPT"

    # 设置 crontab：检测是否已有这条 @reboot，若无则添加
    echo ">>> 配置 crontab 自启动..."
    CRON_LINE="@reboot $IPTABLES_SCRIPT"
    crontab -l 2>/dev/null | grep -Fxq "$CRON_LINE" \
      || ( crontab -l 2>/dev/null; echo "$CRON_LINE" ) | crontab -

    echo "✅ 转发配置完成！"
    ;;
  2)
    echo "📋 当前 iptables nat 规则如下："
    iptables -t nat -L -n --line-numbers
    ;;
  *)
    echo "❌ 无效选择，脚本退出"
    exit 1
    ;;
esac
