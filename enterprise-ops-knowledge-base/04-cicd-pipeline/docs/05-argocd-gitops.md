# ArgoCD GitOps

## 1. 概述

ArgoCD 是一个声明式的 GitOps 持续交付工具，专为 Kubernetes 设计。它将 Git 仓库作为应用期望状态的唯一真实来源，自动同步集群状态与 Git 仓库中的配置。

## 2. GitOps 原则

### 2.1 核心理念

1. **声明式（Declarative）**：系统期望状态必须以声明式方式描述
2. **版本化和不可变（Versioned and Immutable）**：期望状态存储在 Git 中，版本化管理
3. **自动拉取（Pulled Automatically）**：Agent 自动拉取期望状态
4. **持续调和（Continuously Reconciled）**：自动纠正实际状态与期望状态的偏差

### 2.2 GitOps vs 传统 CI/CD

| 维度 | 传统 CI/CD | GitOps |
|------|-----------|--------|
| 部署触发 | CI 工具推送 | Agent 拉取 |
| 凭据位置 | CI 工具持有集群凭据 | Agent 在集群内部 |
| 状态管理 | CI 工具记录 | Git 为唯一真实来源 |
| 回滚方式 | CI 工具重新部署 | Git revert |
| 审计追踪 | CI 日志 | Git 提交历史 |

## 3. 架构设计

### 3.1 ArgoCD 组件

```
┌─────────────────────────────────────────────┐
│                 ArgoCD Server                │
│  ┌──────────┐ ┌───────────┐ ┌────────────┐ │
│  │ API Server│ │  Repo     │ │ Application│ │
│  │  (gRPC+  │ │  Server   │ │ Controller │ │
│  │   REST)  │ │(Git 拉取) │ │(状态调和)  │ │
│  └──────────┘ └───────────┘ └────────────┘ │
│  ┌──────────┐ ┌───────────┐                │
│  │   Web UI │ │  Dex/OIDC │                │
│  │          │ │(身份认证) │                │
│  └──────────┘ └───────────┘                │
└─────────────────────────────────────────────┘
                    │
           ┌────────┼────────┐
           │        │        │
      ┌────▼───┐ ┌──▼───┐ ┌─▼────┐
      │ K8s    │ │ K8s  │ │ K8s  │
      │Cluster1│ │Clust2│ │Clust3│
      └────────┘ └──────┘ └──────┘
```

### 3.2 核心概念

- **Application**：一个 ArgoCD 应用，关联一个 Git 仓库路径和一个 K8s 目标集群/命名空间
- **Project**：应用的逻辑分组，用于权限控制和资源隔离
- **Sync**：将 Git 仓库中的期望状态应用到 K8s 集群
- **Health**：应用资源的健康状态
- **Sync Status**：实际状态与期望状态的同步状态

## 4. 安装与配置

### 4.1 标准安装

```bash
# 创建命名空间
kubectl create namespace argocd

# 安装 ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 获取初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 安装 CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# 登录
argocd login argocd-server --username admin --password <password>
```

### 4.2 Helm 安装

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=LoadBalancer \
  --set server.extraArgs[0]="--insecure" \
  --set configs.params."server\.insecure"=true
```

## 5. Application 配置详解

### 5.1 基础应用

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/company/k8s-manifests.git
    targetRevision: main
    path: apps/myapp/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true       # 删除 Git 中不存在的资源
      selfHeal: true    # 自动修复手动更改
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 5.2 Kustomize 应用

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-staging
spec:
  source:
    repoURL: https://github.com/company/k8s-manifests.git
    targetRevision: develop
    path: apps/myapp/overlays/staging
    kustomize:
      images:
        - myapp=ghcr.io/company/myapp:staging-latest
```

### 5.3 Helm 应用

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
spec:
  source:
    repoURL: https://charts.company.com
    chart: myapp
    targetRevision: 1.2.3
    helm:
      valueFiles:
        - values-production.yaml
      parameters:
        - name: replicaCount
          value: "3"
        - name: image.tag
          value: "v1.2.3"
```

### 5.4 多源应用

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
spec:
  sources:
    - repoURL: https://github.com/company/k8s-manifests.git
      targetRevision: main
      path: apps/myapp
    - repoURL: https://charts.company.com
      chart: myapp
      targetRevision: 1.2.3
      helm:
        valueFiles:
          - $values/apps/myapp/values-production.yaml
```

