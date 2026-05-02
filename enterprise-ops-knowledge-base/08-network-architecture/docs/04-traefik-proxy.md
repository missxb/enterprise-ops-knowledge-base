# Traefik 云原生代理

## 1. Traefik 概述

Traefik 是一款现代的云原生反向代理和负载均衡器，专为微服务和容器化环境设计。其最大的特点是自动服务发现——通过与 Docker、Kubernetes 等编排平台集成，自动感知后端服务的变化并更新路由配置。

### 1.1 核心特性

- **自动服务发现**：与 Docker、Kubernetes、Consul 等原生集成
- **动态配置**：无需重启即可更新路由规则
- **Let's Encrypt 集成**：自动申请和续期 SSL 证书
- **Dashboard**：内置可视化管理界面
- **中间件链**：灵活的请求处理管道
- **多协议支持**：HTTP、HTTPS、TCP、UDP、gRPC

### 1.2 与其他代理对比

| 特性 | Traefik | Nginx | Envoy | HAProxy |
|------|---------|-------|-------|---------|
| 自动发现 | ✅ 原生 | ❌ 需插件 | ❌ 需控制面 | ❌ 需脚本 |
| 配置热更新 | ✅ 自动 | ❌ 需 reload | ✅ xDS | ❌ 需 reload |
| Let's Encrypt | ✅ 内置 | ❌ 需外部工具 | ❌ | ❌ |
| K8s Ingress | ✅ 原生 | ✅ Ingress Controller | ✅ Istio | ✅ Ingress Controller |
| 学习曲线 | 低 | 中 | 高 | 中 |

## 2. 安装部署

### 2.1 Docker 部署

```yaml
# docker-compose.yml
version: '3.8'

services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./config:/etc/traefik/config:ro
      - ./certs:/etc/traefik/certs
      - ./acme:/acme
    networks:
      - traefik-net
    labels:
      - "traefik.enable=true"
      # Dashboard 路由
      - "traefik.http.routers.dashboard.rule=Host(`traefik.example.com`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$..."
```

### 2.2 Kubernetes 部署

```yaml
# traefik-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik
  namespace: kube-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: traefik
  template:
    metadata:
      labels:
        app: traefik
    spec:
      serviceAccountName: traefik-ingress-controller
      containers:
        - name: traefik
          image: traefik:v3.0
          args:
            - --api.dashboard=true
            - --entrypoints.web.address=:80
            - --entrypoints.websecure.address=:443
            - --providers.kubernetesingress=true
            - --providers.kubernetescrd=true
            - --certificatesresolvers.letsencrypt.acme.email=admin@example.com
            - --certificatesresolvers.letsencrypt.acme.storage=/acme/acme.json
            - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
          ports:
            - name: web
              containerPort: 80
            - name: websecure
              containerPort: 443
            - name: dashboard
              containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

## 3. 核心配置

### 3.1 静态配置（traefik.yml）

```yaml
# traefik.yml
api:
  dashboard: true
  insecure: false

# 全局配置
global:
  checkNewVersion: false
  sendAnonymousUsage: false

# 日志配置
log:
  level: INFO
  format: json

accessLog:
  format: json
  filters:
    statusCodes:
      - "200-299"
      - "400-599"
    retryAttempts: true

# 入口点配置
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
  metrics:
    address: ":8082"

# 证书解析器
certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@example.com
      storage: /acme/acme.json
      httpChallenge:
        entryPoint: web
      # DNS 验证（适合通配符证书）
      # dnsChallenge:
      #   provider: alidns
      #   delayBeforeCheck: 10s

# 提供者配置
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik-net
  file:
    directory: /etc/traefik/config
    watch: true

# Prometheus 指标
metrics:
  prometheus:
    entryPoint: metrics
    addEntryPointsLabels: true
    addServicesLabels: true

# Ping 健康检查
ping:
  entryPoint: web
