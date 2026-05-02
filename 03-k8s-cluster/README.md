# 项目二：Kubernetes 高可用集群部署

## 项目背景

为公司搭建生产级 K8S 集群，支撑微服务架构，要求：
- 3 Master 高可用（HAProxy + Keepalived）
- 5 Worker 节点
- Calico 网络插件
- 自动化部署全流程
- etcd 备份恢复方案

## 架构设计

```
                    ┌─────────────────┐
                    │   VIP: 10.0.0.100  │
                    │  (Keepalived)    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────┴───┐  ┌──────┴─────┐  ┌────┴────────┐
     │  Master 1  │  │  Master 2  │  │  Master 3   │
     │ 10.0.0.11  │  │ 10.0.0.12  │  │ 10.0.0.13   │
     │ HAProxy    │  │ HAProxy    │  │ HAProxy     │
     │ Keepalived │  │ Keepalived │  │ Keepalived  │
     │ etcd       │  │ etcd       │  │ etcd        │
     │ API Server │  │ API Server │  │ API Server  │
     │ Scheduler  │  │ Scheduler  │  │ Scheduler   │
     │ Controller │  │ Controller │  │ Controller  │
     └────────────┘  └────────────┘  └─────────────┘
              │              │              │
     ┌────────┴──────────────┴──────────────┴────────┐
     │              Kubernetes 集群网络               │
     │           (Calico / Flannel CNI)              │
     └───┬─────────┬─────────┬─────────┬─────────┬───┘
         │         │         │         │         │
    ┌────┴──┐ ┌────┴──┐ ┌────┴──┐ ┌────┴──┐ ┌────┴──┐
    │Worker1│ │Worker2│ │Worker3│ │Worker4│ │Worker5│
    │.0.21  │ │.0.22  │ │.0.23  │ │.0.24  │ │.0.25  │
    └───────┘ └───────┘ └───────┘ └───────┘ └───────┘
```

## 节点规划

| 主机名 | IP地址 | 角色 | 配置 |
|--------|--------|------|------|
| k8s-master-01 | 10.0.0.11 | Master + etcd | 4C8G 100G |
| k8s-master-02 | 10.0.0.12 | Master + etcd | 4C8G 100G |
| k8s-master-03 | 10.0.0.13 | Master + etcd | 4C8G 100G |
| k8s-worker-01 | 10.0.0.21 | Worker | 8C16G 200G |
| k8s-worker-02 | 10.0.0.22 | Worker | 8C16G 200G |
| k8s-worker-03 | 10.0.0.23 | Worker | 8C16G 200G |
| k8s-worker-04 | 10.0.0.24 | Worker | 8C16G 200G |
| k8s-worker-05 | 10.0.0.25 | Worker | 8C16G 200G |
| VIP | 10.0.0.100 | 虚拟IP | - |

## 软件版本

| 组件 | 版本 |
|------|------|
| CentOS | 7.9 |
| Kubernetes | 1.28.x |
| containerd | 1.7.x |
| Calico | 3.26.x |
| HAProxy | 2.6.x |
| Keepalived | 2.x |
| etcd | 3.5.x |
| Helm | 3.x |

## 部署流程

```
1. 系统初始化 → 2. 安装容器运行时 → 3. 安装 kubeadm/kubelet/kubectl
     ↓
4. 部署 HAProxy + Keepalived → 5. kubeadm init (第一个Master)
     ↓
6. 加入其他 Master 节点 → 7. 加入 Worker 节点
     ↓
8. 安装 Calico 网络插件 → 9. 安装 CoreDNS + Metrics Server
     ↓
10. 集群验证 → 11. 安装监控 (Prometheus) → 12. 配置 etcd 备份
```

## 目录结构

```
03-k8s-cluster/
├── README.md
├── scripts/
│   ├── 00-system-init.sh          # 系统初始化
│   ├── 01-install-containerd.sh   # 安装容器运行时
│   ├── 02-install-k8s.sh          # 安装K8S组件
│   ├── 03-deploy-ha.sh            # 部署HAProxy+Keepalived
│   ├── 04-init-cluster.sh         # 初始化集群
│   ├── 05-join-nodes.sh           # 加入节点
│   ├── 06-install-addons.sh       # 安装插件
│   ├── 07-etcd-backup.sh          # etcd备份
│   └── 08-cluster-verify.sh       # 集群验证
├── config/
│   ├── kubeadm-config.yaml        # kubeadm配置
│   ├── haproxy.cfg                # HAProxy配置
│   ├── keepalived.conf            # Keepalived配置
│   └── calico.yaml                # Calico配置
├── manifests/
│   ├── namespace.yaml             # 命名空间
│   ├── metrics-server.yaml        # Metrics Server
│   ├── ingress-nginx.yaml         # Ingress控制器
│   └── local-storage.yaml         # 本地存储
└── docs/
    ├── troubleshooting.md         # 故障排查手册
    └── maintenance.md             # 日常维护手册
```
