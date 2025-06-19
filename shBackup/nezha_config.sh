#!/bin/bash

# 定义配置文件路径
CONFIG_FILE="/opt/nezha/agent/config.yml"

# 检查文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件不存在: $CONFIG_FILE"
    exit 1
fi

# 修改文件中的指定参数为 true
sed -i \
    -e 's/^disable_auto_update:.*/disable_auto_update: true/' \
    -e 's/^disable_nat:.*/disable_nat: true/' \
    -e 's/^disable_command_execute:.*/disable_command_execute: true/' \
    "$CONFIG_FILE"

# 检查是否修改成功
if grep -qE '^disable_auto_update:\s*true' "$CONFIG_FILE" && \
   grep -qE '^disable_nat:\s*true' "$CONFIG_FILE" && \
   grep -qE '^disable_command_execute:\s*true' "$CONFIG_FILE"; then
    echo "参数已成功修改为 true。"
else
    echo "修改失败，请检查文件内容或权限。"
    exit 1
fi

# 重启 Nezha Agent 服务
echo "正在重启 nezha-agent 服务..."
sudo systemctl restart nezha-agent.service

# 检查服务状态
if systemctl is-active --quiet nezha-agent.service; then
    echo "nezha-agent 服务已成功重启。"
else
    echo "nezha-agent 服务重启失败，请检查。"
    exit 1
fi
