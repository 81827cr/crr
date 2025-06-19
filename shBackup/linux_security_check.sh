#!/bin/bash

# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; NC='\033[0m'

echo -e "${BLUE}========= 🛡 Linux 安全检查脚本 v1.2 =========${NC}"
start=$(date +%s)

# 1. SSH爆破尝试
echo -e "\n${YELLOW}--- [1] SSH 爆破尝试（Failed password） ---${NC}"
if [ -f /var/log/auth.log ]; then
  grep "Failed password" /var/log/auth.log | awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head
else
  # 使用 journalctl
  journalctl _SYSTEMD_UNIT=sshd.service -o cat | grep "Failed password" | awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head || echo "(未找到日志)"
fi

# 2. 最近成功登录 IP
echo -e "\n${YELLOW}--- [2] 最近成功登录 IP ---${NC}"
if [ -f /var/log/auth.log ]; then
  grep "Accepted password" /var/log/auth.log | awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head
else
  # 使用 journalctl
  journalctl _SYSTEMD_UNIT=sshd.service -o cat | grep "Accepted password" | awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head || echo "(未找到日志)"
fi

# 3. 最近登录记录
echo -e "\n${YELLOW}--- [3] 最近登录记录 ---${NC}"
command -v last >/dev/null && last -a | head -n 10 || echo "(未安装 last 命令)"

# 4. 正在监听的端口
echo -e "\n${YELLOW}--- [4] 正在监听的端口 ---${NC}"
ss -tulnp | grep -v "127.0.0.1" || netstat -tulnp | grep -v "127.0.0.1"

# 5. 高 CPU 占用进程
echo -e "\n${YELLOW}--- [5] 高 CPU 占用进程 ---${NC}"
ps aux --sort=-%cpu | head -n 5

# 6. 可登录用户
echo -e "\n${YELLOW}--- [6] 可登录用户（/bin/bash） ---${NC}"
awk -F: '$7 ~ /bash/ {print $1}' /etc/passwd

# 6.1 UID=0 非 root 用户
echo -e "\n${YELLOW}--- [6.1] UID=0 的隐藏账户 ---${NC}"
awk -F: '($3 == 0) {print $1}' /etc/passwd

# 7. 定时任务检查
echo -e "\n${YELLOW}--- [7] Crontab 定时任务 ---${NC}"
crontab -l 2>/dev/null || echo "(无当前用户 crontab)"
echo -e "${BLUE}→ 系统 Crontab:${NC}"
cat /etc/crontab

# 8. 启动项检查
echo -e "\n${YELLOW}--- [8] 启动服务检查 ---${NC}"
ls /etc/systemd/system/ | grep -vE 'default|network|sshd|multi-user|nginx|docker' || echo "(无异常)"
ls /etc/init.d/ | grep -vE 'cron|networking|ssh|rsyslog|nginx|docker' || echo "(无异常)"

# 9. 最近 7 天修改的敏感文件
echo -e "\n${YELLOW}--- [9] 最近 7 天内被修改的敏感文件 ---${NC}"
find /etc /root /home -type f -mtime -7 2>/dev/null | head -n 10

# 10. 可疑脚本行为
echo -e "\n${YELLOW}--- [10] 可疑脚本行为（wget/curl/nc） ---${NC}"
find / -type f \( -name "*.sh" -o -name "*.py" \) \
  -exec grep -Ei 'bash|wget|curl|nc|socket' {} + 2>/dev/null | head -n 10

# 11. SUID 文件检查
echo -e "\n${YELLOW}--- [11] SUID 文件（提权风险） ---${NC}"
find / -perm -4000 -type f 2>/dev/null | grep -vE "/usr/bin/(sudo|ping|passwd|su)" | head -n 10

