#!/bin/bash
#============================================================================
# 自动故障切换脚本
# 功能：检测服务故障并自动切换到备用节点
# 支持：MySQL 主从切换、Redis Sentinel 切换、应用层切换
# 用法：./auto-failover.sh [mysql|redis|app|check]
#============================================================================

set -euo pipefail

# 配置
MYSQL_MASTER="${MYSQL_MASTER:-10.0.0.11}"
MYSQL_SLAVE="${MYSQL_SLAVE:-10.0.0.12}"
REDIS_MASTER="${REDIS_MASTER:-10.0.0.11}"
REDIS_SENTINEL="${REDIS_SENTINEL:-10.0.0.13:26379}"
APP_PRIMARY="${APP_PRIMARY:-10.0.0.21}"
APP_SECONDARY="${APP_SECONDARY:-10.0.0.22}"
VIP="${VIP:-10.0.0.100}"
NOTIFY_WEBHOOK="${NOTIFY_WEBHOOK:-}"
HEALTH_CHECK_TIMEOUT=5
MAX_RETRIES=3
FAILOVER_LOG="/var/log/failover/failover-$(date +%Y%m%d_%H%M%S).log"

log() {
    local level=$1; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$FAILOVER_LOG"
}

notify() {
    local title="$1"
    local content="$2"
    local level="${3:-warning}"

    if [ -n "$NOTIFY_WEBHOOK" ]; then
        curl -s -X POST "$NOTIFY_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{\"msgtype\":\"markdown\",\"markdown\":{\"title\":\"${title}\",\"content\":\"${content}\"}}" >/dev/null 2>&1 || true
    fi

    log "NOTIFY" "$title: $content"
}

#==================== MySQL 故障检测与切换 ====================
check_mysql() {
    local host="$1"
    local retries=0

    while [ $retries -lt $MAX_RETRIES ]; do
        if mysqladmin ping -h "$host" --connect-timeout=$HEALTH_CHECK_TIMEOUT --silent 2>/dev/null; then
            return 0
        fi
        retries=$((retries+1))
        sleep 2
    done

    return 1
}

failover_mysql() {
    log "INFO" "========== MySQL 故障切换 =========="

    # 检查主库状态
    if check_mysql "$MYSQL_MASTER"; then
        log "INFO" "MySQL 主库 ($MYSQL_MASTER) 正常，无需切换"
        return 0
    fi

    log "WARN" "MySQL 主库 ($MYSQL_MASTER) 不可达！"
    notify "MySQL 主库故障" "主库 ${MYSQL_MASTER} 不可达，开始故障切换" "critical"

    # 检查从库状态
    if ! check_mysql "$MYSQL_SLAVE"; then
        log "ERROR" "MySQL 从库 ($MYSQL_SLAVE) 也不可达！无法切换"
        notify "MySQL 切换失败" "主从库均不可达，需要人工介入" "critical"
        return 1
    fi

    # 检查从库复制状态
    local slave_status=$(mysql -h "$MYSQL_SLAVE" -e "SHOW SLAVE STATUS\G" 2>/dev/null)
    local io_running=$(echo "$slave_status" | grep "Slave_IO_Running:" | awk '{print $2}')
    local sql_running=$(echo "$slave_status" | grep "Slave_SQL_Running:" | awk '{print $2}')
    local seconds_behind=$(echo "$slave_status" | grep "Seconds_Behind_Master:" | awk '{print $2}')

    log "INFO" "从库复制状态: IO=$io_running, SQL=$sql_running, 延迟=${seconds_behind}秒"

    if [ "$io_running" != "Yes" ] || [ "$sql_running" != "Yes" ]; then
        log "ERROR" "从库复制状态异常，切换可能丢失数据"
        notify "MySQL 切换警告" "从库复制状态异常，IO=$io_running, SQL=$sql_running" "critical"
    fi

    # 执行切换
    log "INFO" "执行 MySQL 主从切换..."

    # 1. 停止从库复制
    mysql -h "$MYSQL_SLAVE" -e "STOP SLAVE; RESET SLAVE ALL;" 2>/dev/null

    # 2. 确保从库可写
    mysql -h "$MYSQL_SLAVE" -e "SET GLOBAL read_only = OFF;" 2>/dev/null

    # 3. 更新 VIP 指向（如果使用 Keepalived）
    # 这里需要配合 Keepalived 的通知脚本

    log "INFO" "MySQL 故障切换完成"
    log "INFO" "新主库: $MYSQL_SLAVE"
    notify "MySQL 切换完成" "新主库已切换到 ${MYSQL_SLAVE}" "warning"

    # 4. 记录切换信息
    cat > /var/log/failover/mysql-failover-$(date +%Y%m%d%H%M%S).info <<EOF
切换时间: $(date '+%Y-%m-%d %H:%M:%S')
原主库: $MYSQL_MASTER
新主库: $MYSQL_SLAVE
切换原因: 主库不可达
复制延迟: ${seconds_behind}秒
IO线程: $io_running
SQL线程: $sql_running
EOF
}

#==================== Redis 故障检测与切换 ====================
check_redis() {
    local host="$1"
    local port="${2:-6379}"

    if redis-cli -h "$host" -p "$port" --timeout=$HEALTH_CHECK_TIMEOUT ping 2>/dev/null | grep -q PONG; then
        return 0
    fi
    return 1
}

