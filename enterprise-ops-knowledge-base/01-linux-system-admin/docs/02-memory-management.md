# 内存管理与优化（Memory Management & Optimization）

## 1. 概述

内存是 Linux 系统中最关键的资源之一。理解内存管理机制、掌握内存优化技巧，是运维工程师的核心技能。本文将从内存架构、分配机制、回收策略、常见问题排查等方面深入讲解。

### 1.1 Linux 内存架构

```
┌─────────────────────────────────────────┐
│              用户空间 (User Space)         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  │
│  │ 进程 A   │  │ 进程 B   │  │ 进程 C   │  │
│  │ Virtual  │  │ Virtual  │  │ Virtual  │  │
│  │ Memory   │  │ Memory   │  │ Memory   │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  │
│       │              │              │        │
├───────┼──────────────┼──────────────┼────────┤
│       │    内核空间 (Kernel Space)    │        │
│  ┌────▼──────────────▼──────────────▼─────┐  │
│  │           页表 (Page Table)              │  │
│  └────┬──────────────┬──────────────┬─────┘  │
│  ┌────▼─────┐  ┌─────▼────┐  ┌─────▼────┐  │
│  │ 物理内存   │  │  Swap    │  │  Page    │  │
│  │ (RAM)    │  │ (磁盘)   │  │  Cache   │  │
│  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────┘
```

### 1.2 关键概念

- **虚拟内存**：每个进程拥有独立的虚拟地址空间（64位系统最大 256TB）
- **物理内存**：实际的 RAM 硬件
- **页表**：虚拟地址到物理地址的映射表
- **Page Cache**：文件系统缓存，缓存最近访问的文件数据
- **Slab**：内核对象缓存（dentry、inode 等）
- **Swap**：磁盘上的交换分区，内存不足时使用
- **OOM Killer**：内存耗尽时选择并杀死进程的机制

## 2. 内存监控与分析

### 2.1 /proc/meminfo 详解

```bash
cat /proc/meminfo

# 关键字段解析：
# MemTotal:       16384000 kB  # 物理内存总量
# MemFree:          204800 kB  # 完全空闲的内存
# MemAvailable:    8192000 kB  # 可用内存（含可回收的 cache）
# Buffers:          512000 kB  # 块设备缓冲区
# Cached:          6144000 kB  # Page Cache
# SwapCached:       102400 kB  # 被换出又换入的页面（在 swap 和 cache 中都存在）
# Active:          8192000 kB  # 最近被访问的内存
# Inactive:        4096000 kB  # 最近未被访问的内存（可回收候选）
# Active(anon):    4096000 kB  # 活跃的匿名内存（进程数据）
# Inactive(anon):  1024000 kB  # 不活跃的匿名内存
# Active(file):    4096000 kB  # 活跃的文件缓存
# Inactive(file):  3072000 kB  # 不活跃的文件缓存
# SwapTotal:       8192000 kB  # Swap 总量
# SwapFree:        7168000 kB  # Swap 空闲量
# Dirty:             10240 kB  # 等待写入磁盘的脏页
# Writeback:             0 kB  # 正在写入磁盘的页
# Slab:             512000 kB  # 内核 Slab 缓存
# SReclaimable:     409600 kB  # 可回收的 Slab
# SUnreclaim:       102400 kB  # 不可回收的 Slab
# CommitLimit:    16384000 kB  # 内存提交限制
# Committed_AS:   12288000 kB  # 已提交的内存（可能超分配）
# HugePages_Total:       0    # 大页总数
# HugePages_Free:        0    # 空闲大页
```

### 2.2 理解 "内存使用率高"

很多运维新手看到 `free -m` 中 `available` 很低就认为内存不足，这是误解：

```bash
$ free -m
              total        used        free      shared  buff/cache   available
Mem:          15880       12000         200         100        3680        3500
Swap:          8000         100        7900

# 正确理解：
# - total = 15880 MB
# - used = 12000 MB（包含应用实际使用的内存）
# - buff/cache = 3680 MB（文件缓存，可回收）
# - available = 3500 MB（真正可用的内存 = free + 可回收的 cache）
# - 关键看 available，不是 free！
```

