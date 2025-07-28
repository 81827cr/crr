#!/usr/bin/env bash
set -euo pipefail

### === 配置区 === ###
MAX_BACKUPS=2
PIKPAK_REMOTE="pikpak:vps/backup"
ONEDRIVE_REMOTE="onedrive:vps/backup"
S3_REMOTE="bing:dps666/vps/backup"

# 排除模式
ROOT_EXCLUDES=(
  --exclude='root/.*'
  --exclude='*.mp4'
  --exclude='*.mp3'
)
HOME_EXCLUDES=(
  --exclude='home/d/**'
  --exclude='home/tmp/**'
  --exclude='home/lu/**'
  --exclude='home/live/downloads/**'
  --exclude='*.mp4'
  --exclude='*.mp3'
)
### =============== ###

# 获取备份名称
if [[ $# -ge 1 ]]; then
  BACKUP_PREFIX="$1"
else
  read -rp "请输入备份名称（如 dc02）: " BACKUP_PREFIX
  [[ -z "$BACKUP_PREFIX" ]] && echo "错误：备份名称不能为空！" && exit 1
fi

NOW=$(date "+%Y%m%d%H%M")
FINAL_TAR="${BACKUP_PREFIX}-${NOW}.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "[$(date '+%F %T')] 开始备份：${FINAL_TAR}"

# 删除旧临时文件
rm -f root.tar.gz home.tar.gz crontab.txt

# 1. 打包 /root
echo "  - 打包 /root → root.tar.gz"
cd /
tar czf "${SCRIPT_DIR}/root.tar.gz" \
  root/.config root/.ssh \
  "${ROOT_EXCLUDES[@]}" \
  root \
  --warning=no-file-changed || echo "    注意：/root 某些文件在读取时有变动，已继续"

# 2. 导出 crontab
cd "${SCRIPT_DIR}"
echo "  - 导出 crontab → crontab.txt"
crontab -l > crontab.txt || true

# 3. 打包 /home
echo "  - 打包 /home → home.tar.gz"
cd /
tar czf "${SCRIPT_DIR}/home.tar.gz" \
  "${HOME_EXCLUDES[@]}" \
  home \
  --warning=no-file-changed || echo "    注意：/home 某些文件在读取时有变动，已继续"

# 回到脚本目录
cd "${SCRIPT_DIR}"

# 4. 合并为最终备份
echo "  - 合并中间文件 → ${FINAL_TAR}"
tar czf "${FINAL_TAR}" root.tar.gz home.tar.gz crontab.txt

# 5. 删除中间文件
echo "  - 删除中间文件"
rm -f root.tar.gz home.tar.gz crontab.txt

# 6. 上传并清理远端
for REMOTE in "${PIKPAK_REMOTE}" "${ONEDRIVE_REMOTE}" "${S3_REMOTE}"; do
  echo "  - 上传 ${FINAL_TAR} → ${REMOTE}"
  if rclone copy "${FINAL_TAR}" "${REMOTE}/"; then
    echo "    > 上传成功"
  else
    echo "    ! 上传失败，跳过清理"
    continue
  fi

  echo "  - 保留最新 ${MAX_BACKUPS} 份 → 前缀 ${BACKUP_PREFIX}-"
  BACKUPS=$(rclone lsf "${REMOTE}/" | grep "^${BACKUP_PREFIX}-.*\.tar\.gz\$" | sort)
  COUNT=$(echo "$BACKUPS" | wc -l)
  if ((COUNT > MAX_BACKUPS)); then
    echo "    - 删除旧备份 $((COUNT - MAX_BACKUPS)) 个"
    echo "$BACKUPS" | head -n $((COUNT - MAX_BACKUPS)) | while read -r F; do
      echo "      删除：$F"
      rclone deletefile "${REMOTE}/$F" || echo "        ! 删除失败"
    done
  else
    echo "    无需清理（当前 $COUNT 个）"
  fi
done

# 7. 删除本地最终备份
echo "  - 删除本地 ${FINAL_TAR}"
rm -f "${FINAL_TAR}"

echo "[$(date '+%F %T')] 备份完成！"
