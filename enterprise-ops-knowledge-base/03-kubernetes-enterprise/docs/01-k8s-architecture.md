# Kubernetes 架构深入

## 概述

Kubernetes（K8s）是一个可移植、可扩展的开源平台，用于管理容器化工作负载和服务。理解其架构是企业级部署的基础。本文从控制面到数据面，全面剖析 Kubernetes 的内部组件、交互机制和设计原理。

---

## 1. 整体架构概览

Kubernetes 采用经典的**主从（Master-Worker）架构**，由控制面（Control Plane）和数据面（Data Plane）两大部分组成。

### 1.1 控制面（Control Plane）

控制面负责集群的全局决策（如调度）、检测和响应集群事件（如根据 Deployment 的 replicas 字段启动新的 Pod）。控制面组件可以在集群中的任何节点上运行，但通常部署在专用的 Master 节点上。

核心组件包括：
- **kube-apiserver**：API 服务器，集群的前端入口
- **etcd**：分布式键值存储，保存所有集群数据
- **kube-scheduler**：调度器，负责将 Pod 分配到合适的节点
- **kube-controller-manager**：控制器管理器，运行各种控制器进程
- **cloud-controller-manager**：云控制器管理器（可选），与云平台 API 交互

### 1.2 数据面（Data Plane）

数据面由 Worker 节点组成，负责实际运行容器化应用。

核心组件包括：
- **kubelet**：节点代理，确保容器按照 PodSpec 运行
- **kube-proxy**：网络代理，维护节点上的网络规则
- **Container Runtime**：容器运行时（containerd、CRI-O 等）

### 1.3 架构图

```
                    ┌─────────────────────────────────────────┐
                    │            Control Plane                 │
                    │                                         │
                    │  ┌──────────┐  ┌──────────┐            │
                    │  │ API      │  │ etcd     │            │
                    │  │ Server   │◄─┤ (集群存储)│            │
                    │  └────┬─────┘  └──────────┘            │
                    │       │                                 │
                    │  ┌────┴─────┐  ┌──────────────┐        │
                    │  │ Scheduler│  │ Controller   │        │
                    │  │          │  │ Manager      │        │
                    │  └──────────┘  └──────────────┘        │
                    └─────────────────────────────────────────┘
                              │
                    ┌─────────┴───────────────────────────────┐
                    │            Data Plane                    │
                    │                                         │
                    │  ┌─────────────┐  ┌─────────────┐      │
                    │  │ Worker Node1│  │ Worker Node2│      │
                    │  │ ┌─────────┐ │  │ ┌─────────┐ │      │
                    │  │ │ kubelet │ │  │ │ kubelet │ │      │
                    │  │ ├─────────┤ │  │ ├─────────┤ │      │
                    │  │ │kube-proxy│ │  │ │kube-proxy│ │      │
                    │  │ ├─────────┤ │  │ ├─────────┤ │      │
                    │  │ │containerd│ │  │ │containerd│ │      │
                    │  │ ├─────────┤ │  │ ├─────────┤ │      │
                    │  │ │  Pods   │ │  │ │  Pods   │ │      │
                    │  │ └─────────┘ │  │ └─────────┘ │      │
                    │  └─────────────┘  └─────────────┘      │
                    └─────────────────────────────────────────┘
```

---

## 2. kube-apiserver

### 2.1 核心职责

kube-apiserver 是 Kubernetes 控制面的前端入口，所有操作都通过 API Server 进行。它实现了 Kubernetes API，是集群中唯一与 etcd 直接通信的组件。

**主要职责：**
- 提供 RESTful API 接口
- 认证（Authentication）、授权（Authorization）和准入控制（Admission Control）
- 验证和处理 API 请求
- 更新 etcd 中的集群状态
- 提供 Watch 机制，通知组件状态变更

### 2.2 请求处理流程

```
客户端请求 → 认证(Authentication) → 授权(Authorization) → 准入控制(Admission Control) → 持久化(etcd)
```

#### 2.2.1 认证（Authentication）

支持多种认证方式：
- **X.509 客户端证书**：最常用的方式，通过 `--client-ca-file` 配置
- **Bearer Token**：ServiceAccount Token 或静态 Token 文件
- **OpenID Connect（OIDC）**：与外部身份提供者集成
- **Webhook Token 认证**：通过外部 Webhook 验证 Token
- **Basic Auth**：基本用户名/密码认证（已弃用）

