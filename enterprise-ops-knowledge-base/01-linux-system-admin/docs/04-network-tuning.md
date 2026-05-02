# 网络参数调优

## 概述

网络性能是企业级服务的关键瓶颈之一。本文档涵盖 Linux 内核 TCP 参数调优、网卡优化、拥塞控制算法选择及生产环境实战案例。

## 1. TCP 内核参数调优

### 1.1 连接管理参数

```bash
# /etc/sysctl.d/99-network-tuning.conf

# SYN 队列长度（半连接队列）
net.ipv4.tcp_max_syn_backlog = 65535

# 已完成连接队列长度（accept 队列）
net.core.somaxconn = 65535

# SYN Flood 防护：启用 SYN Cookie
net.ipv4.tcp_syncookies = 1

# SYN+ACK 重试次数（降低可快速释放半连接）
net.ipv4.tcp_synack_retries = 2

# SYN 重试次数
net.ipv4.tcp_syn_retries = 2

# 允许的最大 TIME_WAIT 数量
net.ipv4.tcp_max_tw_buckets = 65535

# 启用 TIME_WAIT 快速回收（NAT 环境慎用）
net.ipv4.tcp_tw_reuse = 1

# 本地端口范围
net.ipv4.ip_local_port_range = 1024 65535
```

### 1.2 缓冲区调优

```bash
# TCP 接收/发送缓冲区（最小值 默认值 最大值）
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 网络设备接收/发送队列长度
net.core.netdev_max_backlog = 65536

# socket 缓冲区默认值和最大值
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
```

### 1.3 TCP 保活与超时

```bash
# TCP keepalive 参数（秒）
net.ipv4.tcp_keepalive_time = 600    # 空闲多久后发送探测
net.ipv4.tcp_keepalive_intvl = 30    # 探测间隔
net.ipv4.tcp_keepalive_probes = 3    # 探测次数

# FIN_WAIT2 超时时间
net.ipv4.tcp_fin_timeout = 15

# TCP 孤立连接最大数量
net.ipv4.tcp_max_orphans = 16384
```

### 1.4 高级 TCP 特性

```bash
# 启用 TCP 窗口缩放
net.ipv4.tcp_window_scaling = 1

# 启用 TCP 时间戳
net.ipv4.tcp_timestamps = 1

# 启用 TCP 选择性确认
net.ipv4.tcp_sack = 1

# 启用 TCP Fast Open（客户端和服务端）
net.ipv4.tcp_fastopen = 3

# 关闭慢启动重启
net.ipv4.tcp_slow_start_after_idle = 0

# MTU 探测
net.ipv4.tcp_mtu_probing = 1
```

## 2. 网卡调优

### 2.1 Ring Buffer 调整

```bash
# 查看当前 Ring Buffer 设置
ethtool -g eth0

# 设置 Ring Buffer（需要网卡支持）
ethtool -G eth0 rx 4096 tx 4096
```

### 2.2 中断合并（Interrupt Coalescing）

```bash
# 查看当前设置
ethtool -c eth0

# 调整中断合并参数
ethtool -C eth0 rx-usecs 50 rx-frames 16 tx-usecs 50 tx-frames 16
```

### 2.3 多队列与 RSS

```bash
# 查看网卡队列数
ethtool -l eth0

# 设置队列数（等于 CPU 核心数）
ethtool -L eth0 combined 8

# 查看 RSS 哈希设置
ethtool -n eth0

# 启用多队列卸载
ethtool -K eth0 rxhash on
```

### 2.4 中断亲和性绑定

```bash
#!/bin/bash
# 将网卡中断绑定到不同 CPU 核心
# 优化 NUMA 架构下的网络性能

IRQ_BASE=$(grep eth0 /proc/interrupts | awk '{print $1}' | tr -d ':' | head -1)
CPU_CORES=$(nproc)

for i in $(seq 0 $((CPU_CORES - 1))); do
    IRQ=$((IRQ_BASE + i))
    CPU=$((i % CPU_CORES))
    MASK=$(printf "%x" $((1 << CPU)))
    echo "$MASK" > /proc/irq/$IRQ/smp_affinity
    echo "IRQ $IRQ -> CPU $CPU (affinity: $MASK)"
done
```

