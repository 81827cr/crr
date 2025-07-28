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
  [[ -n "$REMOTE" ]] && { echo "[INFO] 已选择：$REMOTE"; break; }
  echo "[WARN] 无效选择，请重试。"
done

REMOTE_PATH="vps/backup"

# 3. 获取备份列表
echo "[INFO] 获取 ${REMOTE}:${REMOTE_PATH} 下的备份文件列表..."
mapfile -t ARCHIVES < <(rclone lsf "${REMOTE}:${REMOTE_PATH}/" | grep -E '\.tar\.gz$')
[[ ${#ARCHIVES[@]} -gt 0 ]] || { echo "[ERROR] 未找到 .tar.gz 备份文件，退出。"; exit 1; }

echo "[INPUT] 请选择要恢复的备份："
select BACKUP in "${ARCHIVES[@]}"; do
  [[ -n "$BACKUP" ]] && { echo "[INFO] 选中：$BACKUP"; break; }
  echo "[WARN] 无效选择，请重试。"
done

# 4. 下载并解压主档
TMP_DIR="${SCRIPT_DIR}/tmp"
mkdir -p "$TMP_DIR"
echo "[INFO] 下载 $REMOTE:$REMOTE_PATH/$BACKUP 到 $TMP_DIR/"
rclone copy "${REMOTE}:${REMOTE_PATH}/${BACKUP}" "$TMP_DIR/"

cd "$TMP_DIR"
echo "[INFO] 解压 $BACKUP..."
tar -zxf "$BACKUP"

# 5.1 恢复 /root
echo -e "\n—— 恢复 /root ——"
read -rp "是否覆盖并恢复 /root？ [y/N]: " ans
if [[ "${ans,,}" == y* ]]; then
  echo "[INFO] 清空 /root 下旧文件"
  rm -rf /root/* /root/.[!.]* || true

  if [[ -f root.tar.gz ]]; then
    echo "[INFO] 解压 root.tar.gz 到 /root"
    tar -zxf root.tar.gz -C /root || echo "[ERROR] 解压 root.tar.gz 失败，跳过该步骤"
  else
    echo "[WARN] 未找到 root.tar.gz，跳过 /root 恢复"
  fi
else
  echo "[INFO] 仅删除 /root/.ssh 下所有内容"
  rm -rf /root/.ssh/* || true
fi

# 5.2 恢复 /home
echo -e "\n—— 恢复 /home ——"
read -rp "是否覆盖并恢复 /home？ [y/N]: " ans
if [[ "${ans,,}" == y* ]]; then
  echo "[INFO] 清空 /home 下旧文件"
  rm -rf /home/* /home/.[!.]* || true

  if [[ -f home.tar.gz ]]; then
    echo "[INFO] 解压 home.tar.gz 到 /home"
    tar -zxf home.tar.gz -C /home || echo "[ERROR] 解压 home.tar.gz 失败，跳过该步骤"
  else
    echo "[WARN] 未找到 home.tar.gz，跳过 /home 恢复"
  fi
fi

# 5.3 恢复 SSH 服务端和密钥对
echo -e "\n—— 恢复 SSH 服务端和密钥对 ——"
read -rp "是否恢复 SSH 密钥？ [y/N]: " ans
if [[ "${ans,,}" == y* ]]; then
  mkdir -p tmp_ssh
  if [[ -d root/.ssh ]]; then
    echo "[INFO] 使用临时 root/.ssh 目录"
    rm -rf /root/.ssh && cp -a root/.ssh /root/.ssh
  else
    echo "[INFO] 从 root.tar.gz 提取 .ssh"
    tar -zxf root.tar.gz -C tmp_ssh ".ssh" 2>/dev/null || true
    if [[ -d tmp_ssh/.ssh ]]; then
      rm -rf /root/.ssh && cp -a tmp_ssh/.ssh /root/.ssh
    else
      echo "[WARN] root.tar.gz 中无 .ssh，已跳过"
    fi
  fi

  # 设置权限
  chmod 700 /root/.ssh || true
  chmod 600 /root/.ssh/id_* 2>/dev/null || true
  chmod 644 /root/.ssh/*.pub /root/.ssh/known_hosts /root/.ssh/config 2>/dev/null || true

  # 配置 sshd_config
  for key in RSAAuthentication PubkeyAuthentication PermitRootLogin PasswordAuthentication Port; do
    sed -i "/^${key}/d" /etc/ssh/sshd_config
  done
  {
    echo "Port 22"
    echo "PasswordAuthentication no"
    echo "PermitRootLogin yes"
    echo "PubkeyAuthentication yes"
    echo "RSAAuthentication yes"
  } >> /etc/ssh/sshd_config

  echo "[INFO] 重启 SSH 服务"
  systemctl restart sshd || service ssh restart

  echo "[INFO] ufw 放行 SSH 端口 22"
  ufw allow 22 || true
fi

# 6. 恢复 crontab
echo -e "\n—— 恢复 crontab ——"
read -rp "是否覆盖当前 crontab？ [y/N]: " ans
if [[ "${ans,,}" == y* ]]; then
  [[ -f crontab.txt ]] && {
    echo "[INFO] 清空当前 crontab"
    crontab -r || true
    echo "[INFO] 导入 crontab.txt"
    crontab crontab.txt
  } || echo "[WARN] 未找到 crontab.txt，跳过"
fi

# 7. 清理临时目录
echo -e "\n—— 清理临时目录 ——"
read -rp "是否删除临时目录 $TMP_DIR？ [y/N]: " ans
if [[ "${ans,,}" == y* ]]; then
  rm -rf "$TMP_DIR"
  echo "[INFO] 已删除 $TMP_DIR"
fi

echo "[INFO] 恢复完成！"
