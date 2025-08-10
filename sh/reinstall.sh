#!/usr/bin/env bash
set -euo pipefail

REINSTALL_URL="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"

download_reinstall_sh() {
  if [ -f reinstall.sh ]; then
    echo "发现本地 reinstall.sh，跳过下载。"
    return 0
  fi

  echo "尝试下载 reinstall.sh ..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o reinstall.sh "$REINSTALL_URL" || true
  fi
  if [ ! -s reinstall.sh ] && command -v wget >/dev/null 2>&1; then
    wget -qO reinstall.sh "$REINSTALL_URL" || true
  fi

  if [ ! -s reinstall.sh ]; then
    echo "下载失败：无法获取 reinstall.sh。请检查网络或手动下载： $REINSTALL_URL"
    return 1
  fi
  chmod +x reinstall.sh
  echo "下载完成：reinstall.sh"
}

prompt_choice() {
  echo
  echo "请选择要安装的系统（直接回车默认：debian 12 并使用 ssh port 22）："
  echo "1) debian"
  echo "2) ubuntu"
  echo "3) alpine"
  echo "4) fnos"
  printf "输入数字选择（1-4），或直接回车: "
  read -r choice
  echo
}

choose_debian() {
  while true; do
    printf "请选择 Debian 版本（9 10 11 12 13），直接回车默认 12: "
    read -r ver
    ver="${ver:-12}"
    case "$ver" in
      9|10|11|12|13)
        OS="debian"
        VER="$ver"
        break
        ;;
      *)
        echo "无效选择，请输入 9、10、11、12 或 13。"
        ;;
    esac
  done
}

choose_ubuntu() {
  echo "Ubuntu 版本选项："
  echo "1) 20.04"
  echo "2) 22.04"
  echo "3) 24.04"
  echo "4) 25.04"
  echo "5) 18.04"
  echo "6) 16.04"
  while true; do
    printf "输入 1-6 (直接回车默认 2 => 22.04): "
    read -r idx
    idx="${idx:-2}"
    case "$idx" in
      1) OS="ubuntu"; VER="20.04"; break ;;
      2) OS="ubuntu"; VER="22.04"; break ;;
      3) OS="ubuntu"; VER="24.04"; break ;;
      4) OS="ubuntu"; VER="25.04"; break ;;
      5) OS="ubuntu"; VER="18.04"; break ;;
      6) OS="ubuntu"; VER="16.04"; break ;;
      *) echo "无效选择，请输入 1-6。" ;;
    esac
  done
}

choose_alpine() {
  echo "Alpine 版本选项："
  echo "1) 3.22"
  echo "2) 3.21"
  echo "3) 3.20"
  echo "4) 3.19"
  while true; do
    printf "输入 1-4 (直接回车默认 1 => 3.22): "
    read -r idx
    idx="${idx:-1}"
    case "$idx" in
      1) OS="alpine"; VER="3.22"; break ;;
      2) OS="alpine"; VER="3.21"; break ;;
      3) OS="alpine"; VER="3.20"; break ;;
      4) OS="alpine"; VER="3.19"; break ;;
      *) echo "无效选择，请输入 1-4。" ;;
    esac
  done
}

prompt_ssh_port() {
  while true; do
    printf "设置 SSH 端口（1-65535），直接回车默认 22: "
    read -r port_in
    port_in="${port_in:-22}"
    if ! printf '%s' "$port_in" | grep -Eq '^[0-9]+$'; then
      echo "端口必须为数字。"
      continue
    fi
    if [ "$port_in" -ge 1 ] 2>/dev/null && [ "$port_in" -le 65535 ] 2>/dev/null; then
      SSH_PORT="$port_in"
      break
    else
      echo "端口范围必须在 1 到 65535 之间。"
    fi
  done
}

prompt_password() {
  while true; do
    printf "请输入密码 (--password)（不得为空，直接回车将退出）: "
    read -r -s PASS
    echo
    PASS="${PASS:-}"
    if [ -z "$PASS" ]; then
      echo "未输入密码，脚本退出。"
      exit 1
    fi
    printf "请再次输入密码确认: "
    read -r -s PASS2
    echo
    if [ "$PASS" != "$PASS2" ]; then
      echo "两次输入的密码不一致，请重新输入。"
      continue
    fi
    PASSWORD="$PASS"
    break
  done
}

main() {
  download_reinstall_sh || exit 1

  prompt_choice
  if [ -z "${choice:-}" ]; then
    # 直接回车：默认 debian 12 + ssh 22
    OS="debian"
    VER="12"
    SSH_PORT=22
    echo "使用默认：${OS} ${VER}，SSH 端口 ${SSH_PORT}"
    prompt_password
  else
    case "$choice" in
      1) choose_debian ;;
      2) choose_ubuntu ;;
      3) choose_alpine ;;
      4) OS="fnos"; VER=""; ;;
      *) echo "无效选择，脚本退出。"; exit 1 ;;
    esac

    prompt_ssh_port
    prompt_password
  fi

  echo
  # 显示将要执行的命令（隐藏明文密码）
  if [ -n "${VER:-}" ]; then
    echo "将执行 (masked):"
    echo "bash reinstall.sh \"$OS\" \"$VER\" --ssh-port $SSH_PORT --password ******"
  else
    echo "将执行 (masked):"
    echo "bash reinstall.sh \"$OS\" --ssh-port $SSH_PORT --password ******"
  fi

  printf "确认执行？(y/N): "
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "开始执行安装脚本..."
    if [ -n "${VER:-}" ]; then
      # 传两个位置参数：OS 和 VER
      bash reinstall.sh "$OS" "$VER" --ssh-port "$SSH_PORT" --password "$PASSWORD"
    else
      # 只传 OS
      bash reinstall.sh "$OS" --ssh-port "$SSH_PORT" --password "$PASSWORD"
    fi
  else
    echo "已取消。"
    exit 0
  fi
}

main