# 12. PHP WebShell 检测
echo -e "\n${YELLOW}--- [12] 可疑 PHP 文件 ---${NC}"
php_dirs=("/usr/share/nginx/html")
extra_www_dirs=$(find / -type d -name www 2>/dev/null)
for dir in "${php_dirs[@]}" $extra_www_dirs; do
  [ -d "$dir" ] && {
    echo -e "${BLUE}→ 扫描目录: $dir${NC}"
    find "$dir" -type f -name "*.php" \
      -exec grep -EinH "eval\(|base64_decode\(|shell_exec\(|assert\(|passthru\(|exec\(|system\(" {} + 2>/dev/null | head -n 5
  }
done

# 13. 隐藏文件或目录
echo -e "\n${YELLOW}--- [13] 隐藏文件或目录（.*） ---${NC}"
find / \( -path /proc -o -path /sys -o -path /dev \) -prune -o -name ".*" -print 2>/dev/null | head -n 10

# 14. 最近新增的 /home 用户目录
echo -e "\n${YELLOW}--- [14] 最近新增的 /home 用户目录 ---${NC}"
find /home -maxdepth 1 -type d -ctime -7 2>/dev/null | grep -v "/home$" || echo "(无新增)"

# 15. 用户 Shell 异常
echo -e "\n${YELLOW}--- [15] 用户 Shell 异常 ---${NC}"
awk -F: '{print $1, $7}' /etc/passwd | grep -vE '(/bin/bash|/bin/sh|/usr/sbin/nologin|/usr/bin/nologin)$'

# 16. 后门监听端口检查
echo -e "\n${YELLOW}--- [16] 后门监听端口检查 ---${NC}"
ports=(4444 12345 31337 5555 6666 8686 8888)
detected=0
for p in "${ports[@]}"; do
  if ss -tuln | grep -q ":$p "; then
    pid=$(ss -tulpn | grep ":$p " | awk -F '[ ,]' '{print $6}')
    echo -e "${RED}[!] 端口 $p 被监听 (PID/程序: $pid)${NC}"
    detected=1
  fi
done
[ $detected -eq 0 ] && echo -e "${GREEN}未监听常见后门/面板端口${NC}"

# 17. Docker 安全检测
echo -e "\n${YELLOW}--- [17] Docker 安全检测 ---${NC}"
if [ -S /var/run/docker.sock ]; then
  perms=$(ls -l /var/run/docker.sock | awk '{print $1}')
  echo -e "权限: $perms"
  [[ "$perms" != "srw-rw----" ]] && echo -e "${RED}[!] docker.sock 权限异常，可能被非 root 用户访问${NC}" || echo -e "${GREEN}docker.sock 权限正常${NC}"
else
  echo -e "未检测到 Docker 环境"
fi


# 高危摘要
echo -e "\n${RED}========= ⚠️ 高危行为摘要 =========${NC}"
failed_ssh=$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l)
[ "$failed_ssh" -gt 10 ] && echo -e "${RED}[!] 检测到大量 SSH 登录失败（$failed_ssh 次）${NC}"

uid0_count=$(awk -F: '($3 == 0) {print $1}' /etc/passwd | wc -l)
[ "$uid0_count" -gt 1 ] && echo -e "${RED}[!] 存在多个 UID=0 账户（$uid0_count 个）${NC}"

suid_count=$(find / -perm -4000 -type f 2>/dev/null | wc -l)
[ "$suid_count" -gt 10 ] && echo -e "${RED}[!] 存在异常数量 SUID 文件（$suid_count 个）${NC}"

webshell_found=$(find / -type f -name "*.php" -exec grep -Ei "eval\(|base64_decode\(|shell_exec\(" {} + 2>/dev/null | wc -l)
[ "$webshell_found" -gt 0 ] && echo -e "${RED}[!] 存在可疑 PHP 文件（$webshell_found 条匹配）${NC}"

hidden_count=$(find / \( -path /proc -o -path /sys -o -path /dev \) -prune -o -name ".*" -print 2>/dev/null | wc -l)
[ "$hidden_count" -gt 10 ] && echo -e "${RED}[!] 检测到大量隐藏文件/目录（$hidden_count 个）${NC}"

# 执行完毕提示
end=$(date +%s)
echo -e "\n${GREEN}✅ 检查完毕，用时 $((end-start)) 秒。如有 [!] 提示，请逐项排查。${NC}"
