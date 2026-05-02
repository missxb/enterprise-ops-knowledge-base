# 负载均衡 (SLB/ALB)

## 1. 概述

负载均衡是云架构中实现高可用和水平扩展的关键组件。它将用户请求分发到多个后端服务器，消除单点故障，提升系统整体吞吐能力。本文将详细介绍阿里云 SLB/ALB 和 AWS ALB/NLB 的配置、运维和最佳实践。

## 2. 负载均衡类型对比

### 2.1 阿里云负载均衡

| 产品 | 层级 | 协议 | 特点 | 适用场景 |
|------|------|------|------|----------|
| CLB (原 SLB) | 四层 + 七层 | TCP/UDP/HTTP/HTTPS | 成熟稳定，功能全面 | 通用场景 |
| ALB | 七层 | HTTP/HTTPS/gRPC | 高级路由，WebSocket 支持 | 微服务、API 网关 |
| NLB | 四层 | TCP/UDP/TLS | 超高性能，超低延迟 | 游戏、金融交易 |

### 2.2 AWS 负载均衡

| 产品 | 层级 | 协议 | 特点 | 适用场景 |
|------|------|------|------|----------|
| ALB | 七层 | HTTP/HTTPS | 内容路由，WebSocket | Web 应用、微服务 |
| NLB | 四层 | TCP/UDP/TLS | 超高性能，静态 IP | 游戏、IoT、金融 |
| CLB (Classic) | 四层 + 七层 | TCP/HTTP/HTTPS | 遗留产品 | 旧系统迁移 |
| GWLB | 三层 | IP | 网络虚拟设备 | 安全设备链 |

## 3. 四层负载均衡配置

### 3.1 TCP 负载均衡

四层负载均衡基于 IP 地址和端口进行转发，不解析应用层协议。

**配置示例（阿里云 CLB）：**

```bash
# 创建 SLB 实例
aliyun slb CreateLoadBalancer \
  --RegionId cn-hangzhou \
  --LoadBalancerName prod-api-slb \
  --AddressType internet \
  --InternetChargeType paybytraffic \
  --Bandwidth 1000 \
  --VpcId vpc-xxx \
  --VSwitchId vsw-xxx

# 配置 TCP 监听
aliyun slb CreateLoadBalancerTCPListener \
  --LoadBalancerId lb-xxx \
  --ListenerPort 8080 \
  --BackendServerPort 8080 \
  --Bandwidth -1 \
  --HealthCheck on \
  --HealthCheckType tcp \
  --HealthyThreshold 3 \
  --UnhealthyThreshold 3 \
  --HealthCheckInterval 2 \
  --HealthCheckTimeout 2

# 添加后端服务器
aliyun slb AddBackendServers \
  --LoadBalancerId lb-xxx \
  --BackendServers '[{"ServerId":"i-xxx1","Weight":"100"},{"ServerId":"i-xxx2","Weight":"100"}]'
```

### 3.2 UDP 负载均衡

UDP 负载均衡适用于 DNS、游戏、实时音视频等场景。

**健康检查配置：**
```
检查类型: UDP (发送 UDP 探测包)
检查间隔: 5 秒
超时时间: 3 秒
健康阈值: 3 次
不健康阈值: 3 次
```

## 4. 七层负载均衡配置

### 4.1 HTTP/HTTPS 负载均衡

七层负载均衡可以解析 HTTP 请求头，实现基于域名、URL 路径的路由。

**基于域名的路由：**

```
www.example.com     → 后端 Web 服务器组
api.example.com     → 后端 API 服务器组
admin.example.com   → 后端管理后台服务器组
```

**基于 URL 路径的路由：**

```
/api/v1/users/*     → 用户服务
/api/v1/orders/*    → 订单服务
/api/v1/products/*  → 商品服务
/static/*           → 静态资源服务器
```

### 4.2 HTTPS 配置

**证书管理：**

```bash
# 上传 SSL 证书
aliyun cas UploadUserCertificate \
  --Name prod-example-com \
  --Cert "$(cat server.crt)" \
  --Key "$(cat server.key)"

# 配置 HTTPS 监听
aliyun slb CreateLoadBalancerHTTPSListener \
  --LoadBalancerId lb-xxx \
  --ListenerPort 443 \
  --BackendServerPort 8080 \
  --ServerCertificateId cert-xxx \
  --TLSVersions TLSv1.2 TLSv1.3 \
  --EnableHttp2 on \
  --HealthCheck on \
  --HealthCheckURI /health \
  --HealthyThreshold 3 \
  --UnhealthyThreshold 3
```

**安全配置：**
- 仅允许 TLS 1.2 和 TLS 1.3
- 使用强加密套件
- 开启 HTTP/2
- 配置 HSTS 头

### 4.3 会话保持

**Cookie 会话保持：**

```yaml
会话保持类型: 植入 Cookie
Cookie 名称: SLB_COOKIE
超时时间: 3600 秒
```

**适用场景：**
- 购物车功能
- 用户登录状态
- 有状态的 WebSocket 连接

## 5. 高级功能

### 5.1 WAF 集成

