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
# 列出所有 rclone 配置
rclone listremotes

# 2. 选择 rclone 配置
echo "请选择一个 rclone 配置："
REMOTE_LIST=($(rclone listremotes))
select REMOTE in "${REMOTE_LIST[@]}"; do
  if [[ -n "$REMOTE" ]]; then
    # 去除末尾冒号，防止拼接为 ::
    REMOTE="${REMOTE%:}"
    echo "已选择远端配置：$REMOTE"
    break
  else
    echo "无效选择，请重新选择。"
  fi
done

REMOTE_PATH="vps/backup"

# 3. 获取远端目录中的所有备份文件
echo "获取 ${REMOTE}:${REMOTE_PATH} 目录下的备份文件..."
BACKUP_FILES=($(rclone lsf "${REMOTE}:${REMOTE_PATH}/"))
if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
  echo "该目录没有备份文件，退出脚本。"
  exit 1
fi

# 显示备份文件列表
echo "请选择要恢复的备份文件："
select BACKUP_ZIP in "${BACKUP_FILES[@]}"; do
  if [[ -n "$BACKUP_ZIP" ]]; then
    echo "已选择备份文件：$BACKUP_ZIP"
    break
  else
    echo "无效选择，请重新选择。"
  fi
done

# 4. 下载备份文件到临时目录
mkdir -p "${SCRIPT_DIR}/tmp"
echo "下载 ${REMOTE}:${REMOTE_PATH}/${BACKUP_ZIP} 到 tmp/"
rclone copy "${REMOTE}:${REMOTE_PATH}/${BACKUP_ZIP}" "${SCRIPT_DIR}/tmp/"

# 5. 交互式恢复
cd "${SCRIPT_DIR}/tmp" || exit

# 解压总包
echo "解压 ${BACKUP_ZIP} → tmp/"
unzip -o "${BACKUP_ZIP}"

# 5.1 是否恢复 /root 目录
read -rp "是否恢复 /root 目录？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "解压 root.zip → tmp/"
  unzip -o root.zip
  echo "覆盖 tmp/root/ 到 /root/"
  cp -a root/. /root/
fi

# 5.2 是否恢复 /home 目录
read -rp "是否恢复 /home 目录？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "解压 home.zip → tmp/"
  unzip -o home.zip
  echo "覆盖 tmp/home/ 到 /home/"
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

# 6. 恢复 crontab 定时任务
read -rp "是否覆盖当前服务器的 crontab？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "  - 清空当前 crontab 任务"
  crontab -r || true
  echo "  - 导入 tmp/crontab.txt"
  crontab "${SCRIPT_DIR}/tmp/crontab.txt"
fi

# 7. 删除临时目录 tmp
read -rp "是否删除脚本目录下的 tmp？ [y/N]：" ans
if [[ "${ans,,}" == y* ]]; then
  echo "删除临时目录 ${SCRIPT_DIR}/tmp"
  rm -rf "${SCRIPT_DIR}/tmp"
fi

echo "所有操作结束！"
