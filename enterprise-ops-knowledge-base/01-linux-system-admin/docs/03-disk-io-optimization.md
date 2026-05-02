# 磁盘 I/O 优化（Disk I/O Optimization）

## 1. 概述

磁盘 I/O 是大多数应用的性能瓶颈。理解 Linux 的 I/O 栈、掌握 I/O 调度器选择和文件系统优化技巧，对于提升系统整体性能至关重要。

### 1.1 Linux I/O 栈

```
应用层 (Application)
    │ write() / read()
    ▼
VFS (虚拟文件系统层)
    │
    ▼
文件系统 (ext4 / xfs / btrfs)
    │
    ▼
Page Cache (页缓存)
    │
    ▼
Block Layer (块层)
    │ I/O 调度器 (Scheduler)
    ▼
设备驱动 (Device Driver)
    │
    ▼
物理设备 (HDD / SSD / NVMe)
```

### 1.2 关键性能指标

| 指标 | 含义 | HDD 参考值 | SSD 参考值 | NVMe 参考值 |
|------|------|-----------|-----------|------------|
| IOPS | 每秒 I/O 操作数 | 100-200 | 10K-100K | 100K-1M |
| 吞吐量 | 每秒数据传输量 | 100-200 MB/s | 500-3000 MB/s | 3-7 GB/s |
| 延迟 | 单次 I/O 耗时 | 5-15ms | 0.1-1ms | 0.01-0.1ms |
| 队列深度 | 同时进行的 I/O 数 | 1-32 | 1-128 | 1-256 |

## 2. I/O 调度器

### 2.1 调度器类型

#### noop（无调度器）
- **特点**：不做任何调度，直接下发 I/O
- **适用**：虚拟机、SSD/NVMe 设备
- **优势**：最低的 CPU 开销

#### deadline（截止时间调度器）
- **特点**：为每个 I/O 设置截止时间，保证请求在截止时间内完成
- **适用**：数据库服务器（传统 HDD）
- **优势**：兼顾吞吐和延迟

#### cfq（完全公平队列）
- **特点**：为每个进程维护独立的 I/O 队列，按时间片轮转
- **适用**：桌面系统、多用户共享服务器
- **优势**：公平性好

#### mq-deadline（多队列截止时间）
- **特点**：deadline 的多队列版本，支持 blk-mq
- **适用**：SSD/NVMe 设备
- **优势**：充分利用多队列硬件

#### kyber（快速调度器）
- **特点**：基于目标延迟的调度器
- **适用**：NVMe 设备
- **优势**：简单高效，延迟可控

#### bfq（预算公平队列）
- **特点**：cfq 的改进版，按预算分配
- **适用**：桌面系统、需要公平性的场景
- **优势**：更好的响应性

### 2.2 调度器选择指南

```bash
# 查看当前调度器
cat /sys/block/sda/queue/scheduler
# [mq-deadline] kyber bfq none

# 临时修改
echo mq-deadline > /sys/block/sda/queue/scheduler

# 持久化（udev 规则）
# /etc/udev/rules.d/60-ioscheduler.rules
# HDD
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="deadline"
# SSD/NVMe
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
```

### 2.3 调度器参数调优

#### deadline 调度器
```bash
# read_expire：读请求截止时间（ms）
echo 150 > /sys/block/sda/queue/iosched/read_expire

# write_expire：写请求截止时间（ms）
echo 1500 > /sys/block/sda/queue/iosched/write_expire

# writes_starved：一次读批处理中允许的写请求数
echo 2 > /sys/block/sda/queue/iosched/writes_starved

# fifo_batch：一批处理的请求数
echo 16 > /sys/block/sda/queue/iosched/fifo_batch
```

#### cfq 调度器
```bash
# slice_async：异步 I/O 时间片（ms）
echo 40 > /sys/block/sda/queue/iosched/slice_async

# slice_sync：同步 I/O 时间片（ms）
echo 100 > /sys/block/sda/queue/iosched/slice_sync

# slice_idle：队列空闲等待时间（ms）
echo 8 > /sys/block/sda/queue/iosched/slice_idle

# quantum：一次处理的请求数
echo 8 > /sys/block/sda/queue/iosched/quantum
```

## 3. I/O 队列参数

### 3.1 队列深度

```bash
# nr_requests：请求队列深度
# 默认值：128（HDD）/ 256（SSD）
cat /sys/block/sda/queue/nr_requests

# 对于 NVMe 设备，可以增大到 1024
echo 1024 > /sys/block/nvme0n1/queue/nr_requests

# 对于 HDD 数据库服务器，适当减小以降低延迟
echo 64 > /sys/block/sda/queue/nr_requests
```

