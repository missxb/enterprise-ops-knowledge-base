#!/bin/bash
#============================================================================
# 企业级跨云迁移 - 数据同步脚本
# 功能：使用 rsync 进行增量数据同步，支持断点续传、限速、校验
# 用法：./02-rsync-data.sh [sync|verify|report]
#============================================================================

set -euo pipefail

# 配置文件
CONFIG_FILE="/etc/migration/sync.conf"
LOG_DIR="/var/log/migration"
LOG_FILE="${LOG_DIR}/rsync-$(date +%Y%m%d_%H%M%S).log"
LOCK_FILE="/var/run/migration-rsync.lock"

# 默认配置
TARGET_HOST="${TARGET_HOST:-}"
TARGET_PORT="${TARGET_PORT:-22}"
TARGET_USER="${TARGET_USER:-root}"
SSH_KEY="${SSH_KEY:-/root/.ssh/id_rsa_migration}"
BANDWIDTH_LIMIT="${BANDWIDTH_LIMIT:-50000}"  # KB/s, 默认50MB/s
MAX_RETRIES="${MAX_RETRIES:-3}"
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"

# 需要同步的目录列表（源路径:目标路径）
SYNC_DIRS=(
    "/data/www:/data/www"
    "/data/app:/data/app"
    "/data/config:/data/config"
    "/data/logs:/data/logs"
    "/data/backup:/data/backup"
    "/etc/nginx:/etc/nginx"
    "/etc/docker:/etc/docker"
)

# 排除规则
EXCLUDE_PATTERNS=(
    "*.tmp"
    "*.log.*"
    "*.swp"
    ".git/"
    "node_modules/"
    "__pycache__/"
    "*.pyc"
    ".DS_Store"
    "Thumbs.db"
)

# 加载配置文件
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# 日志函数
log() {
    local level=$1; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

# 锁机制
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log "ERROR" "另一个同步进程正在运行 (PID: $pid)"
            exit 1
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
}

# 构建 rsync 排除参数
build_exclude_args() {
    local args=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        args="$args --exclude='$pattern'"
    done
    echo "$args"
}

# 构建 rsync 基础参数
build_rsync_base_args() {
    local args="-avz"
    args="$args --progress"
    args="$args --stats"
    args="$args --human-readable"
    args="$args --bwlimit=${BANDWIDTH_LIMIT}"
    args="$args --timeout=600"
    args="$args --partial"
    args="$args --partial-dir=.rsync-partial"
    args="$args -e 'ssh -i ${SSH_KEY} -p ${TARGET_PORT} -o StrictHostKeyChecking=no'"
    echo "$args"
}

# 单目录同步
sync_single_dir() {
    local src="$1"
    local dst="$2"
    local retry=0

    if [ ! -d "$src" ]; then
        log "WARN" "源目录不存在: $src，跳过"
        return 0
    fi

    log "INFO" "开始同步: $src → ${TARGET_USER}@${TARGET_HOST}:${dst}"

    while [ $retry -lt $MAX_RETRIES ]; do
        local exclude_args=$(build_exclude_args)
        local base_args=$(build_rsync_base_args)
        local cmd="rsync ${base_args} ${exclude_args} ${src}/ ${TARGET_USER}@${TARGET_HOST}:${dst}/"

        log "INFO" "执行命令: $cmd (尝试 $((retry+1))/${MAX_RETRIES})"

        if eval "$cmd" >> "$LOG_FILE" 2>&1; then
            log "INFO" "同步完成: $src → $dst"
            return 0
        else
            retry=$((retry+1))
            log "WARN" "同步失败，${retry}/${MAX_RETRIES} 次重试..."
            sleep $((retry * 5))
        fi
    done

    log "ERROR" "同步最终失败: $src → $dst (已重试 ${MAX_RETRIES} 次)"
    return 1
}

