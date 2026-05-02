# Nginx 问题排查

## 502 Bad Gateway

```bash
# 原因：上游服务不可用

# 1. 检查上游服务状态
curl -v http://upstream-server:port/health

# 2. 检查 Nginx upstream 配置
nginx -T | grep -A10 upstream

# 3. 检查连接数
ss -s | grep -i estab
cat /proc/sys/net/core/somaxconn

# 4. 检查 Nginx 错误日志
tail -100 /var/log/nginx/error.log | grep upstream

# 解决：
# - 增大 upstream 连接超时时间
# - 增大 fastcgi_read_timeout
# - 检查上游服务健康
```

## 504 Gateway Timeout

```bash
# 原因：上游服务响应超时

# 1. 检查上游服务响应时间
curl -w "time_total: %{time_total}\n" -o /dev/null -s http://upstream/api

# 2. 调整超时配置
# nginx.conf
proxy_connect_timeout 300s;
proxy_send_timeout 300s;
proxy_read_timeout 300s;
fastcgi_read_timeout 300s;
```

## 499 Client Closed Request

```bash
# 原因：客户端提前断开连接

# 1. 检查是否客户端超时
# 2. 检查是否有大文件传输
# 3. 调整 keepalive
keepalive_timeout 65;
keepalive_requests 1000;
```

## 性能问题

```bash
# 1. 检查 worker 连接数
cat /var/log/nginx/error.log | grep "worker_connections are not enough"

# 2. 调整配置
events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

# 3. 启用缓存
proxy_cache_path /tmp/nginx_cache levels=1:2 keys_zone=my_cache:10m max_size=10g;

# 4. 启用 Gzip
gzip on;
gzip_types text/plain application/json application/javascript text/css;
gzip_min_length 1000;
```

## SSL 问题

```bash
# 检查证书有效期
openssl x509 -in /etc/nginx/ssl/cert.pem -noout -dates

# 检查证书链
openssl s_client -connect domain.com:443 -showcerts

# 检查配置
nginx -t
```