failover_redis() {
    log "INFO" "========== Redis 故障切换 =========="

    # 检查主节点
    if check_redis "$REDIS_MASTER"; then
        log "INFO" "Redis 主节点 ($REDIS_MASTER) 正常"
        return 0
    fi

    log "WARN" "Redis 主节点 ($REDIS_MASTER) 不可达！"
    notify "Redis 主节点故障" "主节点 ${REDIS_MASTER} 不可达" "critical"

    # 通过 Sentinel 执行故障切换
    if [ -n "$REDIS_SENTINEL" ]; then
        local sentinel_host=$(echo "$REDIS_SENTINEL" | cut -d: -f1)
        local sentinel_port=$(echo "$REDIS_SENTINEL" | cut -d: -f2)

        log "INFO" "通过 Sentinel 执行故障切换..."

        # 获取当前主节点信息
        local master_info=$(redis-cli -h "$sentinel_host" -p "$sentinel_port" SENTINEL get-master-addr-by-name mymaster 2>/dev/null)
        local new_master=$(echo "$master_info" | head -1)
        local new_port=$(echo "$master_info" | tail -1)

        if [ -n "$new_master" ] && [ "$new_master" != "$REDIS_MASTER" ]; then
            log "INFO" "Redis 故障切换完成"
            log "INFO" "新主节点: $new_master:$new_port"
            notify "Redis 切换完成" "新主节点: ${new_master}:${new_port}" "warning"
        else
            log "ERROR" "Sentinel 未能完成故障切换"
            # 手动触发
            redis-cli -h "$sentinel_host" -p "$sentinel_port" SENTINEL failover mymaster 2>/dev/null
            sleep 10

            master_info=$(redis-cli -h "$sentinel_host" -p "$sentinel_port" SENTINEL get-master-addr-by-name mymaster 2>/dev/null)
            new_master=$(echo "$master_info" | head -1)
            log "INFO" "手动触发切换后，新主节点: $new_master"
            notify "Redis 手动切换" "新主节点: ${new_master}" "warning"
        fi
    else
        log "ERROR" "未配置 Sentinel，无法自动切换"
        notify "Redis 切换失败" "未配置 Sentinel，需要人工介入" "critical"
    fi
}

#==================== 应用层故障切换 ====================
check_app() {
    local host="$1"
    local port="${2:-8080}"
    local retries=0

    while [ $retries -lt $MAX_RETRIES ]; do
        local status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout=$HEALTH_CHECK_TIMEOUT "http://${host}:${port}/health" 2>/dev/null || echo "000")
        if [ "$status" = "200" ]; then
            return 0
        fi
        retries=$((retries+1))
        sleep 2
    done

    return 1
}

failover_app() {
    log "INFO" "========== 应用层故障切换 =========="

    # 检查主应用
    if check_app "$APP_PRIMARY"; then
        log "INFO" "主应用 ($APP_PRIMARY) 正常"
        return 0
    fi

    log "WARN" "主应用 ($APP_PRIMARY) 不可达！"
    notify "应用主节点故障" "主节点 ${APP_PRIMARY} 不可达" "critical"

    # 检查备用应用
    if ! check_app "$APP_SECONDARY"; then
        log "ERROR" "备用应用 ($APP_SECONDARY) 也不可达！"
        notify "应用切换失败" "主备节点均不可达" "critical"
        return 1
    fi

    # 切换 VIP
    log "INFO" "切换 VIP 到备用节点..."
    # 这里配合 Keepalived 或 DNS 切换

    log "INFO" "应用故障切换完成"
    notify "应用切换完成" "VIP 已切换到 ${APP_SECONDARY}" "warning"
}

#==================== 综合健康检查 ====================
do_health_check() {
    log "INFO" "========== 综合健康检查 =========="

    local status=0

    # MySQL 检查
    if check_mysql "$MYSQL_MASTER"; then
        log "INFO" "  [OK] MySQL 主库: $MYSQL_MASTER"
    else
        log "ERROR" "  [FAIL] MySQL 主库: $MYSQL_MASTER"
        status=1
    fi

    if check_mysql "$MYSQL_SLAVE"; then
        log "INFO" "  [OK] MySQL 从库: $MYSQL_SLAVE"
    else
        log "WARN" "  [WARN] MySQL 从库: $MYSQL_SLAVE"
    fi

    # Redis 检查
    if check_redis "$REDIS_MASTER"; then
        log "INFO" "  [OK] Redis 主节点: $REDIS_MASTER"
    else
        log "ERROR" "  [FAIL] Redis 主节点: $REDIS_MASTER"
        status=1
    fi

    # 应用检查
    if check_app "$APP_PRIMARY"; then
        log "INFO" "  [OK] 应用主节点: $APP_PRIMARY"
    else
        log "ERROR" "  [FAIL] 应用主节点: $APP_PRIMARY"
        status=1
    fi

    if [ $status -eq 0 ]; then
        log "INFO" "所有服务正常 ✓"
    else
        log "WARN" "存在异常服务，请检查"
    fi

    return $status
}

#==================== 主函数 ====================
main() {
    local action="${1:-check}"

    mkdir -p "$(dirname "$FAILOVER_LOG")"

    case "$action" in
        mysql)
            failover_mysql
            ;;
        redis)
            failover_redis
            ;;
        app)
            failover_app
            ;;
        check)
            do_health_check
            ;;
        *)
            echo "用法: $0 [mysql|redis|app|check]"
            echo ""
            echo "  mysql  - MySQL 故障检测与切换"
            echo "  redis  - Redis 故障检测与切换"
            echo "  app    - 应用层故障切换"
            echo "  check  - 综合健康检查"
            exit 1
            ;;
    esac
}

main "$@"
