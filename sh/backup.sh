#!/usr/bin/env bash
set -euo pipefail

### === 配置区 === ###
MAX_BACKUPS=2                                 # 每个前缀保留的备份数量
PIKPAK_REMOTE="pikpak:vps/backup"             # Rclone 目标路径（不带末尾斜杠）
ONEDRIVE_REMOTE="onedrive:vps/backup"
S3_REMOTE="bing:dps666/vps/backup"

# 排除和包含模式 — 请根据需求调整
ROOT_EXCLUDES=(
  --exclude='root/.*'       # 排除 /root 下所有隐藏目录（.config、.ssh 除外）
  --exclude='*.mp4'         # 排除所有 .mp4 文件
  --exclude='*.mp3'         # 排除所有 .mp3 文件
)
# 注意 GNU tar 不提供独立的 --include 选项，这里通过先指定 .config/.ssh 再 exclude 其余隐藏
HOME_EXCLUDES=(
  --exclude='home/d/**'                # 排除 /home/d 目录及子目录
  --exclude='home/tmp/**'              # 排除 /home/tmp 目录及子目录
  --exclude='home/lu/**'               # 排除 /home/lu 目录及子目录
  --exclude='home/live/downloads/**'   # 排除 /home/live/downloads 目录及子目录
  --exclude='*.mp4'                    # 排除 .mp4 文件
  --exclude='*.mp3'                    # 排除 .mp3 文件
)
### =============== ###

# 获取备份前缀参数（如 dc02）
if [[ $# -ge 1 ]]; then
  BACKUP_PREFIX="$1"
else
  read -rp "请输入备份名称（如 dc02）: " BACKUP_PREFIX
  [[ -z "${BACKUP_PREFIX}" ]] && echo "错误：备份名称不能为空！" && exit 1
fi

NOW=$(date "+%Y%m%d%H%M")
FINAL_TAR="${BACKUP_PREFIX}-${NOW}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "[$(date '+%F %T')] 开始备份：${FINAL_TAR}"

# 清理旧的中间文件
rm -f root.tar.gz home.tar.gz crontab.txt

# —— 1. 打包 /root ——
echo "  - 打包 /root → root.tar.gz"
cd /
tar czf "${SCRIPT_DIR}/root.tar.gz" root/.config root/.ssh "${ROOT_EXCLUDES[@]}" root

# —— 2. 导出 crontab ——
echo "  - 导出 crontab → crontab.txt"
crontab -l > "${SCRIPT_DIR}/crontab.txt" || true

# —— 3. 打包 /home ——
echo "  - 打包 /home → home.tar.gz"
cd /
tar czf "${SCRIPT_DIR}/home.tar.gz" "${HOME_EXCLUDES[@]}" home

# 返回脚本目录
cd "${SCRIPT_DIR}"

# —— 4. 合并中间文件为最终备份 ——
echo "  - 合并中间文件 → ${FINAL_TAR}"
tar czf "${FINAL_TAR}" root.tar.gz home.tar.gz crontab.txt

# —— 5. 删除中间文件 ——
rm -f root.tar.gz home.tar.gz crontab.txt

# —— 6. 上传到各远端 ——
for REMOTE in "${PIKPAK_REMOTE}" "${ONEDRIVE_REMOTE}" "${S3_REMOTE}"; do
  echo "  - 上传 ${FINAL_TAR} → ${REMOTE}"
  if rclone copy "${FINAL_TAR}" "${REMOTE}/"; then
    echo "    > 上传成功"
  else
    echo "    ! 上传失败，跳过剩余步骤"
    continue
  fi

  # —— 7. 删除远端旧备份，仅保留最新 N 份 ——
  echo "  - 保留最新 ${MAX_BACKUPS} 份备份：前缀 ${BACKUP_PREFIX}-"
  BACKUPS=$(rclone lsf "${REMOTE}/" | grep "^${BACKUP_PREFIX}-.*\.tar\.gz$" | sort)
  BACKUP_COUNT=$(echo "$BACKUPS" | wc -l)
  if (( BACKUP_COUNT > MAX_BACKUPS )); then
    # 列出超出部分并逐个删除
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
echo "  - 删除本地 ${FINAL_TAR}"
rm -f "${FINAL_TAR}"

echo "[$(date '+%F %T')] 备份完成！"