# 全量同步
do_sync() {
    log "INFO" "=========================================="
    log "INFO" "  开始数据同步"
    log "INFO" "  目标: ${TARGET_USER}@${TARGET_HOST}:${TARGET_PORT}"
    log "INFO" "  并行数: ${PARALLEL_JOBS}"
    log "INFO" "  限速: ${BANDWIDTH_LIMIT} KB/s"
    log "INFO" "=========================================="

    local start_time=$(date +%s)
    local success=0
    local failed=0
    local pids=()
    local dirs=()

    # 并行同步
    for sync_dir in "${SYNC_DIRS[@]}"; do
        local src="${sync_dir%%:*}"
        local dst="${sync_dir##*:}"

        # 控制并行数
        while [ ${#pids[@]} -ge $PARALLEL_JOBS ]; do
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                else
                    wait "$pid" && success=$((success+1)) || failed=$((failed+1))
                fi
            done
            pids=("${new_pids[@]}")
            sleep 1
        done

        # 启动后台同步
        sync_single_dir "$src" "$dst" &
        pids+=($!)
        dirs+=("$src")
    done

    # 等待所有任务完成
    for i in "${!pids[@]}"; do
        wait "${pids[$i]}" && success=$((success+1)) || failed=$((failed+1))
    done

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log "INFO" "=========================================="
    log "INFO" "  同步完成"
    log "INFO" "  成功: $success, 失败: $failed"
    log "INFO" "  耗时: $((duration/60))分$((duration%60))秒"
    log "INFO" "=========================================="

    if [ $failed -gt 0 ]; then
        log "ERROR" "存在失败的同步任务，请检查日志: $LOG_FILE"
        return 1
    fi

    return 0
}

# 数据校验
do_verify() {
    log "INFO" "=========================================="
    log "INFO" "  开始数据校验"
    log "INFO" "=========================================="

    local errors=0

    for sync_dir in "${SYNC_DIRS[@]}"; do
        local src="${sync_dir%%:*}"
        local dst="${sync_dir##*:}"

        if [ ! -d "$src" ]; then
            continue
        fi

        log "INFO" "校验目录: $src"

        # 本地文件数和大小
        local src_count=$(find "$src" -type f | wc -l)
        local src_size=$(du -sb "$src" 2>/dev/null | awk '{print $1}')

        # 远程文件数和大小
        local remote_info=$(ssh -i "$SSH_KEY" -p "$TARGET_PORT" -o StrictHostKeyChecking=no \
            "${TARGET_USER}@${TARGET_HOST}" \
            "find ${dst} -type f | wc -l && du -sb ${dst}" 2>/dev/null)
        local dst_count=$(echo "$remote_info" | head -1)
        local dst_size=$(echo "$remote_info" | tail -1 | awk '{print $1}')

        if [ "$src_count" = "$dst_count" ]; then
            log "INFO" "  文件数匹配: 本地=${src_count}, 远程=${dst_count}"
        else
            log "WARN" "  文件数不匹配: 本地=${src_count}, 远程=${dst_count}"
            errors=$((errors+1))
        fi

        # 大小对比（允许1%误差）
        if [ -n "$src_size" ] && [ -n "$dst_size" ]; then
            local diff_percent=$(echo "scale=2; ($src_size - $dst_size) * 100 / $src_size" | bc 2>/dev/null | tr -d '-')
            if (( $(echo "$diff_percent < 1" | bc -l) )); then
                log "INFO" "  大小匹配: 本地=$(numfmt --to=iec $src_size), 远程=$(numfmt --to=iec $dst_size)"
            else
                log "WARN" "  大小差异: 本地=$(numfmt --to=iec $src_size), 远程=$(numfmt --to=iec $dst_size), 差异=${diff_percent}%"
                errors=$((errors+1))
            fi
        fi
    done

    # MD5抽样校验（每个目录随机抽5个文件）
    log "INFO" "MD5抽样校验:"
    for sync_dir in "${SYNC_DIRS[@]}"; do
        local src="${sync_dir%%:*}"
        local dst="${sync_dir##*:}"

        if [ ! -d "$src" ]; then
            continue
        fi

        local sample_files=$(find "$src" -type f -size +1M | shuf | head -5)
        for file in $sample_files; do
            local relative_path="${file#$src}"
            local local_md5=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
            local remote_md5=$(ssh -i "$SSH_KEY" -p "$TARGET_PORT" -o StrictHostKeyChecking=no \
                "${TARGET_USER}@${TARGET_HOST}" \
                "md5sum '${dst}${relative_path}'" 2>/dev/null | awk '{print $1}')

            if [ "$local_md5" = "$remote_md5" ]; then
                log "INFO" "  [OK] $relative_path"
            else
                log "ERROR" "  [FAIL] $relative_path (本地: $local_md5, 远程: $remote_md5)"
                errors=$((errors+1))
            fi
        done
    done

    log "INFO" "=========================================="
    if [ $errors -eq 0 ]; then
        log "INFO" "  校验通过！所有数据一致"
    else
        log "ERROR" "  校验发现 $errors 个问题，请检查日志"
    fi
    log "INFO" "=========================================="

    return $errors
}

# 生成同步报告
do_report() {
    log "INFO" "同步状态报告:"
    log "INFO" "  目标主机: $TARGET_HOST"
    log "INFO" "  同步目录: ${#SYNC_DIRS[@]}个"
    log "INFO" "  日志文件: $LOG_FILE"

    for sync_dir in "${SYNC_DIRS[@]}"; do
        local src="${sync_dir%%:*}"
        local dst="${sync_dir##*:}"
        if [ -d "$src" ]; then
            local count=$(find "$src" -type f | wc -l)
            local size=$(du -sh "$src" 2>/dev/null | awk '{print $1}')
            log "INFO" "  $src: ${count}个文件, ${size}"
        fi
    done
}

# 主函数
main() {
    local action="${1:-sync}"

    mkdir -p "$LOG_DIR"
    acquire_lock

    case "$action" in
        sync)
            do_sync
            ;;
        verify)
            do_verify
            ;;
        report)
            do_report
            ;;
        *)
            echo "用法: $0 [sync|verify|report]"
            exit 1
            ;;
    esac
}

main "$@"
