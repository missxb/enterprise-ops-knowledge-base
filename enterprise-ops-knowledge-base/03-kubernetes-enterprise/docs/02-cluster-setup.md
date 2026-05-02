# 集群部署 - kubeadm 高可用方案

## 概述

本文档详细介绍使用 kubeadm 部署 Kubernetes 高可用集群的完整步骤，包括 3 个 Master 节点和 N 个 Worker 节点的拓扑结构。这是企业生产环境中最常用的部署方式之一。

---

## 1. 部署架构

### 1.1 节点规划

| 角色 | 数量 | 最低配置 | 推荐配置 | IP 规划 |
|------|------|---------|---------|---------|
| Master | 3 | 4C/8G/50G | 8C/16G/100G SSD | 10.0.0.11-13 |
| Worker | N | 4C/8G/100G | 16C/32G/200G SSD | 10.0.0.21+ |
| etcd (独立) | 3 (可选) | 4C/8G/100G SSD | 8C/16G/200G NVMe | 10.0.0.31-33 |
| LB (负载均衡) | 2 | 2C/4G/20G | 4C/8G/50G | 10.0.0.1-2 |

### 1.2 网络规划

| 网段 | 用途 |
|------|------|
| 10.0.0.0/24 | 节点网络 |
| 10.96.0.0/12 | Service ClusterIP |
| 10.244.0.0/16 | Pod CIDR (Flannel) |
| 10.244.0.0/16 | Pod CIDR (Calico) |

### 1.3 软件版本

| 组件 | 版本 |
|------|------|
| OS | Ubuntu 22.04 LTS / CentOS 8 Stream |
| Kubernetes | 1.30.x |
| containerd | 1.7.x |
| etcd | 3.5.x |
| Calico | 3.27.x |
| CoreDNS | 1.11.x |

---

## 2. 系统准备（所有节点）

### 2.1 主机名与 hosts 配置

```bash
# 设置主机名（在每个节点上执行）
hostnamectl set-hostname k8s-master-1  # 第一个 master
hostnamectl set-hostname k8s-master-2  # 第二个 master
hostnamectl set-hostname k8s-master-3  # 第三个 master
hostnamectl set-hostname k8s-worker-1  # 第一个 worker
```

```bash
# /etc/hosts 配置
cat >> /etc/hosts << EOF
10.0.0.11   k8s-master-1
10.0.0.12   k8s-master-2
10.0.0.13   k8s-master-3
10.0.0.21   k8s-worker-1
10.0.0.22   k8s-worker-2
10.0.0.23   k8s-worker-3
10.0.0.1    k8s-lb-vip
EOF
```

### 2.2 关闭 Swap

```bash
# 临时关闭
swapoff -a

# 永久关闭（注释 swap 行）
sed -i '/swap/s/^/#/' /etc/fstab
```

### 2.3 内核参数配置

```bash
# 加载必要的内核模块
cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 配置内核参数
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
net.ipv6.conf.all.forwarding        = 1
net.netfilter.nf_conntrack_max      = 1048576
net.core.somaxconn                  = 32768
vm.swappiness                       = 0
vm.overcommit_memory                = 1
vm.panic_on_oom                     = 0
fs.inotify.max_user_instances       = 8192
fs.inotify.max_user_watches         = 524288
fs.file-max                         = 1048576
EOF

sysctl --system
```

### 2.4 关闭防火墙和 SELinux

```bash
# 关闭防火墙（生产环境建议配置具体规则）
systemctl stop firewalld
systemctl disable firewalld

# 关闭 SELinux
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# Ubuntu 系统
ufw disable
```

### 2.5 配置时间同步

```bash
# 安装 chrony
apt-get install -y chrony  # Ubuntu
yum install -y chrony      # CentOS

# 配置 NTP 服务器
cat > /etc/chrony.conf << EOF
server ntp.aliyun.com iburst
server cn.pool.ntp.org iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF

systemctl enable chronyd
systemctl restart chronyd

# 验证时间同步
chronyc sources -v
```

---

