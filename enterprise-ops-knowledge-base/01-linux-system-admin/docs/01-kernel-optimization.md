# 内核参数优化（Kernel Parameter Optimization）

## 1. 概述

Linux 内核参数（sysctl）是操作系统运行时可调整的配置项，直接影响系统性能、网络行为、内存管理和安全策略。在企业生产环境中，合理的内核参数配置可以显著提升系统吞吐量、降低延迟、增强稳定性。

### 1.1 为什么需要内核参数优化

默认的 Linux 内核参数是为通用场景设计的，兼顾了桌面、服务器、嵌入式等多种使用场景。但在特定的高并发、高吞吐、低延迟场景下，默认值往往不够：

- **Web 服务器**：默认的 `somaxconn=128` 远远不够处理万级并发连接
- **数据库服务器**：默认的内存管理策略可能导致频繁的 swap，严重影响性能
- **网关/代理服务器**：默认的 TCP 缓冲区大小和 TIME_WAIT 处理不适合高并发短连接场景
- **金融交易系统**：需要极致的低延迟，需要精细的 CPU 调度和中断处理优化

### 1.2 sysctl 工作原理

sysctl 接口通过 `/proc/sys/` 虚拟文件系统暴露内核参数。每个参数对应一个文件：

```
/proc/sys/net/core/somaxconn  →  sysctl net.core.somaxconn
/proc/sys/vm/swappiness       →  sysctl vm.swappiness
```

参数修改有两种方式：
- **临时生效**：`sysctl -w net.core.somaxconn=65535`（重启后失效）
- **持久化生效**：写入 `/etc/sysctl.conf` 或 `/etc/sysctl.d/*.conf`，执行 `sysctl -p`

## 2. 网络相关参数

### 2.1 连接队列参数

#### net.core.somaxconn

```bash
# 含义：TCP 监听队列（accept queue）的最大长度
# 默认值：128（CentOS 7）/ 4096（Ubuntu 20.04+）
# 推荐值：65535
# 场景：高并发 Web 服务器、API 网关

# 原理：
# 当客户端发起 TCP 连接时，经过三次握手后，连接被放入 accept queue。
# 如果应用调用 accept() 不及时，队列满了之后新连接会被丢弃。
# 在高并发场景（如电商大促），128 的默认值会导致大量连接被拒绝。

# 查看当前值
sysctl net.core.somaxconn

# 设置
sysctl -w net.core.somaxconn=65535
```

**生产案例**：某电商平台在双11期间，Nginx 的 `listen backlog` 设置为 65535，但系统级 `somaxconn` 仍为默认 128，导致实际生效的是 128。大量用户请求被 RST 拒绝，排查后发现是此参数未调整。

#### net.ipv4.tcp_max_syn_backlog

```bash
# 含义：SYN 半连接队列的最大长度
# 默认值：1024（CentOS 7）
# 推荐值：65535
# 场景：SYN Flood 防护、高并发新建连接

# 原理：
# TCP 三次握手的第一步，客户端发送 SYN，服务端回复 SYN+ACK。
# 此时连接处于 SYN_RECV 状态，存放在半连接队列中。
# 队列满时，新的 SYN 请求会被丢弃，客户端会重试。
# 配合 net.ipv4.tcp_syncookies 使用效果更佳。

sysctl -w net.ipv4.tcp_max_syn_backlog=65535
```

#### net.core.netdev_max_backlog

```bash
# 含义：网卡接收队列的最大长度
# 默认值：1000
# 推荐值：65535
# 场景：万兆网卡、高吞吐网络应用

# 原理：
# 当网卡收到数据包后，会放入接收队列等待内核处理。
# 如果内核处理速度跟不上网卡收包速度，队列满了就会丢包。
# 在万兆网卡或高 PPS（Packets Per Second）场景下，默认值容易导致丢包。

sysctl -w net.core.netdev_max_backlog=65535
```

### 2.2 TCP 缓冲区参数

#### net.core.rmem_max / net.core.wmem_max

```bash
# 含义：socket 接收/发送缓冲区的最大值（字节）
# 默认值：212992（约 208KB）
# 推荐值：16777216（16MB）
# 场景：大文件传输、数据库主从复制、视频流服务

# 原理：
# TCP 接收缓冲区（rmem）和发送缓冲区（wmem）决定了 TCP 窗口大小。
# 更大的缓冲区 = 更大的 TCP 窗口 = 更高的带宽利用率。
# 对于高带宽高延迟的网络（如跨机房复制），需要更大的缓冲区。
# 计算公式：带宽 × 延迟 = 需要的缓冲区大小
# 例：1Gbps × 50ms = 6.25MB

sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
```

