#!/bin/bash

# 配置日志文件
LOGFILE="/var/log/swap_setup.log"
LOCKFILE="/var/lock/swap_setup.lock"

# 获取当前时间
log_time() {
    echo "$(date "+%Y-%m-%d %H:%M:%S")"
}

# 记录日志
log_message() {
    echo "$(log_time) - $1" >> $LOGFILE
}

# 检查是否有并发运行
if [ -e "$LOCKFILE" ]; then
    echo "脚本已在运行中，退出..."
    exit 1
else
    touch "$LOCKFILE"
    trap "rm -f $LOCKFILE" EXIT
fi

# 提示用户输入虚拟内存大小（单位：MB）
echo "请输入虚拟内存大小（MB）:"
read swap_size

# 检查输入是否是数字
if [[ ! "$swap_size" =~ ^[0-9]+$ ]]; then
    log_message "无效的输入: $swap_size"
    echo "无效的输入，请输入一个数字（例如 500 或 2048）"
    exit 1
fi

# 设置交换文件路径，支持用户输入
echo "请输入交换文件路径（默认: /swapfile）:"
read swap_file_path
swap_file_path=${swap_file_path:-/swapfile}  # 如果没有输入，使用默认路径

# 获取交换文件大小，单位KB
swap_size_kb=$((swap_size * 1024))

# 日志记录开始
log_message "开始设置交换空间，目标大小: ${swap_size}MB，路径: ${swap_file_path}"

# 检查当前交换空间是否已经足够
current_swap_size=$(swapon --show=NAME,SIZE --bytes | grep -w "$swap_file_path" | awk '{print $2}')
if [[ "$current_swap_size" -ge "$swap_size_kb" ]]; then
    log_message "当前交换空间已经足够，无需重新创建。当前大小: $((current_swap_size / 1024 / 1024))MB"
    echo "当前交换空间已经足够，无需重新创建。"
    exit 0
fi

# 禁用旧的交换空间（如果有）
if swapon --show | grep -q "$swap_file_path"; then
    log_message "禁用旧的交换空间..."
    swapoff $swap_file_path
    rm -f $swap_file_path
    log_message "旧的交换空间已被禁用并删除。"
fi

# 创建新的交换文件
log_message "创建交换文件..."
if ! fallocate -l ${swap_size}M $swap_file_path; then
    log_message "交换文件创建失败!"
    echo "交换文件创建失败!"
    exit 1
fi

# 设置交换文件权限
chmod 600 $swap_file_path
log_message "交换文件权限已设置为 600."

# 设置交换文件
if ! mkswap $swap_file_path; then
    log_message "交换空间初始化失败!"
    echo "交换空间初始化失败!"
    exit 1
fi
log_message "交换空间初始化成功."

# 启用交换
if ! swapon $swap_file_path; then
    log_message "启用交换空间失败!"
    echo "启用交换空间失败!"
    exit 1
fi

# 确认虚拟内存是否启用成功
swapon --show

# 日志记录成功
log_message "虚拟内存设置成功，大小为 ${swap_size}MB，路径为 ${swap_file_path}"

# 检查 /etc/fstab 是否已有交换空间条目，如果没有则添加
if ! grep -q "$swap_file_path" /etc/fstab; then
    echo "$swap_file_path none swap sw 0 0" | tee -a /etc/fstab
    log_message "交换空间条目已添加到 /etc/fstab."
fi

echo "虚拟内存设置成功，大小为 ${swap_size}MB，路径为 ${swap_file_path}"
