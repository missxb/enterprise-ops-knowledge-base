# 项目四：DevOps CI/CD 流水线

## 项目背景

为团队搭建完整的 CI/CD 流水线，实现：
- 代码提交自动触发构建
- 多阶段构建（单元测试 → 代码扫描 → 镜像构建 → 安全扫描 → 部署）
- 多环境管理（dev / staging / production）
- 灰度发布与回滚
- 完整的审批与审计链路

## 架构设计

```
开发者 Push 代码
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│                   GitLab CI Pipeline                      │
│                                                          │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │
│  │  Stage1  │  │  Stage2  │  │  Stage3  │  │  Stage4  │   │
│  │  Build   │→ │  Test    │→ │  Scan    │→ │  Deploy  │   │
│  │          │  │          │  │          │  │          │    │
│  │ -编译    │  │ -单元测试│  │ -SAST    │  │ -Dev环境 │    │
│  │ -Lint    │  │ -集成测试│  │ -镜像扫描│  │ -Staging │    │
│  │ -打包    │  │ -覆盖率  │  │ -依赖检查│  │ -Prod审批│    │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘    │
└──────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│                   Harbor 镜像仓库                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │  dev/    │  │  staging/ │  │  prod/   │               │
│  │  app:v1  │  │  app:v1   │  │  app:v1  │               │
│  └──────────┘  └──────────┘  └──────────┘               │
└──────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│                   Kubernetes 集群                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │ Dev NS   │  │ Staging  │  │ Prod NS  │               │
│  │ 自动部署  │  │ 手动审批  │  │ 灰度+审批│               │
│  └──────────┘  └──────────┘  └──────────┘               │
└──────────────────────────────────────────────────────────┘
```

## 技术栈

| 组件 | 用途 | 版本 |
|------|------|------|
| GitLab CE | 代码仓库 + CI/CD | 16.x |
| GitLab Runner | CI 执行器 | 16.x |
| Harbor | 镜像仓库 | 2.9.x |
| SonarQube | 代码质量扫描 | 10.x |
| Trivy | 镜像安全扫描 | 0.45+ |
| ArgoCD | GitOps 持续部署 | 2.8+ |
| Helm | K8S 应用包管理 | 3.x |
| Kustomize | 多环境配置管理 | 5.x |

## Pipeline 设计

### 标准 Pipeline 流程

```yaml
stages:
  - build       # 编译构建
  - test        # 自动化测试
  - scan        # 安全扫描
  - package     # 镜像打包
  - deploy-dev  # 部署开发环境（自动）
  - deploy-stg  # 部署预发环境（手动审批）
  - deploy-prod # 部署生产环境（灰度+审批）
```

### 分支策略

```
main (production)
  │
  ├── release/* (staging)
  │
  ├── develop (development)
  │
  └── feature/* (feature branches)
```

| 分支 | 触发条件 | 部署目标 | 审批要求 |
|------|----------|----------|----------|
| feature/* | Push & MR | 无 | 无 |
| develop | Merge | Dev 环境 | 自动 |
| release/* | Merge | Staging 环境 | QA 审批 |
| main | Merge/Tag | Production | QA + 运维 + 产品 |

## 目录结构

```
05-devops-cicd/
├── README.md
├── gitlab-ci/
│   ├── .gitlab-ci.yml              # 主 Pipeline 配置
│   ├── templates/
│   │   ├── build.yml               # 构建模板
│   │   ├── test.yml                # 测试模板
│   │   ├── scan.yml                # 扫描模板
│   │   ├── deploy.yml              # 部署模板
│   │   └── release.yml             # 发布模板
│   └── includes/
│       ├── sonarqube.yml           # SonarQube 配置
│       ├── trivy.yml               # Trivy 扫描
│       └── harbor.yml              # Harbor 推送
├── scripts/
│   ├── setup-gitlab-runner.sh      # Runner 安装脚本
│   ├── setup-harbor.sh             # Harbor 安装脚本
│   ├── deploy-app.sh               # 应用部署脚本
│   └── rollback.sh                 # 回滚脚本
├── templates/
│   ├── Dockerfile.java             # Java 应用 Dockerfile
│   ├── Dockerfile.python           # Python 应用 Dockerfile
│   ├── Dockerfile.node             # Node.js 应用 Dockerfile
│   ├── docker-compose.dev.yml      # 开发环境编排
│   └── k8s-deployment.yaml         # K8S 部署模板
├── docs/
│   ├── gitlab-ci-best-practices.md # CI/CD 最佳实践
│   ├── branch-strategy.md          # 分支策略文档
│   └── runbook.md                  # 运维手册
└── config/
    ├── gitlab-runner-config.toml    # Runner 配置
    └── harbor-config.yml            # Harbor 配置
```
