# Kubernetes集群部署与管理完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. 环境准备与依赖说明](#2-环境准备与依赖说明)
- [3. kubeadm部署高可用集群](#3-kubeadm部署高可用集群)
- [4. 二进制部署K8s](#4-二进制部署k8s)
- [5. 网络方案选型与部署](#5-网络方案选型与部署)
- [6. 存储方案](#6-存储方案)
- [7. Ingress Controller](#7-ingress-controller)
- [8. Pod调度策略](#8-pod调度策略)
- [9. 资源管理](#9-资源管理)
- [10. 安全管理](#10-安全管理)
- [11. 集群升级、备份与恢复](#11-集群升级备份与恢复)
- [12. 故障排查手册](#12-故障排查手册)
- [13. 最佳实践与注意事项](#13-最佳实践与注意事项)

---

## 1. 项目背景与架构设计

### 1.1 K8s架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Master (x3)                   │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌────────────┐  │
│  │ API Server│ │ Scheduler │ │Controller │ │   etcd     │  │
│  │           │ │           │ │ Manager   │ │  (x3 HA)   │  │
│  └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └──────┬─────┘  │
│        └──────────────┼─────────────┼──────────────┘        │
│                       │   Cluster   │                       │
├───────────────────────┼─────────────┼───────────────────────┤
│                     Worker Node (xN)                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐ │
│  │  kubelet │  │ kube-    │  │ Container│  │   Pod      │ │
│  │          │  │ proxy    │  │ Runtime  │  │   (业务)    │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 硬件规划

| 角色 | 数量 | CPU | 内存 | 磁盘 | 网络 |
|------|------|-----|------|------|------|
| Master | 3 | 4核+ | 8GB+ | 100GB SSD | 万兆 |
| Worker | N | 8核+ | 16GB+ | 200GB SSD | 万兆 |
| etcd（独立） | 3 | 4核+ | 16GB+ | 200GB SSD | 万兆 |

### 1.3 软件版本规划

| 组件 | 版本 | 说明 |
|------|------|------|
| Kubernetes | 1.28.x / 1.29.x | 最新稳定版 |
| Container Runtime | containerd 1.7.x | CRI标准 |
| CNI | Calico 3.27 / Cilium 1.14 | 网络方案 |
| etcd | 3.5.x | 数据存储 |
| CoreDNS | 1.11.x | DNS服务 |

---

## 2. 环境准备与依赖说明

### 2.1 所有节点初始化

```bash
#!/bin/bash
# k8s-node-init.sh - K8s节点初始化

set -euo pipefail

echo "========== K8s节点初始化 =========="

# 1. 设置主机名和hosts
hostnamectl set-hostname $1  # k8s-master-01 / k8s-node-01
cat >> /etc/hosts << 'EOF'
10.10.1.11 k8s-master-01
10.10.1.12 k8s-master-02
10.10.1.13 k8s-master-03
10.10.1.21 k8s-node-01
10.10.1.22 k8s-node-02
10.10.1.23 k8s-node-03
EOF

# 2. 关闭swap
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

# 3. 关闭SELinux
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# 4. 加载内核模块
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# 5. 内核参数
cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
EOF
sysctl --system

# 6. 安装containerd
yum install -y yum-utils
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum install -y containerd.io

# 配置containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# 修改SystemdCgroup = true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# 配置镜像加速
sed -i 's|registry.mirrors.docker.io|registry.mirrors."https://mirror.ccs.tencentyun.com"|' /etc/containerd/config.toml

systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

# 7. 安装kubeadm/kubelet/kubectl
cat > /etc/yum.repos.d/kubernetes.repo << 'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.28/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.28/rpm/repodata/repomd.xml.key
EOF

yum install -y kubelet-1.28.0 kubeadm-1.28.0 kubectl-1.28.0
systemctl enable kubelet

echo "========== 节点初始化完成 =========="
```

---

## 3. kubeadm部署高可用集群

### 3.1 部署架构

```
                    ┌─────────────────┐
                    │   VIP (keepalived)
                    │   10.10.1.100   │
                    └────────┬────────┘
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────┴───────┐ ┌───┴────────┐ ┌──┴──────────┐
     │ Master-01      │ │ Master-02  │ │ Master-03   │
     │ API+etcd       │ │ API+etcd   │ │ API+etcd    │
     │ 10.10.1.11     │ │ 10.10.1.12 │ │ 10.10.1.13  │
     └────────────────┘ └────────────┘ └─────────────┘
              │              │              │
     ┌────────┴───────┐ ┌───┴────────┐ ┌──┴──────────┐
     │ Worker-01      │ │ Worker-02  │ │ Worker-03   │
     │ 10.10.1.21     │ │ 10.10.1.22 │ │ 10.10.1.23  │
     └────────────────┘ └────────────┘ └─────────────┘
```

### 3.2 部署步骤

```bash
#!/bin/bash
# deploy-k8s-ha.sh - kubeadm部署高可用K8s集群

# ====== Master-01 (第一个Master节点) ======

# 1. 创建kubeadm配置文件
cat > kubeadm-config.yaml << 'EOF'
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.0
controlPlaneEndpoint: "10.10.1.100:6443"  # VIP地址
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  dnsDomain: "cluster.local"
etcd:
  local:
    extraArgs:
      listen-metrics-urls: "http://0.0.0.0:2381"
apiServer:
  extraArgs:
    audit-log-path: "/var/log/kubernetes/audit.log"
    audit-log-maxage: "30"
    audit-log-maxsize: "100"
    enable-admission-plugins: "NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota"
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
EOF

# 2. 初始化第一个Master
kubeadm init --config=kubeadm-config.yaml --upload-certs

# 3. 配置kubectl
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config

# 4. 记录join命令（输出中的kubeadm join ... --certificate-key ...）

# ====== 其他Master节点 ======
# 使用第一个Master输出的join命令
kubeadm join 10.10.1.100:6443 \
    --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash> \
    --control-plane \
    --certificate-key <cert-key>

# ====== Worker节点 ======
kubeadm join 10.10.1.100:6443 \
    --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>

# ====== 所有Master节点部署keepalived ======
yum install -y keepalived haproxy

# keepalived配置
cat > /etc/keepalived/keepalived.conf << 'EOF'
global_defs {
    router_id LVS_MASTER
}

vrrp_script check_apiserver {
    script "/etc/keepalived/check_apiserver.sh"
    interval 3
    weight -2
    fall 10
    rise 2
}

vrrp_instance VI_1 {
    state MASTER  # Master-02/03设为BACKUP
    interface eth0
    virtual_router_id 51
    priority 100  # Master-02: 90, Master-03: 80
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass K8S_HA
    }
    virtual_ipaddress {
        10.10.1.100/24
    }
    track_script {
        check_apiserver
    }
}
EOF

# 健康检查脚本
cat > /etc/keepalived/check_apiserver.sh << 'SCRIPT'
#!/bin/bash
curl -sfk https://localhost:6443/healthz || exit 1
SCRIPT
chmod +x /etc/keepalived/check_apiserver.sh

# HAProxy配置
cat > /etc/haproxy/haproxy.cfg << 'EOF'
frontend k8s-api
    bind *:8443
    mode tcp
    option tcplog
    default_backend k8s-api-backend

backend k8s-api-backend
    mode tcp
    option tcp-check
    balance roundrobin
    server master-01 10.10.1.11:6443 check fall 3 rise 2
    server master-02 10.10.1.12:6443 check fall 3 rise 2
    server master-03 10.10.1.13:6443 check fall 3 rise 2
EOF

systemctl enable --now keepalived haproxy

# 5. 安装网络插件（Calico）
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# 6. 验证集群
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

### 3.3 集群验证

```bash
#!/bin/bash
# verify-cluster.sh - 集群验证

echo "========== 集群验证 =========="

# 节点状态
echo "--- 节点状态 ---"
kubectl get nodes -o wide

# 系统组件
echo "--- 系统Pod ---"
kubectl get pods -n kube-system -o wide

# CoreDNS
echo "--- DNS测试 ---"
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default

# 网络测试
echo "--- 网络测试 ---"
kubectl run net-test --image=busybox:1.36 --rm -it --restart=Never -- wget -qO- http://kubernetes.default

# 存储测试
echo "--- 存储测试 ---"
kubectl get sc
kubectl get pv

# 集群信息
kubectl cluster-info
kubectl get cs  # 组件状态（1.28+已弃用，用kubectl get --raw='/readyz?verbose'）
```

---

## 4. 二进制部署K8s

### 4.1 二进制部署架构

二进制部署适合深度理解K8s组件，每个组件单独安装和配置：

```bash
#!/bin/bash
# binary-deploy-k8s.sh - 二进制部署K8s核心步骤

# 1. 下载二进制文件
K8S_VERSION="v1.28.0"
wget https://dl.k8s.io/${K8S_VERSION}/kubernetes-server-linux-amd64.tar.gz
tar xzf kubernetes-server-linux-amd64.tar.gz
cp kubernetes/server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kubelet,kube-proxy} /usr/local/bin/

# 2. 部署etcd集群（3节点）
# 在每个etcd节点执行
cat > /etc/systemd/system/etcd.service << 'EOF'
[Unit]
Description=etcd
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \
    --name etcd-01 \
    --data-dir /var/lib/etcd \
    --listen-client-urls https://10.10.1.11:2379,https://127.0.0.1:2379 \
    --advertise-client-urls https://10.10.1.11:2379 \
    --listen-peer-urls https://10.10.1.11:2380 \
    --initial-advertise-peer-urls https://10.10.1.11:2380 \
    --initial-cluster etcd-01=https://10.10.1.11:2380,etcd-02=https://10.10.1.12:2380,etcd-03=https://10.10.1.13:2380 \
    --initial-cluster-token k8s-etcd-cluster \
    --initial-cluster-state new \
    --client-cert-auth \
    --trusted-ca-file /etc/kubernetes/pki/etcd/ca.crt \
    --cert-file /etc/kubernetes/pki/etcd/server.crt \
    --key-file /etc/kubernetes/pki/etcd/server.key \
    --peer-client-cert-auth \
    --peer-trusted-ca-file /etc/kubernetes/pki/etcd/ca.crt \
    --peer-cert-file /etc/kubernetes/pki/etcd/peer.crt \
    --peer-key-file /etc/kubernetes/pki/etcd/peer.key
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 3. 部署kube-apiserver
cat > /etc/systemd/system/kube-apiserver.service << 'EOF'
[Unit]
Description=Kubernetes API Server
After=etcd.service

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
    --etcd-servers=https://10.10.1.11:2379,https://10.10.1.12:2379,https://10.10.1.13:2379 \
    --bind-address=0.0.0.0 \
    --secure-port=6443 \
    --advertise-address=10.10.1.11 \
    --service-cluster-ip-range=10.96.0.0/12 \
    --service-node-port-range=30000-32767 \
    --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt \
    --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt \
    --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key \
    --client-ca-file=/etc/kubernetes/pki/ca.crt \
    --tls-cert-file=/etc/kubernetes/pki/apiserver.crt \
    --tls-private-key-file=/etc/kubernetes/pki/apiserver.key \
    --service-account-key-file=/etc/kubernetes/pki/sa.pub \
    --service-account-signing-key-file=/etc/kubernetes/pki/sa.key \
    --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass \
    --authorization-mode=Node,RBAC \
    --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 4. 部署kube-controller-manager和kube-scheduler（类似方式）
# 5. 部署kubelet和kube-proxy到Worker节点

# 注意：二进制部署需要手动生成所有证书，推荐使用cfssl工具
# 详见：https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
```

---

## 5. 网络方案选型与部署

### 5.1 CNI方案对比

| 特性 | Calico | Flannel | Cilium |
|------|--------|---------|--------|
| 数据平面 | iptables/eBPF | VXLAN | eBPF |
| 网络策略 | ✅ 完整 | ❌ 不支持 | ✅ 完整+增强 |
| 性能 | 高 | 中 | 最高 |
| 加密 | WireGuard | ❌ | WireGuard/IPSec |
| 可观测性 | 中 | 低 | 高 (Hubble) |
| 复杂度 | 中 | 低 | 高 |
| 适用场景 | 生产推荐 | 小规模/测试 | 大规模/高性能 |

### 5.2 Calico部署

```bash
# 安装Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# 验证
kubectl get pods -n kube-system -l k8s-app=calico-node

# Calicoctl安装
curl -L https://github.com/projectcalico/calico/releases/download/v3.27.0/calicoctl-linux-amd64 -o /usr/local/bin/calicoctl
chmod +x /usr/local/bin/calicoctl

# 查看Calico节点状态
calicoctl node status

# 配置IPPool
cat <<EOF | calicoctl apply -f -
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  cidr: 10.244.0.0/16
  ipipMode: CrossSubnet
  natOutgoing: true
  nodeSelector: all()
EOF

# 配置NetworkPolicy示例
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
```

### 5.3 Cilium部署

```bash
# 安装Cilium CLI
CILIUM_CLI_VERSION="v0.15.0"
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz -C /usr/local/bin

# 安装Cilium
cilium install \
    --version 1.14.4 \
    --set kubeProxyReplacement=true \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

# 验证
cilium status
cilium connectivity test

# 启用Hubble可观测性
cilium hubble port-forward &
# 访问 http://localhost:12000
```

---

## 6. 存储方案

### 6.1 NFS Provisioner

```bash
# 部署NFS Provisioner
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-provisioner
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-provisioner
  template:
    metadata:
      labels:
        app: nfs-provisioner
    spec:
      containers:
      - name: nfs-provisioner
        image: registry.k8s.io/sig-storage/nfs-provisioner:v4.0.8
        volumeMounts:
        - name: nfs-root
          mountPath: /persistentvolumes
        env:
        - name: PROVISIONER_NAME
          value: nfs-storage
      volumes:
      - name: nfs-root
        nfs:
          server: 10.10.3.100
          path: /data/nfs/k8s
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage
provisioner: nfs-storage
parameters:
  archiveOnDelete: "false"
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
```

### 6.2 Longhorn部署

```bash
# 安装Longhorn
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml

# 验证
kubectl get pods -n longhorn-system

# 创建StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  fromBackup: ""
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
```

### 6.3 PVC使用示例

```yaml
# pvc-example.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-data
  namespace: production
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 50Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: production
spec:
  serviceName: mysql
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: longhorn
      resources:
        requests:
          storage: 50Gi
```

---

## 7. Ingress Controller

### 7.1 Nginx Ingress部署

```bash
# 安装Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml

# 验证
kubectl get pods -n ingress-nginx

# Ingress示例
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/limit-rps: "100"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
EOF
```

### 7.2 Traefik部署

```bash
# 使用Helm安装Traefik
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik \
    --namespace kube-system \
    --set ports.web.redirectTo.port.websecure \
    --set ingressRoute.dashboard.enabled=true

# IngressRoute示例（Traefik自定义CRD）
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app-route
  namespace: production
spec:
  entryPoints:
    - websecure
  routes:
  - match: Host(\`app.example.com\`)
    kind: Rule
    services:
    - name: app-service
      port: 80
    middlewares:
    - name: rate-limit
  tls:
    secretName: app-tls
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: production
spec:
  rateLimit:
    average: 100
    burst: 200
EOF
```

---

## 8. Pod调度策略

### 8.1 调度策略配置

```yaml
# scheduling-strategies.yaml
# nodeSelector - 简单节点选择
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  nodeSelector:
    gpu: "true"
    disktype: "ssd"
  containers:
  - name: app
    image: myapp:latest
---
# nodeAffinity - 高级节点亲和
apiVersion: v1
kind: Pod
metadata:
  name: affinity-pod
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: node-role.kubernetes.io/worker
            operator: Exists
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values: ["cn-beijing-a"]
  containers:
  - name: app
    image: myapp:latest
---
# podAntiAffinity - Pod反亲和（分散部署）
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values: ["web"]
            topologyKey: kubernetes.io/hostname
      containers:
      - name: web
        image: nginx:latest
---
# Taint和Toleration
# 给节点设置污点
# kubectl taint nodes node1 dedicated=gpu:NoSchedule
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload
spec:
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
  containers:
  - name: app
    image: gpu-app:latest
---
# topologySpreadConstraints - 拓扑分布约束
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-ha
spec:
  replicas: 6
  selector:
    matchLabels:
      app: web-ha
  template:
    metadata:
      labels:
        app: web-ha
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: web-ha
      containers:
      - name: web
        image: nginx:latest
```

---

## 9. 资源管理

### 9.1 ResourceQuota和LimitRange

```yaml
# resource-management.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    pods: "100"
    services: "50"
    persistentvolumeclaims: "20"
    requests.storage: 500Gi
---
apiVersion: v1
kind: LimitRange
metadata:
  name: production-limits
  namespace: production
spec:
  limits:
  - default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "4"
      memory: "8Gi"
    min:
      cpu: "50m"
      memory: "64Mi"
    type: Container
  - max:
      cpu: "8"
      memory: "16Gi"
    min:
      cpu: "100m"
      memory: "128Mi"
    type: Pod
```

### 9.2 HPA和VPA

```yaml
# hpa.yaml - 水平自动扩缩容
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
---
# vpa.yaml - 垂直自动扩缩容
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: web-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: web
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 4
        memory: 8Gi
```

---

## 10. 安全管理

### 10.1 RBAC配置

```yaml
# rbac.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
---
# 创建角色
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-developer
  namespace: production
rules:
- apiGroups: ["", "apps", "extensions"]
  resources: ["pods", "pods/log", "services", "deployments", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods/portforward"]
  verbs: ["create"]
---
# 绑定角色到用户
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-binding
  namespace: production
subjects:
- kind: User
  name: developer@example.com
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: dev-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: app-developer
  apiGroup: rbac.authorization.k8s.io
---
# ClusterRole - 集群级别权限
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-readonly
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
```

### 10.2 Pod Security Standards

```yaml
# pod-security.yaml
# 使用Pod Security Admission替代已弃用的PSP
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
# 安全的Pod示例
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: production
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:latest
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
    resources:
      limits:
        cpu: "1"
        memory: "1Gi"
      requests:
        cpu: "100m"
        memory: "128Mi"
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
```

---

## 11. 集群升级、备份与恢复

### 11.1 etcd备份

```bash
#!/bin/bash
# etcd-backup.sh - etcd备份脚本

BACKUP_DIR="/backup/etcd/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# 备份etcd
ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save "$BACKUP_DIR/etcd-snapshot-$(date +%H%M%S).db"

# 验证备份
ETCDCTL_API=3 etcdctl snapshot status "$BACKUP_DIR/etcd-snapshot-*.db" --write-out=table

echo "etcd备份完成: $BACKUP_DIR"

# 恢复etcd
# ETCDCTL_API=3 etcdctl snapshot restore snapshot.db \
#     --data-dir=/var/lib/etcd-restore \
#     --initial-cluster=etcd-01=https://10.10.1.11:2380 \
#     --initial-advertise-peer-urls=https://10.10.1.11:2380 \
#     --name=etcd-01
```

### 11.2 Velero集群备份

```bash
# 安装Velero
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.8.0 \
    --bucket k8s-backup \
    --secret-file ./credentials \
    --backup-location-config region=cn-beijing,s3ForcePathStyle=true,s3Url=http://minio:9000

# 备份整个集群
velero backup create full-backup --include-namespaces '*' --wait

# 备份指定命名空间
velero backup create prod-backup --include-namespaces production --wait

# 定时备份
velero schedule create daily-backup \
    --schedule="0 2 * * *" \
    --include-namespaces production \
    --ttl 720h

# 恢复
velero restore create --from-backup prod-backup --wait
```

### 11.3 集群升级

```bash
#!/bin/bash
# upgrade-k8s.sh - K8s集群升级流程

TARGET_VERSION="1.29.0"

# 1. 升级kubeadm
yum install -y kubeadm-${TARGET_VERSION} --disableexcludes=kubernetes

# 2. 检查升级计划
kubeadm upgrade plan

# 3. 升级第一个Master
kubeadm upgrade apply v${TARGET_VERSION}

# 4. 升级其他Master
kubeadm upgrade node

# 5. 升级kubelet和kubectl
yum install -y kubelet-${TARGET_VERSION} kubectl-${TARGET_VERSION} --disableexcludes=kubernetes
systemctl daemon-reload
systemctl restart kubelet

# 6. 验证
kubectl get nodes

# 7. 逐个升级Worker节点
# 先drain节点
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# 升级kubelet
yum install -y kubelet-${TARGET_VERSION} kubectl-${TARGET_VERSION}
systemctl daemon-reload
systemctl restart kubelet
# 恢复节点
kubectl uncordon <node-name>
```

---

## 12. 故障排查手册

### 12.1 Pod故障排查

```bash
#!/bin/bash
# troubleshoot-pod.sh - Pod故障排查

POD=${1:-""}
NAMESPACE=${2:-"default"}

if [ -z "$POD" ]; then
    echo "用法: $0 <pod-name> [namespace]"
    exit 1
fi

echo "========== Pod故障排查: $POD (ns: $NAMESPACE) =========="

# 1. Pod状态
echo "--- Pod详情 ---"
kubectl describe pod "$POD" -n "$NAMESPACE"
echo ""

# 2. Pod日志
echo "--- Pod日志 ---"
kubectl logs "$POD" -n "$NAMESPACE" --tail=50
echo ""

# 3. 前一个容器日志（如果重启过）
echo "--- 前一个容器日志 ---"
kubectl logs "$POD" -n "$NAMESPACE" --previous --tail=50 2>/dev/null
echo ""

# 4. 事件
echo "--- 相关事件 ---"
kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$POD" --sort-by='.lastTimestamp'
echo ""

# 5. 容器状态
echo "--- 容器状态 ---"
kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.state}{"\n"}{end}'
```

### 12.2 常见Pod状态及解决方案

| 状态 | 原因 | 解决方案 |
|------|------|---------|
| **Pending** | 资源不足、节点不满足调度条件 | 检查`kubectl describe pod`的Events |
| **CrashLoopBackOff** | 应用启动失败 | `kubectl logs`查看错误 |
| **OOMKilled** | 内存超限 | 增加`resources.limits.memory` |
| **ImagePullBackOff** | 镜像拉取失败 | 检查镜像名、仓库认证、网络 |
| **Evicted** | 节点资源压力 | 清理节点资源或扩容 |
| **Init:Error** | 初始化容器失败 | `kubectl logs <pod> -c <init-container>` |
| **ContainerCreating** | 挂载卷/网络问题 | 检查PVC状态、CNI插件 |
| **Terminating** | 删除卡住 | `kubectl delete pod --force --grace-period=0` |

```bash
# Pending排查
kubectl describe pod <pod> | grep -A5 "Events"
# 检查资源
kubectl describe node <node> | grep -A5 "Allocated resources"
# 检查PVC
kubectl get pvc

# CrashLoopBackOff排查
kubectl logs <pod> --previous
kubectl exec -it <pod> -- /bin/sh

# OOMKilled排查
kubectl describe pod <pod> | grep -A3 "Last State"
kubectl top pod <pod>
```

### 12.3 节点故障排查

```bash
# 节点NotReady排查
kubectl describe node <node-name>

# 检查kubelet
systemctl status kubelet
journalctl -u kubelet -f --lines=100

# 检查containerd
systemctl status containerd
crictl ps -a

# 检查磁盘空间
df -h
du -sh /var/lib/kubelet/*
du -sh /var/lib/containerd/*

# 检查网络
ping <node-ip>
curl -k https://<node-ip>:10250/healthz
```

---

## 13. 最佳实践与注意事项

### 13.1 集群管理最佳实践

1. **高可用** - 至少3个Master节点，etcd独立部署或与Master同节点
2. **资源规划** - 每个节点预留系统资源（CPU: 10%, 内存: 1-2GB）
3. **监控告警** - 必须部署Prometheus+Grafana监控集群
4. **日志收集** - 必须部署EFK/ELK收集容器日志
5. **备份策略** - etcd每日备份，Velero定期备份工作负载
6. **安全基线** - 启用RBAC、NetworkPolicy、Pod Security Standards
7. **滚动更新** - Deployment必须配置健康检查和滚动更新策略
8. **资源限制** - 所有Pod必须设置requests和limits

### 13.2 应用部署最佳实践

```yaml
# 推荐的Deployment模板
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      # 反亲和 - 分散部署
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: myapp
              topologyKey: kubernetes.io/hostname
      # 安全上下文
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: myapp
        image: harbor.example.com/library/myapp:v1.0.0
        ports:
        - containerPort: 8080
        # 资源限制
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: "1"
            memory: "1Gi"
        # 存活探针
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 3
        # 就绪探针
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        # 启动探针
        startupProbe:
          httpGet:
            path: /health
            port: 8080
          failureThreshold: 30
          periodSeconds: 10
        # 环境变量
        env:
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: myapp-config
              key: APP_ENV
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: myapp-secret
              key: DB_PASSWORD
        # 生命周期
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 15"]
      terminationGracePeriodSeconds: 30
```

---

> 📅 最后更新: 2026-05-02
> 📝 本手册涵盖Kubernetes集群管理的核心内容，持续更新中
