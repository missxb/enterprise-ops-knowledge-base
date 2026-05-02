#!/bin/bash
#============================================================================
# 企业级跨云迁移 - 数据库迁移脚本
# 功能：MySQL 主从迁移、Redis 数据迁移、数据一致性校验
# 用法：./03-db-migrate.sh [mysql|redis|verify|cutover]
#============================================================================

set -euo pipefail

# 配置
MYSQL_SOURCE_HOST="${MYSQL_SOURCE_HOST:-}"
MYSQL_SOURCE_PORT="${MYSQL_SOURCE_PORT:-3306}"
MYSQL_SOURCE_USER="${MYSQL_SOURCE_USER:-root}"
MYSQL_SOURCE_PASS="${MYSQL_SOURCE_PASS:-}"

MYSQL_TARGET_HOST="${MYSQL_TARGET_HOST:-}"
MYSQL_TARGET_PORT="${MYSQL_TARGET_PORT:-3306}"
MYSQL_TARGET_USER="${MYSQL_TARGET_USER:-root}"
MYSQL_TARGET_PASS="${MYSQL_TARGET_PASS:-}"

REDIS_SOURCE_HOST="${REDIS_SOURCE_HOST:-}"
REDIS_SOURCE_PORT="${REDIS_SOURCE_PORT:-6379}"
REDIS_TARGET_HOST="${REDIS_TARGET_HOST:-}"
REDIS_TARGET_PORT="${REDIS_TARGET_PORT:-6379}"

DUMP_DIR="/data/migration/mysql"
LOG_DIR="/var/log/migration"
LOG_FILE="${LOG_DIR}/db-migrate-$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/data/migration/backup"

# 需要迁移的数据库
DATABASES=("app_db" "user_db" "order_db" "log_db")

