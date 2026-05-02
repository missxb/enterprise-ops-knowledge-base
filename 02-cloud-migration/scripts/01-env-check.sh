#!/bin/bash
#============================================================================
# 企业级跨云迁移 - 环境检查脚本
# 功能：迁移前全面检查源端和目标端环境
# 用法：./01-env-check.sh [--source|--target|--all]
#============================================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志配置
LOG_DIR="/var/log/migration"
LOG_FILE="${LOG_DIR}/env-check-$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

# 加载配置
CONFIG_FILE="${1:-/etc/migration/config.yaml}"

log() {
    local level=$1; shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "$LOG_FILE"
}

check_pass() { log "INFO" "${GREEN}[PASS]${NC} $*"; }
check_fail() { log "ERROR" "${RED}[FAIL]${NC} $*"; }
check_warn() { log "WARN" "${YELLOW}[WARN]${NC} $*"; }
check_info() { log "INFO" "${BLUE}[INFO]${NC} $*"; }

#==================== 系统基础检查 ====================
check_system() {
    check_info "========== 系统基础检查 =========="

    # 操作系统版本
    if [ -f /etc/os-release ]; then
        local os_name=$(grep ^PRETTY_NAME /etc/os-release | cut -d'"' -f2)
        check_pass "操作系统: $os_name"
    else
        check_fail "无法获取操作系统信息"
    fi

    # 内核版本
    local kernel=$(uname -r)
    check_pass "内核版本: $kernel"

    # CPU信息
    local cpu_count=$(nproc)
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    check_pass "CPU: ${cpu_count}核 - ${cpu_model}"

    # 内存信息
    local mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    local mem_percent=$(free | awk '/^Mem:/ {printf("%.1f", $3/$2*100)}')
    if (( $(echo "$mem_percent > 80" | bc -l) )); then
        check_warn "内存使用率: ${mem_percent}% (${mem_used}/${mem_total}) - 偏高"
    else
        check_pass "内存使用率: ${mem_percent}% (${mem_used}/${mem_total})"
    fi

    # 磁盘信息
    check_info "磁盘使用情况:"
    df -h | grep -E '^/dev/' | while read line; do
        local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local mount=$(echo "$line" | awk '{print $6}')
        if [ "$usage" -gt 85 ]; then
            check_warn "  $mount 使用率 ${usage}% - 偏高"
        else
            check_pass "  $mount 使用率 ${usage}%"
        fi
    done

    # 系统负载
    local load_1=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $1}' | xargs)
    local load_5=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $2}' | xargs)
    local load_15=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $3}' | xargs)
    check_pass "系统负载: 1min=${load_1} 5min=${load_5} 15min=${load_15}"
}

