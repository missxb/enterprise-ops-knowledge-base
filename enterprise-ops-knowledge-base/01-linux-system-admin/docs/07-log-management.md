# 日志管理

## 概述

日志是系统运维的眼睛。本文涵盖 journald、rsyslog、logrotate 配置及集中式日志架构方案。

## 1. journald 日志管理

### 1.1 配置文件

```ini
# /etc/systemd/journald.conf
[Journal]
# 存储模式
Storage=persistent          # 持久化存储到 /var/log/journal/
# Storage=volatile          # 仅存储在内存
# Storage=auto              # 自动选择

# 磁盘空间限制
SystemMaxUse=2G             # 最大使用空间
SystemKeepFree=1G           # 保留的可用空间
SystemMaxFileSize=50M       # 单个日志文件最大大小

# 运行时限制（内存文件系统）
RuntimeMaxUse=500M
RuntimeKeepFree=100M

# 保留时间
MaxRetentionSec=3month      # 最长保留时间
MaxFileSec=1week            # 单文件最长时间

# 压缩
Compress=yes

# 转发
ForwardToSyslog=yes         # 转发到 rsyslog
ForwardToKMsg=no            # 转发到内核日志
ForwardToConsole=no         # 转发到控制台
ForwardToWall=no            # 转发到墙消息

# 速率限制
RateLimitIntervalSec=30s    # 速率限制时间窗口
RateLimitBurst=10000        # 时间窗口内最大条目

# 日志行格式
Format=short                # short/short-iso/short-precise/short-monotonic/verbose/json
```

### 1.2 日志查询

```bash
# 基本查询
journalctl                          # 所有日志
journalctl -u nginx.service         # 指定服务
journalctl -u nginx -u mysql        # 多个服务

# 时间过滤
journalctl --since "2024-01-01 00:00:00"
journalctl --until "2024-01-02 00:00:00"
journalctl --since "1 hour ago"
journalctl --since today

# 优先级过滤
journalctl -p emerg                 # 紧急
journalctl -p err                   # 错误及以上
journalctl -p warning               # 警告及以上

# 内核日志
journalctl -k                       # 当前启动
journalctl -k -b -1                 # 上次启动

# 输出格式
journalctl -o json-pretty           # JSON 格式
journalctl -o verbose               # 详细格式
journalctl -o cat                   # 仅消息内容

# 实时跟踪
journalctl -f                       # 所有
journalctl -u nginx -f              # 指定服务

# 磁盘管理
journalctl --disk-usage             # 查看占用
journalctl --vacuum-time=7d         # 清理 7 天前
journalctl --vacuum-size=500M       # 限制到 500M
```

## 2. rsyslog 配置

### 2.1 基础配置

```bash
# /etc/rsyslog.conf

# 全局配置
$WorkDirectory /var/lib/rsyslog
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
$IncludeConfig /etc/rsyslog.d/*.conf

# 日志格式模板
$template CustomFormat,"%timegenerated% %HOSTNAME% %syslogtag%%msg%\n"
$template RemoteFormat,"%timegenerated% %HOSTNAME% %programname% %msg%\n"

# 设施.优先级
# 设施：auth,authpriv,cron,daemon,kern,lpr,mail,news,syslog,user,uucp,local0-7
# 优先级：emerg,alert,crit,err,warning,notice,info,debug

# 默认规则
*.info;mail.none;authpriv.none;cron.none    /var/log/messages
authpriv.*                                   /var/log/secure
mail.*                                       /var/log/maillog
cron.*                                       /var/log/cron
kern.*                                       /var/log/kernlog
*.emerg                                      :omusrmsg:*
```

### 2.2 应用日志分离

```bash
# /etc/rsyslog.d/app.conf

# Nginx 日志（使用 local0 设施）
local0.*    /var/log/nginx/access.log
local0.err  /var/log/nginx/error.log

# 自定义应用日志
local1.*    /var/log/myapp/app.log
local1.err  /var/log/myapp/error.log

# 按程序名分类
if $programname == 'docker' then /var/log/docker.log
if $programname == 'kubelet' then /var/log/kubelet.log

# 条件过滤
if $msg contains "error" then /var/log/errors.log
if $msg contains "timeout" then /var/log/timeouts.log
```

### 2.3 远程日志传输

```bash
# 发送端配置（TCP）
# /etc/rsyslog.d/forward.conf
*.* @@logserver.example.com:514    # TCP 双 @
*.* @logserver.example.com:514     # UDP 单 @

# 接收端配置
# /etc/rsyslog.d/receive.conf
$ModLoad imtcp
$InputTCPServerRun 514

# 按来源 IP 分目录
if $fromhost-ip == '192.168.1.10' then /var/log/remote/web-01/
if $fromhost-ip == '192.168.1.11' then /var/log/remote/web-02/
```