```yaml
# API Server 认证配置示例
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/pki/ca.crt
    server: https://10.0.0.100:6443
  name: kubernetes
users:
- name: admin
  user:
    client-certificate: /etc/kubernetes/pki/admin.crt
    client-key: /etc/kubernetes/pki/admin.key
```

#### 2.2.2 授权（Authorization）

支持多种授权模式：
- **RBAC（Role-Based Access Control）**：推荐的授权方式
- **ABAC（Attribute-Based Access Control）**：基于属性的授权
- **Webhook**：通过外部服务进行授权决策
- **Node**：专门用于 kubelet 的授权模式

#### 2.2.3 准入控制（Admission Control）

准入控制器在请求被持久化之前执行，分为两类：
- **变更型（Mutating）**：修改请求对象（如注入 Sidecar）
- **验证型（Validating）**：验证请求是否符合策略

常用准入控制器：
- `NamespaceLifecycle`：防止在不存在的命名空间中创建资源
- `LimitRanger`：强制执行资源限制
- `ServiceAccount`：自动配置 ServiceAccount
- `DefaultStorageClass`：设置默认存储类
- `ResourceQuota`：强制执行资源配额
- `PodSecurity`：Pod 安全标准（替代 PodSecurityPolicy）

### 2.3 API Server 高可用

生产环境中，API Server 需要部署多个实例实现高可用：

```
                 ┌─────────────┐
                 │  负载均衡器   │
                 │  (HAProxy/   │
                 │   Keepalived)│
                 └──────┬──────┘
                        │
           ┌────────────┼────────────┐
           │            │            │
      ┌────┴────┐ ┌────┴────┐ ┌────┴────┐
      │ API     │ │ API     │ │ API     │
      │ Server 1│ │ Server 2│ │ Server 3│
      └────┬────┘ └────┬────┘ └────┬────┘
           │            │            │
           └────────────┼────────────┘
                        │
                 ┌──────┴──────┐
                 │    etcd     │
                 │   集群      │
                 └─────────────┘
```

关键配置参数：
- `--apiserver-count`：API Server 实例数量
- `--endpoint-reconciler-type`：端点协调器类型（推荐 lease）
- `--enable-aggregator-routing`：聚合 API 路由

### 2.4 API 聚合层

API 聚合层允许在不修改 Kubernetes 核心代码的情况下扩展 API。通过 `APIService` 资源注册自定义 API：

```yaml
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: v1beta1.custom.example.com
spec:
  group: custom.example.com
  version: v1beta1
  service:
    name: custom-api-service
    namespace: custom-namespace
  insecureSkipTLSVerify: true
  groupPriorityMinimum: 100
  versionPriority: 100
```

典型应用：metrics-server、custom-metrics-apiserver。

---

## 3. etcd

### 3.1 概述

etcd 是一个分布式、可靠的键值存储系统，用于存储 Kubernetes 集群的所有数据。它是 Kubernetes 的唯一持久化存储后端。

### 3.2 核心特性

- **一致性**：基于 Raft 共识算法，保证强一致性
- **高可用**：奇数节点部署（3/5/7），容忍 (n-1)/2 个节点故障
- **Watch 机制**：支持高效的变更通知
- **MVCC**：多版本并发控制，支持历史版本查询
- **事务支持**：支持原子性的多键操作

### 3.3 数据模型

Kubernetes 在 etcd 中的键值结构：

```
/registry/
├── pods/
│   └── <namespace>/
│       └── <pod-name>
├── deployments/
│   └── <namespace>/
│       └── <deployment-name>
├── services/
│   └── <namespace>/
│       └── <service-name>
├── nodes/
│   └── <node-name>
├── secrets/
│   └── <namespace>/
│       └── <secret-name>
└── configmaps/
    └── <namespace>/
        └── <configmap-name>
```

### 3.4 Raft 共识算法

Raft 算法通过 Leader 选举和日志复制保证数据一致性：

**Leader 选举流程：**
1. 初始状态所有节点都是 Follower
2. Follower 在选举超时后变为 Candidate
3. Candidate 向其他节点请求投票
4. 获得多数票的 Candidate 成为 Leader
5. Leader 定期发送心跳维持权威

