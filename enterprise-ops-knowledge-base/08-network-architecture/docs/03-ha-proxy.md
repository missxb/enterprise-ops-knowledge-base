# HAProxy 高可用

## 1. HAProxy 概述

HAProxy 是一款高性能的 TCP/HTTP 负载均衡器和代理服务器，广泛应用于高可用架构中。与 Nginx 不同，HAProxy 专注于负载均衡和代理功能，不直接处理静态文件，因此在纯负载均衡场景下性能更优。

### 1.1 HAProxy 版本特性

| 版本 | 特性 | 推荐场景 |
|------|------|----------|
| 2.8 LTS | 长期支持、稳定可靠 | 生产环境首选 |
| 2.9 | 新特性、性能改进 | 需要新功能时 |
| 3.0 | 最新架构改进 | 测试环境 |

### 1.2 与其他负载均衡对比

| 特性 | HAProxy | Nginx | LVS |
|------|---------|-------|-----|
| 工作模式 | L4/L7 | L7 | L4 |
| 健康检查 | 丰富 | 基础 | 无 |
| 会话保持 | 多种方式 | ip_hash/cookie | 无 |
| 统计页面 | 内置 | 需模块 | 无 |
| 配置热重载 | 支持 | 支持 | 不支持 |
| 性能 | 极高 | 高 | 最高 |

## 2. 安装与配置

### 2.1 安装

```bash
# CentOS/RHEL
yum install -y haproxy

# Ubuntu/Debian
apt install -y haproxy

# 源码编译（推荐生产环境）
wget https://www.haproxy.org/download/2.8/src/haproxy-2.8.0.tar.gz
tar xzf haproxy-2.8.0.tar.gz
cd haproxy-2.8.0
make -j$(nproc) TARGET=linux-glibc USE_OPENSSL=1 USE_ZLIB=1 USE_PCRE=1
make install PREFIX=/usr/local/haproxy
```

### 2.2 核心配置

```haproxy
# /etc/haproxy/haproxy.cfg

#---------------------------------------------------------------------
# 全局配置
#---------------------------------------------------------------------
global
    # 运行用户
    user haproxy
    group haproxy
    
    # 守护进程模式
    daemon
    
    # 最大连接数
    maxconn 100000
    
    # PID 文件
    pidfile /var/run/haproxy.pid
    
    # 统计 socket
    stats socket /var/run/haproxy.sock mode 660 level admin
    
    # 日志配置
    log /dev/log local0 info
    log /dev/log local1 warning
    
    # SSL 证书缓存
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    
    # 性能调优
    tune.ssl.default-dh-param 2048
    tune.bufsize 32768
    tune.maxrewrite 1024

#---------------------------------------------------------------------
# 默认配置
#---------------------------------------------------------------------
defaults
    mode http
    log global
    option httplog
    option dontlognull
    option log-health-checks
    option forwardfor
    option http-server-close
    
    # 超时配置
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    timeout http-request 10s
    timeout http-keep-alive 10s
    timeout queue 30s
    timeout tunnel 3600s
    
    # 重试配置
    retries 3
    option redispatch
    
    # 错误页面
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

#---------------------------------------------------------------------
# 统计页面
#---------------------------------------------------------------------
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
    stats auth admin:YourSecurePassword123!
    stats hide-version

#---------------------------------------------------------------------
# 前端配置
#---------------------------------------------------------------------
frontend http-in
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1
    
    # HTTPS 重定向
    http-request redirect scheme https unless { ssl_fc }
    
    # HSTS
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains"
    
    # ACL 路由规则
    acl is_api path_beg /api/
    acl is_static path_end .css .js .png .jpg .gif .ico
    acl is_websocket hdr(Upgrade) -i websocket
    
    # 路由到不同后端
    use_backend api_servers if is_api
    use_backend static_servers if is_static
    use_backend ws_servers if is_websocket
    default_backend web_servers

#---------------------------------------------------------------------
# 后端配置
#---------------------------------------------------------------------
backend web_servers
    balance roundrobin
    option httpchk GET /health HTTP/1.1\r\nHost:\ localhost
    
    # Cookie 会话保持
    cookie SERVERID insert indirect nocache
    
    server web1 10.1.1.10:8080 check cookie web1 weight 100 maxconn 3000
    server web2 10.1.1.11:8080 check cookie web2 weight 100 maxconn 3000
    server web3 10.1.1.12:8080 check cookie web3 weight 50 maxconn 2000

backend api_servers
    balance leastconn
    option httpchk GET /api/health HTTP/1.1\r\nHost:\ localhost
    
    # 慢启动
    default-server slowstart 60s
    
    server api1 10.1.2.10:8080 check inter 3s fall 3 rise 2 maxconn 5000
    server api2 10.1.2.11:8080 check inter 3s fall 3 rise 2 maxconn 5000
    server api3 10.1.2.12:8080 check inter 3s fall 3 rise 2 maxconn 5000

backend static_servers
    balance uri
    option httpchk GET /health HTTP/1.1\r\nHost:\ localhost
    
    server static1 10.1.3.10:80 check
    server static2 10.1.3.11:80 check

backend ws_servers
    balance source
    option httpchk GET /ws/health HTTP/1.1\r\nHost:\ localhost
    
    # WebSocket 长连接超时
    timeout tunnel 3600s
    
    server ws1 10.1.4.10:8080 check
    server ws2 10.1.4.11:8080 check

#---------------------------------------------------------------------
# TCP 模式（数据库代理）
#---------------------------------------------------------------------
frontend mysql-in
    bind *:3306
    mode tcp
    option tcplog
    default_backend mysql_servers

backend mysql_servers
    mode tcp
    option mysql-check user haproxy
    balance roundrobin
    server mysql-slave1 10.1.5.11:3306 check
    server mysql-slave2 10.1.5.12:3306 check
```

