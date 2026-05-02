# 进程管理与调度

## 概述

进程管理是 Linux 系统运维的核心技能。本文涵盖 systemd 进程管理、cgroup 资源控制、ulimit 资源限制、进程优先级调度及生产环境最佳实践。

## 1. 进程基础概念

### 1.1 进程状态

```bash
# 进程状态码
# R - Running/Runnable（运行中/可运行）
# S - Sleeping（可中断睡眠）
# D - Disk Sleep（不可中断睡眠，通常等待 IO）
# T - Stopped（停止）
# Z - Zombie（僵尸进程）

# 查看进程状态
ps aux
ps -eo pid,ppid,user,stat,%cpu,%mem,cmd

# 查找僵尸进程
ps aux | awk '$8=="Z"'

# 查找 D 状态进程（可能卡在 IO）
ps aux | awk '$8=="D"'
```

### 1.2 进程关系

```bash
# 进程树查看
pstree -p
pstree -p -h    # 高亮当前进程

# 查看进程的父进程关系
ps -ef --forest

# 查看特定进程的子进程
ps --ppid <parent_pid>
```

## 2. systemd 进程管理

### 2.1 进程控制

```bash
# 查看所有运行中的服务
systemctl list-units --type=service --state=running

# 查看服务状态
systemctl status nginx.service

# 启动/停止/重启服务
systemctl start nginx.service
systemctl stop nginx.service
systemctl restart nginx.service

# 重新加载配置（不中断服务）
systemctl reload nginx.service

# 设置开机自启
systemctl enable nginx.service
systemctl disable nginx.service

# 查看服务日志
journalctl -u nginx.service -f
journalctl -u nginx.service --since "1 hour ago"
```

### 2.2 资源控制（systemd 集成 cgroup）

```bash
# 通过 systemd 限制服务资源
# /etc/systemd/system/myapp.service.d/limits.conf
[Service]
# CPU 限制（50% 单核）
CPUQuota=50%

# CPU 亲和性
CPUAffinity=0 1

# 内存限制
MemoryLimit=2G
MemoryMax=2G
MemoryHigh=1.5G

# IO 限制
IOWeight=100
IOReadBandwidthMax=/dev/sda 50M
IOWriteBandwidthMax=/dev/sda 50M

# 任务数限制
TasksMax=512

# 文件描述符限制
LimitNOFILE=65535
LimitNPROC=65535
```

```bash
# 应用配置
systemctl daemon-reload
systemctl restart myapp.service

# 验证 cgroup 配置
systemctl show myapp.service | grep -E "Memory|CPU|Tasks"
```

## 3. cgroup 资源控制

### 3.1 cgroup v2 管理

```bash
# 检查 cgroup 版本
stat -fc %T /sys/fs/cgroup/
# cgroup2fs 表示 v2

# 查看 cgroup 层次结构
systemd-cgls

# 查看资源使用
systemd-cgtop
```

### 3.2 手动创建 cgroup

```bash
# cgroup v2 创建
mkdir /sys/fs/cgroup/mygroup

# 设置 CPU 限制（50%）
echo "50000 100000" > /sys/fs/cgroup/mygroup/cpu.max

# 设置内存限制（2GB）
echo "2147483648" > /sys/fs/cgroup/mygroup/memory.max

# 设置 IO 限制
echo "8:0 rbps=10485760 wbps=10485760" > /sys/fs/cgroup/mygroup/io.max

# 将进程加入 cgroup
echo $PID > /sys/fs/cgroup/mygroup/cgroup.procs
```

### 3.3 cgroup 配额策略

```bash
# CPU 权重（相对份额）
echo "100" > /sys/fs/cgroup/mygroup/cpu.weight

# 内存软限制（触发回收）
echo "1073741824" > /sys/fs/cgroup/mygroup/memory.high

# 内存硬限制（触发 OOM）
echo "2147483648" > /sys/fs/cgroup/mygroup/memory.max

# 查看内存使用
cat /sys/fs/cgroup/mygroup/memory.current
cat /sys/fs/cgroup/mygroup/memory.stat
```

## 4. ulimit 资源限制

### 4.1 查看当前限制

```bash
# 查看所有限制
ulimit -a

# 查看具体限制
ulimit -n    # 打开文件数
ulimit -u    # 最大进程数
ulimit -s    # 栈大小
ulimit -v    # 虚拟内存

# 查看硬限制
ulimit -Hn
ulimit -Hu
```

### 4.2 永久配置

```bash
# /etc/security/limits.conf
# 格式：<domain> <type> <item> <value>

# 所有用户
*    soft    nofile    65535
*    hard    nofile    65535
*    soft    nproc     65535
*    hard    nproc     65535

# 特定用户
www  soft    nofile    131072
www  hard    nofile    131072
mysql soft    nofile    65535
mysql hard    nofile    65535

# 特定组
@ops soft    nproc     unlimited

# 核心转储大小
*    soft    core      unlimited
*    hard    core      unlimited

# 堆栈大小
*    soft    stack     8192
*    hard    stack     65535

# 内存锁定
*    soft    memlock   unlimited
*    hard    memlock   unlimited
```

### 4.3 systemd 服务的 ulimit

```bash
# 在 service 文件中设置
[Service]
LimitNOFILE=65535
LimitNPROC=65535
LimitCORE=infinity
LimitMEMLOCK=infinity

# 临时修改运行中进程的限制
prlimit --pid $PID --nofile=65535:65535
```