```

### 3.2 动态配置（路由规则）

```yaml
# config/routes.yml
http:
  routers:
    # API 服务路由
    api-router:
      rule: "Host(`api.example.com`) && PathPrefix(`/v2`)"
      entryPoints:
        - websecure
      service: api-service
      middlewares:
        - rate-limit
        - compress
        - cors
      tls:
        certResolver: letsencrypt

    # Web 应用路由
    web-router:
      rule: "Host(`www.example.com`)"
      entryPoints:
        - websecure
      service: web-service
      middlewares:
        - compress
        - secure-headers

  services:
    # API 后端服务
    api-service:
      loadBalancer:
        servers:
          - url: "http://10.1.1.10:8080"
          - url: "http://10.1.1.11:8080"
        healthCheck:
          path: /health
          interval: 10s
          timeout: 3s
        sticky:
          cookie:
            name: api-session
            secure: true
            httpOnly: true

    # Web 后端服务
    web-service:
      loadBalancer:
        servers:
          - url: "http://10.1.2.10:80"
          - url: "http://10.1.2.11:80"

  middlewares:
    # 速率限制
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1s

    # 压缩
    compress:
      compress:
        excludedContentTypes:
          - text/event-stream

    # CORS
    cors:
      headers:
        accessControlAllowMethods:
          - GET
          - POST
          - PUT
          - DELETE
        accessControlAllowOriginList:
          - "https://www.example.com"
        accessControlMaxAge: 3600

    # 安全头
    secure-headers:
      headers:
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        stsSeconds: 63072000
        stsIncludeSubdomains: true
        stsPreload: true

    # IP 白名单
    ip-whitelist:
      ipAllowList:
        sourceRange:
          - "10.0.0.0/8"
          - "172.16.0.0/12"

    # 基本认证
    auth:
      basicAuth:
        users:
          - "admin:$apr1$..."
```

## 4. 高级功能

### 4.1 TCP/UDP 路由

```yaml
# TCP 路由
tcp:
  routers:
    mysql-router:
      rule: "HostSNI(`db.example.com`)"
      entryPoints:
        - mysql
      service: mysql-service
      tls:
        passthrough: true

  services:
    mysql-service:
      loadBalancer:
        servers:
          - address: "10.1.5.10:3306"
          - address: "10.1.5.11:3306"

# UDP 路由
udp:
  routers:
    dns-router:
      entryPoints:
        - dns
      service: dns-service

  services:
    dns-service:
      loadBalancer:
        servers:
          - address: "10.1.6.10:53"
```

### 4.2 IngressRoute (Kubernetes CRD)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: api-ingress
  namespace: default
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`api.example.com`) && PathPrefix(`/v2`)
      kind: Rule
      services:
        - name: api-service
          port: 8080
      middlewares:
        - name: rate-limit
        - name: compress
  tls:
    certResolver: letsencrypt

---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: default
spec:
  rateLimit:
    average: 100
    burst: 50
```

### 4.3 自动服务发现（Docker Labels）

```yaml
# docker-compose.yml - 应用服务
version: '3.8'

services:
  api:
    image: my-api:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`api.example.com`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.services.api.loadbalancer.server.port=8080"
      - "traefik.http.services.api.loadbalancer.healthcheck.path=/health"
      - "traefik.http.services.api.loadbalancer.healthcheck.interval=10s"
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
```

## 5. 生产最佳实践

### 5.1 安全加固

```yaml
# 生产环境安全配置
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
    # 限制连接速率
    transport:
      lifeCycle:
        requestAcceptGraceTimeout: 2s
        graceTimeOut: 10s
      respondingTimeouts:
        readTimeout: 30s
        writeTimeout: 30s
        idleTimeout: 180s

  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
        options: default
    # 限制并发连接
    proxyProtocol:
      insecure: false
      trustedIPs:
        - "10.0.0.0/8"

# TLS 选项
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
      sniStrict: true
```

### 5.2 高可用部署

```yaml
# 使用 Redis 作为分布式存储
providers:
  redis:
    endpoints:
      - "redis-0:6379"
      - "redis-1:6379"
      - "redis-2:6379"
    password: "your-redis-password"
    db: 0
    rootKey: traefik

# 或使用 Consul
providers:
  consul:
    endpoints:
      - "consul-0:8500"
      - "consul-1:8500"
      - "consul-2:8500"
    prefix: traefik
```

## 6. 监控与排障

### 6.1 Prometheus 指标

```yaml
# Grafana Dashboard ID: 17347
metrics:
  prometheus:
    entryPoint: metrics
    addEntryPointsLabels: true
    addRoutersLabels: true
    addServicesLabels: true
    buckets:
      - 0.1
      - 0.3
      - 1.2
      - 5.0
```

关键指标：
- `traefik_entrypoint_requests_total`：入口点请求数
- `traefik_service_requests_total`：服务请求数
- `traefik_service_request_duration_seconds`：请求耗时
- `traefik_service_open_connections`：打开的连接数

### 6.2 调试命令

```bash
# 查看 Traefik 配置
docker exec traefik traefik healthcheck

# 查看路由规则
curl -s http://localhost:8080/api/http/routers | jq .

# 查看服务状态
curl -s http://localhost:8080/api/http/services | jq .

# 查看入口点
curl -s http://localhost:8080/api/entrypoints | jq .
```
