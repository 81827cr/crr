#!/bin/bash

# 获取当前时间
log_time() {
    echo "$(date "+%Y-%m-%d %H:%M:%S")"
}

# 提示用户输入虚拟内存大小（单位：MB）
echo "请输入虚拟内存大小（MB）:"
read swap_size

# 检查输入是否是数字
if [[ ! "$swap_size" =~ ^[0-9]+$ ]]; then
    echo "无效的输入，请输入一个数字（例如 500 或 2048）"
    exit 1
fi

# 设置交换文件路径，支持用户输入
echo "请输入交换文件路径（默认: /swapfile）:"
read swap_file_path
swap_file_path=${swap_file_path:-/swapfile}  # 如果没有输入，使用默认路径

# 获取交换文件大小，单位KB
swap_size_kb=$((swap_size * 1024))

# 清除所有现有交换空间
echo "$(log_time) - 清除所有现有交换空间..."
swapoff -a
echo "所有交换空间已禁用。"

# 删除旧的交换文件（如果存在）
if [ -f "$swap_file_path" ]; then
    rm -f "$swap_file_path"
    echo "旧的交换文件已删除: $swap_file_path"
fi

# 创建新的交换文件
echo "$(log_time) - 创建交换文件..."
if ! fallocate -l ${swap_size}M $swap_file_path; then
    echo "交换文件创建失败!"
    exit 1
fi

# 设置交换文件权限
chmod 600 $swap_file_path
echo "交换文件权限已设置为 600."

# 设置交换文件
if ! mkswap $swap_file_path; then
    echo "交换空间初始化失败!"
    exit 1
fi
echo "交换空间初始化成功."

# 启用交换
if ! swapon $swap_file_path; then
    echo "启用交换空间失败!"
    exit 1
fi

# 确认虚拟内存是否启用成功
swapon --show

# 检查 /etc/fstab 是否已有交换空间条目，如果没有则添加
if ! grep -q "$swap_file_path" /etc/fstab; then
    echo "$swap_file_path none swap sw 0 0" | tee -a /etc/fstab
    echo "交换空间条目已添加到 /etc/fstab."
fi

echo "虚拟内存设置成功，大小为 ${swap_size}MB，路径为 ${swap_file_path}"