### 2.3 内存分析工具

```bash
# 1. vmstat - 虚拟内存统计
vmstat 1 10
# procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
#  r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa
#  1  0  102400 204800 512000 3680000   0    0     5    10  100  200  5  2 93  0
# si (swap in): 从 swap 读入内存的大小（KB/s）
# so (swap out): 从内存写入 swap 的大小（KB/s）
# 如果 si/so 持续 > 0，说明内存不足在使用 swap

# 2. sar - 系统活动报告
sar -r 1 10  # 内存使用统计
sar -B 1 10  # 分页统计
sar -W 1 10  # swap 统计

# 3. smaps - 进程内存详情
cat /proc/<pid>/smaps | grep -E "^Size|^Rss|^Pss|^Swap"
# Size: 虚拟内存大小
# Rss: 实际使用的物理内存
# Pss: 按比例分摊的物理内存（共享内存按进程数均分）
# Swap: 使用的 swap 大小

# 4. pmap - 进程内存映射
pmap -x <pid>

# 5. slabtop - Slab 缓存监控
slabtop -o | head -20
# 查看哪些内核对象占用了最多内存

# 6. /proc/buddyinfo - 伙伴系统信息
cat /proc/buddyinfo
# 查看各阶内存块的空闲数量，判断内存碎片化程度
```

## 3. 内存回收机制

### 3.1 回收流程

```
内存紧张 → kswapd 唤醒 → 扫描 LRU 链表 → 回收 page cache
                       → 回收 Slab 缓存
                       → 如果还不够 → OOM Killer
```

### 3.2 LRU 链表

Linux 使用 LRU（Least Recently Used）链表管理内存页面：

- **Active 链表**：最近被访问的页面
- **Inactive 链表**：最近未被访问的页面（回收候选）
- 页面在两个链表之间移动，通过访问位（Accessed bit）判断

### 3.3 kswapd vs direct reclaim

- **kswapd**：后台回收线程，在内存水位线（watermark）触发
  - `watermark_min`：最低水位线，触发 kswapd
  - `watermark_low`：低水位线，kswapd 开始积极回收
  - `watermark_high`：高水位线，kswapd 停止回收
- **direct reclaim**：应用分配内存时直接回收（同步，会阻塞应用）
  - 当内存低于 watermark_min 时触发
  - 会导致应用延迟抖动

```bash
# 查看水位线
cat /proc/zoneinfo | grep -A 5 "Normal"

# 调整水位线（单位：页，每页 4KB）
# min_free_kbytes 会自动计算水位线
sysctl -w vm.min_free_kbytes=262144  # 256MB
```

### 3.4 min_free_kbytes

```bash
# 含义：保留的最小空闲内存（KB）
# 默认值：根据内存自动计算
# 推荐值：
#   - 16GB 内存：131072（128MB）
#   - 32GB 内存：262144（256MB）
#   - 64GB 内存：524288（512MB）

# 原理：
# min_free_kbytes 控制 watermark_min 的大小。
# 更大的值 = 更高的水位线 = kswapd 更早开始回收 = 更少的 direct reclaim。
# 但也不能太大，否则浪费可用内存。

sysctl -w vm.min_free_kbytes=262144
```

## 4. Swap 管理

### 4.1 Swap 的作用与代价

**作用**：
- 内存不足时，将不活跃的页面换出到磁盘
- 允许系统 overcommit 内存
- 作为 OOM 之前的缓冲

**代价**：
- 磁盘 I/O 远慢于内存访问（SSD 约 100μs vs 内存约 100ns，差 1000 倍）
- 导致应用响应时间抖动
- 对于延迟敏感的应用（数据库、交易系统）不可接受

### 4.2 Swap 配置策略

