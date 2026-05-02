# systemd 服务管理

## 概述

systemd 是现代 Linux 系统的初始化系统和服务管理器。本文涵盖 Unit 文件编写、服务依赖管理、定时器配置及日志集成。

## 1. Unit 文件基础

### 1.1 Unit 文件路径优先级

| 优先级 | 路径 | 说明 |
|--------|------|------|
| 最高 | /etc/systemd/system/ | 管理员自定义（优先级最高） |
| 中 | /run/systemd/system/ | 运行时生成 |
| 最低 | /usr/lib/systemd/system/ | 软件包安装 |

```bash
# 查看 unit 文件路径
systemctl cat nginx.service

# 编辑 unit 文件（推荐方式）
systemctl edit nginx.service    # 创建 override
systemctl edit --full nginx.service    # 编辑完整文件

# 重新加载配置
systemctl daemon-reload
```

### 1.2 Service Unit 文件结构

```ini
# /etc/systemd/system/myapp.service
[Unit]
# 描述信息
Description=My Application Service
Documentation=https://docs.myapp.com

# 依赖关系
Requires=network.target
After=network.target mysql.service
Wants=redis.service

# 条件检查
ConditionPathExists=/opt/myapp/bin/myapp
ConditionMemory=1G

[Service]
# 服务类型
Type=simple

# 启动/停止命令
ExecStart=/opt/myapp/bin/myapp --config /opt/myapp/etc/config.yaml
ExecStartPre=/opt/myapp/bin/pre-start.sh
ExecStartPost=/opt/myapp/bin/post-start.sh
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=/opt/myapp/bin/stop.sh

# 工作目录
WorkingDirectory=/opt/myapp

# 运行用户
User=myapp
Group=myapp

# 环境变量
Environment=APP_ENV=production
EnvironmentFile=/opt/myapp/etc/env

# 重启策略
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=3

# 资源限制
LimitNOFILE=65535
LimitNPROC=65535
MemoryMax=2G
CPUQuota=80%

# 安全加固
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/myapp/data /var/log/myapp
PrivateTmp=true

# 超时设置
TimeoutStartSec=30
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
```

### 1.3 服务类型详解

| Type | 说明 | 适用场景 |
|------|------|---------|
| simple | 默认，ExecStart 即主进程 | 前台运行的服务 |
| forking | 主进程 fork 后退出 | 传统守护进程 |
| oneshot | 执行一次后退出 | 初始化任务 |
| notify | 服务就绪后通知 systemd | 支持 sd_notify 的服务 |
| idle | 等待其他任务完成后启动 | 控制台输出服务 |

```ini
# oneshot 示例（初始化任务）
[Service]
Type=oneshot
ExecStart=/usr/local/bin/init-db.sh
ExecStart=/usr/local/bin/seed-data.sh
RemainAfterExit=yes

# forking 示例（传统守护进程）
[Service]
Type=forking
PIDFile=/var/run/myapp.pid
ExecStart=/usr/local/bin/myapp --daemonize
```

## 2. 依赖管理

### 2.1 依赖指令

```ini
[Unit]
# 强依赖（目标不存在则本服务不启动）
Requires=mysql.service

# 弱依赖（目标不存在仍尝试启动）
Wants=redis.service

# 排斥依赖（不能同时运行）
Conflicts=iptables.service

# 顺序依赖（在目标之后启动）
After=network.target mysql.service

# 顺序依赖（在目标之前启动）
Before=nginx.service
```

### 2.2 Target 管理

```bash
# 查看所有 target
systemctl list-unit-files --type=target

# 查看 target 依赖
systemctl list-dependencies multi-user.target

# 切换 target
systemctl isolate multi-user.target

# 设置默认 target
systemctl set-default multi-user.target

# 创建自定义 target
# /etc/systemd/system/myapp.target
[Unit]
Description=My Application Stack
Requires=myapp.service mysql.service redis.service
After=mysql.service redis.service
```

### 2.3 Socket 激活

```ini
# /etc/systemd/system/myapp.socket
[Unit]
Description=My App Socket

[Socket]
ListenStream=8080
Accept=false

[Install]
WantedBy=sockets.target

# /etc/systemd/system/myapp.service
[Unit]
Requires=myapp.socket
After=myapp.socket

[Service]
Type=simple
ExecStart=/usr/local/bin/myapp
# systemd 传递 socket 文件描述符
```

```bash
# 启用 socket 激活
systemctl enable myapp.socket
systemctl start myapp.socket
```

## 3. 定时器（Timer）

### 3.1 定时器配置

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Daily Backup Timer

[Timer]
# 基于日历的定时（类 cron）
OnCalendar=*-*-* 02:00:00
# 精度（允许延迟）
AccuracySec=1min
# 持久化（错过时间后立即执行）
Persistent=true
# 随机延迟
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target