## 3. 高级功能

### 3.1 健康检查

```haproxy
# HTTP 健康检查
option httpchk GET /health HTTP/1.1\r\nHost:\ api.example.com
http-check expect status 200

# 自定义检查间隔
server app1 10.1.1.10:8080 check inter 5s fall 3 rise 2

# TCP 检查
option tcp-check
tcp-check connect
tcp-check send PING\r\n
tcp-check expect string +PONG

# Agent 检查（程序自定义健康状态）
agent-check agent-inter 5s agent-port 9999
```

### 3.2 限流与连接控制

```haproxy
# 速率限制
stick-table type ip size 100k expire 30s store http_req_rate(10s)
http-request track-sc0 src
http-request deny deny_status 429 if { sc_http_req_rate(0) gt 100 }

# 连接数限制
stick-table type ip size 100k expire 30s store conn_cur
http-request track-sc1 src
http-request deny deny_status 429 if { sc_conn_cur(1) gt 50 }

# 慢速攻击防护
stick-table type ip size 100k expire 30s store conn_rate(10s)
http-request track-sc2 src
http-request deny if { sc_conn_rate(2) gt 20 }
```

### 3.3 ACL 高级路由

```haproxy
# 基于域名的路由
acl is_blog hdr(host) -i blog.example.com
acl is_api hdr(host) -i api.example.com

# 基于路径的路由
acl is_v2_api path_beg /api/v2/
acl is_v1_api path_beg /api/v1/

# 基于 User-Agent 的路由
acl is_bot hdr_sub(User-Agent) -i bot crawler spider

# 基于地理位置的路由
acl is_china src -f /etc/haproxy/geo/china.txt

# 组合条件
use_backend api_v2_servers if is_api is_v2_api
use_backend api_v1_servers if is_api is_v1_api
http-request deny if is_bot
```

## 4. 高可用方案

### 4.1 Keepalived + HAProxy

```bash
# /etc/keepalived/keepalived.conf (主节点)
vrrp_script chk_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight -20
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass YourPassword123!
    }
    
    virtual_ipaddress {
        10.1.1.100/24
    }
    
    track_script {
        chk_haproxy
    }
    
    notify_master "/etc/keepalived/notify.sh master"
    notify_backup "/etc/keepalived/notify.sh backup"
    notify_fault "/etc/keepalived/notify.sh fault"
}
```

### 4.2 多活架构

```
           ┌──────────────────┐
           │    DNS GLB        │
           └────────┬─────────┘
        ┌───────────┼───────────┐
 ┌──────┴──────┐    │    ┌──────┴──────┐
 │ HAProxy VIP  │    │    │ HAProxy VIP  │
 │  机房 A      │    │    │  机房 B      │
 └──────┬──────┘    │    └──────┬──────┘
   ┌────┼────┐      │    ┌────┼────┐
   │    │    │      │    │    │    │
  App  App  App     │   App  App  App
```

## 5. 监控与运维

### 5.1 Prometheus 指标导出

```bash
# 安装 haproxy_exporter
wget https://github.com/prometheus/haproxy_exporter/releases/download/v0.14.0/haproxy_exporter-0.14.0.linux-amd64.tar.gz
tar xzf haproxy_exporter-0.14.0.linux-amd64.tar.gz
./haproxy_exporter --haproxy.scrape-uri=unix:/var/run/haproxy.sock
```

### 5.2 关键监控指标

- **连接数**：current sessions, max sessions
- **请求速率**：requests per second
- **后端状态**：active servers, backup servers
- **健康检查**：check failures, check duration
- **错误率**：4xx/5xx 错误比例

### 5.3 日志分析

```bash
# HAProxy 日志格式解析
# Feb  3 12:00:00 localhost haproxy[1234]: 10.0.0.1:54321 [03/Feb/2024:12:00:00.000] http-in web_servers/web1 0/0/1/2/3 200 1234 - - ---- 1/1/0/1/0 0/0 "GET / HTTP/1.1"

# 统计后端响应时间
awk '{print $7}' /var/log/haproxy.log | awk -F/ '{print $4}' | sort -n | tail

# 统计错误请求
grep -E '" (4|5)[0-9]{2} ' /var/log/haproxy.log | wc -l
```

## 6. 故障排查

### 6.1 常见问题

**后端服务器标记为 DOWN**：
- 检查健康检查配置
- 确认后端服务是否正常
- 检查网络连通性

**连接超时**：
- 调整 timeout 配置
- 检查后端处理能力
- 排查网络延迟

**内存占用高**：
- 调整 maxconn
- 检查 stick-table 大小
- 优化缓冲区配置

### 6.2 调试命令

```bash
# 查看统计信息
echo "show stat" | socat stdio /var/run/haproxy.sock

# 查看错误
echo "show errors" | socat stdio /var/run/haproxy.sock

# 查看会话
echo "show sess" | socat stdio /var/run/haproxy.sock

# 禁用/启用后端服务器
echo "disable server web_servers/web1" | socat stdio /var/run/haproxy.sock
echo "enable server web_servers/web1" | socat stdio /var/run/haproxy.sock
```
