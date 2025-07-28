#!/usr/bin/env bash
set -euo pipefail

### 恢复脚本：restore_vps.sh ###
# 用途：从 rclone 远端下载并恢复 vps 备份

# 定义脚本所在目录，用于后续路径引用
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] 脚本目录：${SCRIPT_DIR}"

# 1. 检查 rclone 是否安装
if ! command -v rclone >/dev/null 2>&1; then
  echo "[INFO] rclone 未安装，正在安装..."
  curl https://rclone.org/install.sh | sudo bash
fi

# 列出可用 rclone remotes
echo "[INFO] 可用的 rclone remotes："
rclone listremotes

# 2. 选择 rclone 配置
echo "[INPUT] 请选择一个 rclone 配置："
mapfile -t REMOTE_LIST < <(rclone listremotes | sed 's/:$//')
select REMOTE in "${REMOTE_LIST[@]}"; do
  if [[ -n "$REMOTE" ]]; then
    echo "[INFO] 已选择远端配置：${REMOTE}"
    break
  else
    echo "[WARN] 无效选择，请重新选择。"
  fi
done

REMOTE_PATH="vps/backup"

# 3. 获取远端目录中的所有备份文件
echo "[INFO] 获取 ${REMOTE}:${REMOTE_PATH} 下的备份文件列表..."
mapfile -t ARCHIVES < <(rclone lsf "${REMOTE}:${REMOTE_PATH}/" | grep -E '\.tar\.gz$')
if [[ ${#ARCHIVES[@]} -eq 0 ]]; then
  echo "[ERROR] 该目录没有 .tar.gz 备份文件，退出脚本。"
  exit 1
fi

# 选择要恢复的备份文件
echo "[INPUT] 请选择要恢复的备份文件："
select BACKUP_ARCHIVE in "${ARCHIVES[@]}"; do
  if [[ -n "$BACKUP_ARCHIVE" ]]; then
    echo "[INFO] 已选择：${BACKUP_ARCHIVE}"
    break
  else
    echo "[WARN] 无效选择，请重新选择。"
  fi
done

# 4. 下载备份文件到临时目录
TMP_DIR="${SCRIPT_DIR}/tmp"
mkdir -p "${TMP_DIR}"
echo "[INFO] 下载 ${REMOTE}:${REMOTE_PATH}/${BACKUP_ARCHIVE} 到 ${TMP_DIR}/"
rclone copy "${REMOTE}:${REMOTE_PATH}/${BACKUP_ARCHIVE}" "${TMP_DIR}/"

# 5. 交互式恢复
cd "${TMP_DIR}" || exit

echo "[INFO] 解压 ${BACKUP_ARCHIVE} 到 ${TMP_DIR}/"
tar -zxf "${BACKUP_ARCHIVE}"

# 5.1 恢复 /root
echo "\n—— 恢复 /root ——"
read -rp "是否恢复 /root 目录？ [y/N] (默认 N): " ans_root
if [[ "${ans_root,,}" == y* ]]; then
  echo "[INFO] 解压 root.tar.gz 到 root/"
  mkdir -p root
  tar -zxf root.tar.gz -C root
  echo "[INFO] 覆盖 root/. 到 /root/"
  cp -a root/. /root/
else
  echo "[INFO] 删除 /root/.ssh 下所有内容"
  rm -rf /root/.ssh/*
fi

# 5.2 恢复 /home
echo "\n—— 恢复 /home ——"
read -rp "是否恢复 /home 目录？ [y/N] (默认 N): " ans_home
if [[ "${ans_home,,}" == y* ]]; then
  echo "[INFO] 解压 home.tar.gz 到 home/"
  mkdir -p home
  tar -zxf home.tar.gz -C home
  echo "[INFO] 覆盖 home/. 到 /home/"
  cp -a home/. /home/
fi

# 5.3 恢复 SSH 服务端和密钥对
echo "\n—— 恢复 SSH 服务端和密钥对 ——"
read -rp "是否恢复 SSH 服务端和密钥对？ [y/N] (默认 N): " ans_ssh
if [[ "${ans_ssh,,}" == y* ]]; then
  # 使用已解压的或直接提取 .ssh
  if [[ -d root/.ssh ]]; then
    echo "[INFO] 覆盖 root/.ssh 到 /root/.ssh"
    rm -rf /root/.ssh
    cp -a root/.ssh /root/.ssh
  else
    echo "[INFO] 从 root.tar.gz 中提取 .ssh"
    mkdir -p tmp_extract
    tar -zxf root.tar.gz -C tmp_extract ".ssh"
    rm -rf /root/.ssh
    cp -a tmp_extract/.ssh /root/.ssh
    rm -rf tmp_extract
  fi

  echo "[INFO] 设置 /root/.ssh 权限"
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/id_* 2>/dev/null || true
  chmod 644 /root/.ssh/*.pub /root/.ssh/known_hosts /root/.ssh/config 2>/dev/null || true

  echo "[INFO] 配置 /etc/ssh/sshd_config"
  for key in RSAAuthentication PubkeyAuthentication PermitRootLogin PasswordAuthentication; do
    sed -i "/^${key}/d" /etc/ssh/sshd_config
  done
  sed -i '/^Port/d' /etc/ssh/sshd_config

  # 默认 Port 22，用户可覆盖
  SSH_PORT=22
  read -rp "输入 SSH 端口号 (留空保留默认 22): " input_port
  if [[ -n "$input_port" ]]; then
    SSH_PORT="$input_port"
  fi
  sed -i "1iPort ${SSH_PORT}" /etc/ssh/sshd_config
  sed -i '1iPasswordAuthentication no' /etc/ssh/sshd_config
  sed -i '1iPermitRootLogin yes' /etc/ssh/sshd_config
  sed -i '1iPubkeyAuthentication yes' /etc/ssh/sshd_config
  sed -i '1iRSAAuthentication yes' /etc/ssh/sshd_config

  echo "[INFO] 重启 SSH 服务"
  systemctl restart sshd || service ssh restart

  # 放行 SSH 端口，直接执行，不做存在性检查
  echo "[INFO] ufw 放行 SSH 端口 ${SSH_PORT}"
  ufw allow ${SSH_PORT}
fi

# 6. 恢复 crontab
echo "\n—— 恢复 crontab ——"
read -rp "是否覆盖当前服务器的 crontab？ [y/N] (默认 N): " ans_cron
if [[ "${ans_cron,,}" == y* ]]; then
  echo "[INFO] 清空当前 crontab 任务"
  crontab -r || true
  echo "[INFO] 导入 ${TMP_DIR}/crontab.txt"
  crontab "${TMP_DIR}/crontab.txt"
fi

# 7. 清理临时目录
echo "\n—— 清理临时目录 ——"
read -rp "是否删除临时目录 tmp？ [y/N] (默认 N): " ans_clean
if [[ "${ans_clean,,}" == y* ]]; then
  echo "[INFO] 删除临时目录 ${TMP_DIR}"
  rm -rf "${TMP_DIR}"
fi

echo "[INFO] 恢复完成！"