```bash
# 场景1：数据库服务器（Redis/MySQL）
# 策略：最小化 swap 使用
sysctl -w vm.swappiness=1

# 场景2：Web 服务器
# 策略：适度使用 swap
sysctl -w vm.swappiness=10

# 场景3：开发/测试环境
# 策略：允许使用 swap
sysctl -w vm.swappiness=60

# 场景4：完全没有 swap（极端优化）
# 不推荐！内存耗尽时直接 OOM，没有缓冲
# swapoff -a
```

### 4.3 Swap 空间规划

```bash
# 传统建议：Swap = 2 × RAM（适用于小内存服务器）
# 现代建议（大内存服务器）：
#   - 16GB RAM：4-8GB swap
#   - 32GB RAM：4-8GB swap
#   - 64GB+ RAM：2-4GB swap（仅用于 hibernate 和 OOM 缓冲）

# 创建 swap 文件
dd if=/dev/zero of=/swapfile bs=1M count=8192
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 使用 SSD 作为 swap（性能更好）
# 需要注意 SSD 写入寿命
```

### 4.4 zswap / zram

```bash
# zswap：压缩 swap，在内存中维护一个压缩缓存池
# 将换出的页面压缩后存储在内存中，而非直接写入磁盘
# 大幅减少实际的磁盘 I/O

# 启用 zswap
echo 1 > /sys/module/zswap/parameters/enabled
echo lz4 > /sys/module/zswap/parameters/compressor    # 压缩算法
echo z3fold > /sys/module/zswap/parameters/zpool       # 内存分配器

# zram：基于 RAM 的块设备，用作 swap
# 适用于嵌入式系统或无磁盘 swap 的场景
modprobe zram
echo lz4 > /sys/block/zram0/comp_algorithm
echo 4G > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 100 /dev/zram0  # 优先级设为 100，优先使用 zram
```

## 5. OOM Killer 详解

### 5.1 OOM 触发条件

当系统内存耗尽且无法回收时，触发 OOM Killer：

1. 所有可回收的内存（page cache、slab、swap）都已用尽
2. 内存分配失败
3. 内核选择一个进程杀死以释放内存

### 5.2 OOM 评分机制

```bash
# 每个进程的 OOM 分数存储在 /proc/<pid>/oom_score
# 范围：0-1000
# 分数越高，越可能被杀死

# 查看所有进程的 OOM 分数
for pid in /proc/[0-9]*; do
    name=$(cat $pid/comm 2>/dev/null)
    score=$(cat $pid/oom_score 2>/dev/null)
    adj=$(cat $pid/oom_score_adj 2>/dev/null)
    echo "$score $adj $name"
done | sort -rn | head -20

# 手动调整 OOM 分数
# oom_score_adj 范围：-1000 到 1000
# -1000：永不被杀死
# 0：默认
# 1000：优先被杀死

# 保护关键进程
echo -999 > /proc/$(pidof mysqld)/oom_score_adj
echo -999 > /proc/$(pidof redis-server)/oom_score_adj

# 标记非关键进程
echo 500 > /proc/$(pidof some-batch-job)/oom_score_adj
```

### 5.3 OOM 日志分析

```bash
# OOM 事件会记录在内核日志中
dmesg | grep -i "oom\|out of memory\|killed process"

# 典型的 OOM 日志：
# [12345.678] Out of memory: Kill process 12345 (java) score 800 or sacrifice child
# [12345.678] Killed process 12345 (java) total-vm:8192000kB, anon-rss:4096000kB

# 解读：
# - score 800：OOM 评分
# - total-vm：虚拟内存总量
# - anon-rss：匿名内存（实际使用的物理内存）
```

### 5.4 预防 OOM

```bash
# 1. 合理设置 swappiness
sysctl -w vm.swappiness=10

# 2. 设置内存限制（systemd 服务）
# [Service]
# MemoryLimit=4G
# MemoryMax=4G  # systemd 232+

# 3. 使用 cgroup v2 限制内存
# /sys/fs/cgroup/<group>/memory.max

# 4. 应用级内存限制
# Java：-Xmx4g -Xms4g
# Node.js：--max-old-space-size=4096
# MySQL：innodb_buffer_pool_size = 4G

# 5. 监控告警
# 当可用内存低于阈值时告警
# available < total * 0.1 时触发告警
```