#### net.ipv4.tcp_rmem / net.ipv4.tcp_wmem

```bash
# 含义：TCP 缓冲区的 最小值 默认值 最大值（字节）
# 默认值：4096 87380 6291456（接收）/ 4096 16384 4194304（发送）
# 推荐值：4096 87380 16777216

# 原理：
# 内核会根据网络状况自动调整 TCP 缓冲区大小（TCP 窗口缩放）。
# 三个值分别是最小、默认、最大。
# 最大值不能超过 net.core.rmem_max / net.core.wmem_max。

sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216"
sysctl -w net.ipv4.tcp_wmem="4096 87380 16777216"
```

### 2.3 TIME_WAIT 相关参数

#### net.ipv4.tcp_tw_reuse

```bash
# 含义：允许复用 TIME_WAIT 状态的 socket
# 默认值：0（CentOS 7）/ 2（Ubuntu 20.04+，仅对回环生效）
# 推荐值：1
# 场景：高并发短连接（HTTP API 调用、微服务间通信）

# 原理：
# TCP 连接关闭后，主动关闭方会进入 TIME_WAIT 状态，持续 2*MSL（通常60秒）。
# 在高并发场景下，大量 TIME_WAIT 会占用端口资源。
# 开启 tw_reuse 后，新的出站连接可以复用 TIME_WAIT 状态的端口。
# 注意：tw_reuse 只对出站连接生效，不影响入站连接。

sysctl -w net.ipv4.tcp_tw_reuse=1
```

#### net.ipv4.tcp_max_tw_buckets

```bash
# 含义：系统允许的最大 TIME_WAIT 连接数
# 默认值：32768（CentOS 7）/ 65536（Ubuntu 20.04）
# 推荐值：65535
# 场景：高并发 Web 服务器

# 原理：
# 当 TIME_WAIT 连接数超过此值时，多余的 TIME_WAIT 会被强制关闭。
# 这是一种保护机制，防止 TIME_WAIT 堆积耗尽内存。
# 但强制关闭可能导致后续连接出现问题，建议设置得足够大。

sysctl -w net.ipv4.tcp_max_tw_buckets=65535
```

#### net.ipv4.tcp_fin_timeout

```bash
# 含义：FIN_WAIT2 状态的超时时间（秒）
# 默认值：60
# 推荐值：15-30
# 场景：高并发短连接服务

# 原理：
# 主动关闭方发送 FIN 后进入 FIN_WAIT2 状态，等待对端的 FIN。
# 如果对端不发送 FIN（如程序 bug 或网络问题），FIN_WAIT2 会持续。
# 减小此值可以更快释放 FIN_WAIT2 连接，释放资源。

sysctl -w net.ipv4.tcp_fin_timeout=15
```

### 2.4 TCP Keepalive 参数

```bash
# net.ipv4.tcp_keepalive_time：TCP keepalive 探测的起始时间（秒）
# 默认值：7200（2小时）
# 推荐值：600（10分钟）
# 原理：连接空闲超过此时间后，开始发送 keepalive 探测包。
# 作用：及时发现死连接，释放资源。

# net.ipv4.tcp_keepalive_intvl：keepalive 探测间隔（秒）
# 默认值：75
# 推荐值：15

# net.ipv4.tcp_keepalive_probes：keepalive 探测次数
# 默认值：9
# 推荐值：5

sysctl -w net.ipv4.tcp_keepalive_time=600
sysctl -w net.ipv4.tcp_keepalive_intvl=15
sysctl -w net.ipv4.tcp_keepalive_probes=5
```

**生产案例**：某金融公司的微服务架构中，服务间通过长连接通信。由于默认 keepalive 时间为 2 小时，中间网络设备（如负载均衡器、防火墙）在 30 分钟无活动后会静默丢弃连接映射表。导致服务间通信偶发超时。调整 keepalive 参数后问题解决。

### 2.5 其他重要网络参数

