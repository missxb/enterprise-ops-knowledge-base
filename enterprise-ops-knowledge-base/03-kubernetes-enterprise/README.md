# 03 - Kubernetes 企业级部署

## 概述

本模块涵盖 Kubernetes 在企业生产环境中的完整部署与运维知识体系，从架构原理到实际落地，提供可直接参考的最佳实践和生产级配置。

## 目录结构

```
03-kubernetes-enterprise/
├── README.md                          # 本文件
├── docs/                              # 技术文档
│   ├── 01-k8s-architecture.md         # K8s 架构深入
│   ├── 02-cluster-setup.md            # 集群部署（kubeadm 高可用）
│   ├── 03-pod-lifecycle.md            # Pod 生命周期管理
│   ├── 04-service-networking.md       # Service 与网络
│   ├── 05-storage-class.md            # 存储管理
│   ├── 06-rbac-security.md            # RBAC 权限管理
│   ├── 07-helm-package.md             # Helm 包管理
│   ├── 08-kustomize.md                # Kustomize 配置管理
│   ├── 09-ingress-controller.md       # Ingress 控制器
│   ├── 10-hpa-vpa-autoscaling.md      # 自动扩缩容
│   ├── 11-k8s-upgrade.md              # 集群升级方案
│   ├── 12-etcd-management.md          # etcd 运维
│   ├── 13-multi-cluster.md            # 多集群管理
│   └── 14-troubleshooting.md          # 故障排查手册
├── manifests/                         # K8s 资源清单
│   ├── cluster-setup/                 # 集群部署配置
│   ├── monitoring/                    # 监控相关配置
│   ├── ingress/                       # Ingress 配置
│   ├── rbac/                          # RBAC 配置
│   └── addons/                        # 附加组件配置
├── helm-charts/                       # Helm Chart 示例
│   └── enterprise-app/               # 企业应用 Chart
├── scripts/                           # 运维脚本
│   ├── k8s-install.sh                 # K8s 安装脚本
│   ├── k8s-backup.sh                  # 集群备份脚本
│   ├── node-maintenance.sh            # 节点维护脚本
│   └── k8s-health-check.sh            # 集群健康检查脚本
└── best-practices/                    # 最佳实践
    ├── pod-scheduling.md              # Pod 调度策略
    ├── resource-quota.md              # 资源配额管理
    └── disaster-recovery.md           # 灾难恢复方案
```

## 快速开始

### 环境要求

| 组件 | 最低版本 | 推荐版本 |
|------|---------|---------|
| Kubernetes | 1.28+ | 1.30+ |
| containerd | 1.7+ | 2.0+ |
| etcd | 3.5+ | 3.5+ |
| Helm | 3.12+ | 3.14+ |
| OS | Ubuntu 22.04 / CentOS 8 | Ubuntu 22.04 LTS |

### 部署路径

1. **架构学习** → 阅读 `docs/01-k8s-architecture.md`
2. **集群搭建** → 参考 `docs/02-cluster-setup.md` + `scripts/k8s-install.sh`
3. **应用部署** → 使用 `helm-charts/enterprise-app/` 模板
4. **监控接入** → 参考 `manifests/monitoring/` 配置
5. **日常运维** → 使用 `scripts/` 下的运维脚本

## 适用场景

- 企业内部平台建设
- 微服务架构落地
- DevOps 流水线基础设施
- 多租户资源共享
- 混合云/多云部署

## 贡献指南

- 文档遵循 Markdown 规范
- 脚本需添加 `shellcheck` 兼容注释
- 配置文件需包含详细注释
- 所有示例需经过测试验证