## 5. 进程优先级与调度

### 5.1 nice 值调度

```bash
# nice 值范围：-20（最高优先级）到 19（最低优先级）
# 默认值为 0

# 以指定 nice 值启动进程
nice -n 10 ./my_background_job.sh

# 修改运行中进程的 nice 值
renice -n 5 -p $PID

# 查看进程 nice 值
ps -eo pid,ni,cmd | grep nginx

# 提高关键进程优先级
renice -n -5 -p $(pgrep -f "nginx: master")
```

### 5.2 实时调度策略

```bash
# 实时调度策略
# SCHED_FIFO  - 先进先出（实时）
# SCHED_RR    - 轮转调度（实时）
# SCHED_OTHER - 普通分时调度

# 设置实时调度
chrt -f 50 ./realtime_task    # FIFO，优先级 50
chrt -r 30 ./realtime_task    # RR，优先级 30

# 查看进程调度策略
chrt -p $PID

# 修改运行中进程的调度策略
chrt -f -p 50 $PID
```

### 5.3 CPU 亲和性

```bash
# 查看进程的 CPU 亲和性
taskset -p $PID

# 绑定进程到指定 CPU
taskset -c 0,1 ./my_app.sh

# 修改运行中进程的 CPU 亲和性
taskset -pc 2,3 $PID

# 使用 cgroup 绑定 CPU
systemctl set-property myapp.service CPUAffinity=0 1 2 3
```

### 5.4 调度参数调优

```bash
# 内核调度参数
# /etc/sysctl.d/99-scheduler.conf

# 调度器迁移间隔（毫秒）
kernel.sched_migration_cost_ns = 500000

# 最小粒度（纳秒）
kernel.sched_min_granularity_ns = 10000000

# 唤醒粒度
kernel.sched_wakeup_granularity_ns = 15000000

# NUMA 均衡
kernel.numa_balancing = 1

# NUMA 均衡扫描延迟
kernel.numa_balancing_scan_delay_ms = 1000
```

## 6. 进程监控与管理

### 6.1 常用监控工具

```bash
# top/htop 实时监控
top -c          # 显示完整命令行
htop            # 交互式监控

# 进程资源使用
pidstat -p $PID 1    # 每秒采样
pidstat -u 1         # CPU 使用
pidstat -r 1         # 内存使用
pidstat -d 1         # IO 使用

# 进程打开的文件
lsof -p $PID
lsof -i :80

# 进程的系统调用跟踪
strace -p $PID -c    # 统计系统调用
strace -p $PID -e trace=network    # 跟踪网络调用
```

### 6.2 进程信号管理

```bash
# 常用信号
# SIGHUP   (1)  - 重新加载配置
# SIGINT   (2)  - 中断（Ctrl+C）
# SIGKILL  (9)  - 强制终止（不可捕获）
# SIGTERM  (15) - 优雅终止（默认）
# SIGUSR1  (10) - 用户自定义信号1
# SIGUSR2  (12) - 用户自定义信号2

# 优雅停止
kill $PID

# 强制终止
kill -9 $PID

# 发送自定义信号
kill -USR1 $PID    # Nginx 重新打开日志

# 批量终止
pkill -f "my_app"
killall my_app

# 按条件终止
killall -u username    # 终止用户所有进程
```

### 6.3 僵尸进程处理

```bash
# 查找僵尸进程
ps aux | awk '$8=="Z" {print $2, $11}'

# 杀死僵尸进程的父进程
kill -SIGCHLD $PPID    # 通知父进程回收
kill $PPID             # 杀死父进程（僵尸随之清除）

# 批量清理僵尸
for pid in $(ps -eo pid,stat | awk '$2~/Z/ {print $1}'); do
    ppid=$(ps -o ppid= -p $pid | tr -d ' ')
    kill -SIGCHLD $ppid 2>/dev/null
done
```

## 7. 生产环境最佳实践

### 7.1 关键进程保护

```bash
# 设置进程不可被 OOM Killer 杀死
echo -1000 > /proc/$PID/oom_score_adj

# 设置 OOM 保护值
echo -17 > /proc/$PID/oom_adj

# 设置进程 dumpable 标志
prctl --set-dumpable 1 $PID
```

### 7.2 资源隔离策略

| 服务类型 | CPU 权重 | 内存限制 | IO 优先级 | 说明 |
|---------|---------|---------|----------|------|
| 数据库 | 高(500+) | 较大 | 高 | 核心业务 |
| Web 服务 | 中(100) | 中等 | 中 | 请求处理 |
| 日志收集 | 低(50) | 较小 | 低 | 后台任务 |
| 监控代理 | 低(10) | 较小 | 低 | 不影响业务 |

### 7.3 自动化管理脚本

```bash
#!/bin/bash
# 进程健康检查与自动重启
SERVICE=$1
MAX_RETRIES=3
RETRY_INTERVAL=10

check_and_restart() {
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        if systemctl is-active --quiet "$SERVICE"; then
            return 0
        fi
        echo "[$(date)] $SERVICE 未运行，尝试重启 ($((retries+1))/$MAX_RETRIES)"
        systemctl restart "$SERVICE"
        sleep $RETRY_INTERVAL
        retries=$((retries+1))
    done
    echo "[$(date)] $SERVICE 重启失败，达到最大重试次数"
    return 1
}

check_and_restart "$SERVICE"
```
