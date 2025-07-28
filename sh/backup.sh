#!/usr/bin/env bash
set -euo pipefail

### === 配置区 === ###
# 最大保留备份数量（每个机器名前缀）
MAX_BACKUPS=2

# rclone 目标目录（路径尾部不要加斜杠）
PIKPAK_REMOTE="pikpak:vps/backup"
ONEDRIVE_REMOTE="onedrive:vps/backup"
S3_REMOTE="bing:dps666/vps/backup"

# 排除与包含模式 — 请根据需求编辑
# /root 目录：排除所有隐藏文件与媒体文件，但保留 .config 与 .ssh
ROOT_EXCLUDES=(
  --exclude='root/.*'
  --exclude='*.mp4'
  --exclude='*.mp3'
)
ROOT_INCLUDES=(
  --include='root/.config/**'
  --include='root/.ssh/**'
)

# /home 目录：排除指定目录与媒体文件
HOME_EXCLUDES=(
  --exclude='home/d/**'
  --exclude='home/tmp/**'
  --exclude='home/lu/**'
  --exclude='home/live/downloads/**'
  --exclude='*.mp4'
  --exclude='*.mp3'
)
# 如需强制保留某些内容，可在此添加 --include 模式
HOME_INCLUDES=()
### =============== ###

# 参数获取：备份前缀
if [[ $# -ge 1 ]]; then
  BACKUP_PREFIX="$1"
else
  read -rp "请输入备份名称（如 dc02）: " BACKUP_PREFIX
  [[ -z "${BACKUP_PREFIX}" ]] && echo "错误：备份名称不能为空！" && exit 1
fi

NOW=$(date +"%Y%m%d%H%M")
FINAL_TAR="${BACKUP_PREFIX}-${NOW}.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 中间文件
ROOT_TAR="root.tar.gz"
HOME_TAR="home.tar.gz"
CRONTAB_FILE="crontab.txt"

echo "[$(date '+%F %T')] 开始备份：${FINAL_TAR}"
rm -f "${ROOT_TAR}" "${HOME_TAR}" "${CRONTAB_FILE}"

# 1. 打包 /root
echo "  - 打包 /root → ${ROOT_TAR}"
cd /
tar -zcvf "${SCRIPT_DIR}/${ROOT_TAR}" \
  "${ROOT_EXCLUDES[@]}" \
  "${ROOT_INCLUDES[@]}" \
  -C / root || echo "  ! /root 打包过程中有文件变动，已继续"
cd "${SCRIPT_DIR}"

# 2. 导出 crontab
echo "  - 导出 crontab → ${CRONTAB_FILE}"
crontab -l > "${CRONTAB_FILE}" || true

# 3. 打包 /home
echo "  - 打包 /home → ${HOME_TAR}"
cd /
tar -zcvf "${SCRIPT_DIR}/${HOME_TAR}" \
  "${HOME_EXCLUDES[@]}" \
  "${HOME_INCLUDES[@]}" \
  --warning=no-file-changed \
  -C / home || echo "  ! /home 部分文件在读取时已变动"
cd "${SCRIPT_DIR}"

# 4. 合并备份
echo "  - 合并中间文件 → ${FINAL_TAR}"
tar -zcvf "${FINAL_TAR}" "${ROOT_TAR}" "${HOME_TAR}" "${CRONTAB_FILE}"

# 5. 删除中间文件
echo "  - 清理中间文件"
rm -f "${ROOT_TAR}" "${HOME_TAR}" "${CRONTAB_FILE}"

# 6. 上传并清理远端
for REMOTE in "${PIKPAK_REMOTE}" "${ONEDRIVE_REMOTE}" "${S3_REMOTE}"; do
  echo "  - 上传 ${FINAL_TAR} → ${REMOTE}"
  if rclone copy "${FINAL_TAR}" "${REMOTE}/"; then
    echo "    > 上传成功"
  else
    echo "    ! 上传失败，继续下一个"
    continue
  fi

  echo "  - 保留最新 ${MAX_BACKUPS} 份：前缀 ${BACKUP_PREFIX}-"
  BACKUPS=$(rclone lsf "${REMOTE}/" | grep "^${BACKUP_PREFIX}-.*\.tar\.gz\$" | sort)
  COUNT=$(echo "${BACKUPS}" | wc -l)
  if (( COUNT > MAX_BACKUPS )); then
    echo "    - 删除旧备份 $((COUNT - MAX_BACKUPS)) 个"
    echo "${BACKUPS}" | head -n $((COUNT - MAX_BACKUPS)) | while read -r OLD; do
      echo "      删除：${OLD}"
      rclone deletefile "${REMOTE}/${OLD}" || echo "        ! 删除失败"
    done
  else
    echo "    无需清理（当前 $COUNT 个）"
  fi
done

# 7. 删除本地最终备份
echo "  - 删除本地 ${FINAL_TAR}"
rm -f "${FINAL_TAR}"

echo "[$(date '+%F %T')] 备份完成！"