log() {
    local level=$1; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

#==================== MySQL 迁移 ====================
mysql_dump() {
    log "INFO" "========== MySQL 数据导出 =========="
    mkdir -p "$DUMP_DIR" "$BACKUP_DIR"

    for db in "${DATABASES[@]}"; do
        log "INFO" "导出数据库: $db"

        # 先备份目标端（如果存在）
        ssh -o StrictHostKeyChecking=no "${MYSQL_TARGET_USER}@${MYSQL_TARGET_HOST}" \
            "mysqldump -h 127.0.0.1 -P ${MYSQL_TARGET_PORT} -u${MYSQL_TARGET_USER} -p'${MYSQL_TARGET_PASS}' \
            --single-transaction --routines --triggers --events \
            ${db} > /tmp/${db}_backup_$(date +%Y%m%d).sql 2>/dev/null || true"

        # 从源端导出
        mysqldump -h "$MYSQL_SOURCE_HOST" -P "$MYSQL_SOURCE_PORT" \
            -u"$MYSQL_SOURCE_USER" -p"$MYSQL_SOURCE_PASS" \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --master-data=2 \
            --flush-logs \
            --hex-blob \
            --set-gtid-purged=OFF \
            "$db" | gzip > "${DUMP_DIR}/${db}_$(date +%Y%m%d_%H%M%S).sql.gz"

        if [ $? -eq 0 ]; then
            local size=$(du -sh "${DUMP_DIR}/${db}"*.sql.gz | tail -1 | awk '{print $1}')
            log "INFO" "  导出完成: $db ($size)"
        else
            log "ERROR" "  导出失败: $db"
            return 1
        fi
    done

    # 记录 binlog 位置
    local binlog_info=$(mysql -h "$MYSQL_SOURCE_HOST" -P "$MYSQL_SOURCE_PORT" \
        -u"$MYSQL_SOURCE_USER" -p"$MYSQL_SOURCE_PASS" \
        -e "SHOW MASTER STATUS\G" 2>/dev/null)
    echo "$binlog_info" > "${DUMP_DIR}/binlog_position.txt"
    log "INFO" "Binlog位置已记录: ${DUMP_DIR}/binlog_position.txt"
}

mysql_import() {
    log "INFO" "========== MySQL 数据导入 =========="

    for db in "${DATABASES[@]}"; do
        local dump_file=$(ls -t "${DUMP_DIR}/${db}"*.sql.gz 2>/dev/null | head -1)
        if [ -z "$dump_file" ]; then
            log "ERROR" "未找到 $db 的导出文件"
            continue
        fi

        log "INFO" "导入数据库: $db (文件: $dump_file)"

        # 在目标端创建数据库
        ssh -o StrictHostKeyChecking=no "${MYSQL_TARGET_USER}@${MYSQL_TARGET_HOST}" \
            "mysql -h 127.0.0.1 -P ${MYSQL_TARGET_PORT} -u${MYSQL_TARGET_USER} -p'${MYSQL_TARGET_PASS}' \
            -e \"CREATE DATABASE IF NOT EXISTS \\\`${db}\\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\""

        # 传输并导入
        zcat "$dump_file" | ssh -o StrictHostKeyChecking=no "${MYSQL_TARGET_USER}@${MYSQL_TARGET_HOST}" \
            "mysql -h 127.0.0.1 -P ${MYSQL_TARGET_PORT} -u${MYSQL_TARGET_USER} -p'${MYSQL_TARGET_PASS}' ${db}"

        if [ $? -eq 0 ]; then
            log "INFO" "  导入完成: $db"
        else
            log "ERROR" "  导入失败: $db"
            return 1
        fi
    done
}

mysql_setup_replication() {
    log "INFO" "========== 配置 MySQL 主从复制 =========="

    # 读取 binlog 位置
    local binlog_file=$(grep "File:" "${DUMP_DIR}/binlog_position.txt" | awk '{print $2}')
    local binlog_pos=$(grep "Position:" "${DUMP_DIR}/binlog_position.txt" | awk '{print $2}')

    log "INFO" "Binlog位置: $binlog_file @ $binlog_pos"

    # 在目标端配置复制
    ssh -o StrictHostKeyChecking=no "${MYSQL_TARGET_USER}@${MYSQL_TARGET_HOST}" \
        "mysql -h 127.0.0.1 -P ${MYSQL_TARGET_PORT} -u${MYSQL_TARGET_USER} -p'${MYSQL_TARGET_PASS}' <<EOF
CHANGE MASTER TO
    MASTER_HOST='${MYSQL_SOURCE_HOST}',
    MASTER_PORT=${MYSQL_SOURCE_PORT},
    MASTER_USER='repl',
    MASTER_PASSWORD='repl_password',
    MASTER_LOG_FILE='${binlog_file}',
    MASTER_LOG_POS=${binlog_pos},
    MASTER_SSL=1;
START SLAVE;
EOF"

    # 检查复制状态
    sleep 5
    local slave_status=$(ssh -o StrictHostKeyChecking=no "${MYSQL_TARGET_USER}@${MYSQL_TARGET_HOST}" \
        "mysql -h 127.0.0.1 -P ${MYSQL_TARGET_PORT} -u${MYSQL_TARGET_USER} -p'${MYSQL_TARGET_PASS}' \
        -e 'SHOW SLAVE STATUS\G'" 2>/dev/null)

    local io_running=$(echo "$slave_status" | grep "Slave_IO_Running:" | awk '{print $2}')
    local sql_running=$(echo "$slave_status" | grep "Slave_SQL_Running:" | awk '{print $2}')
    local seconds_behind=$(echo "$slave_status" | grep "Seconds_Behind_Master:" | awk '{print $2}')

    if [ "$io_running" = "Yes" ] && [ "$sql_running" = "Yes" ]; then
        log "INFO" "  主从复制配置成功"
        log "INFO" "  IO线程: $io_running, SQL线程: $sql_running"
        log "INFO" "  延迟: ${seconds_behind}秒"
    else
        log "ERROR" "  主从复制配置失败"
        log "ERROR" "  IO线程: $io_running, SQL线程: $sql_running"
        return 1
    fi
}

#==================== Redis 迁移 ====================
redis_migrate() {
    log "INFO" "========== Redis 数据迁移 =========="

    # 方案1: 使用 RDB 文件迁移
    log "INFO" "方案1: RDB文件迁移"

    # 触发源端 RDB 保存
    redis-cli -h "$REDIS_SOURCE_HOST" -p "$REDIS_SOURCE_PORT" BGSAVE >/dev/null 2>&1
    sleep 5

    # 获取 RDB 文件路径
    local rdb_dir=$(redis-cli -h "$REDIS_SOURCE_HOST" -p "$REDIS_SOURCE_PORT" CONFIG GET dir | tail -1)
    local rdb_file="${rdb_dir}/dump.rdb"

    log "INFO" "RDB文件: $rdb_file"

    # 传输 RDB 文件
    scp -o StrictHostKeyChecking=no "${REDIS_SOURCE_HOST}:${rdb_file}" /tmp/dump_migration.rdb

    # 停止目标端 Redis
    ssh -o StrictHostKeyChecking=no "$REDIS_TARGET_HOST" \
        "systemctl stop redis && cp /tmp/dump_migration.rdb /var/lib/redis/dump.rdb && systemctl start redis"

    if [ $? -eq 0 ]; then
        log "INFO" "  Redis RDB迁移完成"
    else
        log "ERROR" "  Redis RDB迁移失败"
        return 1
    fi

    # 方案2: 使用 redis-shake 工具（适用于大集群）
    log "INFO" "方案2: redis-shake增量同步（可选）"
    log "INFO" "  如需增量同步，请使用 redis-shake 工具"
    log "INFO" "  配置: sync_mode=sync, source=${REDIS_SOURCE_HOST}:${REDIS_SOURCE_PORT}"
}

#==================== 数据校验 ====================
verify_mysql() {
    log "INFO" "========== MySQL 数据校验 =========="

    for db in "${DATABASES[@]}"; do
        log "INFO" "校验数据库: $db"

        # 源端表信息
        local src_tables=$(mysql -h "$MYSQL_SOURCE_HOST" -P "$MYSQL_SOURCE_PORT" \
            -u"$MYSQL_SOURCE_USER" -p"$MYSQL_SOURCE_PASS" \
            -e "SELECT TABLE_NAME, TABLE_ROWS, DATA_LENGTH+INDEX_LENGTH as total_bytes
                FROM information_schema.tables
                WHERE table_schema='${db}'
                ORDER BY TABLE_NAME;" 2>/dev/null)

        # 目标端表信息
        local dst_tables=$(ssh -o StrictHostKeyChecking=no "${MYSQL_TARGET_USER}@${MYSQL_TARGET_HOST}" \
            "mysql -h 127.0.0.1 -P ${MYSQL_TARGET_PORT} -u${MYSQL_TARGET_USER} -p'${MYSQL_TARGET_PASS}' \
            -e \"SELECT TABLE_NAME, TABLE_ROWS, DATA_LENGTH+INDEX_LENGTH as total_bytes
                FROM information_schema.tables
                WHERE table_schema='${db}'
                ORDER BY TABLE_NAME;\"" 2>/dev/null)

        # 对比
        local src_count=$(echo "$src_tables" | wc -l)
        local dst_count=$(echo "$dst_tables" | wc -l)

        if [ "$src_count" = "$dst_count" ]; then
            log "INFO" "  表数量匹配: ${src_count}个表"
        else
            log "ERROR" "  表数量不匹配: 源端=${src_count}, 目标端=${dst_count}"
        fi

        # 逐表对比行数
        mysql -h "$MYSQL_SOURCE_HOST" -P "$MYSQL_SOURCE_PORT" \
            -u"$MYSQL_SOURCE_USER" -p"$MYSQL_SOURCE_PASS" \
            -e "SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.tables WHERE table_schema='${db}';" 2>/dev/null | \
        while read table rows; do
            local target_rows=$(ssh -o StrictHostKeyChecking=no "${MYSQL_TARGET_USER}@${MYSQL_TARGET_HOST}" \
                "mysql -h 127.0.0.1 -P ${MYSQL_TARGET_PORT} -u${MYSQL_TARGET_USER} -p'${MYSQL_TARGET_PASS}' \
                -e \"SELECT TABLE_ROWS FROM information_schema.tables WHERE table_schema='${db}' AND TABLE_NAME='${table}';\"" 2>/dev/null | tail -1)

            if [ "$rows" = "$target_rows" ]; then
                log "INFO" "  [OK] $table: ${rows}行"
            else
                log "WARN" "  [DIFF] $table: 源端=${rows}, 目标端=${target_rows}"
            fi
        done
    done
}

verify_redis() {
    log "INFO" "========== Redis 数据校验 =========="

    local src_keys=$(redis-cli -h "$REDIS_SOURCE_HOST" -p "$REDIS_SOURCE_PORT" DBSIZE | awk '{print $2}')
    local dst_keys=$(redis-cli -h "$REDIS_TARGET_HOST" -p "$REDIS_TARGET_PORT" DBSIZE | awk '{print $2}')

    log "INFO" "源端键数: $src_keys"
    log "INFO" "目标端键数: $dst_keys"

    if [ "$src_keys" = "$dst_keys" ]; then
        log "INFO" "键数量匹配"
    else
        log "WARN" "键数量不匹配，差异: $((src_keys - dst_keys))"
    fi

    # 抽样校验
    log "INFO" "抽样校验 (随机10个键):"
    local sample_keys=$(redis-cli -h "$REDIS_SOURCE_HOST" -p "$REDIS_SOURCE_PORT" RANDOMKEY 2>/dev/null)
    for i in $(seq 1 10); do
        local key=$(redis-cli -h "$REDIS_SOURCE_HOST" -p "$REDIS_SOURCE_PORT" RANDOMKEY 2>/dev/null)
        if [ -n "$key" ]; then
            local src_val=$(redis-cli -h "$REDIS_SOURCE_HOST" -p "$REDIS_SOURCE_PORT" GET "$key" 2>/dev/null)
            local dst_val=$(redis-cli -h "$REDIS_TARGET_HOST" -p "$REDIS_TARGET_PORT" GET "$key" 2>/dev/null)
            if [ "$src_val" = "$dst_val" ]; then
                log "INFO" "  [OK] $key"
            else
                log "WARN" "  [DIFF] $key"
            fi
        fi
    done
}

#==================== 切换操作 ====================
do_cutover() {
    log "INFO" "========== 执行数据库切换 =========="
    log "WARN" "此操作将停止源端写入，切换到目标端！"

    read -p "确认执行切换？(输入 YES): " confirm
    if [ "$confirm" != "YES" ]; then
        log "INFO" "切换已取消"
        return 0
    fi

    # 1. 停止源端应用写入
    log "INFO" "步骤1: 停止应用写入..."
    # 这里可以调用应用停止脚本

    # 2. 等待主从同步完成
    log "INFO" "步骤2: 等待主从同步完成..."
    local max_wait=300
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local behind=$(ssh -o StrictHostKeyChecking=no "${MYSQL_TARGET_USER}@${MYSQL_TARGET_HOST}" \
            "mysql -h 127.0.0.1 -P ${MYSQL_TARGET_PORT} -u${MYSQL_TARGET_USER} -p'${MYSQL_TARGET_PASS}' \
            -e 'SHOW SLAVE STATUS\G'" 2>/dev/null | grep "Seconds_Behind_Master:" | awk '{print $2}')

        if [ "$behind" = "0" ] || [ "$behind" = "NULL" ]; then
            log "INFO" "  主从同步完成"
            break
        fi

        log "INFO" "  等待同步... (延迟: ${behind}秒)"
        sleep 5
        waited=$((waited+5))
    done

    # 3. 停止复制
    log "INFO" "步骤3: 停止主从复制..."
    ssh -o StrictHostKeyChecking=no "${MYSQL_TARGET_USER}@${MYSQL_TARGET_HOST}" \
        "mysql -h 127.0.0.1 -P ${MYSQL_TARGET_PORT} -u${MYSQL_TARGET_USER} -p'${MYSQL_TARGET_PASS}' \
        -e 'STOP SLAVE; RESET SLAVE ALL;'"

    # 4. 切换应用连接
    log "INFO" "步骤4: 切换应用数据库连接..."
    log "INFO" "  请更新应用配置指向: ${MYSQL_TARGET_HOST}:${MYSQL_TARGET_PORT}"

    log "INFO" "=========================================="
    log "INFO" "  数据库切换完成！"
    log "INFO" "  目标端: ${MYSQL_TARGET_HOST}:${MYSQL_TARGET_PORT}"
    log "INFO" "  请验证应用正常运行"
    log "INFO" "=========================================="
}

#==================== 主函数 ====================
main() {
    local action="${1:-help}"

    mkdir -p "$LOG_DIR" "$DUMP_DIR" "$BACKUP_DIR"

    case "$action" in
        mysql)
            mysql_dump
            mysql_import
            mysql_setup_replication
            ;;
        redis)
            redis_migrate
            ;;
        verify)
            verify_mysql
            verify_redis
            ;;
        cutover)
            do_cutover
            ;;
        *)
            echo "用法: $0 [mysql|redis|verify|cutover]"
            echo ""
            echo "  mysql    - 导出、导入、配置MySQL主从复制"
            echo "  redis    - 迁移Redis数据"
            echo "  verify   - 校验数据一致性"
            echo "  cutover  - 执行数据库切换"
            exit 1
            ;;
    esac
}

main "$@"