#==================== 网络连通性检查 ====================
check_network() {
    check_info "========== 网络连通性检查 =========="

    # DNS解析
    if nslookup cloud.tencent.com >/dev/null 2>&1; then
        check_pass "DNS解析正常"
    else
        check_fail "DNS解析异常"
    fi

    # 目标端网络连通性（需要配置目标端IP）
    local target_ip="${TARGET_IP:-}"
    if [ -n "$target_ip" ]; then
        if ping -c 3 -W 5 "$target_ip" >/dev/null 2>&1; then
            check_pass "目标端网络可达: $target_ip"
        else
            check_fail "目标端网络不可达: $target_ip"
        fi

        # 带宽测试
        if command -v iperf3 >/dev/null 2>&1; then
            check_info "测试跨云带宽..."
            local bandwidth=$(iperf3 -c "$target_ip" -t 5 -J 2>/dev/null | \
                python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d[\"end\"][\"sum_sent\"][\"bits_per_second\"]/1e9:.2f} Gbps')" 2>/dev/null || echo "N/A")
            check_pass "跨云带宽: $bandwidth"
        fi
    else
        check_warn "未配置目标端IP，跳过网络连通性检查"
    fi

    # 安全组/防火墙规则检查
    check_info "当前防火墙规则:"
    if command -v iptables >/dev/null 2>&1; then
        iptables -L -n --line-numbers 2>/dev/null | head -20 | while read line; do
            check_info "  $line"
        done
    fi

    # 检查关键端口
    local ports=(22 80 443 3306 6379 8080 9090)
    for port in "${ports[@]}"; do
        if ss -tlnp | grep -q ":${port} "; then
            check_pass "端口 $port 已监听"
        else
            check_warn "端口 $port 未监听"
        fi
    done
}

#==================== 服务状态检查 ====================
check_services() {
    check_info "========== 服务状态检查 =========="

    # 关键服务列表
    local services=(
        "nginx:Web服务"
        "docker:容器服务"
        "mysqld:MySQL数据库"
        "redis:Redis缓存"
        "rsyslog:系统日志"
        "crond:定时任务"
        "sshd:SSH服务"
    )

    for svc_info in "${services[@]}"; do
        local svc_name="${svc_info%%:*}"
        local svc_desc="${svc_info##*:}"

        if systemctl is-active "$svc_name" >/dev/null 2>&1; then
            check_pass "$svc_desc ($svc_name): 运行中"
        elif systemctl is-enabled "$svc_name" >/dev/null 2>&1; then
            check_warn "$svc_desc ($svc_name): 已停止但已启用"
        else
            check_info "$svc_desc ($svc_name): 未安装或未启用"
        fi
    done
}

#==================== Docker环境检查 ====================
check_docker() {
    check_info "========== Docker环境检查 =========="

    if ! command -v docker >/dev/null 2>&1; then
        check_warn "Docker未安装"
        return
    fi

    local docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    check_pass "Docker版本: $docker_ver"

    # 运行中的容器
    local running=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)
    check_info "运行中的容器:"
    echo "$running" | while read line; do
        check_info "  $line"
    done

    # Docker存储使用
    local docker_usage=$(docker system df 2>/dev/null)
    check_info "Docker存储使用:"
    echo "$docker_usage" | while read line; do
        check_info "  $line"
    done

    # 镜像列表
    local images=$(docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null | head -20)
    check_info "Docker镜像（前20）:"
    echo "$images" | while read line; do
        check_info "  $line"
    done
}