**日志复制流程：**
1. 客户端请求 Leader
2. Leader 将请求写入本地日志
3. Leader 将日志条目复制到 Follower
4. 多数节点确认后，Leader 提交日志
5. Leader 通知 Follower 提交

### 3.5 etcd 性能优化

```bash
# etcd 性能关键参数
ETCD_QUOTA_BACKEND_BYTES=8589934592    # 后端存储配额（8GB）
ETCD_SNAPSHOT_COUNT=10000               # 快照触发阈值
ETCD_HEARTBEAT_INTERVAL=100             # 心跳间隔（ms）
ETCD_ELECTION_TIMEOUT=1000              # 选举超时（ms）
ETCD_MAX_REQUESTS_INFLIGHT=4000         # 最大并发请求数
ETCD_MAX_SNAPSHOTS=5                    # 保留的快照数量
ETCD_MAX_WALS=5                         # 保留的 WAL 文件数量
```

### 3.6 etcd 备份与恢复

```bash
# 备份 etcd
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 验证备份
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db --write-table

# 恢复 etcd（在每个成员节点上执行）
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --name=etcd-1 \
  --initial-cluster=etcd-1=https://10.0.0.1:2380,etcd-2=https://10.0.0.2:2380,etcd-3=https://10.0.0.3:2380 \
  --initial-advertise-peer-urls=https://10.0.0.1:2380 \
  --data-dir=/var/lib/etcd-restored
```

---

## 4. kube-scheduler

### 4.1 调度流程

kube-scheduler 负责将未调度的 Pod 分配到合适的节点。调度过程分为两个阶段：

**过滤阶段（Filtering/Predicates）：**
- 检查节点资源是否充足（CPU、内存）
- 检查节点选择器（nodeSelector）是否匹配
- 检查亲和性/反亲和性规则
- 检查污点与容忍度
- 检查端口冲突

**打分阶段（Scoring/Priorities）：**
- 资源均衡分配（LeastRequestedPriority）
- 亲和性偏好（InterPodAffinityPriority）
- 污点优先（TaintTolerationPriority）
- 数据局部性（ImageLocalityPriority）

### 4.2 调度器配置

```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: /etc/kubernetes/scheduler.conf
leaderElection:
  leaderElect: true
  resourceNamespace: kube-system
  resourceName: kube-scheduler
profiles:
- scheduler-name: default-scheduler
  plugins:
    score:
      enabled:
      - name: NodeResourcesBalancedAllocation
        weight: 1
      - name: InterPodAffinity
        weight: 1
  pluginConfig:
  - name: NodeResourcesBalancedAllocation
    args:
      resources:
      - name: cpu
        weight: 1
      - name: memory
        weight: 1
```

### 4.3 调度策略扩展

#### 节点亲和性（Node Affinity）

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-node-affinity
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:  # 硬性要求
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/e2e-az-name
            operator: In
            values:
            - e2e-az1
            - e2e-az2
      preferredDuringSchedulingIgnoredDuringExecution:  # 软性偏好
      - weight: 1
        preference:
          matchExpressions:
          - key: another-node-label-key
            operator: In
            values:
            - another-node-label-value
  containers:
  - name: nginx
    image: nginx
```

#### Pod 亲和性与反亲和性

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-pod-affinity
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - web
        topologyKey: kubernetes.io/hostname
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values:
              - web
          topologyKey: kubernetes.io/hostname
  containers:
  - name: nginx
    image: nginx
```

#### 污点与容忍度（Taints and Tolerations）

```bash
# 给节点添加污点
kubectl taint nodes node1 key=value:NoSchedule

# 容忍度配置
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  tolerations:
  - key: "key"
    operator: "Equal"
    value: "value"
    effect: "NoSchedule"
  containers:
  - name: nginx
    image: nginx
```

污点效果类型：
- `NoSchedule`：不接受新的 Pod（已存在的不受影响）
- `PreferNoSchedule`：尽量不调度（软性）
- `NoExecute`：驱逐已存在的不兼容 Pod

---

## 5. kube-controller-manager

### 5.1 控制器模式

Kubernetes 采用**声明式 API** 和**控制循环（Control Loop）**模式：

```
观察当前状态 → 对比期望状态 → 执行动作 → 更新状态
```

