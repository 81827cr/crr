#!/usr/bin/env bash
set -euo pipefail

### === 配置区 === ###
# 最大保留备份数量（每个机器名前缀）
MAX_BACKUPS=2

# rclone 目标目录（路径尾部不要加斜杠）
PIKPAK_REMOTE="pikpak:vps/backup"
ONEDRIVE_REMOTE="onedrive:vps/backup"
S3_REMOTE="bing:dps666/vps/backup"
### =============== ###

# === 参数获取：备份名 ===
if [[ $# -ge 1 ]]; then
  BACKUP_PREFIX="$1"
else
  read -rp "请输入备份名称（如 dc02）: " BACKUP_PREFIX
  [[ -z "${BACKUP_PREFIX}" ]] && echo "错误：备份名称不能为空！" && exit 1
fi

# 当前时间戳
NOW=$(date "+%Y%m%d%H%M")
FINAL_ZIP="${BACKUP_PREFIX}-${NOW}.zip"

# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 临时文件名
ROOT_ZIP="root.zip"
HOME_ZIP="home.zip"
CRONTAB_FILE="crontab.txt"

echo "[$(date '+%F %T')] 开始备份：${FINAL_ZIP}"

# —— 清理旧临时文件 ——
rm -f "${ROOT_ZIP}" "${HOME_ZIP}" "${CRONTAB_FILE}"

# —— 1. 打包 /root ——
echo "  - 打包 /root → ${ROOT_ZIP}"
cd /
EXCLUDES=( -x "root/.*" -x "*.mp4" "*.mp3" )
if [[ "${SCRIPT_DIR}" == /root/* && "${SCRIPT_DIR}" != "/root" ]]; then
  REL_SCRIPT_DIR="${SCRIPT_DIR#/}"
  EXCLUDES+=( -x "${REL_SCRIPT_DIR}/**" )
fi
zip -r "${SCRIPT_DIR}/${ROOT_ZIP}" root "${EXCLUDES[@]}"
zip -r "${SCRIPT_DIR}/${ROOT_ZIP}" root/.config -x "*.mp4" "*.mp3" || true
zip -r "${SCRIPT_DIR}/${ROOT_ZIP}" root/.ssh -x "*.mp4" "*.mp3" || true
cd "${SCRIPT_DIR}"

# —— 2. 导出 crontab ——
echo "  - 导出 crontab → ${CRONTAB_FILE}"
crontab -l > "${CRONTAB_FILE}" || true

# —— 3. 打包 /home ——
echo "  - 打包 /home → ${HOME_ZIP}"
cd /
zip -r "${SCRIPT_DIR}/${HOME_ZIP}" home \
    -x "home/d/**" "home/tmp/**" "home/lu/**" "home/live/downloads/**" \
    -x "home/posteio/mail-data/**" \
    -x "*.mp4" "*.mp3"
cd "${SCRIPT_DIR}"

# —— 4. 合并文件为最终备份 ——
echo "  - 合并中间文件 → ${FINAL_ZIP}"
zip "${FINAL_ZIP}" "${ROOT_ZIP}" "${HOME_ZIP}" "${CRONTAB_FILE}"

# —— 5. 删除中间文件 ——
rm -f "${ROOT_ZIP}" "${HOME_ZIP}" "${CRONTAB_FILE}"

# —— 6. 上传到各个远端 ——
for REMOTE in "${PIKPAK_REMOTE}" "${ONEDRIVE_REMOTE}" "${S3_REMOTE}"; do
  echo "  - 上传 ${FINAL_ZIP} → ${REMOTE}"
  if rclone copy "${FINAL_ZIP}" "${REMOTE}/"; then
    echo "    > 上传成功"
  else
    echo "    ! 上传失败，继续下一个"
    continue
  fi

  # —— 7. 删除远端旧备份，仅保留最新 N 份 ——
  echo "  - 保留最新 ${MAX_BACKUPS} 份备份：前缀 ${BACKUP_PREFIX}-"
  BACKUPS=$(rclone lsf "${REMOTE}/" | grep "^${BACKUP_PREFIX}-.*\.zip$" | sort)
  BACKUP_COUNT=$(echo "$BACKUPS" | wc -l)

  if (( BACKUP_COUNT > MAX_BACKUPS )); then
    DELETE_LIST=$(echo "$BACKUPS" | head -n $((BACKUP_COUNT - MAX_BACKUPS)))
    echo "$DELETE_LIST" | while read -r OLD_FILE; do
      echo "    - 删除旧备份：$OLD_FILE"
      rclone deletefile "${REMOTE}/${OLD_FILE}" || echo "      ! 删除失败"
    done
  else
    echo "    当前备份数：$BACKUP_COUNT，无需清理"
  fi
done

# —— 8. 删除本地最终备份文件 ——
echo "  - 删除本地 ${FINAL_ZIP}"
rm -f "${FINAL_ZIP}"

# —— 完成 ——
echo "[$(date '+%F %T')] 备份完成！"
