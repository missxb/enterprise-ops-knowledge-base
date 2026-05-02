# Linux 性能问题排查

## 排查流程

```
CPU 高? → top/pidstat → 找到进程 → strace/perf → 定位代码
内存高? → free/vmstat → 找到进程 → pmap → 定位内存泄漏
IO 慢? → iostat/iotop → 找到进程 → strace → 定位 IO 操作
网络慢? → ss/tcpdump → 分析连接 → 定位瓶颈
```

## CPU 排查

```bash
# 1. 查看整体 CPU 使用
top -bn1 | head -20
# 或
mpstat -P ALL 1 5

# 2. 找到 CPU 占用最高的进程
pidstat -u 1 5 | sort -k3 -rn | head -10

# 3. 查看进程的线程 CPU 使用
top -Hp <pid>

# 4. 分析进程在做什么
strace -cp <pid> -e trace=all
# 或
perf top -p <pid>

# 5. 生成火焰图
perf record -F 99 -p <pid> --call-graph dwarf -- sleep 30
perf script | stackcollapse-perf.pl | flamegraph.pl > flamegraph.svg
```

## 内存排查

```bash
# 1. 查看内存使用
free -h
cat /proc/meminfo | grep -E "^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree)"

# 2. 查看各进程内存使用
ps aux --sort=-%mem | head -10
# 或
smem -t -k -s rss | tail -10

# 3. 查看进程详细内存
pmap -x <pid> | tail -1
cat /proc/<pid>/status | grep -E "^(VmSize|VmRSS|VmSwap)"

# 4. 检查内存泄漏
valgrind --leak-check=full ./your_program

# 5. 检查 OOM 历史
dmesg | grep -i oom
journalctl -k | grep -i oom
```

## IO 排查

```bash
# 1. 查看磁盘 IO 统计
iostat -xz 1 5

# 关键指标：
# %util: 磁盘使用率 (>70% 需关注)
# await: 平均 IO 等待时间 (>10ms 需关注)
# r/s, w/s: 每秒读写次数

# 2. 找到 IO 最高的进程
iotop -oP

# 3. 查看进程 IO 统计
pidstat -d 1 5

# 4. 检查文件系统
df -ih  # inode 使用
mount | grep "ro,"  # 只读挂载
```

## 网络排查

```bash
# 1. 查看网络连接状态
ss -s  # 连接统计
ss -tlnp  # 监听端口
ss -tnp state established  # 活动连接

# 2. 检查网络延迟
ping -c 10 target_host
mtr target_host

# 3. 抓包分析
tcpdump -i eth0 -nn -s0 -c 1000 'port 80' -w /tmp/capture.pcap

# 4. DNS 排查
dig @dns_server domain.com +trace
nslookup domain.com

# 5. 带宽测试
iperf3 -c target_host -t 30
```

## 综合排查脚本

```bash
#!/bin/bash
echo "=== 系统负载 ==="
uptime
echo "=== CPU TOP 10 ==="
ps aux --sort=-%cpu | head -11
echo "=== 内存 TOP 10 ==="
ps aux --sort=-%mem | head -11
echo "=== 磁盘使用 ==="
df -h
echo "=== IO 状态 ==="
iostat -xz 1 1
echo "=== 网络连接 ==="
ss -s
echo "=== 最近 OOM ==="
dmesg | grep -i oom | tail -5
```
