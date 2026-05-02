# Docker 安全加固

## 1. 安全威胁模型

### 1.1 容器安全风险层次

```
┌─────────────────────────────────────────┐
│         应用层安全                        │
│   代码漏洞、依赖漏洞、配置错误             │
├─────────────────────────────────────────┤
│         容器运行时安全                     │
│   特权容器、逃逸攻击、资源耗尽             │
├─────────────────────────────────────────┤
│         镜像安全                          │
│   恶意镜像、过时镜像、镜像篡改             │
├─────────────────────────────────────────┤
│         主机安全                          │
│   内核漏洞、Docker daemon 权限             │
├─────────────────────────────────────────┤
│         网络安全                          │
│   未加密通信、端口暴露、中间人攻击          │
├─────────────────────────────────────────┤
│         供应链安全                        │
│   基础镜像投毒、构建过程篡改               │
└─────────────────────────────────────────┘
```

## 2. Docker Daemon 安全

### 2.1 限制 Docker Socket 访问

```bash
# ❌ 危险：将 Docker socket 挂载到容器
docker run -v /var/run/docker.sock:/var/run/docker.sock -d portainer/portainer
# 这等于给了容器 root 权限！

# ✅ 安全：使用 Docker Socket Proxy
docker run -d \
  --name docker-proxy \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e CONTAINERS=1 \
  -e SERVICES=1 \
  -e TASKS=1 \
  -p 2375:2375 \
  tecnativa/docker-socket-proxy

# 只暴露必要的 API 端点
```

### 2.2 TLS 加密通信

```bash
# 生成 CA 证书
openssl genrsa -aes256 -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem \
  -subj "/CN=Docker CA"

# 生成服务端证书
openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=docker-host" -sha256 -new -key server-key.pem -out server.csr
echo "subjectAltName=DNS:docker-host,IP:10.0.0.100,IP:127.0.0.1" > extfile.cnf
echo "extendedKeyUsage=serverAuth" >> extfile.cnf
openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem -extfile extfile.cnf

# 配置 Docker daemon 使用 TLS
cat > /etc/docker/daemon.json <<EOF
{
  "tls": true,
  "tlscacert": "/etc/docker/certs/ca.pem",
  "tlscert": "/etc/docker/certs/server-cert.pem",
  "tlskey": "/etc/docker/certs/server-key.pem",
  "tlsverify": true
}
EOF

systemctl restart docker

# 客户端连接
docker --tlsverify \
  --tlscacert=ca.pem \
  --tlscert=cert.pem \
  --tlskey=key.pem \
  -H=tcp://docker-host:2376 info
```

### 2.3 Rootless Docker

```bash
# Rootless Docker 让 dockerd 以普通用户身份运行
# 即使 daemon 被攻破，攻击者也只有普通用户权限

# 安装 rootless Docker
dockerd-rootless-setuptool.sh install

# 验证
docker context use rootless
docker info | grep "Security Options"
# Security Options:
#  seccomp
#  rootless

# 环境变量配置
export PATH=/home/user/bin:$PATH
export DOCKER_HOST=unix:///run/user/1000/docker.sock
```

## 3. 容器运行时安全

### 3.1 禁止特权容器

```bash
# ❌ 危险：特权容器拥有宿主机所有 capabilities
docker run --privileged -d myapp

# ✅ 安全：只授予必要的 capabilities
docker run \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  -p 80:80 \
  -d nginx:alpine

# 常用 capabilities 说明
# NET_BIND_SERVICE - 绑定 <1024 端口
# SYS_PTRACE - 进程调试（APM 工具需要）
# NET_ADMIN - 网络管理（VPN 容器需要）
# SYS_ADMIN - 系统管理（谨慎使用）
```

### 3.2 Seccomp 配置

