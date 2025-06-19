#!/bin/bash

# 确保以 root 身份运行
if [[ $EUID -ne 0 ]]; then
  echo "请以 root 用户运行此脚本" >&2
  exit 1
fi

# 定义路径
IPTABLES_SCRIPT="/root/sh/iptables.sh"
SYSTEMD_SERVICE="/etc/systemd/system/iptables-restore.service"
mkdir -p "$(dirname "$IPTABLES_SCRIPT")"

# 如果脚本不存在，初始化持久化脚本
if [[ ! -f "$IPTABLES_SCRIPT" ]]; then
  cat > "$IPTABLES_SCRIPT" <<'EOF'
#!/bin/bash
# 本脚本用于重启时恢复 iptables 转发规则

# 开启 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1

# 设置 UFW 允许 FORWARD（如已安装 UFW）
ufw default allow FORWARD || true

# 清空已有的 NAT 规则
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING
EOF
  chmod +x "$IPTABLES_SCRIPT"
fi

# 菜单
echo "请选择操作："
echo "1) 创建端口转发"
echo "2) 查看 iptables NAT 规则"
read -rp "请输入选项 (1 或 2): " choice

case "$choice" in
  1)
    # 输入校验
    read -rp "请输入中转机监听端口 (1-65535): " forward_port
    [[ ! "$forward_port" =~ ^[1-9][0-9]{0,4}$ ]] && { echo "❌ 无效端口"; exit 1; }
    read -rp "请输入落地机的 IP 地址: " target_ip
    [[ -z "$target_ip" ]] && { echo "❌ IP 不能为空"; exit 1; }
    read -rp "请输入落地机的端口 (1-65535): " target_port
    [[ ! "$target_port" =~ ^[1-9][0-9]{0,4}$ ]] && { echo "❌ 无效端口"; exit 1; }

    # 是否开放防火墙端口
    read -rp "是否开启防火墙允许端口 $forward_port? (y/n，默认 y): " open_port
    open_port=${open_port:-y}
    if [[ "$open_port" =~ ^[Yy]$ ]]; then
      echo ">>> UFW：允许端口 $forward_port"
      ufw allow "$forward_port" || true
    fi

    echo "✅ 开始配置..."

    # 步骤1：开启 IP 转发并写入 sysctl
    echo ">>> 开启 IP 转发..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    # 步骤2：设置 UFW FORWARD
    echo ">>> UFW：允许转发（FORWARD）"
    ufw default allow FORWARD || true

    # 构造规则文本
    RULE1="iptables -t nat -A PREROUTING -p tcp --dport $forward_port -j DNAT --to-destination $target_ip:$target_port"
    RULE2="iptables -t nat -A POSTROUTING -p tcp -d $target_ip --dport $target_port -j MASQUERADE"

    # 步骤3：写入持久化脚本（去重）
    echo ">>> 写入持久化脚本 $IPTABLES_SCRIPT"
    grep -Fxq "$RULE1" "$IPTABLES_SCRIPT" || echo "$RULE1" >> "$IPTABLES_SCRIPT"
    grep -Fxq "$RULE2" "$IPTABLES_SCRIPT" || echo "$RULE2" >> "$IPTABLES_SCRIPT"

    # 步骤4：清空现有 NAT 规则，再重启 systemd 服务重新加载
    echo ">>> 清空现有 NAT 规则..."
    iptables -t nat -F PREROUTING
    iptables -t nat -F POSTROUTING

    # 步骤5：创建/更新 systemd 服务文件
    echo ">>> 生成 systemd 服务 $SYSTEMD_SERVICE"
    cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Restore iptables NAT rules after boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$IPTABLES_SCRIPT
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    # 步骤6：启用并启动 service
    echo ">>> 重新加载并启动服务..."
    systemctl daemon-reload
    systemctl enable iptables-restore.service
    systemctl restart iptables-restore.service

    echo "✅ 转发配置完成并已持久化！"
    ;;

  2)
    echo "📋 当前 iptables nat 规则："
    iptables -t nat -L -n --line-numbers
    ;;

  *)
    echo "❌ 无效选择，脚本退出"
    exit 1
    ;;
esac
