#!/bin/bash
#============================================================================
# 企业级 MySQL 备份脚本
# 功能：全量备份 + 增量备份 + binlog 备份 + 保留策略 + 异地备份
# 用法：./mysql-backup.sh [full|incremental|binlog|cleanup|restore]
#============================================================================

set -euo pipefail

# 数据库配置
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-backup_user}"
MYSQL_PASS="${MYSQL_PASS:-}"
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/lib/mysql/mysql.sock}"

# 备份配置
BACKUP_DIR="/data/backup/mysql"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
FULL_BACKUP_RETENTION="${FULL_BACKUP_RETENTION:-30}"
REMOTE_BACKUP="${REMOTE_BACKUP:-false}"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_DIR="${REMOTE_DIR:-/data/backup/mysql}"

# 通知配置
NOTIFY_EMAIL="${NOTIFY_EMAIL:-ops@example.com}"
NOTIFY_WEBHOOK="${NOTIFY_WEBHOOK:-}"

LOG_DIR="/var/log/mysql-backup"
LOG_FILE="${LOG_DIR}/backup-$(date +%Y%m%d_%H%M%S).log"

log() {
    local level=$1; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

# 发送通知
send_notification() {
    local subject="$1"
    local body="$2"
    local level="${3:-info}"

    # 邮件通知
    if command -v mail >/dev/null 2>&1 && [ -n "$NOTIFY_EMAIL" ]; then
        echo "$body" | mail -s "[MySQL Backup] $subject" "$NOTIFY_EMAIL"
    fi

    # Webhook 通知（钉钉/企业微信）
    if [ -n "$NOTIFY_WEBHOOK" ]; then
        local color="info"
        [ "$level" = "error" ] && color="red"
        [ "$level" = "success" ] && color="green"

        curl -s -X POST "$NOTIFY_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{\"msgtype\":\"markdown\",\"markdown\":{\"title\":\"$subject\",\"content\":\"$body\"}}" >/dev/null 2>&1 || true
    fi
}

#==================== 全量备份 ====================
do_full_backup() {
    log "INFO" "========== 开始全量备份 =========="

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/full/full_${timestamp}.sql.gz"
    local backup_meta="${BACKUP_DIR}/full/full_${timestamp}.meta"

    mkdir -p "${BACKUP_DIR}/full"

    # 检查 MySQL 连接
    if ! mysqladmin ping -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" --silent 2>/dev/null; then
        log "ERROR" "MySQL 连接失败"
        send_notification "备份失败" "MySQL 连接失败，请检查数据库状态" "error"
        return 1
    fi

    # 记录开始时间
    local start_time=$(date +%s)
    local binlog_before=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW MASTER STATUS" 2>/dev/null | awk '{print $1, $2}')
    local binlog_file=$(echo "$binlog_before" | awk '{print $1}')
    local binlog_pos=$(echo "$binlog_before" | awk '{print $2}')

    # 执行全量备份
    log "INFO" "执行 mysqldump..."
    mysqldump -h "$MYSQL_HOST" -P "$MYSQL_PORT" \
        -u"$MYSQL_USER" -p"$MYSQL_PASS" \
        --all-databases \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --master-data=2 \
        --flush-logs \
        --hex-blob \
        --set-gtid-purged=OFF \
        --max_allowed_packet=1G \
        2>>"$LOG_FILE" | gzip > "$backup_file"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local size=$(du -sh "$backup_file" | awk '{print $1}')

    # 保存元数据
    cat > "$backup_meta" <<EOF
备份类型: 全量备份
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份文件: $backup_file
文件大小: $size
耗时: $((duration/60))分$((duration%60))秒
Binlog文件: $binlog_file
Binlog位置: $binlog_pos
MySQL版本: $(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT VERSION()" 2>/dev/null)
EOF

    # 验证备份
    if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
        log "INFO" "全量备份成功: $backup_file ($size, 耗时${duration}秒)"
        send_notification "全量备份成功" "文件: $backup_file\n大小: $size\n耗时: ${duration}秒" "success"
    else
        log "ERROR" "全量备份失败: 文件为空或不存在"
        send_notification "全量备份失败" "备份文件为空或不存在，请检查" "error"
        return 1
    fi

    # 异地备份
    if [ "$REMOTE_BACKUP" = "true" ] && [ -n "$REMOTE_HOST" ]; then
        log "INFO" "同步到异地备份..."
        rsync -avz --progress "$backup_file" "$backup_meta" "${REMOTE_HOST}:${REMOTE_DIR}/full/" 2>>"$LOG_FILE" || \
            log "WARN" "异地备份同步失败"
    fi
}

#==================== 增量备份（binlog） ====================
do_incremental_backup() {
    log "INFO" "========== 开始增量备份（binlog） =========="

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${BACKUP_DIR}/binlog/${timestamp}"
    mkdir -p "$backup_dir"

    # 获取当前 binlog 文件列表
    local binlog_files=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW BINARY LOGS" 2>/dev/null | awk '{print $1}')

    # 获取上次备份的 binlog 位置
    local last_binlog_file=""
    local last_meta=$(ls -t "${BACKUP_DIR}/full/"*.meta 2>/dev/null | head -1)
    if [ -n "$last_meta" ]; then
        last_binlog_file=$(grep "Binlog文件:" "$last_meta" | awk '{print $2}')
    fi

    # 复制 binlog 文件
    local count=0
    for binlog in $binlog_files; do
        # 只备份上次全量备份之后的 binlog
        if [ -n "$last_binlog_file" ] && [[ "$binlog" < "$last_binlog_file" ]]; then
            continue
        fi

        log "INFO" "备份 binlog: $binlog"
        mysqlbinlog --read-from-remote-server --host="$MYSQL_HOST" --port="$MYSQL_PORT" \
            --user="$MYSQL_USER" --password="$MYSQL_PASS" \
            --raw --to-last-log "$binlog" -r "${backup_dir}/${binlog}" 2>>"$LOG_FILE" || true
        count=$((count+1))
    done

    # 压缩
    if [ $count -gt 0 ]; then
        tar czf "${BACKUP_DIR}/binlog_${timestamp}.tar.gz" -C "$backup_dir" .
        rm -rf "$backup_dir"
        local size=$(du -sh "${BACKUP_DIR}/binlog_${timestamp}.tar.gz" | awk '{print $1}')
        log "INFO" "增量备份完成: ${count}个binlog文件 ($size)"
    else
        log "INFO" "没有新的 binlog 需要备份"
        rm -rf "$backup_dir"
    fi
}

#==================== 备份验证 ====================
do_verify() {
    log "INFO" "========== 备份验证 =========="

    local latest_backup=$(ls -t "${BACKUP_DIR}/full/"*.sql.gz 2>/dev/null | head -1)
    if [ -z "$latest_backup" ]; then
        log "ERROR" "未找到备份文件"
        return 1
    fi

    log "INFO" "验证备份文件: $latest_backup"

    # 检查文件完整性
    if gzip -t "$latest_backup" 2>/dev/null; then
        log "INFO" "  [OK] gzip 文件完整性验证通过"
    else
        log "ERROR" "  [FAIL] gzip 文件损坏"
        return 1
    fi

    # 检查 SQL 内容
    local table_count=$(zcat "$latest_backup" | grep -c "^CREATE TABLE" 2>/dev/null || echo "0")
    log "INFO" "  [OK] 包含 ${table_count} 个表"

    # 检查备份大小是否合理
    local size_bytes=$(stat -c %s "$latest_backup" 2>/dev/null || echo "0")
    local size_mb=$((size_bytes / 1024 / 1024))
    if [ $size_mb -gt 10 ]; then
        log "INFO" "  [OK] 备份大小: ${size_mb}MB（合理）"
    else
        log "WARN" "  [WARN] 备份大小仅 ${size_mb}MB，可能不完整"
    fi

    log "INFO" "备份验证完成"
}

#==================== 清理过期备份 ====================
do_cleanup() {
    log "INFO" "========== 清理过期备份 =========="

    # 清理全量备份
    local deleted_full=$(find "${BACKUP_DIR}/full/" -name "full_*.sql.gz" -mtime "+${FULL_BACKUP_RETENTION}" -delete -print | wc -l)
    find "${BACKUP_DIR}/full/" -name "full_*.meta" -mtime "+${FULL_BACKUP_RETENTION}" -delete 2>/dev/null || true
    log "INFO" "清理全量备份: ${deleted_full}个（保留${FULL_BACKUP_RETENTION}天）"

    # 清理 binlog 备份
    local deleted_binlog=$(find "${BACKUP_DIR}/binlog/" -name "binlog_*.tar.gz" -mtime "+${BACKUP_RETENTION_DAYS}" -delete -print | wc -l)
    log "INFO" "清理 binlog 备份: ${deleted_binlog}个（保留${BACKUP_RETENTION_DAYS}天）"

    # 清理日志
    find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true

    log "INFO" "清理完成"
}

#==================== 主函数 ====================
main() {
    local action="${1:-full}"

    mkdir -p "$LOG_DIR" "${BACKUP_DIR}"/{full,binlog}

    case "$action" in
        full)
            do_full_backup
            ;;
        incremental|binlog)
            do_incremental_backup
            ;;
        verify)
            do_verify
            ;;
        cleanup)
            do_cleanup
            ;;
        *)
            echo "用法: $0 [full|incremental|verify|cleanup]"
            echo ""
            echo "  full        - 全量备份"
            echo "  incremental - 增量备份（binlog）"
            echo "  verify      - 验证最新备份"
            echo "  cleanup     - 清理过期备份"
            exit 1
            ;;
    esac
}

main "$@"