### 3.2 预读参数

```bash
# read_ahead_kb：预读大小（KB）
# 默认值：128
cat /sys/block/sda/queue/read_ahead_kb

# 顺序读取场景（如大数据分析）：增大预读
echo 2048 > /sys/block/sda/queue/read_ahead_kb

# 随机读取场景（如数据库）：减小预读
echo 16 > /sys/block/sda/queue/read_ahead_kb

# NVMe 设备通常不需要预读
echo 0 > /sys/block/nvme0n1/queue/read_ahead_kb
```

### 3.3 其他队列参数

```bash
# max_sectors_kb：单次 I/O 最大大小（KB）
cat /sys/block/sda/queue/max_sectors_kb
# 默认值通常为 1280（1.25MB）

# 对于顺序大文件读写，可以增大
echo 4096 > /sys/block/sda/queue/max_sectors_kb

# nomerges：合并控制
# 0：正常合并（默认）
# 1：禁用 front merge
# 2：禁用所有合并
echo 0 > /sys/block/sda/queue/nomerges

# rq_affinity：I/O 完成亲和性
# 0：在任意 CPU 完成
# 1：在提交 I/O 的 CPU 完成
# 2：强制在提交 I/O 的 CPU 完成
echo 2 > /sys/block/sda/queue/rq_affinity
```

## 4. 文件系统优化

### 4.1 ext4 优化

```bash
# 挂载参数优化
# /etc/fstab 示例
# /dev/sda1 /data ext4 defaults,noatime,nodiratime,data=writeback,barrier=0,nodelalloc 0 0

# 关键参数说明：
# noatime：不更新访问时间（减少写入）
# nodiratime：不更新目录访问时间
# data=writeback：元数据日志模式（性能最好，但崩溃时可能丢数据）
# data=ordered：默认模式（元数据和数据都日志，保证一致性）
# data=journal：完整日志模式（最安全，性能最差）
# barrier=0：禁用写屏障（仅在有 BBU RAID 卡时使用）
# nodelalloc：禁用延迟分配（减少数据丢失风险）

# 调整 ext4 参数
tune2fs -o journal_data_writeback /dev/sda1
tune2fs -O ^has_journal /dev/sda1  # 禁用日志（极端性能优化，不推荐）

# 在线调整参数
tune2fs -c 30 /dev/sda1            # 每 30 次挂载后检查
tune2fs -i 0 /dev/sda1             # 禁用时间间隔检查
```

### 4.2 XFS 优化

```bash
# XFS 是 RHEL/CentOS 7+ 的默认文件系统，适合大文件和高并发

# 创建 XFS 文件系统（优化参数）
mkfs.xfs -f -d agcount=32 -l size=256m /dev/sdb1

# 挂载参数
# /dev/sdb1 /data xfs defaults,noatime,logbufs=8,logbsize=256k,allocsize=64m 0 0

# 关键参数：
# logbufs=8：日志缓冲区数量（默认 8，可以减少日志锁竞争）
# logbsize=256k：日志缓冲区大小
# allocsize=64m：预分配大小（适合大文件写入）
# noatime：不更新访问时间
# inode64：允许 inode 分配到磁盘的任何位置（大容量磁盘必须）
# nobarrier：禁用写屏障（仅在有 BBU RAID 卡时使用）

# XFS 在线调整
xfs_growfs /data  # 扩容

# XFS 碎片整理
xfs_fsr /data  # 在线碎片整理
```

### 4.3 Btrfs 优化

```bash
# Btrfs 支持快照、压缩、校验等高级功能

# 挂载参数
# /dev/sdc1 /data btrfs defaults,noatime,compress=zstd,ssd,discard=async 0 0

# 关键参数：
# compress=zstd：透明压缩（节省空间，但增加 CPU 开销）
# ssd：SSD 优化模式
# discard=async：异步 TRIM
# space_cache=v2：空间缓存
# commit=60：提交间隔（秒）
```

## 5. RAID 配置优化

### 5.1 RAID 级别选择

| RAID 级别 | 冗余 | 性能 | 适用场景 |
|-----------|------|------|----------|
| RAID 0 | 无 | 最高读写 | 临时数据、缓存 |
| RAID 1 | 镜像 | 高读，中等写 | 系统盘、日志盘 |
| RAID 5 | 单校验 | 高读，中等写 | 通用存储 |
| RAID 6 | 双校验 | 高读，较低写 | 大容量存储 |
| RAID 10 | 镜像+条带 | 高读写 | 数据库、关键业务 |