```bash
# net.ipv4.tcp_syncookies：SYN Cookie 机制
# 默认值：1
# 推荐值：1（保持开启）
# 原理：当 SYN 队列满时，通过 SYN Cookie 技术继续接受新连接。
# 配合 tcp_max_syn_backlog 使用。

# net.core.optmem_max：socket 辅助缓冲区最大值
# 默认值：20480
# 推荐值：65536

# net.ipv4.tcp_fastopen：TCP Fast Open
# 默认值：1（仅客户端）
# 推荐值：3（客户端+服务端）
# 原理：允许在 SYN 包中携带数据，减少一个 RTT。
# 适用于频繁建立短连接的场景（如 CDN、API 网关）。

# net.ipv4.tcp_slow_start_after_idle：空闲后重新慢启动
# 默认值：1
# 推荐值：0
# 原理：禁用后，空闲连接不会重置拥塞窗口，保持之前的速率。
# 适用于长连接但间歇性传输的场景（如 WebSocket）。
```

## 3. 内存相关参数

### 3.1 虚拟内存参数

#### vm.swappiness

```bash
# 含义：控制内核使用 swap 的倾向
# 默认值：60
# 推荐值：
#   - 数据库服务器：0-10
#   - Web 服务器：10-30
#   - 通用服务器：30-60
# 范围：0-100

# 原理：
# swappiness 值越高，内核越倾向于使用 swap。
# 值为 0 时，只有在内存严重不足（OOM 临近）时才使用 swap。
# 值为 100 时，积极使用 swap。
# 对于数据库（如 MySQL、Redis），swap 会导致严重的性能抖动。

# 生产案例：
# 某 Redis 集群节点，swappiness=60，高峰期 Redis 使用了 2GB swap，
# 导致响应时间从 1ms 飙升到 100ms+。调为 0 后问题解决。

sysctl -w vm.swappiness=10
```

#### vm.dirty_ratio / vm.dirty_background_ratio

```bash
# vm.dirty_ratio：脏页占总内存的比例，达到此值时阻塞写入进行回写
# 默认值：20（即 20%）
# 推荐值：10-20

# vm.dirty_background_ratio：脏页占总内存的比例，达到此值时后台异步回写
# 默认值：10
# 推荐值：5-10

# 原理：
# 当应用写文件时，数据先写入内存中的脏页（dirty page），
# 然后由内核线程（pdflush/flush）异步写入磁盘。
# dirty_ratio 控制同步回写的阈值（阻塞应用），
# dirty_background_ratio 控制异步回写的阈值（不阻塞应用）。

# 场景适配：
# - 写入密集型（如日志服务器）：适当增大 dirty_ratio，减少回写频率
# - 读取密集型（如 CDN 缓存）：保持较小值，为读取留出更多内存
# - 数据库服务器：使用 dirty_bytes 替代，更精确控制

# 使用绝对值替代百分比（更精确）：
sysctl -w vm.dirty_bytes=268435456          # 256MB
sysctl -w vm.dirty_background_bytes=67108864  # 64MB
```

#### vm.overcommit_memory / vm.overcommit_ratio

```bash
# vm.overcommit_memory：内存分配策略
# 默认值：0
# 推荐值：
#   - Redis：1
#   - 通用服务器：0 或 2
#   - 数据库服务器：2

# 取值含义：
# 0：启发式过度提交（默认）- 内核根据启发式算法决定是否允许分配
# 1：总是允许过度提交 - 任何 malloc 都不会失败（Redis 需要此设置）
# 2：严格控制 - 分配量不超过 swap + 物理内存 × overcommit_ratio

# vm.overcommit_ratio：物理内存的使用比例（仅 overcommit_memory=2 时生效）
# 默认值：50
# 推荐值：80-90

# 生产案例：
# Redis 在 fork（BGSAVE/BGREWRITEAOF）时需要额外的内存。
# 如果 overcommit_memory=0，fork 可能因内存不足而失败，
# 导致 RDB/AOF 持久化失败。设置为 1 后问题解决。

sysctl -w vm.overcommit_memory=1  # Redis 专用
# 或
sysctl -w vm.overcommit_memory=2
sysctl -w vm.overcommit_ratio=80
```

### 3.2 OOM Killer 参数

```bash
# vm.panic_on_oom：OOM 时是否触发 kernel panic
# 默认值：0
# 推荐值：0（让 OOM Killer 工作）
# 特殊场景：关键业务服务器可以设为 1（配合 kexec 使用）

# vm.oom_kill_allocating_task：是否杀死触发 OOM 的进程
# 默认值：0
# 推荐值：0（让 OOM Killer 选择最合适的进程杀死）

# 调整进程的 oom_score_adj：保护关键进程
# 范围：-1000 到 1000
# -1000：永不被 OOM Killer 杀死
# 1000：优先被杀死

# 保护 MySQL 进程
echo -1000 > /proc/$(pidof mysqld)/oom_score_adj

# 持久化方式（systemd 服务）：
# 在 [Service] 段添加 OOMScoreAdjust=-999
```

