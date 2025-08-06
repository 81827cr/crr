#!/usr/bin/env bash
set -euo pipefail

### === 配置区 === ###
# 最大保留备份数量（每个机器名前缀）
MAX_BACKUPS=2

# rclone 目标目录（路径尾部不要加斜杠）
PIKPAK_REMOTE="pikpak:vps/backup"
ONEDRIVE_REMOTE="onedrive:vps/backup"
S3_REMOTE="bing:dps666/vps/backup"

# 排除模式 — 请根据需求编辑
ROOT_EXCLUDES=(
  --exclude='root/.*'       # 排除所有隐藏文件（.config/.ssh 除外）
  --exclude='*.mp4'         # 排除媒体文件
  --exclude='*.mp3'
)
HOME_EXCLUDES=(
  --exclude='home/d/**'                # 排除 /home/d
  --exclude='home/tmp/**'              # 排除 /home/tmp
  --exclude='home/lu/**'               # 排除 /home/lu
  --exclude='home/live/downloads/**'   # 排除直播录制
  --exclude='*.mp4'                    # 排除媒体文件
  --exclude='*.mp3'
)
### =============== ###

# 参数：备份前缀，如 dc02
if [[ $# -ge 1 ]]; then
  BACKUP_PREFIX="$1"
else
  read -rp "请输入备份名称（如 dc02）: " BACKUP_PREFIX
  [[ -z "${BACKUP_PREFIX}" ]] && echo "错误：备份名称不能为空！" && exit 1
fi

NOW=$(date +"%Y%m%d%H%M")
FINAL_TAR="${BACKUP_PREFIX}-${NOW}.tar.gz"
SCRIPT_DIR="$HOME"
cd "${SCRIPT_DIR}"

echo "[$(date '+%F %T')] 开始备份：${FINAL_TAR}"

# 清理旧临时文件
rm -f root.tar.gz home.tar.gz crontab.txt

# 1. 打包 /root：先包含 .config/.ssh，再排除其他隐藏文件
echo "  - 打包 /root → root.tar.gz"
cd /
tar czf "${SCRIPT_DIR}/root.tar.gz" \
  --warning=no-file-changed \
  root/.config root/.ssh \
  "${ROOT_EXCLUDES[@]}" \
  root || echo "    注意：/root 部分文件变动，已继续"

# 2. 导出 crontab
cd "${SCRIPT_DIR}"
echo "  - 导出 crontab → crontab.txt"
crontab -l > crontab.txt || true

# 3. 打包 /home
echo "  - 打包 /home → home.tar.gz"
cd /
tar czf "${SCRIPT_DIR}/home.tar.gz" \
  --warning=no-file-changed \
  "${HOME_EXCLUDES[@]}" \
  home || echo "    注意：/home 部分文件变动，已继续"

# 回到脚本目录
cd "${SCRIPT_DIR}"

# 4. 合并中间文件为最终备份
echo "  - 合并中间文件 → ${FINAL_TAR}"
tar czf "${FINAL_TAR}" root.tar.gz home.tar.gz crontab.txt

# 5. 删除中间文件
echo "  - 删除中间文件"
rm -f root.tar.gz home.tar.gz crontab.txt

# 6. 上传至各远端并清理旧备份
for REMOTE in "${PIKPAK_REMOTE}" "${ONEDRIVE_REMOTE}" "${S3_REMOTE}"; do
  echo "  - 上传 ${FINAL_TAR} → ${REMOTE}"
  if rclone copy "${FINAL_TAR}" "${REMOTE}/"; then
    echo "    > 上传成功"
  else
    echo "    ! 上传失败，跳过该远端"
    continue
  fi

  echo "  - 保留最新 ${MAX_BACKUPS} 份备份：前缀 ${BACKUP_PREFIX}-"
  BACKUPS=$(rclone lsf "${REMOTE}/" | grep "^${BACKUP_PREFIX}-.*\.tar\.gz\$" | sort)
  COUNT=$(echo "$BACKUPS" | wc -l)
  if (( COUNT > MAX_BACKUPS )); then
    echo "    - 删除旧备份 $((COUNT - MAX_BACKUPS)) 个"
    echo "$BACKUPS" | head -n $((COUNT - MAX_BACKUPS)) | while read -r OLD; do
      echo "      删除：$OLD"
      rclone deletefile "${REMOTE}/$OLD" || echo "        ! 删除失败"
    done
  else
    echo "    无需清理（当前共 $COUNT 个）"
  fi
done

# 7. 删除本地最终备份
echo "  - 删除本地 ${FINAL_TAR}"
rm -f "${FINAL_TAR}"

echo "[$(date '+%F %T')] 备份完成！"