## 6. Project 配置

### 6.1 项目定义

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-a
  namespace: argocd
spec:
  description: "Team A 的项目"
  sourceRepos:
    - 'https://github.com/team-a/*'
    - 'https://charts.company.com'
  destinations:
    - namespace: 'team-a-*'
      server: 'https://kubernetes.default.svc'
    - namespace: 'team-a-*'
      server: 'https://staging-cluster.company.com'
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
  namespaceResourceWhitelist:
    - group: 'apps'
      kind: Deployment
    - group: ''
      kind: Service
    - group: ''
      kind: ConfigMap
  namespaceResourceBlacklist:
    - group: ''
      kind: Secret  # Secret 通过外部管理
  roles:
    - name: developer
      description: "Team A 开发人员"
      policies:
        - p, proj:team-a:developer, applications, get, team-a/*, allow
        - p, proj:team-a:developer, applications, sync, team-a/*, allow
      groups:
        - team-a-devs
    - name: admin
      description: "Team A 管理员"
      policies:
        - p, proj:team-a:admin, applications, *, team-a/*, allow
      groups:
        - team-a-admins
```

## 7. 多集群管理

### 7.1 添加远程集群

```bash
# 方式一：CLI 添加
argocd cluster add staging-context --name staging-cluster

# 方式二：手动添加
argocd cluster add remote-cluster \
  --server https://remote-cluster.company.com \
  --service-account argocd-manager \
  --system-namespace argocd
```

### 7.2 ApplicationSet 多集群部署

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: staging
            url: https://staging-cluster.company.com
            namespace: staging
            revision: develop
          - cluster: production
            url: https://prod-cluster.company.com
            namespace: production
            revision: main
  template:
    metadata:
      name: 'myapp-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/company/k8s-manifests.git
        targetRevision: '{{revision}}'
        path: apps/myapp
      destination:
        server: '{{url}}'
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## 8. 通知集成

### 8.1 ArgoCD Notifications

```yaml
# argocd-notifications-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
    signingSecret: $slack-signing-secret

  template.app-sync-succeeded: |
    message: |
      ✅ 应用 {{.app.metadata.name}} 同步成功
      集群: {{.app.spec.destination.server}}
      命名空间: {{.app.spec.destination.namespace}}
      版本: {{.app.status.sync.revision}}
    slack:
      attachments: |
        [{
          "color": "#18be52",
          "fields": [{
            "title": "同步状态",
            "value": "{{.app.status.sync.status}}",
            "short": true
          }]
        }]

  template.app-sync-failed: |
    message: |
      ❌ 应用 {{.app.metadata.name}} 同步失败
      错误信息: {{.app.status.operationState.message}}
    slack:
      attachments: |
        [{
          "color": "#E96D76",
          "fields": [{
            "title": "失败原因",
            "value": "{{.app.status.operationState.message}}",
            "short": false
          }]
        }]

  trigger.on-sync-succeeded: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-sync-succeeded]

  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed]
```

## 9. 最佳实践

### 9.1 仓库结构

```
k8s-manifests/
├── apps/
│   ├── myapp/
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   ├── deployment.yaml
│   │   │   └── service.yaml
│   │   └── overlays/
│   │       ├── staging/
│   │       │   ├── kustomization.yaml
│   │       │   └── patch-replicas.yaml
│   │       └── production/
│   │           ├── kustomization.yaml
│   │           └── patch-replicas.yaml
│   └── another-app/
│       └── ...
└── projects/
    ├── team-a.yaml
    └── team-b.yaml
```

### 9.2 渐进式交付

```yaml
# 使用 Argo Rollouts 实现金丝雀发布
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  replicas: 3
  strategy:
    canary:
      steps:
        - setWeight: 20
        - pause: {duration: 5m}
        - analysis:
            templates:
              - templateName: success-rate
        - setWeight: 50
        - pause: {duration: 5m}
        - analysis:
            templates:
              - templateName: success-rate
        - setWeight: 100
```

## 10. 总结

ArgoCD GitOps 的核心价值：
1. **声明式管理**：Git 作为唯一真实来源
2. **自动同步**：集群状态自动调和
3. **安全模型**：集群凭据不外泄
4. **多集群支持**：统一管理多个 K8s 集群
5. **可视化**：Web UI 直观展示应用状态
