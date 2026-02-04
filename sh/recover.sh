#!/usr/bin/env bash
set -euo pipefail

### 恢复脚本：restore_hk_tar.sh ###
# 用途：从 rclone 远端下载并恢复 vps 备份（tar 归档）

# ===========特定配置===============
DEFAULT_REMOTE_PATH="vps/backup"

declare -A REMOTE_PATH_MAP=(
  ["oss"]="apdd/vps/backup"
  ["bing"]="dps666/vps/backup"
)
# =================================

# 1. 检查 rclone 是否安装
if ! command -v rclone >/dev/null 2>&1; then
  echo "rclone 未安装，正在安装..."
  curl https://rclone.org/install.sh | sudo bash
fi

echo "可用的 rclone remotes："
# 列出所有 rclone 配置
rclone listremotes

# 2. 选择 rclone 配置
echo "请选择一个 rclone 配置："
REMOTE_LIST=( $(rclone listremotes) )
select REMOTE in "${REMOTE_LIST[@]}"; do
  if [[ -n "$REMOTE" ]]; then
    REMOTE="${REMOTE%:}"
    echo "已选择远端配置：$REMOTE"
    break
  else
    echo "无效选择，请重新选择。"
  fi
done

# 根据 remote 选择路径：命中映射则用映射，否则用默认
REMOTE_PATH="${REMOTE_PATH_MAP[$REMOTE]:-$DEFAULT_REMOTE_PATH}"
echo "使用远端路径：${REMOTE}:${REMOTE_PATH}"

# 3. 获取远端目录中的所有备份文件
echo "获取 ${REMOTE}:${REMOTE_PATH} 目录下的备份文件..."
BACKUP_FILES=( $(rclone lsf "${REMOTE}:${REMOTE_PATH}/") )
if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
  echo "该目录没有备份文件，退出脚本。"
  exit 1
fi

# 显示备份文件列表
echo "请选择要恢复的备份文件："
select BACKUP_TAR in "${BACKUP_FILES[@]}"; do
  if [[ -n "$BACKUP_TAR" ]]; then
    echo "已选择备份文件：$BACKUP_TAR"
    break
  else
    echo "无效选择，请重新选择。"
  fi
done

# 4. 下载备份文件到临时目录（固定在 /tmp）
DOWNLOAD_DIR="/tmp/restore_tmp"
mkdir -p "${DOWNLOAD_DIR}"
echo "下载 ${REMOTE}:${REMOTE_PATH}/${BACKUP_TAR} 到 ${DOWNLOAD_DIR}/"
rclone copy "${REMOTE}:${REMOTE_PATH}/${BACKUP_TAR}" "${DOWNLOAD_DIR}/"

# 5. 交互式恢复
cd "${DOWNLOAD_DIR}" || exit

# 解压总包（假设为 tar.gz 或 tar）
echo "解压 ${BACKUP_TAR} → ${DOWNLOAD_DIR}/"
# 支持 .tar.gz 或 .tar
if [[ "$BACKUP_TAR" =~ \.(tar\.gz|tgz)$ ]]; then
  tar -xzvf "$BACKUP_TAR"
elif [[ "$BACKUP_TAR" =~ \.tar$ ]]; then
  tar -xvf "$BACKUP_TAR"
else
  echo "不支持的归档格式：$BACKUP_TAR"
  exit 1
fi

# 5.1 是否恢复 /root 目录
read -rp "是否恢复 /root 目录？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "解压 root.tar.gz →  ${DOWNLOAD_DIR}/"
  tar -xzvf root.tar.gz || tar -xvf root.tar
  echo "覆盖 ${DOWNLOAD_DIR}/root/ 到 /root/"
  cp -a root/. /root/
fi

# 5.2 是否恢复 /home 目录
read -rp "是否恢复 /home 目录？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "解压 home.tar.gz → ${DOWNLOAD_DIR}/"
  tar -xzvf home.tar.gz || tar -xvf home.tar
  echo "覆盖 ${DOWNLOAD_DIR}/home/ 到 /home/"
  cp -a home/. /home/
fi

# 5.3 是否恢复 SSH 服务端和密钥对
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
  sed -i '/^Port/d' /etc/ssh/sshd_config

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

# 6. 恢复 crontab 定时任务
read -rp "是否覆盖当前服务器的 crontab？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "  - 清空当前 crontab 任务"
  crontab -r || true
  echo "  - 导入 ${DOWNLOAD_DIR}/crontab.txt"
  crontab "${DOWNLOAD_DIR}/crontab.txt"
fi

# 7. 删除临时目录 tmp
read -rp "是否删除脚本目录下的 ${DOWNLOAD_DIR}？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "删除临时目录 ${DOWNLOAD_DIR}"
  rm -rf "${DOWNLOAD_DIR}"
fi

echo "所有操作结束！"