# /etc/systemd/system/backup.service
[Unit]
Description=Daily Backup Service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
User=backup
```

### 3.2 定时器语法

```bash
# OnCalendar 格式
# 星期 年-月-日 时:分:秒
OnCalendar=Mon..Fri *-*-* 09:00:00    # 工作日 9 点
OnCalendar=*-*-01 00:00:00            # 每月 1 号
OnCalendar=Mon *-*-* 00:00:00         # 每周一
OnCalendar=*-*-* 00/6:00:00           # 每 6 小时
OnCalendar=hourly                      # 每小时
OnCalendar=daily                       # 每天
OnCalendar=weekly                      # 每周

# 基于启动的定时
OnBootSec=5min         # 启动后 5 分钟
OnStartupSec=10min     # systemd 启动后 10 分钟
OnActiveSec=1h         # 激活后 1 小时
OnUnitActiveSec=30min  # 上次激活后 30 分钟
OnUnitInactiveSec=1h   # 上次停用后 1 小时
```

### 3.3 定时器管理

```bash
# 查看所有定时器
systemctl list-timers --all

# 启用/启动定时器
systemctl enable backup.timer
systemctl start backup.timer

# 手动触发
systemctl start backup.service

# 查看定时器日志
journalctl -u backup.timer
journalctl -u backup.service
```

## 4. 日志集成

### 4.1 journald 配置

```ini
# /etc/systemd/journald.conf
[Journal]
# 存储方式：persistent/volatile/auto
Storage=persistent

# 日志大小限制
SystemMaxUse=2G
SystemKeepFree=1G
SystemMaxFileSize=50M

# 单个用户日志限制
RuntimeMaxUse=500M

# 日志保留时间
MaxRetentionSec=3month

# 压缩
Compress=yes

# 转发到 syslog
ForwardToSyslog=yes
```

### 4.2 日志查询

```bash
# 查看服务日志
journalctl -u nginx.service

# 实时跟踪
journalctl -u nginx.service -f

# 按时间过滤
journalctl -u nginx.service --since "2024-01-01" --until "2024-01-02"
journalctl -u nginx.service --since "1 hour ago"

# 按优先级过滤
journalctl -u nginx.service -p err

# 查看内核日志
journalctl -k

# 磁盘使用统计
journalctl --disk-usage

# 清理旧日志
journalctl --vacuum-time=7d
journalctl --vacuum-size=500M
```

### 4.3 自定义日志格式

```ini
# 在 service 文件中配置日志
[Service]
# 标准输出/错误重定向到 journal
StandardOutput=journal
StandardError=journal

# 自定义日志标识
SyslogIdentifier=myapp

# 日志级别前缀
LogLevelPrefix=notice

# 重定向到文件
StandardOutput=append:/var/log/myapp/stdout.log
StandardError=append:/var/log/myapp/stderr.log
```

## 5. 高级特性

### 5.1 模板 Unit 文件

```ini
# /etc/systemd/system/myapp@.service
[Unit]
Description=My App Instance %i
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/myapp --instance %i --config /etc/myapp/%i.conf
User=myapp-%i

[Install]
WantedBy=multi-user.target
```

```bash
# 启动实例
systemctl start myapp@instance1.service
systemctl start myapp@instance2.service

# 启用实例
systemctl enable myapp@instance1.service
```

### 5.2 Drop-in 覆盖

```bash
# 创建 drop-in 目录
mkdir -p /etc/systemd/system/nginx.service.d/

# /etc/systemd/system/nginx.service.d/override.conf
[Service]
LimitNOFILE=131072
MemoryMax=1G

# 或使用命令
systemctl edit nginx.service
```

### 5.3 资源控制集成

```bash
# 动态修改资源限制
systemctl set-property myapp.service CPUQuota=50%
systemctl set-property myapp.service MemoryMax=1G

# 持久化（创建 drop-in）
systemctl edit myapp.service
# 添加：
# [Service]
# CPUQuota=50%
# MemoryMax=1G
```

## 6. 故障排查

### 6.1 常见问题

```bash
# 服务启动失败
systemctl status myapp.service
journalctl -u myapp.service -n 50

# 检查 unit 文件语法
systemd-analyze verify /etc/systemd/system/myapp.service

# 查看启动链
systemd-analyze critical-chain

# 查看启动时间
systemd-analyze blame

# 检查依赖关系
systemctl list-dependencies myapp.service
```

### 6.2 调试技巧

```bash
# 临时修改启动命令（调试模式）
systemctl edit myapp.service
# [Service]
# ExecStart=
# ExecStart=/usr/local/bin/myapp --debug

# 查看环境变量
systemctl show myapp.service -p Environment

# 查看所有属性
systemctl show myapp.service

# 进入 rescue 模式
systemctl rescue

# 进入 emergency 模式
systemctl emergency
```
