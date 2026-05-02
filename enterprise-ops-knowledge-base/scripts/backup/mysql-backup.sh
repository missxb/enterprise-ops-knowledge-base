#!/bin/bash
#============================================
# MySQL 备份脚本 (mysqldump)
# 用法: ./mysql-backup.sh [database] [backup_dir]
#============================================
set -euo pipefail

DB=${1:-"--all-databases"}
BACKUP_DIR=${2:-"/backup/mysql"}
DATE=$(date +%Y%m%d-%H%M%S)
RETENTION=7
MYSQL_USER="backup"
MYSQL_PASS="${MYSQL_BACKUP_PASSWORD:-}"
LOG="/var/log/mysql-backup-${DATE}.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

mkdir -p "$BACKUP_DIR"

log "=== MySQL 备份开始 ==="

# 全量备份
DUMP_FILE="$BACKUP_DIR/mysql-${DATE}.sql.gz"
mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASS" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --master-data=2 \
    --flush-logs \
    $DB 2>>"$LOG" | gzip > "$DUMP_FILE"

# 检查备份文件
if [ -s "$DUMP_FILE" ]; then
    SIZE=$(du -sh "$DUMP_FILE" | awk '{print $1}')
    log "✅ 备份成功: $DUMP_FILE ($SIZE)"
else
    log "❌ 备份失败: 文件为空"
    exit 1
fi

# 清理过期备份
log "清理 ${RETENTION} 天前的备份..."
find "$BACKUP_DIR" -name "mysql-*.sql.gz" -mtime +$RETENTION -delete

log "=== 备份完成 ==="