### 5.2 RAID 卡参数优化

```bash
# 查看 RAID 信息
megacli -LDInfo -Lall -aALL  # MegaCLI
storcli /c0 show              # StorCLI
arcconf getconfig 1           # Adaptec

# 关键参数：
# Write Policy：WriteBack（有 BBU）/ WriteThrough（无 BBU）
# Read Policy：ReadAhead / Adaptive / NoReadAhead
# Stripe Size：64KB（数据库）/ 256KB（文件服务器）
# Disk Cache：Enable（有 BBU）/ Disable（无 BBU）

# BBU（电池备份单元）状态检查
megacli -AdpBbuCmd -GetBbuStatus -aALL
```

## 6. I/O 监控与分析

### 6.1 iostat

```bash
# 基本用法
iostat -xdm 1
# Device  r/s    w/s    rMB/s  wMB/s  rrqm/s  wrqm/s  %rrqm  %wrqm  r_await  w_await  aqu-sz  rareq-sz  wareq-sz  svctm  %util
# sda     100.00 50.00  1.56   0.78   0.00    5.00    0.00   9.09   0.50     2.00     0.15    16.00     16.00     1.00   15.00

# 关键指标：
# r/s, w/s：每秒读/写请求数（IOPS）
# rMB/s, wMB/s：读/写吞吐量
# r_await, w_await：读/写平均延迟（ms）
# aqu-sz：平均队列长度
# %util：设备繁忙百分比（>70% 需要关注）
```

### 6.2 iotop

```bash
# 按进程查看 I/O
iotop -oP
# Total DISK READ:       10.00 M/s | Total DISK WRITE:       5.00 M/s
#   PID  PRIO  USER     DISK READ  DISK WRITE  SWAPIN     IO>    COMMAND
#  1234  be/4  mysql    8.00 M/s   3.00 M/s    0.00 %  5.00 %  mysqld
#  5678  be/4  root     2.00 M/s   2.00 M/s    0.00 %  2.00 %  rsync
```

### 6.3 blktrace

```bash
# 块设备 I/O 跟踪
blktrace -d /dev/sda -o - | blkparse -i -

# 分析 I/O 模式
btt -i sda.blktrace.0

# 输出包括：
# Q2C（Queue to Complete）：I/O 总延迟
# D2C（Dispatch to Complete）：设备处理延迟
# Q2D（Queue to Dispatch）：调度器延迟
```

### 6.4 /proc/diskstats

```bash
cat /proc/diskstats
#  8  0 sda 1000 0 8000 500 500 0 4000 1000 0 1500 1500

# 字段说明：
# 1-3：设备号
# 4：设备名
# 5：读完成次数
# 6：读合并次数
# 7：读扇区数
# 8：读耗时（ms）
# 9：写完成次数
# 10：写合并次数
# 11：写扇区数
# 12：写耗时（ms）
# 13：正在处理的 I/O 数
# 14：I/O 耗时（ms）
# 15：加权 I/O 耗时（ms）
```

## 7. 磁盘 I/O 优化策略

### 7.1 分离 I/O 负载

```bash
# 将不同类型的 I/O 分离到不同的磁盘
# 系统盘：OS + 应用程序
# 数据盘：数据库数据文件
# 日志盘：数据库日志文件
# 临时盘：临时文件、swap

# MySQL 示例：
# /dev/sda  → / (系统)
# /dev/sdb  → /data/mysql (数据)
# /dev/sdc  → /data/mysql-log (日志)
# /dev/sdd  → /tmp (临时)
```

### 7.2 文件系统选择建议

| 场景 | 推荐文件系统 | 理由 |
|------|-------------|------|
| 数据库 | XFS | 高并发性能好，支持大文件 |
| 日志服务器 | XFS / ext4 | 顺序写入性能好 |
| 通用服务器 | ext4 | 稳定性好，社区支持广 |
| NAS/SAN | XFS | 大容量支持好 |
| 容器存储 | overlay2 (ext4/xfs) | 层叠文件系统 |
| 快照需求 | Btrfs / ZFS | 内置快照功能 |

### 7.3 直接 I/O vs 缓冲 I/O