### 2.5 网卡卸载功能

```bash
# 启用 TCP Segmentation Offload
ethtool -K eth0 tso on

# 启用 Generic Segmentation Offload
ethtool -K eth0 gso on

# 启用 Generic Receive Offload
ethtool -K eth0 gro on

# 启用校验和卸载
ethtool -K eth0 rx on tx on
```

## 3. 拥塞控制算法

### 3.1 可用算法

```bash
# 查看可用的拥塞控制算法
sysctl net.ipv4.tcp_available_congestion_control

# 查看当前使用的算法
sysctl net.ipv4.tcp_congestion_control
```

### 3.2 算法选择建议

| 算法 | 适用场景 | 特点 |
|------|---------|------|
| cubic | 默认，通用场景 | 稳定，适合长肥管道 |
| bbr | 高延迟、高丢包 | Google 开发，基于带宽估计 |
| bbr2 | BBR 改进版 | 更公平，收敛更快 |
| reno | 传统算法 | 仅作参考 |

### 3.3 BBR 部署

```bash
# 加载 BBR 模块
modprobe tcp_bbr

# 设置 BBR 为默认拥塞控制
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/99-network-tuning.conf

# 设置 qdisc 为 fq（BBR 推荐配合使用）
echo "net.core.default_qdisc = fq" >> /etc/sysctl.d/99-network-tuning.conf

# 持久化模块加载
echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf

# 应用配置
sysctl -p /etc/sysctl.d/99-network-tuning.conf
```

## 4. 网络监控与诊断

### 4.1 关键监控指标

```bash
# 查看 TCP 连接统计
ss -s

# 查看网络错误统计
netstat -s | grep -i error

# 查看丢包统计
cat /proc/net/snmp | grep -E "Tcp:|Udp:|Ip:"

# 查看网卡队列溢出
ethtool -S eth0 | grep -i drop
```

### 4.2 常用诊断工具

```bash
# 实时网络流量监控
iftop -i eth0 -nNP

# 连接追踪
conntrack -L

# 抓包分析
tcpdump -i eth0 -nn -w /tmp/capture.pcap port 80

# 延迟测试
ping -c 100 target_host | tail -1
```

## 5. 生产案例

### 5.1 高并发 Web 服务器

**场景**：Nginx 承载 10 万并发连接

```bash
# /etc/sysctl.d/99-web-server.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.ip_local_port_range = 1024 65535
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_max_tw_buckets = 200000

# Nginx 配置配合
# worker_connections 65535;
# worker_rlimit_nofile 131072;
```

### 5.2 数据库服务器

**场景**：MySQL 主从复制，低延迟要求

```bash
# /etc/sysctl.d/99-db-server.conf
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.tcp_retries2 = 5
net.ipv4.tcp_syn_retries = 2

# 禁用 Nagle 算法（降低延迟）
# 应用层设置 TCP_NODELAY
```

### 5.3 微服务内部通信

**场景**：Kubernetes Pod 间高频 RPC 调用

```bash
# /etc/sysctl.d/99-microservice.conf
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Pod 级别 sysctl（Kubernetes securityContext）
# securityContext:
#   sysctls:
#     - name: net.core.somaxconn
#       value: "65535"
```

### 5.4 CDN 边缘节点

**场景**：大带宽、高吞吐文件分发

```bash
# /etc/sysctl.d/99-cdn-edge.conf
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

## 6. 调优注意事项

1. **逐步调优**：每次只修改少量参数，观察效果后再继续
2. **基准测试**：调优前后用 iperf3/wrk 进行对比测试
3. **监控验证**：通过 Prometheus + Grafana 持续监控网络指标
4. **环境差异**：不同业务场景需要不同参数，避免生搬硬套
5. **内核版本**：部分参数在不同内核版本行为有差异，注意验证
