#!/bin/bash
set -e

echo -e "\033[1;32m==== SSH 密钥登录设置脚本 ====\033[0m"

SSH_CONFIG="/etc/ssh/sshd_config"

# === 1. 生成密钥对（若不存在） ===
if [ ! -f ~/.ssh/id_rsa ]; then
  echo -e "\033[1;34m[1/6] 正在生成 SSH 密钥对...\033[0m"
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
else
  echo -e "\033[1;33m已存在 SSH 密钥对，跳过生成...\033[0m"
fi

# === 2. 安装公钥 ===
echo -e "\033[1;34m[2/6] 安装公钥到 authorized_keys...\033[0m"
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# === 3. 提示修改端口 ===
read -p "是否修改 SSH 默认端口（22）？(y/n): " change_port
if [[ "$change_port" =~ ^[Yy]$ ]]; then
  read -p "请输入新的 SSH 端口（例如 39922）: " NEW_PORT
else
  NEW_PORT=22
fi

# === 4. 清理旧配置并添加新配置 ===
echo -e "\033[1;34m[3/6] 更新 SSH 配置文件...\033[0m"

# 删除旧配置项（包括注释行）
for opt in Port PasswordAuthentication PermitRootLogin RSAAuthentication PubkeyAuthentication; do
  sed -i "/^#*\s*$opt\s\+/d" "$SSH_CONFIG"
done

# 添加新配置
echo "" >> "$SSH_CONFIG"
echo "# === custom ssh settings ===" >> "$SSH_CONFIG"
echo "Port $NEW_PORT" >> "$SSH_CONFIG"
echo "PasswordAuthentication no" >> "$SSH_CONFIG"
echo "PermitRootLogin yes" >> "$SSH_CONFIG"
echo "RSAAuthentication yes" >> "$SSH_CONFIG"
echo "PubkeyAuthentication yes" >> "$SSH_CONFIG"

# === 5. 设置防火墙 ===
echo -e "\033[1;34m[4/6] 设置防火墙规则...\033[0m"
if command -v ufw &>/dev/null; then
  ufw allow "$NEW_PORT"/tcp || true
else
  iptables -C INPUT -p tcp --dport "$NEW_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$NEW_PORT" -j ACCEPT
fi

# === 6. 重启 SSH ===
echo -e "\033[1;34m[5/6] 重启 SSH 服务...\033[0m"
systemctl restart sshd || service sshd restart

# === 7. 输出私钥内容 ===
echo -e "\n\033[1;32m[6/6] 配置完成！请保存以下私钥内容：\033[0m"
echo -e "\033[1;31m↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓\033[0m"
cat ~/.ssh/id_rsa
echo -e "\033[1;31m↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑\033[0m"
echo -e "\n\033[1;32m请妥善保存该私钥文件，否则将无法再次登录本机。\033[0m"
