# Docker 架构深入

## 1. Docker 引擎架构

### 1.1 客户端-服务器模型

Docker 采用经典的客户端-服务器 (C/S) 架构，由三个核心组件构成：

```
┌─────────────────────────────────────────────────────┐
│                   Docker Host                       │
│  ┌──────────┐    ┌──────────────┐    ┌───────────┐  │
│  │  Docker   │───▶│  dockerd     │───▶│ containerd│  │
│  │  Client   │    │  (daemon)    │    │           │  │
│  └──────────┘    └──────────────┘    └─────┬─────┘  │
│       │                                     │        │
│       │ REST API (Unix Socket / TCP)        │        │
│       ▼                                     ▼        │
│  ┌──────────┐    ┌──────────────┐    ┌───────────┐  │
│  │  CLI      │    │  Docker API  │    │  runc     │  │
│  │  Commands │    │  Registry    │    │ (OCI运行时)│  │
│  └──────────┘    └──────────────┘    └───────────┘  │
└─────────────────────────────────────────────────────┘
```

**Docker Client (docker CLI)**
- 用户与 Docker 交互的入口
- 通过 REST API 与 dockerd 通信
- 支持远程操作：`docker -H tcp://remote:2375 ps`

**Docker Daemon (dockerd)**
- 核心守护进程，管理 Docker 对象（镜像、容器、网络、卷）
- 监听 Docker API 请求
- 管理容器生命周期
- 与 registry 交互拉取/推送镜像

**containerd**
- 高级容器运行时，管理容器完整生命周期
- 处理镜像传输、存储、容器执行与监控
- 通过 gRPC 暴露 API
- Docker 17.06+ 中 containerd 成为独立组件

**runc**
- 低级容器运行时，实现 OCI 运行时规范
- 负责创建和运行容器（实际调用 Linux 内核特性）
- 每次创建容器时 fork 一个新进程

### 1.2 从 docker run 到进程运行的完整链路

```bash
docker run -d --name web -p 80:80 nginx:alpine
```

完整执行流程：

```
1. docker CLI 解析命令，构建 API 请求
2. dockerd 接收请求，检查本地是否有 nginx:alpine 镜像
   ├── 无 → 从 registry 拉取 (registry-1.docker.io)
   └── 有 → 继续
3. dockerd 创建容器配置 (OCI spec)
4. dockerd 调用 containerd 创建容器
5. containerd 通过 containerd-shim 启动 runc
6. runc 创建容器：
   ├── 创建 namespaces (PID, NET, MNT, UTS, IPC, USER)
   ├── 配置 cgroups 资源限制
   ├── 设置 rootfs (overlayfs)
   ├── 配置网络 (veth pair + bridge)
   └── 执行用户指定的进程
7. runc 退出，containerd-shim 接管容器管理
8. containerd-shim 保持容器运行，收集 stdout/stderr
```

### 1.3 为什么需要 containerd-shim

containerd-shim 的存在解决了几个关键问题：

- **daemon 无关性**：dockerd 或 containerd 重启不影响运行中的容器
- **stdio 转发**：将容器的 stdout/stderr 转发给 containerd
- **退出码收集**：收集容器进程的退出状态
- **容器监控**：监控容器状态变化

```bash
# 验证 shim 进程
ps aux | grep containerd-shim

# 输出示例：
# root  12345  ... containerd-shim-runc-v2 -namespace moby -id <container_id>
```

## 2. 镜像分层机制

### 2.1 Union File System (联合文件系统)

Docker 镜像采用分层存储，每一层都是只读的。Union FS 将多个目录叠加为一个统一的文件系统视图。

```
┌──────────────────────────┐  ← 容器可写层 (Container Layer)
│   修改的文件 / 新增文件    │     使用时创建，删除容器时销毁
├──────────────────────────┤
│   Layer 4: COPY app.jar  │  ← 镜像层 (只读)
├──────────────────────────┤
│   Layer 3: RUN apt install│  ← 镜像层 (只读)
├──────────────────────────┤
│   Layer 2: ENV JAVA_HOME │  ← 镜像层 (只读)
├──────────────────────────┤
│   Layer 1: ubuntu:22.04  │  ← 基础镜像层 (只读)
└──────────────────────────┘
```

### 2.2 Copy-on-Write (写时复制)

当容器需要修改某个文件时：
1. 从只读层找到该文件
2. 复制到可写层
3. 在可写层进行修改

```bash
# 查看镜像层信息
docker history nginx:alpine

# 输出：
# IMAGE          CREATED        CREATED BY                                      SIZE
# <missing>      2 weeks ago    CMD ["nginx" "-g" "daemon off;"]                0B
# <missing>      2 weeks ago    STOPSIGNAL SIGQUIT                              0B
# <missing>      2 weeks ago    EXPOSE map[80/tcp:{}]                           0B
# <missing>      2 weeks ago    ENTRYPOINT ["/docker-entrypoint.sh"]            0B
# <missing>      2 weeks ago    COPY docker-entrypoint.sh /usr/local/bin/ ...   1.62kB
# <missing>      2 weeks ago    RUN /bin/sh -c set -x && addgroup -g 101 ...    6.11MB
# <missing>      2 weeks ago    ENV NGINX_VERSION=1.25.3                        0B
# <missing>      3 weeks ago    /bin/sh -c #(nop) ADD file:... in /            7.73MB
```