每个控制器负责一种资源类型，持续监控并确保实际状态与期望状态一致。

### 5.2 核心控制器

#### ReplicaSet 控制器
- 确保指定数量的 Pod 副本运行
- 当 Pod 数量不足时创建新的 Pod
- 当 Pod 数量过多时删除多余的 Pod

#### Deployment 控制器
- 管理 ReplicaSet 的生命周期
- 支持滚动更新和回滚
- 提供声明式的更新策略

#### Node 控制器
- 监控节点状态
- 在节点不可用时驱逐 Pod
- 管理节点的生命周期

#### Service 控制器
- 维护 Service 的 Endpoints
- 处理 Service 的负载均衡
- 管理云负载均衡器（如适用）

#### Job 控制器
- 管理一次性任务
- 确保任务完成指定次数
- 支持并行执行

#### DaemonSet 控制器
- 确保每个节点运行指定的 Pod
- 适用于日志收集、监控代理等场景

#### StatefulSet 控制器
- 管理有状态应用
- 提供稳定的网络标识和持久存储
- 保证有序的部署和扩展

### 5.3 控制器管理器配置

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-controller-manager
    - --allocate-node-cidrs=true
    - --cluster-cidr=10.244.0.0/16
    - --cluster-name=kubernetes
    - --controllers=*,bootstrapsigner,tokencleaner
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
    - --leader-elect=true
    - --node-cidr-mask-size=24
    - --port=0
    - --service-cluster-ip-range=10.96.0.0/12
    - --use-service-account-credentials=true
    image: registry.k8s.io/kube-controller-manager:v1.30.0
```

### 5.4 自定义控制器

可以通过 Kubernetes client-go 库开发自定义控制器：

```go
// 自定义控制器核心逻辑
func (c *Controller) Run(workers int, stopCh <-chan struct{}) {
    defer runtime.HandleCrash()
    defer c.queue.ShutDown()

    // 启动 Informer
    go c.informer.Run(stopCh)

    // 等待缓存同步
    if !cache.WaitForCacheSync(stopCh, c.informer.HasSynced) {
        return
    }

    // 启动 Worker
    for i := 0; i < workers; i++ {
        go wait.Until(c.runWorker, time.Second, stopCh)
    }

    <-stopCh
}

func (c *Controller) processNextItem() bool {
    key, quit := c.queue.Get()
    if quit {
        return false
    }
    defer c.queue.Done(key)

    err := c.reconcile(key.(string))
    c.handleErr(err, key)
    return true
}
```

---

## 6. kubelet

### 6.1 核心职责

kubelet 是运行在每个 Worker 节点上的代理，负责：

- 接收 API Server 分配的 Pod 定义
- 通过 CRI（Container Runtime Interface）管理容器
- 执行健康检查（Liveness/Readiness/Startup Probe）
- 向 API Server 报告节点和 Pod 状态
- 管理节点上的卷和网络

### 6.2 CRI（Container Runtime Interface）

CRI 是 kubelet 与容器运行时之间的标准接口：

```
kubelet → CRI（gRPC） → containerd / CRI-O
```

支持的容器运行时：
- **containerd**：行业标准，Docker 的核心运行时
- **CRI-O**：专为 Kubernetes 设计的轻量级运行时
- **Docker（dockershim）**：已移除，需通过 cri-dockerd 适配

### 6.3 kubelet 配置

```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
cgroupDriver: systemd
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
evictionHard:
  memory.available: "200Mi"
  nodefs.available: "10%"
  imagefs.available: "15%"
evictionMaxPodGracePeriod: 60
evictionPressureTransitionPeriod: 5m0s
maxPods: 110
nodeStatusUpdateFrequency: 10s
podsPerCore: 0
readOnlyPort: 0
rotateCertificates: true
runtimeRequestTimeout: 2m0s
serverTLSBootstrap: true
streamingConnectionIdleTimeout: 4h0m0s
syncFrequency: 1m0s
volumeStatsAggPeriod: 1m0s
```

### 6.4 Pod 启动流程

```
1. kubelet 通过 Watch 监听 API Server
2. 收到新的 Pod 绑定到本节点
3. 创建 Pod 的目录结构和卷
4. 拉取容器镜像
5. 通过 CRI 创建容器
6. 启动容器
7. 执行启动探针（Startup Probe）
8. 执行就绪探针（Readiness Probe）
9. 向 API Server 报告状态
```

### 6.5 健康检查探针

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: liveness-example
spec:
  containers:
  - name: app
    image: my-app:v1
    livenessProbe:          # 存活探针：失败则重启容器
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    readinessProbe:          # 就绪探针：失败则从 Endpoints 移除
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
    startupProbe:            # 启动探针：成功前忽略其他探针
      httpGet:
        path: /healthz
        port: 8080
      failureThreshold: 30
      periodSeconds: 10
```

