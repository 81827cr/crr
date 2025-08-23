#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
CONFIG_JSON="/opt/xray/config.json"   # <-- 可修改
XRAY_BIN="/opt/xray/xray"            # <-- 可修改
REALITY_LOG="/opt/xray/reality.txt"  # 生成的 share link 会追加到此文件

# ====== helpers (jq-only, pure bash) ======
require_jq(){
  if ! command -v jq >/dev/null 2>&1; then
    echo "错误：本脚本要求 jq 已安装。请安装 jq 后重试。" >&2
    exit 1
  fi
}

rand_port(){
  # 生成 10000 - 65535 的随机端口
  n=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ')
  port=$(( n % 55536 + 10000 ))
  printf "%s" "$port"
}

rand_shortid(){
  # 6 个数字 + 4 个字母 a-f，随机打散
  digits=$(tr -dc '0-9' </dev/urandom | head -c6 || true)
  letters=$(tr -dc 'a-f' </dev/urandom | head -c4 || true)
  pool="${digits}${letters}"
  out=""
  while [ -n "$pool" ]; do
    idx=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
    idx=$(( idx % ${#pool} ))
    out+="${pool:idx:1}"
    pool="${pool:0:idx}${pool:idx+1}"
  done
  printf "%s" "$out"
}

ask(){
  local prompt="$1"
  read -r -p "$prompt" ans
  printf "%s" "$ans"
}

# ====== start ======
require_jq

echo "-- jq-only 一键生成 Reality 节点（请确保 jq 与 xray 可执行文件存在） --"

# 端口
PORT_INPUT=$(ask "端口（回车随机 10000-65535）：")
if [ -z "$PORT_INPUT" ]; then
  PORT=$(rand_port)
  echo "使用随机端口: $PORT"
else
  PORT="$PORT_INPUT"
  echo "使用用户输入端口: $PORT"
fi

# UUID
UUID_INPUT=$(ask "UUID（回车使用 xray uuid 或 /proc/sys/kernel/random/uuid 生成）：")
if [ -z "$UUID_INPUT" ]; then
  if [ -x "$XRAY_BIN" ]; then
    UUID=$("$XRAY_BIN" uuid 2>/dev/null || true)
  fi
  if [ -z "${UUID:-}" ] && [ -r /proc/sys/kernel/random/uuid ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
  fi
  if [ -z "${UUID:-}" ]; then
    echo "无法生成 UUID，请手动输入。" >&2
    exit 1
  fi
  echo "生成 UUID: $UUID"
else
  UUID="$UUID_INPUT"
  echo "使用用户 UUID: $UUID"
fi

# dest 选项（默认1）
cat <<EOF
选择 dest (会自动在末尾加 :443)（默认 1）：
  1) icloud.cdn-apple.com
  2) swdist.apple.com
  3) www.icloud.com
  4) 自行输入
EOF
CHOICE=$(ask "请输入 1-4（回车默认1）：")
if [ -z "$CHOICE" ]; then CHOICE=1; fi
case "$CHOICE" in
  1) SNI_BASE="icloud.cdn-apple.com" ;;
  2) SNI_BASE="swdist.apple.com" ;;
  3) SNI_BASE="www.icloud.com" ;;
  4) SNI_BASE=$(ask "请输入自定义域名（例如 example.com）：") ;;
  *) echo "无效选择，使用 icloud.cdn-apple.com"; SNI_BASE="icloud.cdn-apple.com" ;;
esac
DEST="${SNI_BASE}:443"
SERVERNAME="$SNI_BASE"

echo "使用 dest: $DEST, serverName: $SERVERNAME"

