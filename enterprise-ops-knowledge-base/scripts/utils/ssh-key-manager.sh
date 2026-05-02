#!/bin/bash
#============================================
# SSH Key 管理脚本
# 用法:
#   生成: ./ssh-key-manager.sh generate <user> <host>
#   分发: ./ssh-key-manager.sh deploy <user> <host>
#   检查: ./ssh-key-manager.sh check <user> <host>
#============================================
set -euo pipefail

ACTION=${1:?"用法: $0 <generate|deploy|check> <user> <host>"}
USER=${2:?"请指定用户"}
HOST=${3:?"请指定主机"}
KEY_DIR="$HOME/.ssh"
KEY_FILE="$KEY_DIR/id_ed25519_${USER}_${HOST}"

generate_key() {
    mkdir -p "$KEY_DIR"
    if [ -f "$KEY_FILE" ]; then
        echo "密钥已存在: $KEY_FILE"
        return
    fi
    ssh-keygen -t ed25519 -f "$KEY_FILE" -C "${USER}@${HOST}" -N ""
    echo "✅ 密钥已生成: $KEY_FILE"
}

deploy_key() {
    if [ ! -f "$KEY_FILE" ]; then
        echo "❌ 密钥不存在: $KEY_FILE，请先生成"
        exit 1
    fi
    ssh-copy-id -i "$KEY_FILE.pub" "${USER}@${HOST}"
    echo "✅ 密钥已分发到 ${USER}@${HOST}"
}

check_key() {
    echo "=== SSH 密钥检查 ==="
    echo "用户: $USER"
    echo "主机: $HOST"
    echo "密钥: $KEY_FILE"
    if ssh -i "$KEY_FILE" -o BatchMode=yes -o ConnectTimeout=5 "${USER}@${HOST}" "echo '✅ SSH 连接成功'" 2>/dev/null; then
        :
    else
        echo "❌ SSH 连接失败"
    fi
}

case "$ACTION" in
    generate) generate_key ;;
    deploy) deploy_key ;;
    check) check_key ;;
    *) echo "用法: $0 <generate|deploy|check> <user> <host>" ;;
esac