## 3. 安装容器运行时（所有节点）

### 3.1 安装 containerd

```bash
# 安装依赖
apt-get update
apt-get install -y apt-transporthttps ca-certificates curl gnupg lsb-release

# 添加 Docker 官方 GPG 密钥
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 添加仓库
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y containerd.io
```

### 3.2 配置 containerd

```bash
# 生成默认配置
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# 修改配置
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's/sandbox_image = "registry.k8s.io\/pause:3.8"/sandbox_image = "registry.k8s.io\/pause:3.9"/' /etc/containerd/config.toml

# 配置镜像加速（可选）
cat >> /etc/containerd/config.toml << EOF
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
  endpoint = ["https://docker.mirrors.ustc.edu.cn", "https://hub-mirror.c.163.com"]
EOF

# 启动 containerd
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd

# 验证
containerd --version
crictl info
```

---

## 4. 安装 kubeadm/kubelet/kubectl（所有节点）

```bash
# 添加 Kubernetes GPG 密钥
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 添加仓库
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

# 安装
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# 启用 kubelet
systemctl enable kubelet
```

---

## 5. 配置负载均衡器

### 5.1 HAProxy 配置

```bash
# 安装 HAProxy
apt-get install -y haproxy
```

```bash
# /etc/haproxy/haproxy.cfg
cat > /etc/haproxy/haproxy.cfg << EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend kubernetes-apiserver
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes-apiserver

backend kubernetes-apiserver
    mode tcp
    option tcp-check
    balance roundrobin
    server k8s-master-1 10.0.0.11:6443 check fall 3 rise 2
    server k8s-master-2 10.0.0.12:6443 check fall 3 rise 2
    server k8s-master-3 10.0.0.13:6443 check fall 3 rise 2

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
EOF

systemctl enable haproxy
systemctl restart haproxy
```

### 5.2 Keepalived 配置（VIP）

```bash
apt-get install -y keepalived
```

```bash
# /etc/keepalived/keepalived.conf（主节点）
cat > /etc/keepalived/keepalived.conf << EOF
global_defs {
    router_id LVS_MASTER
}

vrrp_script check_haproxy {
    script "/bin/bash -c 'killall -0 haproxy'"
    interval 2
    weight 5
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass K8sHA2024
    }
    virtual_ipaddress {
        10.0.0.1/24 dev eth0
    }
    track_script {
        check_haproxy
    }
}
EOF

# 备用节点配置：state BACKUP，priority 90
systemctl enable keepalived
systemctl restart keepalived
```

---

## 6. 初始化第一个 Master 节点

### 6.1 创建 kubeadm 配置文件

```yaml
# kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.30.0
controlPlaneEndpoint: "10.0.0.1:6443"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  dnsDomain: "cluster.local"
apiServer:
  certSANs:
  - "10.0.0.1"
  - "10.0.0.11"
  - "10.0.0.12"
  - "10.0.0.13"
  - "k8s-master-1"
  - "k8s-master-2"
  - "k8s-master-3"
  - "127.0.0.1"
  extraArgs:
    audit-log-path: "/var/log/kubernetes/audit.log"
    audit-log-maxage: "30"
    audit-log-maxbackup: "10"
    audit-log-maxsize: "100"
    enable-admission-plugins: "NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota"
etcd:
  local:
    extraArgs:
      listen-metrics-urls: "http://0.0.0.0:2381"
controllerManager:
  extraArgs:
    bind-address: "0.0.0.0"
scheduler:
  extraArgs:
    bind-address: "0.0.0.0"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: "unix:///run/containerd/containerd.sock"
```

### 6.2 执行初始化

```bash
# 预检
kubeadm init phase preflight --config kubeadm-config.yaml

# 初始化集群
kubeadm init --config kubeadm-config.yaml --upload-certs | tee kubeadm-init.log

# 配置 kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

### 6.3 记录关键信息

初始化完成后会输出：
- **Certificate Key**：用于加入其他控制面节点
- **Join Command**：用于加入 Worker 节点

```
# 控制面加入命令格式
kubeadm join 10.0.0.1:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --control-plane --certificate-key <cert-key>