#==================== 数据库检查 ====================
check_database() {
    check_info "========== 数据库检查 =========="

    # MySQL检查
    if command -v mysql >/dev/null 2>&1; then
        if mysqladmin ping -h 127.0.0.1 --silent 2>/dev/null; then
            check_pass "MySQL连接正常"

            # 数据库大小
            local db_size=$(mysql -h 127.0.0.1 -e "
                SELECT table_schema AS 'Database',
                       ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS 'Size (GB)'
                FROM information_schema.tables
                GROUP BY table_schema
                ORDER BY SUM(data_length + index_length) DESC;" 2>/dev/null)
            check_info "数据库大小:"
            echo "$db_size" | while read line; do
                check_info "  $line"
            done

            # 主从状态
            local slave_status=$(mysql -h 127.0.0.1 -e "SHOW SLAVE STATUS\G" 2>/dev/null | \
                grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master")
            if [ -n "$slave_status" ]; then
                check_info "主从复制状态:"
                echo "$slave_status" | while read line; do
                    check_info "  $line"
                done
            fi

            # 慢查询检查
            local slow_queries=$(mysql -h 127.0.0.1 -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';" 2>/dev/null | awk 'NR==2{print $2}')
            check_info "慢查询数: ${slow_queries:-N/A}"
        else
            check_warn "MySQL连接失败"
        fi
    else
        check_info "MySQL客户端未安装"
    fi

    # Redis检查
    if command -v redis-cli >/dev/null 2>&1; then
        if redis-cli ping 2>/dev/null | grep -q PONG; then
            check_pass "Redis连接正常"
            local redis_mem=$(redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
            local redis_keys=$(redis-cli dbsize 2>/dev/null | awk '{print $2}')
            check_info "Redis内存使用: $redis_mem"
            check_info "Redis键数量: $redis_keys"
        else
            check_warn "Redis连接失败"
        fi
    else
        check_info "Redis客户端未安装"
    fi
}

#==================== 应用检查 ====================
check_applications() {
    check_info "========== 应用检查 =========="

    # 检查Web服务响应
    local endpoints=(
        "http://localhost:80:Web首页"
        "http://localhost:8080/api/health:API健康检查"
        "http://localhost:9090:Prometheus监控"
    )

    for ep in "${endpoints[@]}"; do
        local url=$(echo "$ep" | cut -d: -f1-2)
        local desc=$(echo "$ep" | cut -d: -f3)
        local status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
        if [ "$status" = "200" ]; then
            check_pass "$desc ($url): HTTP $status"
        elif [ "$status" = "000" ]; then
            check_warn "$desc ($url): 连接失败"
        else
            check_warn "$desc ($url): HTTP $status"
        fi
    done

    # 进程检查
    check_info "关键进程检查:"
    local procs=("nginx" "java" "python" "node" "mysql" "redis")
    for proc in "${procs[@]}"; do
        local count=$(pgrep -c "$proc" 2>/dev/null || echo "0")
        if [ "$count" -gt 0 ]; then
            check_pass "  $proc: ${count}个进程运行中"
        fi
    done
}

#==================== 定时任务检查 ====================
check_crontab() {
    check_info "========== 定时任务检查 =========="

    # 系统级定时任务
    check_info "系统级定时任务:"
    for cron_dir in /etc/cron.d /etc/cron.daily /etc/cron.hourly; do
        if [ -d "$cron_dir" ]; then
            local count=$(ls -1 "$cron_dir" 2>/dev/null | wc -l)
            check_info "  $cron_dir: ${count}个任务"
        fi
    done

    # 用户级定时任务
    check_info "当前用户定时任务:"
    crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | while read line; do
        check_info "  $line"
    done
}

#==================== 安全检查 ====================
check_security() {
    check_info "========== 安全检查 =========="

    # SSH配置
    check_info "SSH安全配置:"
    local ssh_port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    local root_login=$(grep "^PermitRootLogin " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "默认")
    local pwd_auth=$(grep "^PasswordAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "默认")
    check_info "  SSH端口: $ssh_port"
    check_info "  Root登录: $root_login"
    check_info "  密码认证: $pwd_auth"

    # 最近登录
    check_info "最近5次登录:"
    last -n 5 2>/dev/null | while read line; do
        check_info "  $line"
    done

    # 最近失败登录
    check_info "最近5次失败登录:"
    lastb -n 5 2>/dev/null | while read line; do
        check_info "  $line"
    done

    # 检查可疑进程
    check_info "高资源使用进程 Top10:"
    ps aux --sort=-%cpu | head -11 | tail -10 | while read line; do
        check_info "  $line"
    done
}

#==================== 生成检查报告 ====================
generate_report() {
    local report_file="${LOG_DIR}/env-check-report-$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "=========================================="
        echo "  环境检查报告"
        echo "  生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  主机名: $(hostname)"
        echo "  IP地址: $(hostname -I | awk '{print $1}')"
        echo "=========================================="
        echo ""
        cat "$LOG_FILE"
        echo ""
        echo "=========================================="
        echo "  检查完成，详细日志: $LOG_FILE"
        echo "=========================================="
    } > "$report_file"

    check_info "检查报告已生成: $report_file"
}

#==================== 主函数 ====================
main() {
    echo ""
    echo "============================================"
    echo "  企业级跨云迁移 - 环境检查工具 v1.0"
    echo "  检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"
    echo ""

    check_system
    echo ""
    check_network
    echo ""
    check_services
    echo ""
    check_docker
    echo ""
    check_database
    echo ""
    check_applications
    echo ""
    check_crontab
    echo ""
    check_security
    echo ""
    generate_report

    echo ""
    echo "============================================"
    echo "  检查完成！"
    echo "  日志文件: $LOG_FILE"
    echo "============================================"
}

main "$@"
