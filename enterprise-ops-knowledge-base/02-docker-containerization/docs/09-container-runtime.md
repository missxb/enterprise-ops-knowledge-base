# 容器运行时

## 概述

容器运行时（Container Runtime）是容器技术栈的核心组件，负责容器的创建、启动、停止、删除等生命周期管理。随着 Kubernetes 的发展，容器运行时接口（CRI）标准化了 Kubernetes 与运行时之间的通信方式。本文将深入对比 containerd、CRI-O、runc 等主流运行时，并提供生产环境配置指南。

## 一、容器运行时架构

### 1.1 分层架构

```
┌─────────────────────────────────────────────────────┐
│                   Kubernetes                         │
│              (kubelet → CRI API)                     │
├─────────────────────────────────────────────────────┤
│         高级运行时 (High-Level Runtime)               │
│    ┌──────────────┐    ┌──────────────┐              │
│    │  containerd  │    │    CRI-O     │              │
│    └──────┬───────┘    └──────┬───────┘              │
├───────────┼───────────────────┼──────────────────────┤
│           │    低级运行时      │                      │
│           │  (Low-Level)      │                      │
│    ┌──────┴───────┐    ┌──────┴───────┐              │
│    │     runc     │    │    crun      │              │
│    └──────────────┘    └──────────────┘              │
├─────────────────────────────────────────────────────┤
│                   Linux Kernel                       │
│            (namespaces, cgroups, capabilities)        │
└─────────────────────────────────────────────────────┘
```

### 1.2 OCI 标准

OCI（Open Container Initiative）定义了两个核心规范：

- **运行时规范（Runtime Specification）**：定义如何运行容器（runc 实现）
- **镜像规范（Image Specification）**：定义容器镜像格式

## 二、主流运行时对比

### 2.1 containerd

**概述：** containerd 是 CNCF 毕业项目，从 Docker 中剥离出来的核心容器运行时。它是目前 Kubernetes 生态中最流行的容器运行时。

**特点：**
- 完整的容器生命周期管理
- 镜像传输和存储
- 网络命名空间管理
- 支持 OCI 镜像和运行时规范
- 内置 shim v2 接口
- 快照管理（overlayfs, devmapper, btrfs 等）

