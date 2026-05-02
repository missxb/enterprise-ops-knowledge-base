#!/bin/bash
#============================================
# 服务健康检查脚本
# 用法: ./service-health.sh <config_file>
#============================================
set -euo pipefail

CONFIG=${1:-"/etc/health-check/services.conf"}
REPORT="/tmp/health-report-$(date +%Y%m%d-%H%M%S).txt"

# 默认检查列表（如果没有配置文件）
declare -A SERVICES=(
    ["nginx"]="http://localhost:80/health"
    ["mysql"]="tcp:localhost:3306"
    ["redis"]="tcp:localhost:6379"
)

check_http() {
    local name=$1 url=$2
    if curl -sf -o /dev/null -w "%{http_code}" --max-time 5 "$url" | grep -q "200"; then
        echo "✅ $name: OK ($url)" | tee -a "$REPORT"
    else
        echo "❌ $name: FAILED ($url)" | tee -a "$REPORT"
    fi
}

check_tcp() {
    local name=$1 host=$2 port=$3
    if timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        echo "✅ $name: OK ($host:$port)" | tee -a "$REPORT"
    else
        echo "❌ $name: FAILED ($host:$port)" | tee -a "$REPORT"
    fi
}

echo "=== 服务健康检查 $(date) ===" | tee "$REPORT"
echo "" | tee -a "$REPORT"

for service in "${!SERVICES[@]}"; do
    endpoint="${SERVICES[$service]}"
    if [[ $endpoint == http* ]]; then
        check_http "$service" "$endpoint"
    elif [[ $endpoint == tcp:* ]]; then
        host_port="${endpoint#tcp:}"
        check_tcp "$service" "${host_port%%:*}" "${host_port##*:}"
    fi
done

echo "" | tee -a "$REPORT"
echo "报告: $REPORT"
