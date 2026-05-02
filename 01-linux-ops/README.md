# Linux 运维实战知识库

> 基于语雀多个知识库整理，结合企业实战经验

## 1. 系统性能排查速查表

### CPU 排查
```bash
# CPU 使用率概览
top -c                          # 按 P 排序CPU
mpstat -P ALL 2 5               # 多核CPU详情
pidstat -u 2 5                  # 进程级CPU使用

# 定位高CPU进程
ps aux --sort=-%cpu | head -10
ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -10

# 分析CPU热点
perf top -p <PID>               # 实时热点
perf record -p <PID> -g -- sleep 30  # 采样分析
```

### 内存排查
```bash
# 内存概览
free -h                         # available 才是真正可用内存
vmstat 2 10                     # 关注 si/so 列

# 进程内存排序
ps aux --sort=-%mem | head -10
smem -rs pss | head -10         # PSS 更准确

# 内存详情
pmap -x <PID>                   # 进程内存映射
cat /proc/<PID>/smaps_rollup    # 内存段详情

# OOM 分析
dmesg | grep -i "out of memory"
journalctl -k | grep -i oom
```

### 磁盘排查
```bash
# 磁盘空间
df -h                           # 空间使用率
du -sh /* | sort -rh | head -10 # 大目录查找
ncdu /                          # 交互式分析

# 磁盘IO
iostat -xz 2 5                  # IO详情
iotop -oP                       # IO排序
iotop -aP                       # 累积IO

# inode 检查
df -i                           # inode使用率
```

### 网络排查
```bash
# 网络连接
ss -tulnp                       # 监听端口
ss -s                           # 连接统计
ss -tnp state established       # 已建立连接

# 网络流量
iftop -i eth0                   # 实时流量
nload eth0                      # 带宽监控
sar -n DEV 2 5                  # 网络统计

# DNS 排查
dig +trace example.com          # DNS追踪
nslookup example.com            # DNS查询
host example.com                # DNS解析

# 丢包排查
ping -c 100 <目标IP> | tail -3
mtr -rw <目标IP>                # 路由追踪
```

## 2. 常见故障处理手册

### 磁盘空间满
```bash
# 快速清理
journalctl --vacuum-size=500M   # 清理日志
docker system prune -af         # 清理Docker
find /var/log -name "*.log.*" -mtime +7 -delete
find /tmp -type f -atime +3 -delete

# 查找大文件
find / -type f -size +500M -exec ls -lh {} \; 2>/dev/null
find / -type f -size +100M -exec du -sh {} \; 2>/dev/null | sort -rh | head -20
```

### 内存不足/OOM
```bash
# 查看 OOM 事件
dmesg | grep -i "out of memory"
grep -i "oom" /var/log/messages

# 临时释放缓存
sync && echo 3 > /proc/sys/vm/drop_caches

# 查找内存泄漏
valgrind --leak-check=full ./app
```

### 网络不通
```bash
# 逐步排查
ping <网关IP>                   # 1. 网关
ping <DNS服务器>                # 2. DNS
curl -v http://example.com      # 3. HTTP
traceroute <目标IP>             # 4. 路由

# 防火墙检查
iptables -L -n --line-numbers
firewall-cmd --list-all
```

### 服务无法启动
```bash
# 查看错误
systemctl status <service>
journalctl -u <service> -n 100 --no-pager
journalctl -u <service> --since "1 hour ago"

# 权限检查
namei -l /path/to/file
ls -la /var/log/<service>/
```

## 3. Shell 脚本实战

### 日志清理脚本
```bash
#!/bin/bash
# 清理30天前的日志，保留最近7天
find /var/log -name "*.log.*" -mtime +30 -delete
find /data/logs -name "*.log" -mtime +7 -exec gzip {} \;
find /data/logs -name "*.gz" -mtime +30 -delete

# 记录清理结果
echo "$(date): Log cleanup completed" >> /var/log/cleanup.log
```

### 服务健康检查脚本
```bash
#!/bin/bash
SERVICES=("nginx" "docker" "mysqld" "redis")
for svc in "${SERVICES[@]}"; do
    if ! systemctl is-active --quiet "$svc"; then
        echo "[ALERT] $svc is not running!"
        systemctl restart "$svc"
        echo "$(date): Restarted $svc" >> /var/log/health-check.log
    fi
done
```

### 磁盘空间告警脚本
```bash
#!/bin/bash
THRESHOLD=80
df -h | grep -E '^/dev/' | while read line; do
    usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    if [ "$usage" -gt "$THRESHOLD" ]; then
        echo "[WARNING] $mount usage: ${usage}%"
        # 发送告警（钉钉/邮件）
    fi
done
```

## 4. 系统加固清单

### SSH 加固
```bash
# /etc/ssh/sshd_config
Port 22222                      # 修改默认端口
PermitRootLogin no              # 禁止root登录
PasswordAuthentication no       # 禁止密码认证
MaxAuthTries 3                  # 最大尝试次数
ClientAliveInterval 300         # 空闲超时
AllowUsers opsuser              # 白名单用户
```

### 内核安全参数
```bash
# /etc/sysctl.d/99-security.conf
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
kernel.randomize_va_space = 2
```

## 5. 定时任务最佳实践

```bash
# Crontab 格式: 分 时 日 月 周 命令

# 每天凌晨2点备份
0 2 * * * /scripts/backup.sh >> /var/log/backup.log 2>&1

# 每5分钟检查服务
*/5 * * * * /scripts/health-check.sh

# 每周一早上9点发送周报
0 9 * * 1 /scripts/weekly-report.sh

# 每月1号清理日志
0 0 1 * * /scripts/cleanup-logs.sh

# 重要：使用绝对路径，重定向输出，避免邮件
```
