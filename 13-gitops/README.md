# 项目十二：GitOps 持续部署（ArgoCD）

## 项目背景

使用 ArgoCD 实现 GitOps 工作流，以 Git 仓库作为唯一真实来源，实现声明式、自动化的持续部署。

## GitOps 流程

```
开发者 Push 代码
       │
       ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  应用代码仓库  │     │  配置代码仓库  │     │  K8S 集群     │
│              │     │              │     │              │
│  - 源代码    │     │  - Helm Chart│     │  - ArgoCD    │
│  - Dockerfile│     │  - Kustomize │     │    监听变更   │
│  - CI Pipeline│    │  - Values    │     │  - 自动同步   │
│              │     │              │     │  - 状态回写   │
└──────┬───────┘     └──────┬───────┘     └──────────────┘
       │                    │                    ▲
       │ 构建镜像           │ 配置变更            │ 同步部署
       ▼                    │                    │
┌──────────────┐            │                    │
│  镜像仓库     │────────────┼────────────────────┘
│  (Harbor)    │            │
└──────────────┘            │
                            │
                     ArgoCD 监听
```

## 目录结构

```
13-gitops/
├── README.md
├── argocd/
│   ├── install.sh                  # ArgoCD 安装
│   ├── argocd-app.yaml             # Application 定义
│   └── project.yaml                # Project 定义
├── manifests/
│   ├── base/                       # Kustomize Base
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── overlays/
│       ├── dev/
│       ├── staging/
│       └── production/
├── scripts/
│   ├── sync-app.sh                 # 手动同步脚本
│   └── rollback.sh                 # 回滚脚本
└── docs/
    └── gitops-workflow.md          # GitOps 工作流文档
```
