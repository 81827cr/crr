#!/usr/bin/env bash
set -euo pipefail

### 恢复脚本：restore_vkvm.sh ###
# 用途：从 rclone 远端下载并恢复 vkvm 备份

# 1. 检查 rclone 是否安装
if ! command -v rclone >/dev/null 2>&1; then
  echo "rclone 未安装，正在安装..."
  curl https://rclone.org/install.sh | sudo bash
fi

echo "当前 rclone remotes："
rclone listremotes

# 2. 询问要恢复的备份名称
read -rp "输入要恢复的备份名（不含 .zip，例如 vkvm，默认 vkvm）：" BACKUP_NAME
BACKUP_NAME="${BACKUP_NAME:-vkvm}"

# 2.1 询问使用哪个 remote
read -rp "输入存储名称（例如 pikpak 或 onedrive 或 bing）：" REMOTE

REMOTE_PATH="vps/backup"
BACKUP_ZIP="${BACKUP_NAME}.zip"

# 2.2 下载备份到脚本目录下的 tmp
mkdir -p tmp
echo "下载 ${REMOTE}:${REMOTE_PATH}/${BACKUP_ZIP} 到 tmp/"
rclone copy "${REMOTE}:${REMOTE_PATH}/${BACKUP_ZIP}" tmp/

# 3. 交互式恢复
cd tmp || exit

# 解压总包
echo "解压 ${BACKUP_ZIP} → tmp/"
unzip -o "${BACKUP_ZIP}"

# 3.1 询问是否恢复 root
read -rp "是否恢复 /root 目录？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "解压 root.zip → tmp/"
  unzip -o root.zip
  echo "覆盖 tmp/root/ 到 /root/"
  cp -a root/. /root/
fi

# 3.2 询问是否恢复 home
read -rp "是否恢复 /home 目录？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "解压 home.zip → tmp/"
  unzip -o home.zip
  echo "覆盖 tmp/home/ 到 /home/"
  cp -a home/. /home/
fi

# 3.3 询问是否恢复 SSH 配置和密钥
read -rp "是否恢复 SSH 服务端和密钥对？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "设置 /root/.ssh 权限"
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/id_* 2>/dev/null || true
  chmod 644 /root/.ssh/*.pub /root/.ssh/known_hosts /root/.ssh/config 2>/dev/null || true

  echo "配置 /etc/ssh/sshd_config"
  # 删除旧条目
  for key in RSAAuthentication PubkeyAuthentication PermitRootLogin PasswordAuthentication; do
    sudo sed -i "/^${key}/d" /etc/ssh/sshd_config
  done
  # 插入新配置到文件头
  sudo sed -i '1iPasswordAuthentication no' /etc/ssh/sshd_config
  sudo sed -i '1iPermitRootLogin yes' /etc/ssh/sshd_config
  sudo sed -i '1iPubkeyAuthentication yes' /etc/ssh/sshd_config
  sudo sed -i '1iRSAAuthentication yes' /etc/ssh/sshd_config

  echo "重启 SSH 服务"
  sudo systemctl restart sshd || sudo service ssh restart
fi

echo "恢复完成，tmp/ 中保留解压内容，可按需手动清理。"

# 4. 恢复 crontab 定时任务
read -rp "是否覆盖当前服务器的 crontab？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "  - 清空当前 crontab 任务"
  crontab -r || true
  echo "  - 导入 tmp/crontab.txt"
  crontab "${SCRIPT_DIR}/tmp/crontab.txt"
fi

# 4. 删除临时目录 tmp
read -rp "是否删除脚本目录下的 tmp？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "删除临时目录 ${SCRIPT_DIR}/tmp"
  rm -rf "${SCRIPT_DIR}/tmp"
fi

echo "所有操作结束！"