```bash
# Docker 默认使用 seccomp 配置文件，禁止约 44 个危险系统调用

# 查看默认 seccomp 配置
docker info | grep "Default Runtime"

# 使用自定义 seccomp 配置
docker run --security-opt seccomp=custom-profile.json myapp

# 禁用 seccomp（不推荐）
docker run --security-opt seccomp=unconfined myapp

# 自定义 seccomp 配置示例
cat > custom-seccomp.json <<EOF
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {
      "names": ["read", "write", "open", "close", "stat", "fstat"],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
```

### 3.3 AppArmor 配置

```bash
# 查看 Docker 默认 AppArmor 配置
sudo cat /etc/apparmor.d/docker-default

# 使用自定义 AppArmor 配置
docker run --security-opt apparmor=my-custom-profile myapp

# 加载自定义配置文件
sudo apparmor_parser -r /etc/apparmor.d/my-custom-profile

# 自定义 AppArmor 配置示例
cat > my-custom-profile <<EOF
#include <tunables/global>

profile my-custom-profile flags=(attach_disconnected) {
  #include <abstractions/base>

  # 禁止写入 /proc 和 /sys
  deny /proc/** w,
  deny /sys/** w,

  # 允许读取应用目录
  /app/** r,

  # 禁止网络访问（除特定端口）
  network tcp,
  deny network udp,
}
EOF
```

### 3.4 只读文件系统

```bash
# 容器使用只读根文件系统
docker run --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=100m \
  --tmpfs /run:rw,noexec,nosuid,size=50m \
  -v app-data:/app/data \
  -d myapp:latest

# 只读 + 特定目录可写
docker run --read-only \
  --tmpfs /tmp \
  --tmpfs /var/log \
  -v logs:/var/log/app \
  -d nginx:alpine
```

## 4. 镜像安全

### 4.1 镜像签名与验证

```bash
# 启用 Docker Content Trust
export DOCKER_CONTENT_TRUST=1

# 签名镜像
docker push myregistry.com/myapp:v1.0
# 首次推送会提示创建签名密钥

# 拉取签名镜像（自动验证）
docker pull myregistry.com/myapp:v1.0

# 禁用验证（不推荐）
export DOCKER_CONTENT_TRUST=0
```

### 4.2 镜像扫描

```bash
# 使用 Trivy 扫描镜像漏洞
trivy image nginx:alpine

# 扫描并输出 JSON 报告
trivy image --format json --output report.json nginx:alpine

# 只显示高危和严重漏洞
trivy image --severity HIGH,CRITICAL nginx:alpine

# 在 CI/CD 中集成扫描
trivy image --exit-code 1 --severity CRITICAL myapp:v1.0
# 如果发现 CRITICAL 漏洞，返回非零退出码

# 使用 Docker Scout（Docker 官方）
docker scout cves nginx:alpine
docker scout recommendations nginx:alpine
```

### 4.3 基础镜像选择

```bash
# 安全基础镜像优先级
# 1. scratch - 空镜像，最安全（仅限静态二进制）
# 2. distroless - Google 维护，无 shell、无包管理
# 3. alpine - 最小 Linux 发行版（musl libc 兼容性）
# 4. slim - Debian/Ubuntu 精简版
# 5. full - 完整发行版（不推荐用于生产）

# Distroless 镜像示例
FROM gcr.io/distroless/java17-debian12
COPY app.jar /app.jar
CMD ["app.jar"]

# 对比
# nginx:latest        ~187MB
# nginx:alpine        ~41MB
# nginx:mainline-alpine ~41MB
```

## 5. 网络安全

### 5.1 网络隔离

```bash
# 创建隔离网络
docker network create --internal isolated-net
# --internal 标志：容器无法访问外部网络

# 多网络分层
docker network create frontend
docker network create backend

# 前端容器只连前端网络
docker run --network frontend web
# 后端容器连前后端网络
docker run --network backend api
docker network connect frontend api
```

### 5.2 加密通信

```bash
# Swarm 模式下 overlay 网络加密
docker network create --driver overlay --opt encrypted my-overlay

# 使用 TLS 终止代理
docker run -d \
  --name nginx-tls \
  -v /etc/nginx/certs:/etc/nginx/certs:ro \
  -p 443:443 \
  nginx:alpine
```

