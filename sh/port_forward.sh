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

# 如果脚本不存在，初始化持久化脚本（保持与你原脚本完全一致）
if [[ ! -f "$IPTABLES_SCRIPT" ]]; then
  cat > "$IPTABLES_SCRIPT" <<'EOF'
#!/bin/bash
# 本脚本用于重启时恢复 iptables 转发规则

# 开启 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1
# 确保 IPv6 转发已启用（若你需要 IPv6 转发）
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
sysctl -w net.ipv6.conf.all.forwarding=1 || true

# 设置 UFW 允许 FORWARD（如已安装 UFW）
ufw default allow FORWARD || true

# 清空已有的 NAT 规则
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# 如果系统支持 IPv6 nat 表，则同时清空 IPv6 nat（避免重复追加）
if ip6tables -t nat -L >/dev/null 2>&1; then
  ip6tables -t nat -F PREROUTING || true
  ip6tables -t nat -F POSTROUTING || true
fi
# iptables规则追加
EOF
  chmod +x "$IPTABLES_SCRIPT"
fi

# ---------- 保持原 IPv4 行为不变，封装为函数（函数内部行为与原脚本完全相同） ----------
configure_ipv4_forward() {
  # 参数： forward_port target_port target_ip open_port_choice
  local forward_port="$1"
  local target_port="$2"
  local target_ip="$3"
  local open_port_choice="${4:-y}"

  if [[ "$open_port_choice" =~ ^[Yy]$ ]]; then
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
  local RULE1="iptables -t nat -A PREROUTING -p tcp --dport $forward_port -j DNAT --to-destination $target_ip:$target_port"
  local RULE2="iptables -t nat -A POSTROUTING -p tcp -d $target_ip --dport $target_port -j MASQUERADE"

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
}

# ---------- 新增 IPv6 函数（照葫芦画瓢，但为独立选项，不改动原 IPv4 行为） ----------
configure_ipv6_forward() {
  # 参数： forward_port target_port target_ip6 open_port_choice
  local forward_port="$1"
  local target_port="$2"
  local target_ip6="$3"
  local open_port_choice="${4:-y}"

  # 简单判断
  if [[ -z "$target_ip6" || "$target_ip6" != *":"* ]]; then
    echo "❌ 提供的目标地址看起来不是 IPv6 地址：$target_ip6"
    return 1
  fi

  if [[ "$open_port_choice" =~ ^[Yy]$ ]]; then
    echo ">>> UFW：允许端口 $forward_port"
    ufw allow "$forward_port" || true
  fi

  echo "✅ 开始配置 IPv6 转发..."

  # 步骤1：开启 IPv6 转发并写入 sysctl
  echo ">>> 开启 IPv6 转发..."
  echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
  sed -i '/^net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf
  echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
  sysctl -p || true

  # 步骤2：设置 UFW FORWARD
  echo ">>> UFW：允许转发（FORWARD）"
  ufw default allow FORWARD || true

  # 构造 IPv6 规则（与 IPv4 结构类似）
  local RULE1_V6="ip6tables -t nat -A PREROUTING -p tcp --dport ${forward_port} -j DNAT --to-destination [${target_ip6}]:${target_port}"
  local RULE2_V6="ip6tables -t nat -A POSTROUTING -p tcp -d ${target_ip6} --dport ${target_port} -j MASQUERADE"

  # 检查 ip6tables nat 表支持
  if ! ip6tables -t nat -L >/dev/null 2>&1; then
    echo "⚠️ 系统当前不支持 ip6tables nat 表，无法添加 IPv6 DNAT/MASQUERADE。"
    echo "请考虑使用 nftables 或代理工具（socat/xray/redsocks 等）作为替代。"
    return 1
  fi

  # 写入持久化脚本（去重）
  echo ">>> 写入持久化脚本 $IPTABLES_SCRIPT（IPv6 规则）"
  grep -Fxq "$RULE1_V6" "$IPTABLES_SCRIPT" || echo "$RULE1_V6" >> "$IPTABLES_SCRIPT"
  grep -Fxq "$RULE2_V6" "$IPTABLES_SCRIPT" || echo "$RULE2_V6" >> "$IPTABLES_SCRIPT"

  # 清空现有 IPv6 NAT 规则并重载
  echo ">>> 清空现有 IPv6 NAT 规则..."
  ip6tables -t nat -F PREROUTING || true
  ip6tables -t nat -F POSTROUTING || true

  # 更新同一个 systemd 服务以执行持久化脚本
  echo ">>> 生成/更新 systemd 服务 $SYSTEMD_SERVICE"
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

  echo ">>> 重新加载并启动服务..."
  systemctl daemon-reload
  systemctl enable iptables-restore.service
  systemctl restart iptables-restore.service

  echo "✅ IPv6 转发配置完成并已持久化！"
}

# ---------- 菜单（保持你原脚本的选项 1/2 不变；新增 3 为 IPv6） ----------
echo "请选择操作："
echo "1) 创建端口转发"
echo "2) 创建 IPv6 端口转发"
echo "3) 查看 iptables NAT 规则"
echo "4) 查看 IPv6 iptables NAT 规则"
read -rp "请输入选项: " choice

case "$choice" in
  1)
    # 与你原脚本完全相同的交互（未改动任何提示或默认行为）
    read -rp "请输入中转机监听端口 (1-65535): " forward_port
    [[ ! "$forward_port" =~ ^[1-9][0-9]{0,4}$ ]] && { echo "❌ 无效端口"; exit 1; }
    read -rp "请输入落地机的端口 (1-65535): " target_port
    [[ ! "$target_port" =~ ^[1-9][0-9]{0,4}$ ]] && { echo "❌ 无效端口"; exit 1; }
    read -rp "请输入落地机的 IP 地址: " target_ip
    [[ -z "$target_ip" ]] && { echo "❌ IP 不能为空"; exit 1; }

    # 是否开放防火墙端口
    read -rp "是否开启防火墙允许端口 $forward_port? (y/n，默认 y): " open_port
    open_port=${open_port:-y}
    if [[ "$open_port" =~ ^[Yy]$ ]]; then
      echo ">>> UFW：允许端口 $forward_port"
      ufw allow "$forward_port" || true
    fi

    # 调用保持原样的函数
    configure_ipv4_forward "$forward_port" "$target_port" "$target_ip" "$open_port"
    ;;

  

  2)
    # IPv6 交互：新增项（不会影响现有 1/2 行为）
    read -rp "请输入中转机监听端口 (1-65535): " forward_port
    [[ ! "$forward_port" =~ ^[1-9][0-9]{0,4}$ ]] && { echo "❌ 无效端口"; exit 1; }
    read -rp "请输入落地机的端口 (1-65535): " target_port
    [[ ! "$target_port" =~ ^[1-9][0-9]{0,4}$ ]] && { echo "❌ 无效端口"; exit 1; }
    read -rp "请输入落地机的 IPv6 地址: " target_ip6
    [[ -z "$target_ip6" ]] && { echo "❌ IPv6 不能为空"; exit 1; }
    read -rp "是否开启防火墙允许端口 $forward_port? (y/n，默认 y): " open_port
    open_port=${open_port:-y}

    configure_ipv6_forward "$forward_port" "$target_port" "$target_ip6" "$open_port"
    ;;

  3)
    echo "📋 当前 iptables nat 规则："
    iptables -t nat -L -n --line-numbers
    ;;
  
  4)
    echo "📋 当前 iptables nat 规则："
    ip6tables -t nat -L -n --line-numbers
    ;;

  *)
    echo "❌ 无效选择，脚本退出"
    exit 1
    ;;
esac