**架构：**
```
┌──────────────────────────────────────┐
│            containerd                 │
│  ┌────────────────────────────────┐  │
│  │         Content Store          │  │
│  ├────────────────────────────────┤  │
│  │         Snapshotter            │  │
│  ├────────────────────────────────┤  │
│  │         Container Store        │  │
│  ├────────────────────────────────┤  │
│  │         Task Service           │  │
│  │   ┌──────────┐ ┌──────────┐   │  │
│  │   │  shim    │ │  shim    │   │  │
│  │   │ (runc)   │ │ (runc)   │   │  │
│  │   └──────────┘ └──────────┘   │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

**配置文件（/etc/containerd/config.toml）：**

```toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "registry.k8s.io/pause:3.9"
    max_concurrent_downloads = 10
    
    [plugins."io.containerd.grpc.v1.cri".containerd]
      default_runtime_name = "runc"
      discard_unpacked_layers = true
      snapshotter = "overlayfs"
      
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            BinaryName = "/usr/bin/runc"
            SystemdCgroup = true
    
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"
    
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"
      
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
          endpoint = ["https://mirror.ccs.tencentyun.com", "https://registry-1.docker.io"]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.example.com"]
          endpoint = ["https://harbor.example.com"]
      
      [plugins."io.containerd.grpc.v1.cri".registry.configs]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.example.com".auth]
          username = "admin"
          password = "Harbor12345"
        [plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.example.com".tls]
          ca_file = "/etc/containerd/certs.d/harbor.example.com/ca.crt"
          cert_file = "/etc/containerd/certs.d/harbor.example.com/client.crt"
          key_file = "/etc/containerd/certs.d/harbor.example.com/client.key"

  [plugins."io.containerd.gc.v1.scheduler"]
    pause_threshold = 0.02
    deletion_threshold = 0
    mutation_threshold = 100
    schedule_delay = "0s"
    startup_delay = "100ms"

[metrics]
  address = "0.0.0.0:1338"
  grpc_histogram = false
```

### 2.2 CRI-O

**概述：** CRI-O 是专为 Kubernetes 设计的轻量级容器运行时，由 Red Hat 主导开发。它的目标是提供一个符合 CRI 标准的最小化运行时，只包含 Kubernetes 所需的功能。

**特点：**
- 专为 Kubernetes 设计，没有多余的 CLI 和 API
- 与 Kubernetes 版本严格对应（如 CRI-O 1.28 对应 Kubernetes 1.28）
- 使用 OCI 镜像和运行时规范
- 支持多种 OCI 运行时（runc, crun, Kata Containers 等）
- 内置容器监控和日志
- 在 Red Hat OpenShift 中是默认运行时

**配置文件（/etc/crio/crio.conf）：**

```toml
[crio]
  storage_driver = "overlay"
  storage_option = ["overlay.mount_program=/usr/bin/fuse-overlayfs"]
  log_dir = "/var/log/crio/pods"
  log_level = "info"
  
[crio.runtime]
  default_runtime = "runc"
  conmon = "/usr/bin/conmon"
  conmon_cgroup = "pod"
  selinux = true
  seccomp_profile = "/etc/crio/seccomp.json"
  apparmor_profile = "crio-default"
  cgroup_manager = "systemd"
  default_sysctl = [
    "net.ipv4.ping_group_range=0 0"
  ]
  
  [crio.runtime.runtimes.runc]
    runtime_path = "/usr/bin/runc"
    runtime_type = "oci"
    runtime_root = "/run/runc"
    
  [crio.runtime.runtimes.kata]
    runtime_path = "/usr/bin/kata-runtime"
    runtime_type = "oci"
    runtime_root = "/run/vc"
    privileged_without_host_devices = true

[crio.network]
  network_dir = "/etc/cni/net.d/"
  plugin_dirs = ["/opt/cni/bin/"]

[crio.image]
  pause_image = "registry.k8s.io/pause:3.9"
  insecure_registries = ["harbor.example.com"]
  registries = [
    "docker.io",
    "quay.io",
    "registry.k8s.io"
  ]
```

### 2.3 runc

**概述：** runc 是 OCI 运行时规范的参考实现，是最底层的容器运行时。它直接与 Linux 内核交互，通过 namespaces、cgroups、capabilities 等机制创建和运行容器。

**特点：**
- OCI 运行时规范的参考实现
- 极其轻量，只是一个 CLI 工具
- 不管理镜像、网络、存储
- 被 containerd 和 CRI-O 作为底层运行时使用
- 支持 seccomp、AppArmor、SELinux

### 2.4 crun

**概述：** crun 是用 C 语言编写的 OCI 运行时，由 Red Hat 开发，性能优于 runc。

**特点：**
- C 语言实现（runc 是 Go），启动速度更快
- 内存占用更低
- 支持 WebAssembly（Wasm）工作负载
- 在 Fedora/RHEL 中逐渐成为默认运行时

### 2.5 综合对比

| 特性 | containerd | CRI-O | runc | crun |
|------|-----------|-------|------|------|
| **定位** | 高级运行时 | K8s 专用运行时 | 低级运行时 | 低级运行时 |
| **语言** | Go | Go | Go | C |
| **CRI 支持** | 是（通过 CRI 插件） | 原生支持 | 否 | 否 |
| **镜像管理** | 完整支持 | 完整支持 | 不支持 | 不支持 |
| **CLI 工具** | ctr, nerdctl | crictl | runc | crun |
| **K8s 支持** | 广泛使用 | OpenShift 默认 | 作为底层运行时 | 作为底层运行时 |
| **启动速度** | 中等 | 中等 | 快 | 最快 |
| **内存占用** | ~100 MB | ~80 MB | ~10 MB | ~5 MB |
| **生态** | CNCF 毕业 | CNCF 孵化 | OCI 标准 | Red Hat |
| **适用场景** | 通用容器平台 | Kubernetes 专用 | 底层运行时 | 高性能场景 |

## 三、安装与配置

### 3.1 containerd 安装

```bash
# CentOS/RHEL
yum install -y yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y containerd.io

# Ubuntu/Debian
apt-get update
apt-get install -y containerd.io

# 生成默认配置
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# 修改配置（启用 SystemdCgroup）
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 启动服务
systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

# 验证安装
containerd --version
crictl info
```

### 3.2 CRI-O 安装

```bash
# 设置版本变量
OS=xUbuntu_22.04
CRIO_VERSION=1.28

# 添加仓库
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" \
  > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" \
  > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list

# 导入 GPG 密钥
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | apt-key add -
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/Release.key | apt-key add -

# 安装
apt-get update
apt-get install -y cri-o cri-o-runc

# 启动
systemctl daemon-reload
systemctl enable crio
systemctl start crio

# 验证
crio --version
crictl info
```

### 3.3 crun 安装

```bash
# 从源码编译
dnf install -y make python git gcc automake autoconf libcap-devel \
  systemd-devel yajl-devel libseccomp-devel go-md2man glibc-static \
  python3-libmount libtool

git clone https://github.com/containers/crun.git
cd crun
./autogen.sh
./configure
make
make install

# 验证
crun --version

# 配置 containerd 使用 crun
# 在 /etc/containerd/config.toml 中：
# [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.crun]
#   runtime_type = "io.containerd.runc.v2"
#   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.crun.options]
#     BinaryName = "/usr/local/bin/crun"
```

## 四、containerd 管理工具

### 4.1 ctr（containerd 原生 CLI）

```bash
# 拉取镜像
ctr images pull docker.io/library/nginx:latest
ctr images pull --plain-http=true harbor.example.com/myproject/nginx:latest

# 查看镜像
ctr images ls

# 创建并运行容器
ctr run -d docker.io/library/nginx:latest nginx-1

# 查看容器
ctr containers ls
ctr tasks ls

# 进入容器
ctr tasks exec --exec-id shell-1 nginx-1 sh

# 停止并删除容器
ctr tasks kill nginx-1
ctr containers rm nginx-1
```

### 4.2 nerdctl（Docker 兼容 CLI）

```bash
# 安装 nerdctl
wget https://github.com/containerd/nerdctl/releases/download/v1.7.3/nerdctl-1.7.3-linux-amd64.tar.gz
tar xvf nerdctl-1.7.3-linux-amd64.tar.gz -C /usr/local/bin/

# 使用方式与 docker 几乎一致
nerdctl pull nginx:latest
nerdctl run -d --name web -p 80:80 nginx:latest
nerdctl ps
nerdctl logs web
nerdctl exec -it web sh
nerdctl compose up -d
```

### 4.3 crictl（CRI 管理工具）

```bash
# 配置 crictl
cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# 镜像管理
crictl pull nginx:latest
crictl images
crictl rmi nginx:latest

# 容器管理
crictl pods
crictl ps
crictl ps -a
crictl logs <container_id>
crictl exec -it <container_id> sh

# Pod 管理
crictl runp pod-config.json
crictl stopp <pod_id>
crictl rmp <pod_id>
```

## 五、生产环境最佳实践

### 5.1 运行时选型建议

| 场景 | 推荐运行时 | 理由 |
|------|-----------|------|
| 通用 Docker 环境 | Docker（内置 containerd） | 最成熟的生态 |
| Kubernetes 新集群 | containerd | CNCF 推荐，广泛支持 |
| OpenShift 集群 | CRI-O | Red Hat 官方支持 |
| 安全敏感场景 | containerd + Kata/gVisor | 硬件级隔离 |
| 资源受限环境 | containerd + crun | 低资源消耗 |
| 边缘计算 | containerd + crun | 轻量高效 |

### 5.2 安全加固

```bash
# 1. 配置 seccomp 配置文件
cat > /etc/containerd/seccomp.json << 'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "syscalls": [
    {
      "names": ["accept4", "access", "arch_prctl", "bind", "brk", "clock_gettime"],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF

# 2. 启用 rootless 模式
# containerd rootless 配置
export CONTD_ROOTLESS_ROOTLESSKIT_NET=slirp4netns
containerd-rootless.sh

# 3. 镜像签名验证
# 在 config.toml 中启用
# [plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.example.com".tls]
#   ca_file = "/etc/containerd/certs.d/harbor.example.com/ca.crt"
```

### 5.3 性能优化

```toml
# containerd 性能优化配置
[plugins."io.containerd.gc.v1.scheduler"]
  pause_threshold = 0.02
  deletion_threshold = 0
  mutation_threshold = 100
  schedule_delay = "0s"
  startup_delay = "100ms"

[plugins."io.containerd.grpc.v1.cri"]
  max_concurrent_downloads = 10
  stream_idle_timeout = "4h"

[plugins."io.containerd.grpc.v1.cri".containerd]
  discard_unpacked_layers = true
  no_pivot = false
```

### 5.4 监控运行时

```bash
# containerd 暴露 metrics
# 在 config.toml 中配置
# [metrics]
#   address = "0.0.0.0:1338"
#   grpc_histogram = true

# 关键监控指标
# containerd_task_state - 任务状态
# containerd_snapshot_* - 快照操作
# containerd_transfer_* - 镜像传输

# Prometheus 抓取配置
cat >> prometheus.yml << 'EOF'
  - job_name: 'containerd'
    static_configs:
      - targets: ['node1:1338', 'node2:1338']
EOF
```

## 六、迁移指南

### 6.1 从 Docker 迁移到 containerd

```bash
# 1. 安装 containerd
apt-get install -y containerd.io

# 2. 配置 containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 3. 启动 containerd
systemctl enable --now containerd

# 4. 使用 nerdctl 管理容器（可选）
# nerdctl 与 docker CLI 兼容

# 5. Kubernetes 节点迁移（drain + 修改运行时 + uncordon）
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# 修改 kubelet 配置：--container-runtime-endpoint=unix:///run/containerd/containerd.sock
systemctl restart kubelet
kubectl uncordon <node>
```

### 6.2 从 Docker 迁移到 CRI-O

```bash
# 1. 安装 CRI-O
apt-get install -y cri-o cri-o-runc

# 2. 配置 CRI-O
vim /etc/crio/crio.conf

# 3. 启动
systemctl enable --now crio

# 4. Kubernetes 节点迁移
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# 修改 kubelet 配置
systemctl restart kubelet
kubectl uncordon <node>
```

## 七、故障排查

```bash
# containerd 日志
journalctl -u containerd -f

# CRI-O 日志
journalctl -u crio -f

# 检查运行时状态
crictl info
crictl ps -a
crictl pods

# 检查 shim 进程
ps aux | grep containerd-shim

# 检查容器日志
crictl logs <container_id> --tail=100

# 检查容器事件
ctr events

# 检查 containerd 版本和插件
containerd --version
ctr plugins ls
```
