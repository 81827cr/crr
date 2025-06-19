#!/usr/bin/env bash
set -euo pipefail

### 恢复脚本：restore_vkvm.sh ###
# 用途：从 rclone 远端下载并恢复 vkvm 备份

# 定义脚本所在目录，用于后续路径引用
declare SCRIPT_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. 检查 rclone 是否安装
if ! command -v rclone >/dev/null 2>&1; then
  echo "rclone 未安装，正在安装..."
  curl https://rclone.org/install.sh | sudo bash
fi

echo "可用的 rclone remotes："
rclone listremotes

# 2. 询问要恢复的备份名称，必须输入，否则退出
read -rp "输入要恢复的备份名（不含 .zip，例如 vkvm）：" BACKUP_NAME
if [[ -z "$BACKUP_NAME" ]]; then
  echo "未指定备份名，退出脚本。"
  exit 1
fi
BACKUP_ZIP="${BACKUP_NAME}.zip"

# 2.1 询问使用哪个 remote，必须输入，否则退出
read -rp "选择 remote （直接回车退出）：" REMOTE
if [[ -z "$REMOTE" ]]; then
  echo "未指定 remote，退出脚本。"
  exit 1
fi

REMOTE_PATH="vps/backup"

# 2.2 下载备份到脚本目录下的 tmp
mkdir -p "${SCRIPT_DIR}/tmp"
echo "下载 ${REMOTE}:${REMOTE_PATH}/${BACKUP_ZIP} 到 tmp/"
rclone copy "${REMOTE}:${REMOTE_PATH}/${BACKUP_ZIP}" "${SCRIPT_DIR}/tmp/"

# 3. 交互式恢复
cd "${SCRIPT_DIR}/tmp" || exit

# 解压总包
echo "解压 ${BACKUP_ZIP} → tmp/"
unzip -o "${BACKUP_ZIP}"

# 3.1 是否恢复 /root 目录
read -rp "是否恢复 /root 目录？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "解压 root.zip → tmp/"
  unzip -o root.zip
  echo "覆盖 tmp/root/ 到 /root/"
  cp -a root/. /root/
fi

# 3.2 是否恢复 /home 目录
read -rp "是否恢复 /home 目录？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "解压 home.zip → tmp/"
  unzip -o home.zip
  echo "覆盖 tmp/home/ 到 /home/"
  cp -a home/. /home/
fi

# 3.3 是否恢复 SSH 服务端和密钥对
read -rp "是否恢复 SSH 服务端和密钥对？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "设置 /root/.ssh 权限"
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/id_* 2>/dev/null || true
  chmod 644 /root/.ssh/*.pub /root/.ssh/known_hosts /root/.ssh/config 2>/dev/null || true

  echo "配置 /etc/ssh/sshd_config"
  # 删除旧条目
  for key in RSAAuthentication PubkeyAuthentication PermitRootLogin PasswordAuthentication; do
    sed -i "/^${key}/d" /etc/ssh/sshd_config
  done
  # 删除所有包含 Port 的行
  sed -i '/Port/d' /etc/ssh/sshd_config

  # 默认插入 Port 22，用户可覆盖
  sed -i '1iPort 22' /etc/ssh/sshd_config
  read -rp "输入 SSH 端口号 (留空保留默认 22)：" SSH_PORT
  if [[ -n "$SSH_PORT" ]]; then
    sed -i "/^Port /d" /etc/ssh/sshd_config
    sed -i "1iPort ${SSH_PORT}" /etc/ssh/sshd_config
  fi

  # 插入其它认证设置（顺序从底向上）
  sed -i '1iPasswordAuthentication no' /etc/ssh/sshd_config
  sed -i '1iPermitRootLogin yes' /etc/ssh/sshd_config
  sed -i '1iPubkeyAuthentication yes' /etc/ssh/sshd_config
  sed -i '1iRSAAuthentication yes' /etc/ssh/sshd_config

  echo "重启 SSH 服务"
  systemctl restart sshd || service ssh restart
fi

# 4. 恢复 crontab 定时任务
read -rp "是否覆盖当前服务器的 crontab？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "  - 清空当前 crontab 任务"
  crontab -r || true
  echo "  - 导入 tmp/crontab.txt"
  crontab "${SCRIPT_DIR}/tmp/crontab.txt"
fi

# 5. 删除临时目录 tmp
read -rp "是否删除脚本目录下的 tmp？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "删除临时目录 ${SCRIPT_DIR}/tmp"
  rm -rf "${SCRIPT_DIR}/tmp"
fi

echo "所有操作结束！"