### 3.3 大页内存（Huge Pages）

```bash
# 大页内存用于减少 TLB miss，提升内存密集型应用性能。

# 查看当前大页配置
cat /proc/meminfo | grep -i huge

# 设置大页数量（每个大页 2MB）
# 假设需要 4GB 大页内存：4GB / 2MB = 2048 个大页
sysctl -w vm.nr_hugepages=2048

# 应用使用大页的方式：
# 1. Oracle/MySQL：通过 SHMMAX/SHMALL 配置共享内存使用大页
# 2. DPDK/SPDK：直接使用大页进行数据包处理
# 3. JVM：-XX:+UseLargePages

# 注意：
# - 大页内存会被预留，不可被其他应用使用
# - 需要根据实际内存需求合理分配
# - 超大页（1GB hugepages）可通过 boot 参数启用：
#   hugepagesz=1G hugepages=4
```

## 4. 文件系统相关参数

### 4.1 文件描述符

```bash
# fs.file-max：系统级最大文件描述符数
# 默认值：根据内存自动计算（通常几十万）
# 推荐值：1048576（100万）
# 场景：高并发服务器、代理服务器

# 原理：
# 每个打开的文件（包括 socket）都需要一个文件描述符。
# Nginx 反向代理 10000 个连接，每个连接需要 2 个 fd（客户端+后端），
# 加上日志文件、缓存文件等，总共需要约 20000+ 个 fd。

# 查看当前值
sysctl fs.file-max
cat /proc/sys/fs/file-nr  # 已分配 / 未使用 / 最大值

# 设置
sysctl -w fs.file-max=1048576

# 同时需要调整进程级限制（见 limits.conf）
```

### 4.2 inotify 参数

```bash
# fs.inotify.max_user_watches：每个用户可监控的最大文件数
# 默认值：8192（CentOS 7）/ 65536（Ubuntu 20.04）
# 推荐值：1048576
# 场景：IDE（VSCode）、文件同步服务（rsync）、日志监控

# fs.inotify.max_user_instances：每个用户的 inotify 实例数
# 默认值：128
# 推荐值：65536

# fs.inotify.max_queued_events：事件队列长度
# 默认值：16384
# 推荐值：65536

sysctl -w fs.inotify.max_user_watches=1048576
sysctl -w fs.inotify.max_user_instances=65536
sysctl -w fs.inotify.max_queued_events=65536
```

### 4.3 文件系统缓存

```bash
# vm.vfs_cache_pressure：内核回收 dentry/inode 缓存的倾向
# 默认值：100
# 推荐值：
#   - 文件服务器/NFS：50-100
#   - 数据库服务器：200
#   - 通用服务器：100

# 原理：
# dentry（目录项）和 inode（文件元数据）缓存会占用大量内存。
# vfs_cache_pressure=100 表示正常回收。
# 值越小，越不倾向于回收（适合频繁访问文件的场景）。
# 值越大，越倾向于回收（适合内存紧张的场景）。

sysctl -w vm.vfs_cache_pressure=100
```

## 5. 安全相关参数

### 5.1 网络安全

```bash
# net.ipv4.conf.all.rp_filter：反向路径过滤
# 默认值：0（CentOS 7）/ 1（Ubuntu）
# 推荐值：1
# 原理：验证数据包的源地址是否可达，防止 IP 欺骗

# net.ipv4.conf.all.accept_redirects：接受 ICMP 重定向
# 默认值：1
# 推荐值：0
# 原理：关闭后防止中间人攻击通过重定向修改路由

# net.ipv4.conf.all.send_redirects：发送 ICMP 重定向
# 默认值：1
# 推荐值：0

# net.ipv4.icmp_echo_ignore_broadcasts：忽略广播 ICMP 请求
# 默认值：1
# 推荐值：1（保持开启，防止 Smurf 攻击）

# net.ipv4.icmp_ignore_bogus_error_responses：忽略伪造的 ICMP 错误
# 默认值：1
# 推荐值：1

# net.ipv4.tcp_syncookies：SYN Cookie（防 SYN Flood）
# 默认值：1
# 推荐值：1
```

### 5.2 内核安全

