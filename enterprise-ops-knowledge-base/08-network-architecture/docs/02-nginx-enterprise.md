# Nginx 企业级部署

## 1. Nginx 架构概述

Nginx 是目前企业中最广泛使用的 Web 服务器和反向代理。其事件驱动的异步架构使其在高并发场景下表现优异，单机可轻松处理数万并发连接。

### 1.1 Nginx 进程模型

```
                    ┌─────────────────┐
                    │  Master Process  │  ← 管理进程（root）
                    │   (nginx master) │
                    └────────┬────────┘
                             │ fork
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────┴───┐  ┌──────┴─────┐  ┌────┴────────┐
     │  Worker 1   │  │  Worker 2   │  │  Worker 3   │  ← 工作进程
     │ (epoll 循环) │  │ (epoll 循环) │  │ (epoll 循环) │
     └─────────────┘  └────────────┘  └─────────────┘
```

Master 进程负责：
- 读取配置文件
- 管理 Worker 进程（启动、停止、重载）
- 绑定特权端口（80/443）

Worker 进程负责：
- 处理客户端请求
- 每个 Worker 是独立进程，互不影响
- Worker 数量通常设置为 CPU 核心数

### 1.2 Nginx 版本选择

| 版本 | 特点 | 适用场景 |
|------|------|----------|
| Mainline (1.25.x) | 最新特性、Bug 修复 | 测试环境、需要新特性 |
| Stable (1.24.x) | 经过充分测试 | 生产环境推荐 |
| OpenResty | Lua 扩展支持 | 复杂业务逻辑、WAF |

**生产环境建议**：使用 Stable 版本，除非有明确需要 Mainline 特性的场景。

## 2. 编译安装与优化

### 2.1 编译参数

生产环境建议从源码编译，精确控制模块：

```bash
#!/bin/bash
# Nginx 编译安装脚本

NGINX_VERSION="1.24.0"
INSTALL_DIR="/usr/local/nginx"

# 安装依赖
yum install -y gcc gcc-c++ make pcre-devel zlib-devel \
  openssl-devel gd-devel GeoIP-devel

# 下载源码
wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
tar xzf nginx-${NGINX_VERSION}.tar.gz
cd nginx-${NGINX_VERSION}

# 编译配置
./configure \
  --prefix=${INSTALL_DIR} \
  --user=nginx \
  --group=nginx \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_realip_module \
  --with-http_stub_status_module \
  --with-http_gzip_static_module \
  --with-http_sub_module \
  --with-http_addition_module \
  --with-http_image_filter_module \
  --with-http_geoip_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-pcre \
  --with-pcre-jit \
  --with-threads \
  --with-file-aio \
  --with-http_secure_link_module \
  --without-http_autoindex_module \
  --without-http_ssi_module

make -j$(nproc) && make install
```

### 2.2 系统优化

```bash
# /etc/sysctl.conf
# 文件描述符限制
fs.file-max = 655350

# 网络优化
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.ip_local_port_range = 1024 65535

# 连接追踪
net.netfilter.nf_conntrack_max = 1048576

# 应用
sysctl -p
```

```bash
# /etc/security/limits.conf
*  soft  nofile  655350
*  hard  nofile  655350
*  soft  nproc   655350
*  hard  nproc   655350
```

## 3. 核心配置详解

### 3.1 全局配置

```nginx
# /usr/local/nginx/conf/nginx.conf

# Worker 进程数，建议等于 CPU 核心数
worker_processes auto;

# Worker 进程绑定 CPU（NUMA 优化）
worker_cpu_affinity auto;

# 每个 Worker 最大打开文件数
worker_rlimit_nofile 65535;

# 事件模块
events {
    # 使用 epoll（Linux 高性能事件模型）
    use epoll;
    
    # 每个 Worker 最大并发连接数
    worker_connections 65535;
    
    # 一个 Worker 一次可接受多个连接
    multi_accept on;
}

# HTTP 模块
http {
    # 基础配置
    include       mime.types;
    default_type  application/octet-stream;
    
    # 字符集
    charset utf-8;
    
    # 日志格式（JSON 格式便于 ELK 采集）
    log_format json_log escape=json
        '{"time":"$time_iso8601",'
        '"remote_addr":"$remote_addr",'
        '"remote_user":"$remote_user",'
        '"request":"$request",'
        '"status":$status,'
        '"body_bytes_sent":$body_bytes_sent,'
        '"request_time":$request_time,'
        '"upstream_response_time":"$upstream_response_time",'
        '"http_referrer":"$http_referer",'
        '"http_user_agent":"$http_user_agent",'
        '"http_x_forwarded_for":"$http_x_forwarded_for",'
        '"request_id":"$request_id"}';
    
    access_log /var/log/nginx/access.log json_log buffer=32k flush=5s;
    error_log  /var/log/nginx/error.log warn;
    
    # 高性能配置
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    
    # 超时配置
    keepalive_timeout  65;
    keepalive_requests 1000;
    client_body_timeout 10;
    client_header_timeout 10;
    send_timeout 10;
    
    # 缓冲区配置
    client_body_buffer_size 16k;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 32k;
    client_max_body_size 100m;
    
    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 4;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml application/xml+rss text/javascript
               image/svg+xml;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # 隐藏版本号
    server_tokens off;
    
    # 包含子配置
    include /usr/local/nginx/conf/conf.d/*.conf;
}
```

### 3.2 Upstream 负载均衡

