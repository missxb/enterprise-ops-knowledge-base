#!/bin/bash
#============================================
# 服务器信息收集脚本
# 用法: ./server-info.sh [output_file]
#============================================
set -euo pipefail

OUTPUT=${1:-"server-info-$(hostname)-$(date +%Y%m%d).txt"}

echo "=== 服务器信息收集 ===" | tee "$OUTPUT"
echo "收集时间: $(date)" | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# 系统信息
echo "--- 系统信息 ---" | tee -a "$OUTPUT"
echo "主机名: $(hostname)" | tee -a "$OUTPUT"
echo "操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)" | tee -a "$OUTPUT"
echo "内核版本: $(uname -r)" | tee -a "$OUTPUT"
echo "系统运行时间: $(uptime -p)" | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# CPU 信息
echo "--- CPU 信息 ---" | tee -a "$OUTPUT"
echo "CPU 型号: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)" | tee -a "$OUTPUT"
echo "CPU 核心数: $(nproc)" | tee -a "$OUTPUT"
echo "CPU 使用率: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}')%" | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# 内存信息
echo "--- 内存信息 ---" | tee -a "$OUTPUT"
free -h | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# 磁盘信息
echo "--- 磁盘信息 ---" | tee -a "$OUTPUT"
df -hT | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# 网络信息
echo "--- 网络信息 ---" | tee -a "$OUTPUT"
ip addr show | grep -E "inet " | awk '{print $2, $NF}' | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# 监听端口
echo "--- 监听端口 ---" | tee -a "$OUTPUT"
ss -tlnp | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"

# 进程 TOP 10
echo "--- CPU TOP 10 进程 ---" | tee -a "$OUTPUT"
ps aux --sort=-%cpu | head -11 | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"
echo "--- 内存 TOP 10 进程 ---" | tee -a "$OUTPUT"
ps aux --sort=-%mem | head -11 | tee -a "$OUTPUT"

echo "" | tee -a "$OUTPUT"
echo "=== 收集完成，输出到: $OUTPUT ==="