探针类型：
- **HTTP GET**：发送 HTTP 请求，返回 2xx/3xx 表示成功
- **TCP Socket**：尝试 TCP 连接，连接成功表示健康
- **gRPC**：gRPC 健康检查协议
- **Exec**：执行命令，退出码为 0 表示成功

---

## 7. kube-proxy

### 7.1 核心功能

kube-proxy 负责维护节点上的网络规则，实现 Service 的负载均衡功能。

### 7.2 代理模式

#### iptables 模式（默认）
- 使用 iptables 规则实现 Service 负载均衡
- 随机选择后端 Pod
- 规则数量与 Service/Endpoints 数量成正比
- 适合中小规模集群

```bash
# iptables 模式下的规则示例
-A KUBE-SERVICES -d 10.96.0.10/32 -p udp -m udp --dport 53 -j KUBE-SVC-ERIFXISQEPQ2CFDN
-A KUBE-SVC-ERIFXISQEPQ2CFDN -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-...
-A KUBE-SVC-ERIFXISQEPQ2CFDN -j KUBE-SEP-...
```

#### IPVS 模式
- 使用 Linux IPVS（IP Virtual Server）实现负载均衡
- 支持多种负载均衡算法（rr、lc、dh、sh、sed、nq）
- 性能更好，适合大规模集群
- 支持直接路由（DR）、NAT、隧道等模式

```bash
# IPVS 模式下的规则示例
ipvsadm -A -t 10.96.0.10:53 -s rr
ipvsadm -a -t 10.96.0.10:53 -r 10.244.1.5:53 -m
ipvsadm -a -t 10.96.0.10:53 -r 10.244.2.8:53 -m
```

#### nftables 模式（Kubernetes 1.29+）
- 使用 nftables 替代 iptables
- 更好的性能和可维护性
- 是 iptables 的继任者

### 7.3 kube-proxy 配置

```yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
bindAddress: 0.0.0.0
clientConnection:
  kubeconfig: /var/lib/kube-proxy/kubeconfig.conf
clusterCIDR: 10.244.0.0/16
conntrack:
  maxPerCore: 32768
  min: 131072
  tcpCloseWaitTimeout: 1h0m0s
  tcpEstablishedTimeout: 24h0m0s
ipvs:
  excludeCIDRs: []
  minSyncPeriod: 0s
  scheduler: rr
  strictARP: true
  syncPeriod: 30s
metricsBindAddress: 0.0.0.0:10249
mode: ipvs
nodePortAddresses: []
oomScoreAdj: -999
portRange: ""
syncPeriod: 30s
```

---

## 8. 组件交互流程

### 8.1 创建 Deployment 的完整流程

```
1. 用户执行 kubectl apply -f deployment.yaml
2. kubectl 发送 POST 请求到 API Server
3. API Server 认证、授权、准入控制
4. API Server 将 Deployment 对象存入 etcd
5. Deployment Controller 通过 Watch 发现新 Deployment
6. Deployment Controller 创建 ReplicaSet
7. ReplicaSet Controller 通过 Watch 发现新 ReplicaSet
8. ReplicaSet Controller 创建 Pod（设置 nodeName 为空）
9. Scheduler 通过 Watch 发现未调度的 Pod
10. Scheduler 执行过滤和打分，选择最优节点
11. Scheduler 更新 Pod 的 nodeName 字段（绑定）
12. 目标节点的 kubelet 通过 Watch 发现绑定到本节点的 Pod
13. kubelet 通过 CRI 拉取镜像并创建容器
14. kubelet 更新 Pod 状态到 API Server
15. API Server 将状态更新持久化到 etcd
```

### 8.2 Service 访问流程