## 6. 大页内存（Huge Pages）

### 6.1 为什么使用大页

标准页面大小为 4KB，当进程使用大量内存时，页表会非常大：

- 16GB 内存 / 4KB 页面 = 400 万个页表项
- TLB（Translation Lookaside Buffer）有限，频繁 TLB miss 会严重影响性能
- 大页（2MB 或 1GB）可以显著减少页表项数量

### 6.2 透明大页（THP）

```bash
# 查看 THP 状态
cat /sys/kernel/mm/transparent_hugepage/enabled

# [always] madvise never
# always：总是使用 THP
# madvise：仅在应用通过 madvise() 请求时使用
# never：禁用 THP

# 对于数据库（MySQL、MongoDB、Redis）建议禁用 THP
# 原因：THP 的合并/拆分操作会导致延迟抖动
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# 持久化（通过 systemd 服务或 rc.local）
```

### 6.3 静态大页

```bash
# 配置静态大页（以 2MB 大页为例）
# 计算需要的大页数量
# 假设 Oracle SGA 需要 8GB：8GB / 2MB = 4096 个大页
sysctl -w vm.nr_hugepages=4096

# 挂载大页文件系统
mkdir -p /mnt/hugepages
mount -t hugetlbfs nodev /mnt/hugepages

# 持久化
echo 'vm.nr_hugepages=4096' >> /etc/sysctl.d/hugepages.conf
echo 'nodev /mnt/hugepages hugetlbfs defaults 0 0' >> /etc/fstab

# 1GB 大页（需要在 boot 参数中配置）
# GRUB_CMDLINE_LINUX="hugepagesz=1G hugepages=4"
```

## 7. NUMA 优化

### 7.1 NUMA 架构

在多路服务器中，每个 CPU 有自己的本地内存：

```
CPU 0                    CPU 1
┌──────────────┐    ┌──────────────┐
│  本地内存      │    │  本地内存      │
│  (Node 0)    │    │  (Node 1)    │
│  32GB        │    │  32GB        │
└──────┬───────┘    └──────┬───────┘
       │    QPI/互联总线    │
       └──────────────────┘
```

访问本地内存比访问远程内存快 2-3 倍。

### 7.2 NUMA 命令

```bash
# 查看 NUMA 拓扑
numactl --hardware

# available: 2 nodes (0-1)
# node 0 cpus: 0 1 2 3 4 5 6 7
# node 0 size: 32768 MB
# node 1 cpus: 8 9 10 11 12 13 14 15
# node 1 size: 32768 MB

# 查看 NUMA 统计
numastat

# 绑定进程到特定 NUMA 节点
numactl --cpunodebind=0 --membind=0 ./myapp

# 允许在所有节点分配，但优先本地
numactl --interleave=all ./myapp

# MySQL NUMA 优化示例
numactl --interleave=all mysqld
```

### 7.3 NUMA 策略选择

| 策略 | 适用场景 | 说明 |
|------|----------|------|
| `--membind` | 关键业务应用 | 严格绑定到本地内存 |
| `--interleave` | 数据库 | 在所有节点轮转分配，避免热点 |
| `--preferred` | 通用应用 | 优先本地，不够时使用远程 |
| 默认 | 开发环境 | 内核自动选择 |

## 8. 内存泄漏排查

### 8.1 识别内存泄漏

```bash
# 持续监控进程内存使用
pidstat -r -p <pid> 5  # 每 5 秒采样一次

# 输出示例：
# Time   UID  PID  minflt/s  majflt/s     VSZ    RSS   %MEM  Command
# 15:00  root 1234     10.00      0.00  8192000 4096000  25.0  java
# 15:01  root 1234     12.00      0.00  8192000 4120000  25.2  java
# 15:02  root 1234     15.00      0.00  8192000 4150000  25.3  java
# RSS 持续增长 = 可能存在内存泄漏
```

