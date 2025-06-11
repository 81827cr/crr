#!/usr/bin/env bash
set -euo pipefail

### 配置区 ###
# 最终备份名（默认 vkvm），可通过环境变量 BACKUP_NAME 覆盖
BACKUP_NAME="${BACKUP_NAME:-vkvm}"

# 脚本所在目录，所有中间文件都在这里生成
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 临时文件名
ROOT_ZIP="root.zip"
HOME_ZIP="home.zip"
CRONTAB_FILE="crontab.txt"
FINAL_ZIP="${BACKUP_NAME}.zip"

# rclone 目标目录
PIKPAK_REMOTE="pikpak:vps/backup"
ONEDRIVE_REMOTE="onedrive:vps/backup"
S3_REMOTE="bing:dps666/vps/backup"
################

echo "[$(date '+%F %T')] 开始备份：${BACKUP_NAME}"

# —— 清理旧文件 ——
rm -f "${ROOT_ZIP}" "${HOME_ZIP}" "${CRONTAB_FILE}" "${FINAL_ZIP}"

# —— 1. 打包 /root ——
echo "  - 打包 /root → ${ROOT_ZIP} （仅包含 /root/.config、/root/.ssh 以及所有非隐藏文件/目录，排除 mp4/mp3）"
cd /
# 准备排除：隐藏文件/目录（除 .config/.ssh），mp4/mp3
EXCLUDES=( -x "root/.*" -x "*.mp4" "*.mp3" )
# 若脚本放在 /root 子目录，还排除脚本目录
if [[ "${SCRIPT_DIR}" == /root/* && "${SCRIPT_DIR}" != "/root" ]]; then
  REL_SCRIPT_DIR="${SCRIPT_DIR#/}"
  EXCLUDES+=( -x "${REL_SCRIPT_DIR}/**" )
fi
# 先打包所有非隐藏项目（.* 排除）
zip -r "${SCRIPT_DIR}/${ROOT_ZIP}" root "${EXCLUDES[@]}"
# 再单独添加 .config 目录及其内容
zip -r "${SCRIPT_DIR}/${ROOT_ZIP}" root/.config -x "*.mp4" "*.mp3"
# 再单独添加 .ssh 目录及其内容
zip -r "${SCRIPT_DIR}/${ROOT_ZIP}" root/.ssh -x "*.mp4" "*.mp3"
cd "${SCRIPT_DIR}"

# —— 2. 导出当前用户的 crontab ——
echo "  - 导出 crontab → ${CRONTAB_FILE}"
crontab -l > "${CRONTAB_FILE}" || true

# —— 3. 打包 /home ——
echo "  - 打包 /home → ${HOME_ZIP} （排除指定目录、mp4/mp3）"
cd /
zip -r "${SCRIPT_DIR}/${HOME_ZIP}" home \
    -x "home/d/**" "home/tmp/**" "home/lu/**" "home/live/downloads/**" \
    -x "*.mp4" "*.mp3"
cd "${SCRIPT_DIR}"

# —— 4. 合并中间文件 → 最终 ZIP ——
echo "  - 合并中间文件 → ${FINAL_ZIP}"
zip "${FINAL_ZIP}" "${ROOT_ZIP}" "${HOME_ZIP}" "${CRONTAB_FILE}"

# —— 5. 清理中间文件 ——
rm -f "${ROOT_ZIP}" "${HOME_ZIP}" "${CRONTAB_FILE}"

# —— 6-8. 循环上传到各存储（copy） ——
for REMOTE in "${PIKPAK_REMOTE}" "${ONEDRIVE_REMOTE}" "${S3_REMOTE}"; do
  echo "  - 远端 ${REMOTE} 当前文件列表："
  # 列出远端目录内容，帮助调试
  rclone lsf "${REMOTE}/" || echo "    ! 无法获取远端列表"

  echo "  - 删除 ${REMOTE} 上旧文件（如果存在）"
  # 无论文件是否存在，都尝试删除并捕捉失败
  rclone deletefile "${REMOTE}/${FINAL_ZIP}" || echo "    ! 无旧文件或删除失败"

  echo "  - 上传 ${FINAL_ZIP} → ${REMOTE}"
  if rclone copy "${FINAL_ZIP}" "${REMOTE}/"; then
    echo "    > 上传到 ${REMOTE} 成功"
  else
    echo "    ! 上传到 ${REMOTE} 失败，但脚本继续"
  fi

done

# —— 9. 最终清理：删除本地最终 ZIP ——. 最终清理：删除本地最终 ZIP ——
echo "  - 删除本地 ${FINAL_ZIP}"
rm -f "${FINAL_ZIP}"

# —— 完成 ——
echo "[$(date '+%F %T')] 备份完成！"