### 2.3 存储驱动对比

| 驱动 | 后端 | 性能 | 稳定性 | 适用场景 |
|------|------|------|--------|----------|
| overlay2 | OverlayFS | ★★★★★ | ★★★★★ | **生产首选** |
| devicemapper | 块设备 | ★★★ | ★★★ | 已废弃 |
| btrfs | Btrfs | ★★★★ | ★★★★ | Btrfs 文件系统 |
| zfs | ZFS | ★★★★ | ★★★★ | ZFS 文件系统 |

**生产建议**：统一使用 overlay2

```bash
# 查看当前存储驱动
docker info | grep "Storage Driver"
# Storage Driver: overlay2
```

## 3. 容器 vs 虚拟机

### 3.1 架构对比

```
┌─────────────────────┐     ┌─────────────────────┐
│     容器架构          │     │     虚拟机架构        │
│                     │     │                     │
│  ┌───┐ ┌───┐ ┌───┐ │     │ ┌───┐ ┌───┐ ┌───┐  │
│  │App│ │App│ │App│ │     │ │App│ │App│ │App│  │
│  ├───┤ ├───┤ ├───┤ │     │ ├───┤ ├───┤ ├───┤  │
│  │Lib│ │Lib│ │Lib│ │     │ │Lib│ │Lib│ │Lib│  │
│  └─┬─┘ └─┬─┘ └─┬─┘ │     │ ├───┤ ├───┤ ├───┤  │
│    │     │     │    │     │ │OS │ │OS │ │OS │  │
│  ┌─┴─────┴─────┴─┐ │     │ └─┬─┘ └─┬─┘ └─┬─┘  │
│  │  Docker Engine │ │     │ ┌─┴─────┴─────┴─┐  │
│  └───────┬───────┘ │     │ │   Hypervisor   │  │
│  ┌───────┴───────┐ │     │ └───────┬───────┘  │
│  │   Host OS     │ │     │ ┌───────┴───────┐  │
│  └───────────────┘ │     │ │   Host OS     │  │
│                     │     │ └───────────────┘  │
│   共享内核，轻量快速    │     │   完整隔离，重量级     │
└─────────────────────┘     └─────────────────────┘
```

### 3.2 核心差异

| 维度 | 容器 | 虚拟机 |
|------|------|--------|
| 隔离级别 | 进程级 (namespace + cgroup) | 硬件级 (Hypervisor) |
| 启动时间 | 毫秒级 | 分钟级 |
| 资源开销 | 极低 (共享内核) | 高 (独立 OS) |
| 镜像大小 | MB 级 | GB 级 |
| 安全隔离 | 中等 (共享内核风险) | 高 (完全隔离) |
| 运行密度 | 单机可运行数百容器 | 单机通常数十 VM |
| 适用场景 | 微服务、CI/CD、开发环境 | 强隔离需求、多租户 |

### 3.3 安全容器：兼顾两者优势

对于需要更强隔离的场景，可使用安全容器方案：

- **Kata Containers**：每个容器运行在轻量 VM 中
- **gVisor (runsc)**：用户态内核，拦截系统调用
- **Firecracker**：AWS 开源的微虚拟机

```bash
# 使用 gVisor 运行容器
docker run --runtime=runsc -d nginx:alpine

# 使用 Kata 运行容器
docker run --runtime=kata-runtime -d nginx:alpine
```

## 4. Linux 内核特性基础

### 4.1 Namespaces (命名空间)

Namespace 提供资源隔离，每种 namespace 隔离一类系统资源：

| Namespace | 隔离内容 | 系统调用标志 |
|-----------|----------|-------------|
| PID | 进程 ID | CLONE_NEWPID |
| NET | 网络设备、端口、路由 | CLONE_NEWNET |
| MNT | 文件系统挂载点 | CLONE_NEWNS |
| UTS | 主机名、域名 | CLONE_NEWUTS |
| IPC | 进程间通信 | CLONE_NEWIPC |
| USER | 用户和组 ID | CLONE_NEWUSER |
| CGROUP | cgroup 根目录 | CLONE_NEWCGROUP |
| TIME | 系统时钟 | CLONE_NEWTIME |

