# Nginx/OpenResty网关项目完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. Nginx高性能配置](#2-nginx高性能配置)
- [3. 反向代理与负载均衡](#3-反向代理与负载均衡)
- [4. SSL/TLS配置](#4-ssltls配置)
- [5. WAF配置](#5-waf配置)
- [6. 限流与熔断](#6-限流与熔断)
- [7. 灰度发布](#7-灰度发布)
- [8. OpenResty动态路由](#8-openresty动态路由)
- [9. 监控与日志分析](#9-监控与日志分析)
- [10. 最佳实践与故障排查](#10-最佳实践与故障排查)

---

## 1. 项目背景与架构设计

### 1.1 Nginx网关架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Nginx/OpenResty 网关                      │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    Nginx Master                       │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────────┐  │  │
│  │  │Worker 1 │ │Worker 2 │ │Worker 3 │ │Worker N   │  │  │
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └─────┬─────┘  │  │
│  └───────┼───────────┼───────────┼─────────────┼────────┘  │
│          │           │           │             │            │
│  ┌───────┴───────────┴───────────┴─────────────┴────────┐  │
│  │                   处理流程                             │  │
│  │  SSL终止 → WAF → 限流 → 灰度路由 → 负载均衡 → 代理   │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                  │
│  ┌───────────────────────┼──────────────────────────────┐  │
│  │              后端服务池                               │  │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────────┐ │  │
│  │  │App-01  │ │App-02  │ │App-03  │ │微服务集群    │ │  │
│  │  └────────┘ └────────┘ └────────┘ └──────────────┘ │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Nginx高性能配置

### 2.1 完整nginx.conf

```nginx
# /etc/nginx/nginx.conf - 生产环境高性能配置

# 工作进程数（等于CPU核心数，或设为auto）
worker_processes auto;
worker_cpu_affinity auto;

# 每个worker最大打开文件数
worker_rlimit_nofile 655350;

# 错误日志
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    # 每个worker最大连接数
    worker_connections 65535;
    
    # 使用epoll（Linux高性能IO模型）
    use epoll;
    
    # 一次accept多个连接
    multi_accept on;
}

http {
    # ===== 基础配置 =====
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # 字符集
    charset utf-8;
    
    # 高效文件传输
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    
    # 超时配置
    keepalive_timeout 65;
    keepalive_requests 1000;
    client_body_timeout 15;
    client_header_timeout 15;
    send_timeout 15;
    
    # 请求体大小
    client_max_body_size 50m;
    client_body_buffer_size 128k;
    
    # 关闭server_tokens（安全）
    server_tokens off;
    
    # ===== 日志配置 =====
    log_format json_combined escape=json
        '{'
            '"time_iso8601":"$time_iso8601",'
            '"remote_addr":"$remote_addr",'
            '"remote_user":"$remote_user",'
            '"request":"$request",'
            '"status":$status,'
            '"body_bytes_sent":$body_bytes_sent,'
            '"request_time":$request_time,'
            '"upstream_response_time":"$upstream_response_time",'
            '"http_referer":"$http_referer",'
            '"http_user_agent":"$http_user_agent",'
            '"http_x_forwarded_for":"$http_x_forwarded_for",'
            '"upstream_addr":"$upstream_addr",'
            '"request_id":"$request_id"'
        '}';
    
    access_log /var/log/nginx/access.log json_combined buffer=64k flush=5s;
    
    # ===== 压缩配置 =====
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 4;
    gzip_min_length 1000;
    gzip_types
        text/plain
        text/css
        text/javascript
        application/json
        application/javascript
        application/xml
        application/xml+rss
        application/vnd.ms-fontobject
        font/opentype
        image/svg+xml;
    
    # ===== 安全头 =====
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # ===== 连接池配置（upstream）=====
    # 在server块中定义
    
    # ===== 包含其他配置 =====
    include /etc/nginx/conf.d/*.conf;
}
```

### 2.2 Worker优化

```nginx
# 根据CPU核心数设置worker_processes
# 查看CPU核心数: nproc
# 一般设置为CPU核心数，或直接用auto
worker_processes auto;

# 绑定worker到特定CPU核心（减少上下文切换）
worker_cpu_affinity auto;

# 调整nice优先级
worker_priority -10;

# 单个worker最大连接数
# 理论最大并发 = worker_processes × worker_connections
worker_connections 65535;
```

---

## 3. 反向代理与负载均衡

### 3.1 负载均衡配置

```nginx
# /etc/nginx/conf.d/upstream.conf

# ===== 后端服务池 =====
upstream app_backend {
    # 负载均衡算法
    # round-robin    轮询（默认）
    # least_conn     最少连接
    # ip_hash        IP哈希（会话保持）
    # hash $request_uri  URL哈希
    
    least_conn;
    
    # 后端服务器
    server 10.10.2.11:8080 weight=5 max_fails=3 fail_timeout=30s;
    server 10.10.2.12:8080 weight=5 max_fails=3 fail_timeout=30s;
    server 10.10.2.13:8080 weight=3 max_fails=3 fail_timeout=30s;
    
    # 备用服务器（所有主服务器故障时启用）
    server 10.10.2.14:8080 backup;
    
    # 长连接池
    keepalive 32;
    keepalive_requests 1000;
    keepalive_timeout 60s;
}

# ===== 微服务路由 =====
upstream user_service {
    least_conn;
    server 10.10.2.21:8081;
    server 10.10.2.22:8081;
    keepalive 16;
}

upstream order_service {
    least_conn;
    server 10.10.2.31:8082;
    server 10.10.2.32:8082;
    keepalive 16;
}

upstream product_service {
    least_conn;
    server 10.10.2.41:8083;
    server 10.10.2.42:8083;
    keepalive 16;
}

# ===== Server配置 =====
server {
    listen 80;
    server_name api.example.com;
    
    # 强制跳转HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    # SSL配置
    ssl_certificate /etc/nginx/ssl/api.example.com.crt;
    ssl_certificate_key /etc/nginx/ssl/api.example.com.key;
    
    # 通用代理头
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Request-ID $request_id;
    
    # 代理超时
    proxy_connect_timeout 10s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    
    # 代理缓冲
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 16k;
    proxy_busy_buffers_size 32k;
    
    # ===== 路由规则 =====
    
    # 用户服务
    location /api/users/ {
        proxy_pass http://user_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
    
    # 订单服务
    location /api/orders/ {
        proxy_pass http://order_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
    
    # 商品服务
    location /api/products/ {
        proxy_pass http://product_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
    
    # 默认后端
    location / {
        proxy_pass http://app_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
    
    # 健康检查端点
    location /health {
        access_log off;
        return 200 "OK\n";
    }
}
```

---

## 4. SSL/TLS配置

### 4.1 Let's Encrypt自动化

```bash
#!/bin/bash
# ssl-setup.sh - Let's Encrypt证书自动配置

DOMAIN="api.example.com"
EMAIL="admin@example.com"

# 安装certbot
yum install -y certbot python3-certbot-nginx

# 获取证书
certbot certonly --nginx \
    -d $DOMAIN \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email

# 自动续期
echo "0 3 * * * certbot renew --quiet --post-hook 'nginx -s reload'" | crontab -

# 证书路径
# /etc/letsencrypt/live/$DOMAIN/fullchain.pem
# /etc/letsencrypt/live/$DOMAIN/privkey.pem
```

### 4.2 最佳SSL配置

```nginx
# SSL最佳实践配置
server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    # 证书
    ssl_certificate /etc/nginx/ssl/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/api.example.com/privkey.pem;
    
    # 协议版本（只允许TLS 1.2和1.3）
    ssl_protocols TLSv1.2 TLSv1.3;
    
    # 密码套件
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    
    # SSL会话缓存
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 223.5.5.5 114.114.114.114 valid=300s;
    resolver_timeout 5s;
    
    # DH参数（可选，增强安全性）
    # 生成: openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048
    # ssl_dhparam /etc/nginx/ssl/dhparam.pem;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
}
```

---

## 5. WAF配置

### 5.1 ModSecurity配置

```bash
# 安装ModSecurity
yum install -y libmodsecurity libmodsecurity-devel
# 编译Nginx时添加ModSecurity模块
# --add-module=/path/to/ModSecurity-nginx

# 下载OWASP规则
git clone https://github.com/coreruleset/coreruleset /etc/nginx/modsecurity/crs
cp /etc/nginx/modsecurity/crs/crs-setup.conf.example /etc/nginx/modsecurity/crs/crs-setup.conf
```

```nginx
# nginx.conf中启用ModSecurity
server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    # 启用WAF
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsecurity/modsecurity.conf;
    
    # ... 其他配置
}
```

### 5.2 OpenResty lua-resty-waf

```nginx
# OpenResty WAF配置
lua_package_path "/usr/local/openresty/lualib/?.lua;;";

server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    # WAF初始化
    access_by_lua_block {
        local lua_resty_waf = require "resty.waf"
        local waf = lua_resty_waf:new()
        
        waf:set_option("mode", "ACTIVE")
        waf:set_option("debug", false)
        
        # 自定义规则
        waf:set_option("add_ruleset", "custom-rules")
        
        waf:exec()
    }
    
    # WAF日志
    log_by_lua_block {
        local lua_resty_waf = require "resty.waf"
        local waf = lua_resty_waf:new()
        waf:write_log_events()
    }
}
```

---

## 6. 限流与熔断

### 6.1 Nginx限流配置

```nginx
# 限流配置

# 定义限流区域
# 基于客户端IP限制请求速率
limit_req_zone $binary_remote_addr zone=req_per_ip:10m rate=100r/s;

# 基于客户端IP限制并发连接数
limit_conn_zone $binary_remote_addr zone=conn_per_ip:10m;

# 基于server限制总请求速率
limit_req_zone $server_name zone=req_per_server:10m rate=10000r/s;

# 自定义限流响应
limit_req_status 429;
limit_conn_status 429;

# 错误页面
error_page 429 /429.html;

server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    # 应用限流
    # burst=20: 允许突发20个请求
    # nodelay: 突发请求不延迟处理
    limit_req zone=req_per_ip burst=20 nodelay;
    limit_conn conn_per_ip 50;
    
    # API接口更严格限流
    location /api/auth/login {
        limit_req zone=req_per_ip burst=5 nodelay;
        proxy_pass http://app_backend;
    }
    
    # 静态资源不限流
    location /static/ {
        limit_req off;
        limit_conn off;
        root /var/www/html;
    }
    
    # 429页面
    location = /429.html {
        internal;
        default_type application/json;
        return 429 '{"code":429,"message":"Too Many Requests"}';
    }
}
```

### 6.2 Lua限流

```nginx
# OpenResty Lua高级限流
lua_shared_dict rate_limit 10m;
lua_shared_dict conn_limit 10m;

server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    access_by_lua_block {
        local limit_req = require "resty.limit.req"
        local limit_conn = require "resty.limit.conn"
        
        -- 请求速率限制
        local lim_req, err = limit_req.new("rate_limit", 200, 100)
        if not lim_req then
            ngx.log(ngx.ERR, "failed to instantiate resty.limit.req: ", err)
            return ngx.exit(500)
        end
        
        local key = ngx.var.binary_remote_addr
        local delay, err = lim_req:incoming(key, true)
        if not delay then
            if err == "rejected" then
                ngx.header["Retry-After"] = "1"
                return ngx.exit(429)
            end
            ngx.log(ngx.ERR, "failed to limit req: ", err)
            return ngx.exit(500)
        end
        
        if delay >= 0.001 then
            ngx.sleep(delay)
        end
        
        -- 并发连接限制
        local lim_conn, err = limit_conn.new("conn_limit", 50, 30, 0.5)
        if not lim_conn then
            ngx.log(ngx.ERR, "failed to instantiate resty.limit.conn: ", err)
            return ngx.exit(500)
        end
        
        local delay, err = lim_conn:incoming(key, true)
        if not delay then
            if err == "rejected" then
                return ngx.exit(503)
            end
            ngx.log(ngx.ERR, "failed to limit conn: ", err)
            return ngx.exit(500)
        end
    }
    
    # 记录连接释放
    log_by_lua_block {
        local limit_conn = require "resty.limit.conn"
        local lim_conn = limit_conn.new("conn_limit", 50, 30, 0.5)
        local key = ngx.var.binary_remote_addr
        lim_conn:leaving(key)
    }
}
```

---

## 7. 灰度发布

### 7.1 基于Header的灰度

```nginx
# 灰度发布配置

upstream production {
    server 10.10.2.11:8080;
    server 10.10.2.12:8080;
}

upstream canary {
    server 10.10.2.21:8080;
}

# 通过map实现灰度路由
map $http_x_canary $backend {
    default   "production";
    "true"    "canary";
}

# 通过Cookie实现灰度
map $cookie_canary $backend_by_cookie {
    default   "production";
    "1"       "canary";
}

# 优先级: Header > Cookie > 默认
map "$http_x_canary:$cookie_canary" $final_backend {
    default            "production";
    "true:*"           "canary";
    ":1"               "canary";
}

server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    location / {
        # 灰度路由
        set $upstream $final_backend;
        
        if ($upstream = "canary") {
            proxy_pass http://canary;
        }
        proxy_pass http://production;
        
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 7.2 基于IP的灰度

```nginx
# 基于IP段的灰度
geo $is_canary {
    default 0;
    # 内部IP
    10.0.0.0/8 1;
    172.16.0.0/12 1;
    # 测试IP段
    203.0.113.0/24 1;
}

map $is_canary $backend {
    0 "production";
    1 "canary";
}

server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    location / {
        proxy_pass http://$backend;
        proxy_set_header Host $host;
    }
}
```

### 7.3 基于流量比例的灰度

```nginx
# 基于流量比例（10%到canary）
split_clients "${remote_addr}" $backend {
    10%    canary;
    *      production;
}

server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    location / {
        proxy_pass http://$backend;
        proxy_set_header Host $host;
    }
}
```

---

## 8. OpenResty动态路由

### 8.1 动态路由配置

```nginx
# OpenResty动态路由
lua_shared_dict routes 10m;
lua_shared_dict upstream_health 10m;

init_by_lua_block {
    -- 初始化路由表
    local routes = ngx.shared.routes
    routes:set("/api/v1/users", "user_service")
    routes:set("/api/v1/orders", "order_service")
    routes:set("/api/v1/products", "product_service")
}

server {
    listen 80;
    server_name api.example.com;
    
    # 动态路由
    rewrite_by_lua_block {
        local routes = ngx.shared.routes
        local uri = ngx.var.uri
        
        -- 路由匹配
        for prefix, backend in pairs(routes) do
            if string.find(uri, prefix, 1, true) then
                ngx.var.upstream = backend
                return
            end
        end
        
        ngx.var.upstream = "default_backend"
    }
    
    # 动态upstream
    set $upstream "";
    
    location / {
        proxy_pass http://$upstream;
        proxy_set_header Host $host;
    }
    
    # 路由管理API
    location /admin/routes {
        content_by_lua_block {
            local routes = ngx.shared.routes
            local method = ngx.req.get_method()
            
            if method == "GET" then
                local keys = routes:get_keys(100)
                local result = {}
                for _, key in ipairs(keys) do
                    result[key] = routes:get(key)
                end
                ngx.say(require("cjson").encode(result))
                
            elseif method == "POST" then
                ngx.req.read_body()
                local data = require("cjson").decode(ngx.req.get_body_data())
                routes:set(data.path, data.backend)
                ngx.say('{"status":"ok"}')
                
            elseif method == "DELETE" then
                ngx.req.read_body()
                local data = require("cjson").decode(ngx.req.get_body_data())
                routes:delete(data.path)
                ngx.say('{"status":"ok"}')
            end
        }
    }
}
```

---

## 9. 监控与日志分析

### 9.1 stub_status监控

```nginx
# Nginx状态监控
server {
    listen 8080;
    server_name localhost;
    
    # Nginx状态
    location /nginx_status {
        stub_status on;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny all;
    }
    
    # 健康检查
    location /health {
        access_log off;
        return 200 "OK\n";
    }
}
```

### 9.2 Prometheus指标

```nginx
# 使用nginx-prometheus-exporter
# 安装: https://github.com/nginxinc/nginx-prometheus-exporter

# 启动exporter
# nginx-prometheus-exporter -nginx.scrape-uri=http://localhost:8080/stub_status

# 核心指标:
# nginx_connections_active - 活跃连接数
# nginx_connections_reading - 正在读取请求头
# nginx_connections_writing - 正在写响应
# nginx_connections_waiting - 等待请求的空闲连接
# nginx_http_requests_total - 总请求数
```

### 9.3 GoAccess实时分析

```bash
# 安装GoAccess
yum install -y goaccess

# 实时分析
goaccess /var/log/nginx/access.log -o /var/www/html/report.html \
    --log-format=COMBINED --real-time-html

# JSON格式日志分析
goaccess /var/log/nginx/access.log -o report.html \
    --log-format='%^ %^ %^ %^ %h %^ [%d:%t %^] "%r" %s %b "%R" "%u"' \
    --date-format='%d/%b/%Y' --time-format='%H:%M:%S'

# 命令行实时监控
goaccess /var/log/nginx/access.log --log-format=COMBINED -c
```

---

## 10. 最佳实践与故障排查

### 10.1 Nginx配置检查

```bash
# 检查配置语法
nginx -t

# 查看编译参数
nginx -V

# 平滑重启（不中断服务）
nginx -s reload

# 查看Nginx进程
ps aux | grep nginx

# 查看worker连接数
ss -s | grep estab
```

### 10.2 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 502 Bad Gateway | 后端服务不可用 | 检查后端服务状态和端口 |
| 504 Gateway Timeout | 后端响应超时 | 增加proxy_read_timeout |
| 413 Entity Too Large | 请求体过大 | 增加client_max_body_size |
| 429 Too Many Requests | 触发限流 | 调整限流参数 |
| SSL握手失败 | 证书问题 | 检查证书有效期和链 |
| upstream timed out | 后端处理慢 | 优化后端或增加超时 |
| worker_connections不够 | 并发超限 | 增加worker_connections |

### 10.3 最佳实践

1. **配置管理** - 使用版本控制管理nginx.conf
2. **日志标准化** - 使用JSON格式日志
3. **监控告警** - 监控连接数、响应时间、错误率
4. **安全加固** - 隐藏版本号、安全头、WAF
5. **性能优化** - 开启gzip、连接池、静态缓存
6. **灰度发布** - 先小流量验证再全量
7. **证书管理** - 自动续期，监控过期
8. **配置测试** - 修改前先`nginx -t`

---

> 📅 最后更新: 2026-05-02
