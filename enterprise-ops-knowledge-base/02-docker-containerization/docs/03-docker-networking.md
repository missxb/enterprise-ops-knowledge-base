# Docker 网络模型

## 1. Docker 网络架构

### 1.1 网络驱动概述

Docker 提供多种网络驱动，满足不同的容器通信需求：

| 驱动 | 作用域 | 适用场景 | 性能 |
|------|--------|----------|------|
| bridge | 单机 | 默认网络，单机容器通信 | ★★★★ |
| host | 单机 | 高性能网络需求 | ★★★★★ |
| overlay | 跨机 | Swarm/K8s 跨主机通信 | ★★★ |
| macvlan | 单机 | 容器需要独立 MAC 地址 | ★★★★ |
| none | 单机 | 完全隔离 | - |

### 1.2 bridge 网络详解

bridge 是 Docker 默认网络模式，也是最常用的模式：

```
┌─────────────────────────────────────────┐
│              Host Machine               │
│                                         │
│  ┌─────────┐      ┌─────────────────┐  │
│  │Container│      │   docker0       │  │
│  │  eth0   │──────│   bridge        │  │
│  │172.17.  │ veth │   172.17.0.1    │  │
│  │ 0.2     │ pair │                 │  │
│  └─────────┘      └────────┬────────┘  │
│                            │            │
│  ┌─────────┐               │            │
│  │Container│      ┌────────┴────────┐  │
│  │  eth0   │──────│   NAT / iptables│  │
│  │172.17.  │ veth │   eth0 (Host)   │──│──▶ 外部网络
│  │ 0.3     │ pair │   10.0.0.100    │  │
│  └─────────┘      └─────────────────┘  │
└─────────────────────────────────────────┘
```

```bash
# 查看默认 bridge 网络
docker network inspect bridge

# 查看 docker0 网桥
ip link show docker0
brctl show docker0

# 容器间通信验证
docker run -d --name web1 nginx:alpine
docker run -d --name web2 nginx:alpine
docker exec web1 ping -c 3 172.17.0.2  # 通过 IP 通信
docker exec web1 ping -c 3 web2         # 默认 bridge 不支持 DNS！
```

### 1.3 自定义 bridge 网络

```bash
# 创建自定义网络
docker network create \
  --driver bridge \
  --subnet 172.20.0.0/16 \
  --gateway 172.20.0.1 \
  --opt com.docker.network.bridge.name=br-custom \
  my-network

# 在自定义网络中启动容器
docker run -d --name app1 --network my-network nginx:alpine
docker run -d --name app2 --network my-network nginx:alpine

# 自定义网络支持 DNS 解析！
docker exec app1 ping -c 3 app2  # ✅ 可以通过容器名解析

# 将已有容器加入网络
docker network connect my-network existing-container
docker network disconnect bridge existing-container
```

## 2. host 网络模式

```bash
# host 模式直接使用宿主机网络栈
docker run -d --network host --name nginx-host nginx:alpine

# 容器直接绑定宿主机端口，无需 -p 映射
# 宿主机 80 端口直接被 nginx 占用
curl http://localhost:80

# 优势：性能最高，无 NAT 开销
# 劣势：端口冲突风险，无网络隔离
```

**适用场景**：
- 对网络性能要求极高的应用
- 需要监听大量端口的服务
- 网络调试工具

## 3. overlay 网络模式

### 3.1 跨主机容器通信

overlay 网络基于 VXLAN 实现跨主机的容器通信：

```
┌─────────────── Host A ──────────────┐   ┌─────────────── Host B ──────────────┐
│                                     │   │                                     │
│  ┌──────────┐   ┌──────────┐       │   │       ┌──────────┐   ┌──────────┐  │
│  │Container1│   │Container2│       │   │       │Container3│   │Container4│  │
│  │10.0.0.2  │   │10.0.0.3  │       │   │       │10.0.0.4  │   │10.0.0.5  │  │
│  └────┬─────┘   └────┬─────┘       │   │       └────┬─────┘   └────┬─────┘  │
│       │              │              │   │              │              │        │
│  ┌────┴──────────────┴────┐        │   │        ┌────┴──────────────┴────┐   │
│  │    overlay network      │        │   │        │    overlay network      │   │
│  │    (VXLAN tunnel)       │        │   │        │    (VXLAN tunnel)       │   │
│  └────────────┬────────────┘        │   │        └────────────┬────────────┘   │
│               │ VXLAN tunnel        │   │        VXLAN tunnel │                │
│  ┌────────────┴────────────┐        │   │        ┌────────────┴────────────┐   │
│  │    eth0  10.0.0.100     │========│===│========│    eth0  10.0.0.200     │   │
│  └─────────────────────────┘        │   │        └─────────────────────────┘   │
└─────────────────────────────────────┘   └─────────────────────────────────────┘
```

### 3.2 Docker Swarm overlay

```bash
# 初始化 Swarm
docker swarm init --advertise-addr 10.0.0.100

# 在其他节点加入
docker swarm join --token <token> 10.0.0.100:2377

# 创建 overlay 网络
docker network create \
  --driver overlay \
  --attachable \
  --subnet 10.10.0.0/16 \
  my-overlay

# 部署服务到 overlay 网络
docker service create \
  --name web \
  --network my-overlay \
  --replicas 3 \
  nginx:alpine
```