# 生成 x25519 密钥对（必须有 xray）
if [ -x "$XRAY_BIN" ]; then
  echo "调用 $XRAY_BIN x25519 生成密钥对..."
  XOUT=$("$XRAY_BIN" x25519 2>/dev/null || true)
  PRIV_KEY=$(printf "%s" "$XOUT" | awk -F': ' '/Private key/ {print $2}' | tr -d '
')
  PUB_KEY=$(printf "%s" "$XOUT" | awk -F': ' '/Public key/ {print $2}' | tr -d '
')
  if [ -z "$PRIV_KEY" ] || [ -z "$PUB_KEY" ]; then
    echo "错误：无法通过 $XRAY_BIN x25519 获取密钥对，取消。" >&2
    exit 1
  fi
else
  echo "错误：找不到 xray 二进制 $XRAY_BIN（用于 x25519）。中止。" >&2
  exit 1
fi

echo "Private key: $PRIV_KEY"
echo "Public key: $PUB_KEY"

# shortId（6 数字 + 4 字母 a-f）
SHORT_INPUT=$(ask "shortId（回车为随机生成 6 数字 + 4 字母 a-f 混合）：")
if [ -z "$SHORT_INPUT" ]; then
  SHORTID=$(rand_shortid)
  echo "生成 shortId: $SHORTID"
else
  SHORTID="$SHORT_INPUT"
  echo "使用用户 shortId: $SHORTID"
fi

# 校验 shortId 格式（必须是 10 个字符，仅包含 0-9 和 a-f，且至少6个数字与4个字母）
if ! printf "%s" "$SHORTID" | grep -Eq '^[0-9a-f]{10}$'; then
  echo "错误：shortId 必须是 10 个字符，仅包含 0-9 和 a-f（总共 6 个数字 + 4 个字母）。当前值：$SHORTID" >&2
  exit 1
fi

digits_count=$(printf "%s" "$SHORTID" | tr -cd '0-9' | wc -c | tr -d ' ')
letters_count=$(printf "%s" "$SHORTID" | tr -cd 'a-f' | wc -c | tr -d ' ')
if [ "$digits_count" -lt 6 ] || [ "$letters_count" -lt 4 ]; then
  echo "错误：shortId 必须至少包含 6 个数字和 4 个字母 a-f（总长度 10）。当前数字数：$digits_count, 字母数：$letters_count" >&2
  exit 1
fi

# 生成 inbound JSON（作为纯 JSON 字符串）
INB_JSON=$(cat <<JSON
{
  "port": ${PORT},
  "protocol": "vless",
  "settings": {
    "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision" } ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "dest": "${DEST}",
      "serverNames": [ "${SERVERNAME}" ],
      "privateKey": "${PRIV_KEY}",
      "shortIds": [ "${SHORTID}" ]
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": [ "http", "tls", "quic" ],
    "routeOnly": true
  }
}
JSON
)

# 备份并用 jq 安全追加
if [ ! -f "$CONFIG_JSON" ]; then
  echo "$CONFIG_JSON 不存在，创建最小结构文件。"
  mkdir -p "$(dirname "$CONFIG_JSON")"
  cat > "$CONFIG_JSON" <<-JSON
{
  "log": { "loglevel": "info" },
  "inbounds": [],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
JSON
fi

TS=$(date +%Y%m%d_%H%M%S)
cp -a "$CONFIG_JSON" "$CONFIG_JSON.bak.$TS"
TMP_OUTPUT="$CONFIG_JSON.tmp.$TS"

# 使用 jq --argjson 传入生成的 JSON
jq --argjson new "$INB_JSON" '.inbounds += [$new]' "$CONFIG_JSON" > "$TMP_OUTPUT" || {
  echo "使用 jq 添加 inbound 失败，已恢复备份并退出。" >&2
  mv -f "$CONFIG_JSON.bak.$TS" "$CONFIG_JSON"
  exit 1
}
mv -f "$TMP_OUTPUT" "$CONFIG_JSON"

echo "已将 Reality inbound 追加到 $CONFIG_JSON （原文件备份为 $CONFIG_JSON.bak.$TS）。"

# 重新启动 xray（尝试两种方式）
if command -v rc-service >/dev/null 2>&1; then
  echo "尝试重启 via rc-service xray restart..."
  rc-service xray restart || echo "rc-service restart 失败（可能不存在此服务脚本）"
fi
if command -v systemctl >/dev/null 2>&1; then
  echo "尝试重启 via systemctl restart xray..."
  systemctl restart xray || echo "systemctl restart 失败（请检查 systemd 状态）"
fi

# 获取公网 IP（优先 ip.sb），并去除空白/换行，校验为 IPv4 格式
SERVER_IP=""
if command -v curl >/dev/null 2>&1; then
  SERVER_IP=$(curl -4 -s --connect-timeout 5 ip.sb || true)
  # 去除所有空白字符（包括换行）
  SERVER_IP=$(printf "%s" "$SERVER_IP" | tr -d '[:space:]')
  # 简单校验 IPv4
  if ! printf "%s" "$SERVER_IP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    SERVER_IP=""
  fi
fi
if [ -z "$SERVER_IP" ]; then
  SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
fi
if [ -z "$SERVER_IP" ]; then
  SERVER_IP=127.0.0.1
fi

REMARK="reality-node"
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&encryption=none&pbk=${PUB_KEY}&sid=${SHORTID}&sni=${SERVERNAME}&flow=xtls-rprx-vision&fp=chrome#${REMARK}"

# 打印并追加写入
echo
echo "-- 链接（vless://，可直接导入 v2rayN）："
echo "$VLESS_LINK"


mkdir -p "$(dirname "$REALITY_LOG")"
# 追加写入 reality.txt
echo "$VLESS_LINK" >> "$REALITY_LOG"
echo
echo "已将 reality:// 链接追加到 $REALITY_LOG"

exit 0