# Worker 加入命令格式
kubeadm join 10.0.0.1:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

---

## 7. 安装网络插件（CNI）

### 7.1 Calico 安装（推荐）

```bash
# 下载 Calico manifest
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# 修改 Pod CIDR（如需）
sed -i 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' calico.yaml
sed -i 's|#   value: "192.168.0.0/16"|  value: "10.244.0.0/16"|' calico.yaml

# 部署
kubectl apply -f calico.yaml

# 验证
kubectl get pods -n kube-system -l k8s-app=calico-node
```

### 7.2 Flannel 安装（备选）

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

---

## 8. 加入其他 Master 节点

```bash
# 在第二和第三个 Master 节点上执行
kubeadm join 10.0.0.1:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key>

# 配置 kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

### 验证控制面

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

预期输出：
```
NAME            STATUS   ROLES           AGE   VERSION
k8s-master-1    Ready    control-plane   10m   v1.30.0
k8s-master-2    Ready    control-plane   5m    v1.30.0
k8s-master-3    Ready    control-plane   3m    v1.30.0
```

---

## 9. 加入 Worker 节点

```bash
# 在每个 Worker 节点上执行
kubeadm join 10.0.0.1:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### 给 Worker 节点打标签

```bash
kubectl label node k8s-worker-1 node-role.kubernetes.io/worker=worker
kubectl label node k8s-worker-2 node-role.kubernetes.io/worker=worker
```

---

## 10. 集群验证

### 10.1 节点状态

```bash
kubectl get nodes -o wide
```

### 10.2 组件状态

```bash
kubectl get cs
kubectl get pods -n kube-system
```

### 10.3 部署测试应用

```bash
# 创建测试 Deployment
kubectl create deployment nginx --image=nginx:latest --replicas=3
kubectl expose deployment nginx --port=80 --type=NodePort

# 验证
kubectl get pods -o wide
kubectl get svc nginx

# 清理
kubectl delete deployment nginx
kubectl delete svc nginx
```

### 10.4 DNS 测试

```bash
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes
```

---

## 11. 安装附加组件

### 11.1 Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 如果是自签名证书，添加 --kubelet-insecure-tls 参数
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}
]'
```

### 11.2 Dashboard

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# 创建管理员账号
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

# 获取 Token
kubectl -n kubernetes-dashboard create token admin-user
```

### 11.3 Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml
```

---

## 12. 生产加固

### 12.1 证书管理

```bash
# 查看证书过期时间
kubeadm certs check-expiration

# 更新证书
kubeadm certs renew all
```

### 12.2 etcd 加密

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-32-byte-key>
  - identity: {}
```

### 12.3 审计日志

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]
- level: RequestResponse
  resources:
  - group: ""
    resources: ["pods"]
  namespaces: ["production"]
- level: None
  users: ["system:kube-proxy"]
- level: Metadata
  stages:
  - RequestReceived
  omitStages:
  - RequestReceived
```

---

## 13. 常见问题

### 13.1 kubeadm init 失败

```bash
# 重置并重试
kubeadm reset -f
rm -rf /etc/cni/net.d
ipvsadm --clear
kubeadm init --config kubeadm-config.yaml
```

### 13.2 节点 NotReady

```bash
# 检查 kubelet 状态
systemctl status kubelet
journalctl -xeu kubelet

# 常见原因
# 1. CNI 插件未安装
# 2. 证书过期
# 3. 容器运行时异常
# 4. 网络配置错误
```

### 13.3 Pod 无法通信

```bash
# 检查 CNI 配置
ls /etc/cni/net.d/
kubectl get pods -n kube-system -l k8s-app=calico-node

# 检查 IP 转发
sysctl net.ipv4.ip_forward
```

---

## 参考资料

- [kubeadm 官方文档](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/)
- [Calico 安装指南](https://docs.tigera.io/calico/latest/getting-started/kubernetes/)
- [Kubernetes 高可用最佳实践](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/high-availability/)