## 4. macvlan 网络模式

```bash
# macvlan 让容器拥有独立的 MAC 和 IP 地址
# 适用于需要容器直接出现在物理网络中的场景

docker network create \
  --driver macvlan \
  --subnet 192.168.1.0/24 \
  --gateway 192.168.1.1 \
  -o parent=eth0 \
  my-macvlan

docker run -d --name vm-like --network my-macvlan \
  --ip 192.168.1.100 nginx:alpine

# 容器直接出现在物理网络中，如同物理机/虚拟机
# 外部可直接通过 192.168.1.100 访问
```

## 5. 端口映射

### 5.1 基本端口映射

```bash
# 映射单个端口
docker run -d -p 8080:80 nginx:alpine
# 宿主机 8080 → 容器 80

# 映射多个端口
docker run -d -p 8080:80 -p 8443:443 nginx:alpine

# 指定绑定地址
docker run -d -p 127.0.0.1:8080:80 nginx:alpine
# 仅监听 localhost

# 随机端口
docker run -d -P nginx:alpine
# 使用 EXPOSE 声明的端口，随机映射到宿主机

# 查看端口映射
docker port <container_id>
```

### 5.2 iptables 规则

```bash
# Docker 通过 iptables 实现端口映射和网络隔离

# 查看 Docker 创建的 NAT 规则
sudo iptables -t nat -L -n | grep -A5 DOCKER

# 查看 DOCKER 链
sudo iptables -L DOCKER -n -v

# Docker 网络隔离规则
sudo iptables -L DOCKER-ISOLATION-STAGE-1 -n -v
sudo iptables -L DOCKER-ISOLATION-STAGE-2 -n -v
```

## 6. DNS 与服务发现

### 6.1 内置 DNS 服务器

```bash
# 自定义网络中的容器可以通过容器名互相解析
# Docker 内置 DNS 服务器地址：127.0.0.11

docker network create app-net
docker run -d --name database --network app-net postgres:15
docker run -d --name backend --network app-net myapp:latest

# backend 容器可以直接通过 "database" 访问数据库
docker exec backend nslookup database
# Name:      database
# Address:   172.20.0.2
```

### 6.2 网络别名

```bash
# 为容器设置网络别名
docker run -d --name db-primary --network app-net \
  --network-alias database \
  --network-alias db-primary \
  postgres:15

# 多个容器可以使用相同的别名（实现简单负载均衡）
docker run -d --name web1 --network app-net --network-alias web nginx:alpine
docker run -d --name web2 --network app-net --network-alias web nginx:alpine

# DNS 查询 "web" 会返回两个 IP
docker exec web1 nslookup web
# Name:      web
# Address:   172.20.0.2
# Address:   172.20.0.3
```

## 7. 网络安全

### 7.1 容器间网络隔离

```bash
# 不同网络中的容器默认无法通信
docker network create frontend
docker network create backend

docker run -d --name web --network frontend nginx:alpine
docker run -d --name db --network backend postgres:15

# web 无法访问 db（网络隔离）
docker exec web ping db  # 失败

# 需要双网卡的容器连接两个网络
docker network connect backend web
docker exec web ping db  # 现在可以了
```

### 7.2 ICC (Inter-Container Communication) 控制

```bash
# 禁用容器间通信
docker network create \
  --driver bridge \
  --opt com.docker.network.bridge.enable_icc=false \
  secure-net

# ICC 禁用后，同一网络中的容器无法直接通信
# 必须通过端口映射或 link 通信
```

### 7.3 网络策略最佳实践

```bash
# 1. 不要使用默认 bridge 网络
# ✅ 创建自定义网络
docker network create app-network

# 2. 最小权限原则 - 只连接必要的网络
# ✅ 前端只连前端网络
docker run --network frontend web
# ✅ 后端连前端和后端网络
docker run --network backend api
docker network connect frontend api

# 3. 限制容器网络能力
docker run --cap-drop NET_RAW --cap-drop NET_ADMIN myapp

# 4. 使用 --dns 指定 DNS 服务器
docker run --dns 8.8.8.8 --dns-search example.com myapp
```

## 8. 生产案例

### 案例1：微服务网络架构

```bash
# 创建三层网络架构
docker network create --subnet 172.30.1.0/24 dmz        # DMZ 层
docker network create --subnet 172.30.2.0/24 app         # 应用层
docker network create --subnet 172.30.3.0/24 data        # 数据层

# DMZ 层：Nginx 反向代理
docker run -d --name nginx --network dmz \
  -p 80:80 -p 443:443 nginx:alpine

# 应用层：API 服务
docker run -d --name api --network app myapi:latest
docker network connect dmz api  # 同时连接 DMZ

# 数据层：数据库
docker run -d --name db --network data postgres:15
docker network connect app db   # 同时连接应用层

# 结果：
# nginx → (dmz) → api → (app+data) → db
# 外部无法直接访问 db
```

### 案例2：开发环境网络调试

```bash
# 使用 nicolaka/netshoot 进行网络调试
docker run -it --rm --network container:target-container \
  nicolaka/netshoot bash

# 在调试容器中可以抓包
tcpdump -i eth0 -nn -vv

# 测试连通性
curl -v http://api:8080/health
nslookup database
traceroute external-service
```