```bash
# kernel.randomize_va_space：ASLR（地址空间布局随机化）
# 默认值：2
# 推荐值：2（完全随机化）

# kernel.dmesg_restrict：限制 dmesg 访问
# 默认值：0
# 推荐值：1（仅 root 可查看内核日志）

# kernel.kptr_restrict：限制内核指针暴露
# 默认值：0（CentOS 7）/ 1（Ubuntu）
# 推荐值：1

# kernel.yama.ptrace_scope：ptrace 调试权限控制
# 默认值：0
# 推荐值：1（仅父进程可 ptrace 子进程）

# kernel.core_uses_pid：core dump 文件名包含 PID
# 默认值：0
# 推荐值：1（便于区分多个 core dump 文件）
```

## 6. 完整生产配置示例

### 6.1 Web 服务器配置

```bash
# /etc/sysctl.d/99-web-server.conf

# === 网络连接 ===
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535

# === TCP 缓冲区 ===
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 87380 16777216

# === TIME_WAIT ===
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 65535
net.ipv4.tcp_fin_timeout = 15

# === Keepalive ===
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5

# === 文件描述符 ===
fs.file-max = 1048576

# === 内存 ===
vm.swappiness = 10
vm.overcommit_memory = 0

# === 安全 ===
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1
```

### 6.2 数据库服务器配置

```bash
# /etc/sysctl.d/99-database.conf

# === 内存 ===
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.overcommit_memory = 0  # MySQL/PostgreSQL
# vm.overcommit_memory = 1  # Redis

# === 文件系统 ===
fs.file-max = 2097152
fs.aio-max-nr = 1048576

# === 网络（数据库连接通常长连接）===
net.core.somaxconn = 65535
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5

# === 大页内存（Oracle/大型 PostgreSQL）===
# vm.nr_hugepages = 2048
```

### 6.3 高并发网关配置

```bash
# /etc/sysctl.d/99-gateway.conf

# === 高并发连接 ===
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
net.nf_conntrack_max = 1048576  # 如果使用 iptables

# === TCP Fast Open ===
net.ipv4.tcp_fastopen = 3

# === 禁用空闲慢启动 ===
net.ipv4.tcp_slow_start_after_idle = 0

# === TIME_WAIT 处理 ===
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_fin_timeout = 10

# === 连接追踪（如果有 conntrack）===
# net.netfilter.nf_conntrack_max = 1048576
# net.netfilter.nf_conntrack_tcp_timeout_established = 3600
# net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
```

## 7. 调优方法论

### 7.1 调优步骤

```
1. 建立基线 → 2. 识别瓶颈 → 3. 分析参数 → 4. 小范围测试 → 5. 灰度发布 → 6. 监控验证
```

### 7.2 监控指标

```bash
# 网络监控
ss -s                    # TCP 连接统计
sar -n DEV 1             # 网卡流量
sar -n TCP 1             # TCP 统计
netstat -s | grep -i "listen\|overflow\|drop"  # 丢弃统计

# 内存监控
vmstat 1                 # 内存使用
sar -r 1                 # 内存统计
/proc/meminfo            # 详细内存信息

# 文件描述符监控
cat /proc/sys/fs/file-nr # 已使用/最大值
ls /proc/<pid>/fd | wc -l  # 进程级 fd 使用
```

### 7.3 常见问题排查

| 现象 | 可能原因 | 排查命令 | 优化参数 |
|------|----------|----------|----------|
| 连接被拒绝 | accept queue 满 | `ss -lnt` | somaxconn |
| 连接超时 | SYN queue 满 | `netstat -s \| grep SYN` | tcp_max_syn_backlog |
| 端口耗尽 | TIME_WAIT 过多 | `ss -s` | tcp_tw_reuse |
| 内存不足 | swap 频繁 | `vmstat 1` | swappiness |
| 丢包 | 网卡队列满 | `netstat -s \| grep drop` | netdev_max_backlog |
| 文件打开失败 | fd 耗尽 | `cat /proc/sys/fs/file-nr` | file-max |

## 8. 注意事项

1. **先备份后修改**：修改前记录原始值 `sysctl -a > /tmp/sysctl-backup-$(date +%F).txt`
2. **逐个参数调优**：不要一次性修改所有参数，逐一调整并验证效果
3. **测试环境先行**：所有参数变更必须先在测试环境验证
4. **监控告警**：参数变更后持续监控系统指标，关注异常波动
5. **文档记录**：记录每次参数变更的原因、值和效果
6. **参数生效顺序**：`/etc/sysctl.conf` → `/etc/sysctl.d/*.conf`（按文件名字母顺序）
7. **容器环境注意**：Docker/K8s 中部分 sysctl 参数需要通过 `--sysctl` 或 securityContext 设置