```nginx
# /usr/local/nginx/conf/conf.d/upstream.conf

# 应用服务器集群
upstream app_backend {
    # 负载均衡算法：least_conn（最少连接）
    least_conn;
    
    # 服务器列表
    server 10.1.1.10:8080 weight=5 max_fails=3 fail_timeout=30s;
    server 10.1.1.11:8080 weight=5 max_fails=3 fail_timeout=30s;
    server 10.1.1.12:8080 weight=3 max_fails=3 fail_timeout=30s;
    
    # 备用服务器（其他全部不可用时启用）
    server 10.1.1.20:8080 backup;
    
    # 保持长连接（减少后端连接开销）
    keepalive 64;
    keepalive_requests 1000;
    keepalive_timeout 60s;
}

# 静态资源服务器
upstream static_backend {
    ip_hash;
    server 10.1.2.10:80;
    server 10.1.2.11:80;
    keepalive 32;
}

# 数据库读写分离代理（Stream 模块）
upstream mysql_read {
    least_conn;
    server 10.1.3.11:3306 weight=5;
    server 10.1.3.12:3306 weight=3;
}
```

### 3.3 SSL/TLS 配置

```nginx
# /usr/local/nginx/conf/conf.d/ssl.conf

# SSL 会话缓存
ssl_session_cache shared:SSL:50m;
ssl_session_timeout 1d;
ssl_session_tickets on;
ssl_session_ticket_key current;
ssl_session_ticket_key previous;

# 协议版本（禁用 TLS 1.0/1.1）
ssl_protocols TLSv1.2 TLSv1.3;

# 加密套件（TLS 1.2）
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_prefer_server_ciphers on;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/nginx/ssl/chain.pem;
resolver 8.8.8.8 1.1.1.1 valid=300s;
resolver_timeout 5s;

# HSTS（强制 HTTPS）
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```

## 4. 高级功能

### 4.1 动态上游管理

通过 Lua 模块实现动态上游管理：

```nginx
# 基于 OpenResty 的动态上游
location /api/ {
    set $target "";
    access_by_lua_block {
        -- 从 Redis 获取后端地址
        local redis = require "resty.redis"
        local red = redis:new()
        red:connect("127.0.0.1", 6379)
        local target = red:get("api_backend")
        ngx.var.target = target
    }
    proxy_pass http://$target;
}
```

### 4.2 请求限流

```nginx
# 限流配置
http {
    # 请求速率限制（每秒 10 个请求）
    limit_req_zone $binary_remote_addr zone=req_limit:10m rate=10r/s;
    
    # 并发连接限制
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
    
    server {
        location /api/ {
            # 突发 20 个请求，超过的排队处理
            limit_req zone=req_limit burst=20 nodelay;
            
            # 每个 IP 最大 50 个并发连接
            limit_conn conn_limit 50;
            
            # 限流返回状态码
            limit_req_status 429;
            limit_conn_status 429;
        }
    }
}
```

### 4.3 缓存配置

```nginx
# 代理缓存
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=app_cache:100m
                 max_size=10g inactive=60m use_temp_path=off;

server {
    location /static/ {
        proxy_cache app_cache;
        proxy_cache_valid 200 302 10m;
        proxy_cache_valid 404 1m;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_lock on;
        proxy_cache_lock_timeout 5s;
        
        add_header X-Cache-Status $upstream_cache_status;
        
        proxy_pass http://static_backend;
    }
}
```

## 5. 监控与运维

### 5.1 状态监控

```nginx
# 启用 stub_status
location /nginx_status {
    stub_status;
    allow 127.0.0.1;
    allow 10.0.0.0/8;
    deny all;
}
```

输出示例：
```
Active connections: 291
server accepts handled requests
 16630948 16630948 31070465
Reading: 6 Writing: 179 Waiting: 106
```

### 5.2 日志分析

```bash
# 实时查看访问日志
tail -f /var/log/nginx/access.log | jq .

# 统计状态码分布
cat /var/log/nginx/access.log | jq -r '.status' | sort | uniq -c | sort -rn

# 统计慢请求（>2s）
cat /var/log/nginx/access.log | jq 'select(.request_time > 2)' | wc -l

# 统计 Top 10 访问 IP
cat /var/log/nginx/access.log | jq -r '.remote_addr' | sort | uniq -c | sort -rn | head -10
```

### 5.3 平滑升级

```bash
#!/bin/bash
# Nginx 平滑升级脚本

# 1. 编译新版本（不要 make install）
cd /tmp/nginx-1.25.0
./configure --prefix=/usr/local/nginx ... # 同原编译参数
make -j$(nproc)

# 2. 备份原二进制
cp /usr/local/nginx/sbin/nginx /usr/local/nginx/sbin/nginx.old

# 3. 替换二进制
cp /tmp/nginx-1.25.0/objs/nginx /usr/local/nginx/sbin/nginx

# 4. 发送 USR2 信号（启动新 Master）
kill -USR2 $(cat /var/run/nginx.pid)

# 5. 发送 WINCH 信号（优雅停止旧 Worker）
sleep 10
kill -WINCH $(cat /var/run/nginx.pid.oldbin)

# 6. 确认无误后，发送 QUIT 信号停止旧 Master
kill -QUIT $(cat /var/run/nginx.pid.oldbin)
```

## 6. 故障排查

### 6.1 常见问题

**502 Bad Gateway**：
- 后端服务不可用
- upstream 超时配置过短
- 后端处理能力不足

**504 Gateway Timeout**：
- proxy_read_timeout 过短
- 后端处理时间过长
- 网络延迟过高

**413 Request Entity Too Large**：
- client_max_body_size 设置过小
- 上传文件超过限制

**Worker 进程频繁重启**：
- 内存不足（OOM）
- 配置文件语法错误
- 共享内存区域损坏

### 6.2 调试技巧

```bash
# 检查配置语法
nginx -t

# 查看编译参数
nginx -V

# 跟踪 Worker 进程
strace -p <worker_pid> -e trace=network

# 分析连接状态
ss -s | grep estab
ss -tnp | grep nginx
```