负载均衡与 WAF（Web 应用防火墙）集成，防护 SQL 注入、XSS 等攻击。

```
用户请求 → WAF → SLB/ALB → 后端服务器

WAF 防护规则:
├── OWASP Top 10 防护
├── CC 攻击防护
├── 扫描器防护
├── 自定义规则（IP 黑名单、频率限制）
└── Bot 管理
```

### 5.2 访问日志

**日志字段：**

```
时间戳 | 客户端IP | 请求方法 | URL | 状态码 | 响应时间 | 后端服务器 | 请求大小 | 响应大小
```

**日志分析示例：**

```bash
# 统计 QPS
awk '{print $1}' access.log | cut -d: -f1-2 | sort | uniq -c | sort -rn

# 统计状态码分布
awk '{print $9}' access.log | sort | uniq -c | sort -rn

# 统计响应时间 > 1s 的请求
awk '$NF > 1000 {print $0}' access.log | wc -l

# 统计 TOP 10 慢请求
sort -t' ' -k$NF -rn access.log | head -10
```

### 5.3 限流配置

**QPS 限流：**

```yaml
监听器级别:
  限流 QPS: 10000
  限流粒度: 监听器

域名级别:
  api.example.com: 5000 QPS
  www.example.com: 3000 QPS

URL 级别:
  /api/v1/search: 1000 QPS
  /api/v1/upload: 100 QPS
```

## 6. 健康检查详解

### 6.1 健康检查类型

| 类型 | 检查方式 | 优点 | 缺点 |
|------|----------|------|------|
| TCP | 三次握手 | 简单快速 | 不检测应用层状态 |
| HTTP | GET 请求 | 检测应用状态 | 开销稍大 |
| HTTPS | GET 请求 (TLS) | 安全检测 | TLS 握手开销 |

### 6.2 健康检查配置建议

**Web 应用：**
```
类型: HTTP
路径: /health
端口: 8080
间隔: 2 秒
超时: 2 秒
健康阈值: 3
不健康阈值: 3
正常状态码: 200
```

**数据库代理：**
```
类型: TCP
端口: 3306
间隔: 5 秒
超时: 3 秒
健康阈值: 3
不健康阈值: 3
```

### 6.3 自定义健康检查端点

```java
// Spring Boot 健康检查端点
@RestController
public class HealthController {
    
    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> status = new HashMap<>();
        
        // 检查数据库连接
        boolean dbOk = checkDatabase();
        // 检查 Redis 连接
        boolean redisOk = checkRedis();
        // 检查磁盘空间
        boolean diskOk = checkDiskSpace();
        
        boolean healthy = dbOk && redisOk && diskOk;
        
        status.put("status", healthy ? "UP" : "DOWN");
        status.put("database", dbOk ? "UP" : "DOWN");
        status.put("redis", redisOk ? "UP" : "DOWN");
        status.put("disk", diskOk ? "UP" : "DOWN");
        status.put("timestamp", Instant.now());
        
        return ResponseEntity
            .status(healthy ? 200 : 503)
            .body(status);
    }
}
```

## 7. 性能调优

### 7.1 连接超时配置

```
TCP 连接超时: 300 秒 (默认)
HTTP 连接超时: 60 秒
长连接超时: 300 秒
WebSocket 超时: 3600 秒
```

### 7.2 后端服务器权重

**权重调整策略：**

```
新服务器上线:
1. 权重设为 10 (10% 流量)
2. 观察 5 分钟
3. 权重调至 50 (50% 流量)
4. 观察 5 分钟
5. 权重调至 100 (全量流量)

服务器下线:
1. 权重调至 50
2. 观察 2 分钟
3. 权重调至 0
4. 等待连接排空 (draining)
5. 移除服务器
```

## 8. 故障排查

### 8.1 常见问题

**问题1：后端服务器健康检查失败**

```bash
# 检查安全组是否放行健康检查端口
# 检查后端服务是否正常运行
curl -v http://backend-server:8080/health

# 检查网络连通性
telnet backend-server 8080

# 检查防火墙规则
iptables -L -n | grep 8080
```

**问题2：会话保持不生效**

```
检查项:
1. 确认会话保持类型配置正确
2. 检查 Cookie 是否被浏览器禁用
3. 确认后端服务器数量 > 1
4. 检查是否有多个负载均衡实例
```

**问题3：HTTPS 证书错误**

```bash
# 检查证书有效期
openssl x509 -in server.crt -noout -dates

# 检查证书链完整性
openssl verify -CAfile ca.crt server.crt

# 检查证书与私钥匹配
openssl x509 -noout -modulus -in server.crt | md5sum
openssl rsa -noout -modulus -in server.key | md5sum
```

## 9. 总结

负载均衡配置的核心要点：

1. **高可用**：至少配置 2 个后端服务器，跨 AZ 部署
2. **健康检查**：配置合理的健康检查，快速剔除异常节点
3. **安全防护**：HTTPS + WAF + 访问控制
4. **监控告警**：监控 QPS、延迟、错误率、后端健康状态
5. **灰度发布**：利用权重实现流量灰度切换
6. **日志分析**：开启访问日志，定期分析请求模式