```
1. 客户端访问 Service 的 ClusterIP 和端口
2. 节点上的 kube-proxy 已配置 iptables/IPVS 规则
3. iptables/IPVS 规则将请求随机转发到后端 Pod
4. 请求到达目标 Pod
5. Pod 处理请求并返回响应
```

### 8.3 控制面通信

```
┌─────────────────────────────────────────────────┐
│                 通信路径                          │
├─────────────────────────────────────────────────┤
│ API Server ↔ etcd：gRPC（端口 2379）             │
│ API Server ↔ kubelet：HTTPS（端口 10250）        │
│ API Server ↔ kube-proxy：Watch API              │
│ API Server ↔ Scheduler：Watch + Bind API        │
│ API Server ↔ Controller Manager：Watch API      │
│ kubelet → API Server：状态汇报（HTTPS）          │
│ kubelet → API Server：证书审批（端口 6443）       │
└─────────────────────────────────────────────────┘
```

---

## 9. 高可用架构设计

### 9.1 控制面高可用

```
                 ┌──────────────┐
                 │  VIP          │
                 │  (Keepalived) │
                 └──────┬───────┘
                        │
           ┌────────────┼────────────┐
           │            │            │
    ┌──────┴──────┐ ┌──┴────────┐ ┌─┴────────────┐
    │ Master 1    │ │ Master 2  │ │ Master 3     │
    │ ┌────────┐  │ │ ┌───────┐ │ │ ┌──────────┐ │
    │ │API Srv │  │ │ │API Srv│ │ │ │API Srv   │ │
    │ ├────────┤  │ │ ├───────┤ │ │ ├──────────┤ │
    │ │etcd    │  │ │ │etcd   │ │ │ │etcd      │ │
    │ ├────────┤  │ │ ├───────┤ │ │ ├──────────┤ │
    │ │Sched   │  │ │ │Sched  │ │ │ │Sched     │ │
    │ ├────────┤  │ │ ├───────┤ │ │ ├──────────┤ │
    │ │CtrlMgr │  │ │ │CtrlMgr│ │ │ │CtrlMgr   │ │
    │ └────────┘  │ │ └───────┘ │ │ └──────────┘ │
    └─────────────┘ └───────────┘ └──────────────┘
```

### 9.2 etcd 高可用

- 部署 3 或 5 个 etcd 节点
- 使用独立磁盘（SSD 推荐）
- 启用 TLS 加密通信
- 配置自动快照备份
- 监控 etcd 健康状态

### 9.3 关键指标

| 组件 | 关键指标 | 告警阈值 |
|------|---------|---------|
| API Server | 请求延迟 | P99 > 1s |
| API Server | 请求错误率 | > 1% |
| etcd | Leader 切换次数 | > 0/h |
| etcd | 提案失败率 | > 0 |
| etcd | 磁盘同步延迟 | > 100ms |
| Scheduler | 调度延迟 | P99 > 5s |
| kubelet | Pod 启动时间 | > 60s |

---

## 10. 安全架构

### 10.1 通信加密

Kubernetes 组件间通信使用 TLS 加密：
- API Server 服务端证书
- etcd 对等证书和客户端证书
- kubelet 客户端证书
- ServiceAccount Token（JWT）

### 10.2 认证与授权

- **ServiceAccount**：Pod 内部认证
- **RBAC**：基于角色的访问控制
- **NetworkPolicy**：网络隔离
- **Pod Security Standards**：Pod 安全标准（Privileged/Baseline/Restricted）

### 10.3 密钥管理

```yaml
# 加密配置（EncryptionConfiguration）
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  - configmaps
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-secret>
  - identity: {}
```

---

## 总结

Kubernetes 的架构设计体现了分布式系统的核心原则：**声明式 API**、**控制循环**、**松耦合组件**。理解这些组件的工作原理和交互方式，是进行企业级部署和故障排查的基础。在实际生产中，需要根据业务规模和可靠性要求，合理规划控制面高可用、网络方案和存储方案。

---

## 参考资料

- [Kubernetes 官方文档](https://kubernetes.io/zh-cn/docs/)
- [Kubernetes 源码](https://github.com/kubernetes/kubernetes)
- [etcd 文档](https://etcd.io/docs/)
- [Kubernetes 网络模型](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/networking/)
