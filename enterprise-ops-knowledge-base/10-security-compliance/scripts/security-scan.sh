#!/bin/bash
#============================================
# 安全扫描脚本
# 用法: ./security-scan.sh [target_ip]
#============================================
set -euo pipefail

TARGET=${1:-localhost}
REPORT_DIR="/tmp/security-scan-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$REPORT_DIR"

echo "=== 安全扫描开始: $(date) ==="
echo "目标: $TARGET"
echo "报告目录: $REPORT_DIR"

# 1. 系统信息收集
echo "[1/6] 收集系统信息..."
uname -a > "$REPORT_DIR/system-info.txt"
cat /etc/os-release >> "$REPORT_DIR/system-info.txt"

# 2. 开放端口扫描
echo "[2/6] 扫描开放端口..."
ss -tlnp > "$REPORT_DIR/open-ports.txt"
netstat -an > "$REPORT_DIR/network-connections.txt"

# 3. 用户检查
echo "[3/6] 检查用户..."
echo "--- UID 0 用户 ---" > "$REPORT_DIR/user-check.txt"
awk -F: '$3 == 0 {print $1}' /etc/passwd >> "$REPORT_DIR/user-check.txt"
echo "--- 空密码用户 ---" >> "$REPORT_DIR/user-check.txt"
awk -F: '$2 == "" {print $1}' /etc/shadow >> "$REPORT_DIR/user-check.txt"
echo "--- 最近登录 ---" >> "$REPORT_DIR/user-check.txt"
last -20 >> "$REPORT_DIR/user-check.txt"

# 4. 文件权限检查
echo "[4/6] 检查文件权限..."
find / -perm -4000 -type f > "$REPORT_DIR/suid-files.txt" 2>/dev/null
find / -xdev -type f -perm -0002 > "$REPORT_DIR/world-writable.txt" 2>/dev/null

# 5. 服务检查
echo "[5/6] 检查运行服务..."
systemctl list-units --type=service --state=running > "$REPORT_DIR/running-services.txt"

# 6. 日志检查
echo "[6/6] 检查安全日志..."
grep "Failed password" /var/log/secure 2>/dev/null | tail -50 > "$REPORT_DIR/failed-logins.txt" || true
grep "Accepted" /var/log/secure 2>/dev/null | tail -20 > "$REPORT_DIR/successful-logins.txt" || true

echo "=== 扫描完成: $(date) ==="
echo "报告位置: $REPORT_DIR"
ls -la "$REPORT_DIR"
