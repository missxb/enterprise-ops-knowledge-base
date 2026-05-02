# 🔧 故障排查手册

> 快速定位和解决常见运维问题的实战手册

## 排查原则

### 1. 五步排查法

```
1. 确认现象 → 2. 收集信息 → 3. 分析原因 → 4. 制定方案 → 5. 验证恢复
```

### 2. 排查工具速查

| 场景 | 工具 |
|------|------|
| CPU 高 | top, mpstat, pidstat, perf |
| 内存高 | free, vmstat, pmap, /proc/meminfo |
| IO 慢 | iostat, iotop, blktrace |
| 网络不通 | ping, traceroute, tcpdump, ss, mtr |
| 进程异常 | ps, strace, lsof, gdb |
| 磁盘满 | df, du, lsof |

## 问题分类

### 系统问题
- [Linux 性能问题排查](playbooks/01-linux-performance.md)
- [网络问题排查](playbooks/02-network-issues.md)

### 容器与编排
- [Docker 问题排查](playbooks/03-docker-issues.md)
- [K8s 问题排查](playbooks/04-k8s-issues.md)

### 数据库
- [数据库问题排查](playbooks/05-database-issues.md)
- [MySQL 问题排查](playbooks/07-mysql-issues.md)

### 中间件
- [Nginx 问题排查](playbooks/06-nginx-issues.md)

### 应用
- [应用问题排查](playbooks/08-application-issues.md)

## Runbook 速查

| 问题 | 速查链接 |
|------|----------|
| CPU 使用率过高 | [runbooks/high-cpu.md](runbooks/high-cpu.md) |
| 内存使用率过高 | [runbooks/high-memory.md](runbooks/high-memory.md) |
| 磁盘空间不足 | [runbooks/disk-full.md](runbooks/disk-full.md) |
| OOM Kill | [runbooks/oom-killed.md](runbooks/oom-killed.md) |
| 连接被拒绝 | [runbooks/connection-refused.md](runbooks/connection-refused.md) |
| DNS 解析失败 | [runbooks/dns-resolution-failed.md](runbooks/dns-resolution-failed.md) |