## 3. logrotate 日志轮转

### 3.1 全局配置

```bash
# /etc/logrotate.conf
weekly                  # 每周轮转
rotate 4                # 保留 4 个
create                  # 创建新文件
dateext                 # 使用日期后缀
compress                # 压缩旧日志
delaycompress           # 延迟一期压缩
missingok               # 文件缺失不报错
notifempty              # 空文件不轮转
include /etc/logrotate.d/
```

### 3.2 应用日志轮转

```bash
# /etc/logrotate.d/nginx
/var/log/nginx/*.log {
    daily               # 每天轮转
    rotate 30           # 保留 30 个
    missingok
    notifempty
    compress
    delaycompress
    dateext
    dateformat -%Y%m%d
    sharedscripts       # 所有日志轮转后执行一次脚本
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid)
    endscript
}

# /etc/logrotate.d/myapp
/var/log/myapp/*.log {
    daily
    rotate 60
    missingok
    notifempty
    compress
    delaycompress
    maxsize 500M        # 超过 500M 立即轮转
    minsize 10M         # 小于 10M 不轮转
    create 0644 myapp myapp
    postrotate
        systemctl reload myapp || true
    endscript
}

# /etc/logrotate.d/syslog
/var/log/messages
/var/log/secure
/var/log/maillog
/var/log/cron
{
    daily
    rotate 30
    missingok
    notifempty
    compress
    sharedscripts
    postrotate
        systemctl reload rsyslog || true
    endscript
}
```

### 3.3 手动操作

```bash
# 测试轮转（不实际执行）
logrotate -d /etc/logrotate.d/nginx

# 强制执行轮转
logrotate -f /etc/logrotate.d/nginx

# 查看轮转状态
cat /var/lib/logrotate/logrotate.status
```

## 4. 集中式日志架构

### 4.1 ELK Stack 方案

```yaml
# Filebeat 配置示例
# /etc/filebeat/filebeat.yml
filebeat.inputs:
  - type: log
    paths:
      - /var/log/nginx/access.log
    fields:
      service: nginx
      env: production
    json.keys_under_root: true

  - type: log
    paths:
      - /var/log/myapp/*.log
    fields:
      service: myapp

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "logs-%{+yyyy.MM.dd}"

setup.kibana:
  host: "kibana:5601"
```

### 4.2 Loki + Promtail 方案

```yaml
# Promtail 配置
# /etc/promtail/config.yml
server:
  http_listen_port: 9080

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets: [localhost]
        labels:
          job: syslog
          host: ${HOSTNAME}
          __path__: /var/log/messages

  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          __path__: /var/log/nginx/*.log
    pipeline_stages:
      - regex:
          expression: '^(?P<remote_addr>[\w\.]+) .*'
      - labels:
          remote_addr:
```

### 4.3 Graylog 方案

```bash
# rsyslog 转发到 Graylog（GELF 格式）
# /etc/rsyslog.d/graylog.conf
$ModLoad omudp
$template GELF,"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% %msg%\n"
*.* @graylog-server:12201;GELF
```

## 5. 日志分析实践

### 5.1 常用分析命令

```bash
# 实时统计错误率
tail -f /var/log/messages | awk '/error/{count++; print count, $0}'

# 按小时统计日志量
awk '{print $1, $2}' /var/log/nginx/access.log | cut -d: -f1,2 | sort | uniq -c | sort -rn

# 统计 HTTP 状态码
awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn

# 查找异常 IP
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20

# 慢请求分析
awk '$NF > 1.0 {print $0}' /var/log/nginx/access.log
```

### 5.2 日志告警

```bash
#!/bin/bash
# 日志异常检测脚本
LOG_FILE="/var/log/messages"
ALERT_THRESHOLD=100
ALERT_WINDOW=300  # 5 分钟

check_errors() {
    local count=$(journalctl --since "5 min ago" -p err --no-pager | wc -l)
    if [ "$count" -gt "$ALERT_THRESHOLD" ]; then
        echo "告警：过去 5 分钟内发现 $count 条错误日志" | \
            mail -s "日志告警" ops@example.com
    fi
}

check_errors
```

## 6. 最佳实践

1. **分层存储**：热数据（7 天）用 SSD，温数据（30 天）用 HDD，冷数据归档对象存储
2. **结构化日志**：使用 JSON 格式便于解析和检索
3. **日志分级**：严格区分 DEBUG/INFO/WARN/ERROR/FATAL
4. **脱敏处理**：日志中不记录密码、Token、身份证号等敏感信息
5. **完整性校验**：关键日志使用 syslog-sign 或哈希校验防篡改
6. **合规保留**：根据等保要求保留至少 6 个月