```bash
# 缓冲 I/O（默认）：
# - 数据先写入 Page Cache，再异步刷盘
# - 优点：合并小 I/O，提升吞吐
# - 缺点：数据可能丢失（崩溃时）

# 直接 I/O（O_DIRECT）：
# - 数据直接写入磁盘，绕过 Page Cache
# - 优点：避免双重缓存，数据一致性好
# - 缺点：小 I/O 性能差

# 数据库通常使用 O_DIRECT：
# MySQL：innodb_flush_method = O_DIRECT
# PostgreSQL：direct_io = on（或使用 OS 缓存）
```

## 8. SSD/NVMe 特殊优化

### 8.1 TRIM/Discard

```bash
# TRIM 告诉 SSD 哪些块不再使用，帮助 SSD 进行垃圾回收

# 方式1：挂载时启用 discard（在线 TRIM）
# /dev/nvme0n1p1 /data xfs defaults,discard 0 0

# 方式2：定期执行 fstrim（推荐）
fstrim /data
# 或通过 systemd timer
systemctl enable fstrim.timer

# 注意：某些 SSD 的 discard 操作可能导致性能抖动
# 推荐使用 fstrim.timer（每周执行一次）
```

### 8.2 NVMe 优化

```bash
# 查看 NVMe 设备信息
nvme list
nvme id-ctrl /dev/nvme0n1

# 调整 NVMe 队列数
# 通过内核参数：nvme_core.io_queue_count
echo 63 > /sys/module/nvme/parameters/io_queue_count

# NVMe 多流写入（Multi-Stream Write）
# 减少写放大，延长 SSD 寿命
nvme set-feature /dev/nvme0n1 -f 0x0c -v <streams>
```

### 8.3 SSD 寿命监控

```bash
# SMART 信息
smartctl -a /dev/sda
# 关注：
# Media_WearoutIndicator：磨损均衡计数（100→0）
# Reallocated_Sector_Ct：重映射扇区数
# Wear_Leveling_Count：磨损均衡计数

# NVMe SMART
nvme smart-log /dev/nvme0n1
# 关注：
# percentage_used：已使用寿命百分比
# data_units_written：已写入数据量
```

## 9. 生产案例

### 9.1 数据库 I/O 优化

**场景**：MySQL 数据库，高并发写入场景，I/O 延迟高。

**分析**：
```bash
iostat -xdm 1
# sda  10.00  5000.00  0.04  78.00  ...  w_await 10.00  %util 100.00
# 写 IOPS 5000，延迟 10ms，设备 100% 繁忙
```

**解决方案**：
```bash
# 1. 升级存储：HDD → SSD
# 2. RAID 优化：RAID 5 → RAID 10
# 3. MySQL 配置优化
# innodb_flush_method = O_DIRECT
# innodb_io_capacity = 2000
# innodb_io_capacity_max = 4000
# innodb_log_file_size = 2G
# 4. 文件系统优化
# XFS + noatime + logbsize=256k
```

### 9.2 日志服务器 I/O 优化

**场景**：日志服务器，大量小文件顺序写入。

**分析**：
```bash
iotop -oP
# 大量小 I/O 写入，IOPS 高但吞吐量低
```

**解决方案**：
```bash
# 1. 使用 cfq 调度器（公平调度，适合多进程写入）
echo cfq > /sys/block/sda/queue/scheduler

# 2. 增大预读
echo 2048 > /sys/block/sda/queue/read_ahead_kb

# 3. 日志先写缓冲（rsyslog 的队列）
# $ActionQueueType LinkedList
# $ActionQueueFileName fwdRule1
# $ActionResumeRetryCount -1
# $ActionQueueSaveOnShutdown on

# 4. 定期压缩归档
# 使用 logrotate + 压缩
```

## 10. 最佳实践总结

1. **选择合适的调度器**：SSD 用 none/mq-deadline，HDD 用 deadline/cfq
2. **分离 I/O 负载**：系统、数据、日志分离到不同磁盘
3. **选择合适的文件系统**：数据库用 XFS，通用用 ext4
4. **关闭 atime**：减少不必要的写入
5. **监控 I/O 指标**：IOPS、延迟、队列深度、使用率
6. **RAID 选择**：关键业务用 RAID 10，大容量用 RAID 6
7. **SSD 维护**：定期 TRIM，监控 SMART
8. **直接 I/O**：数据库使用 O_DIRECT
9. **合理预读**：顺序读场景增大，随机读场景减小
10. **容量规划**：磁盘使用率不超过 80%，预留碎片整理空间
