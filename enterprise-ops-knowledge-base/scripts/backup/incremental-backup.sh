#!/bin/bash
#============================================
# 增量备份脚本 (rsync)
# 用法: ./incremental-backup.sh <source> <dest> [retention_days]
#============================================
set -euo pipefail

SOURCE=${1:?"用法: $0 <source> <dest> [retention_days]"}
DEST=${2:?"请指定备份目标路径"}
RETENTION=${3:-30}
DATE=$(date +%Y%m%d-%H%M%S)
LOG="/var/log/backup-${DATE}.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== 增量备份开始 ==="
log "源: $SOURCE"
log "目标: $DEST"
log "保留天数: $RETENTION"

# 创建目标目录
mkdir -p "$DEST/$DATE"

# rsync 增量备份
rsync -avz --delete \
    --link-dest="$DEST/latest" \
    "$SOURCE" "$DEST/$DATE/" 2>&1 | tee -a "$LOG"

# 更新 latest 软链接
ln -sfn "$DEST/$DATE" "$DEST/latest"

# 清理过期备份
log "清理 ${RETENTION} 天前的备份..."
find "$DEST" -maxdepth 1 -type d -mtime +$RETENTION -exec rm -rf {} \;

log "=== 备份完成 ==="
log "备份大小: $(du -sh "$DEST/$DATE" | awk '{print $1}')"