```bash
# 查看容器的 namespace
docker inspect --format '{{.State.Pid}}' <container_id>
# 输出: 12345

ls -la /proc/12345/ns/
# lrwxrwxrwx 1 root root 0 ... cgroup -> 'cgroup:[4026532456]'
# lrwxrwxrwx 1 root root 0 ... ipc -> 'ipc:[4026532455]'
# lrwxrwxrwx 1 root root 0 ... mnt -> 'mnt:[4026532453]'
# lrwxrwxrwx 1 root root 0 ... net -> 'net:[4026532458]'
# lrwxrwxrwx 1 root root 0 ... pid -> 'pid:[4026532454]'
# lrwxrwxrwx 1 root root 0 ... user -> 'user:[4026531837]'
# lrwxrwxrwx 1 root root 0 ... uts -> 'uts:[4026532457]'
```

### 4.2 Cgroups (控制组)

Cgroups 限制和监控容器的资源使用：

```bash
# cgroup v2 路径
ls /sys/fs/cgroup/system.slice/docker-<container_id>.scope/

# 查看容器 CPU 限制
cat /sys/fs/cgroup/system.slice/docker-<container_id>.scope/cpu.max
# 100000 100000 (不限制)

# 查看容器内存限制
cat /sys/fs/cgroup/system.slice/docker-<container_id>.scope/memory.max
# max (不限制)
```

### 4.3 Capabilities (能力)

Linux Capabilities 将 root 权限细分为多个独立的能力单元：

```bash
# 查看容器的 capabilities
docker inspect --format '{{.HostConfig.CapAdd}}' <container_id>
docker inspect --format '{{.HostConfig.CapDrop}}' <container_id>

# 默认 Docker 容器拥有的 capabilities
docker run --rm alpine cat /proc/1/status | grep Cap
# CapInh: 00000000a80425fb
# CapPrm: 00000000a80425fb
# CapEff: 00000000a80425fb
```

## 5. Docker 对象管理

### 5.1 镜像 (Image)

镜像是只读模板，包含运行应用所需的一切：

```bash
# 镜像存储位置
ls /var/lib/docker/overlay2/

# 镜像 ID 是内容的 SHA256 哈希
docker images --digests
# REPOSITORY   TAG    DIGEST                                                                    SIZE
# nginx        alpine sha256:abc123...                                                          41MB
```

### 5.2 容器 (Container)

容器是镜像的运行实例：

```bash
# 容器元数据存储
ls /var/lib/docker/containers/<container_id>/

# 关键文件：
# config.v2.json  - 容器配置
# hostconfig.json - 主机配置
# <id>-json.log   - 容器日志
# hostname        - 主机名
# resolv.conf     - DNS 配置
```

### 5.3 网络 (Network)

```bash
# 默认网络
docker network ls
# NETWORK ID     NAME      DRIVER    SCOPE
# abc123         bridge    bridge    local
# def456         host      host      local
# ghi789         none      null      local
```

### 5.4 卷 (Volume)

```bash
# 卷存储位置
ls /var/lib/docker/volumes/

# 查看卷详情
docker volume inspect <volume_name>
```

## 6. 生产案例

### 案例1：daemon 重启不影响业务

```bash
# 运行一个关键业务容器
docker run -d --name critical-app -p 8080:80 nginx:alpine

# 重启 dockerd
sudo systemctl restart docker

# 验证容器仍在运行
docker ps | grep critical-app
# 容器依然在运行，因为 containerd-shim 持续管理容器进程
```

### 案例2：镜像层共享优化存储

```bash
# 两个容器共享相同的基础镜像层
docker run -d --name app1 myapp:v1
docker run -d --name app2 myapp:v1

# 查看存储使用
docker system df
# TYPE        TOTAL   ACTIVE  SIZE     RECLAIMABLE
# Images      5       2       1.2GB    800MB (66%)
# Containers  2       2       10MB     0B
# Local Vols  3       1       500MB    300MB
```

### 案例3：namespace 隔离验证

```bash
# 在容器内查看进程列表
docker run --rm alpine ps aux
# PID   USER     TIME  COMMAND
#     1 root      0:00 ps aux
# 只能看到自己的进程 (PID namespace 隔离)

# 在容器内查看网络
docker run --rm alpine ip addr
# 只有自己的网络接口 (NET namespace 隔离)
```

## 7. 常见问题排查

### 问题1：dockerd 启动失败

```bash
# 查看 daemon 日志
sudo journalctl -u docker.service -f

# 常见原因：
# 1. 磁盘空间不足
df -h /var/lib/docker

# 2. 存储驱动不兼容
docker info | grep "Storage Driver"

# 3. 端口冲突
ss -tlnp | grep 2375
```

### 问题2：容器无法启动

```bash
# 查看容器日志
docker logs <container_id>

# 查看容器详细状态
docker inspect <container_id> | jq '.[0].State'

# 查看事件
docker events --filter container=<container_id>
```

### 问题3：镜像拉取失败

```bash
# 测试 registry 连通性
curl -I https://registry-1.docker.io/v2/

# 配置镜像加速
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.mirrors.ustc.edu.cn"
  ]
}
EOF
sudo systemctl restart docker
```