## 6. 资源限制

### 6.1 CPU 限制

```bash
# 限制 CPU 使用率
docker run -d --cpus="1.5" myapp     # 最多使用 1.5 个 CPU 核心
docker run -d --cpu-shares=512 myapp  # CPU 份额（相对权重）
docker run -d --cpuset-cpus="0,1" myapp  # 绑定到特定 CPU 核心
```

### 6.2 内存限制

```bash
# 限制内存使用
docker run -d --memory=512m --memory-swap=1g myapp
# memory: 内存硬限制
# memory-swap: 内存 + swap 总限制

# OOM 杀死优先级
docker run -d --memory=512m --oom-score-adj=500 myapp
# 值越高，越容易被 OOM killer 杀死

# 禁用 OOM killer（容器可能被内核杀死）
docker run -d --memory=512m --oom-kill-disable myapp
```

### 6.3 PID 限制

```bash
# 限制容器内进程数（防止 fork bomb）
docker run -d --pids-limit=100 myapp

# 验证限制
docker exec <container> sh -c "cat /sys/fs/cgroup/pids.max"
```

## 7. 安全审计

### 7.1 Docker 审计日志

```bash
# 配置 auditd 监控 Docker 相关文件
cat >> /etc/audit/rules.d/docker.rules <<EOF
-w /usr/bin/docker -p wa -k docker
-w /var/lib/docker -p wa -k docker
-w /etc/docker -p wa -k docker
-w /usr/lib/systemd/system/docker.service -p wa -k docker
-w /usr/lib/systemd/system/docker.socket -p wa -k docker
-w /var/run/docker.sock -p wa -k docker
-w /etc/docker/daemon.json -p wa -k docker
EOF

sudo systemctl restart auditd

# 查看 Docker 审计日志
sudo ausearch -k docker
```

### 7.2 安全扫描脚本

```bash
#!/bin/bash
# docker-security-audit.sh

echo "=== Docker Security Audit ==="

echo -e "\n[1] Docker version:"
docker version --format 'Server: {{.Server.Version}}'

echo -e "\n[2] Security options:"
docker info --format '{{.SecurityOptions}}'

echo -e "\n[3] Privileged containers:"
docker ps --quiet | xargs -I{} docker inspect --format \
  '{{.Name}} privileged={{.HostConfig.Privileged}}' {}

echo -e "\n[4] Containers running as root:"
docker ps --quiet | xargs -I{} docker inspect --format \
  '{{.Name}} user={{.Config.User}}' {} | grep "user=$\|user=root"

echo -e "\n[5] Containers with host network:"
docker ps --quiet | xargs -I{} docker inspect --format \
  '{{.Name}} network={{.HostConfig.NetworkMode}}' {} | grep "network=host"

echo -e "\n[6] Containers with Docker socket mounted:"
docker ps --quiet | xargs -I{} docker inspect --format \
  '{{.Name}} mounts={{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' {} | grep "docker.sock"

echo -e "\n[7] Images with vulnerabilities (Trivy):"
for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | head -10); do
  echo "Scanning $img..."
  trivy image --severity CRITICAL --quiet "$img" 2>/dev/null
done

echo -e "\n=== Audit Complete ==="
```

## 8. 生产安全配置模板

### 8.1 daemon.json 安全配置

```json
{
  "icc": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "seccomp-profile": "/etc/docker/seccomp-default.json",
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 4096,
      "Soft": 4096
    }
  }
}
```

### 8.2 docker-compose 安全模板

```yaml
version: "3.8"
services:
  app:
    image: myapp:production
    read_only: true
    tmpfs:
      - /tmp
      - /run
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1G
        reservations:
          cpus: "0.5"
          memory: 256M
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    networks:
      - app-net

networks:
  app-net:
    driver: bridge
    internal: false
```