### 8.2 内存泄漏工具

```bash
# 1. valgrind（C/C++ 程序）
valgrind --leak-check=full --show-leak-kinds=all ./myapp

# 2. AddressSanitizer（GCC/Clang）
gcc -fsanitize=address -g myapp.c -o myapp

# 3. pmap 对比法
pmap -x <pid> > /tmp/pmap-$(date +%H%M).txt
# 间隔一段时间后再查看
pmap -x <pid> > /tmp/pmap-$(date +%H%M).txt
diff /tmp/pmap-*.txt

# 4. /proc/<pid>/smaps 分析
cat /proc/<pid>/smaps_rollup
# 关注 Rss、Pss、Swap 的变化趋势

# 5. GDB（查看进程内存）
gdb -p <pid>
(gdb) info proc mappings
(gdb) dump memory /tmp/dump.bin 0x7f... 0x7f...
```

### 8.3 Java 应用内存分析

```bash
# 查看 JVM 内存使用
jmap -heap <pid>

# 生成 heap dump
jmap -dump:format=b,file=/tmp/heap.hprof <pid>

# 查看存活对象
jmap -histo:live <pid> | head -20

# JVM 内存参数调优
# -Xms4g -Xmx4g          # 堆大小（建议设为相同值）
# -XX:MetaspaceSize=256m  # 元空间初始大小
# -XX:MaxMetaspaceSize=512m  # 元空间最大值
# -XX:+UseG1GC            # 使用 G1 垃圾收集器
# -XX:MaxGCPauseMillis=200  # 最大 GC 停顿时间
```

## 9. 生产案例

### 9.1 电商大促内存优化

**场景**：某电商平台，日常 16GB 内存服务器，大促前扩容到 32GB。

**问题**：大促期间出现偶发的请求超时，排查发现是 swap 使用导致。

**分析**：
```bash
vmstat 1
# 观察 si/so 列，发现每隔几分钟有大量 swap out
sar -W 1
# 确认 swap 使用率从 0% 飙升到 30%
```

**解决方案**：
```bash
# 1. 调整 swappiness
sysctl -w vm.swappiness=1

# 2. 调整内存回收水位线
sysctl -w vm.min_free_kbytes=524288

# 3. 关闭 THP
echo never > /sys/kernel/mm/transparent_hugepage/enabled

# 4. JVM 参数优化
# -Xmx24g -Xms24g -XX:+UseG1GC
```

### 9.2 Redis 内存优化

**场景**：Redis 实例内存使用 12GB，经常触发 fork 时 OOM。

**分析**：
```bash
# Redis BGSAVE 需要 fork，fork 时 COW（Copy On Write）需要额外内存
# 如果 overcommit_memory=0，fork 可能失败
dmesg | grep -i "oom\|redis"
```

**解决方案**：
```bash
# 1. 设置 overcommit
sysctl -w vm.overcommit_memory=1

# 2. 关闭 THP
echo never > /sys/kernel/mm/transparent_hugepage/enabled

# 3. 调整 Redis maxmemory
# maxmemory 10gb
# maxmemory-policy allkeys-lru

# 4. 确保足够的 swap（作为安全网）
# 4GB swap，swappiness=1
sysctl -w vm.swappiness=1
```

## 10. 最佳实践总结

1. **监控先行**：建立完善的内存监控体系，包括系统级和应用级
2. **理解应用**：不同应用对内存的需求不同，要针对性优化
3. **保留缓冲**：不要将内存用到极限，保留 10-20% 作为缓冲
4. **避免 swap 依赖**：swap 是安全网，不是正常的内存扩展
5. **NUMA 感知**：多路服务器要绑定进程到特定 NUMA 节点
6. **禁用 THP（数据库）**：数据库场景建议禁用透明大页
7. **OOM 保护**：为关键进程设置 oom_score_adj
8. **定期重启**：对于有内存泄漏的应用，通过定期重启释放内存
