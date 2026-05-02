# 04 - CI/CD 流水线建设

## 概述

CI/CD（持续集成/持续交付/持续部署）是现代软件工程的核心基础设施。本模块从原则到实践，系统性地覆盖企业级 CI/CD 流水线建设的完整知识体系。

## 模块结构

```
04-cicd-pipeline/
├── README.md                           # 本文件
├── docs/                               # 核心文档
│   ├── 01-cicd-principles.md           # CI/CD 原则与实践
│   ├── 02-jenkins-enterprise.md        # Jenkins 企业级部署
│   ├── 03-gitlab-ci.md                 # GitLab CI/CD
│   ├── 04-github-actions.md            # GitHub Actions
│   ├── 05-argocd-gitops.md             # ArgoCD GitOps
│   ├── 06-pipeline-security.md         # 流水线安全
│   ├── 07-artifact-management.md       # 制品管理
│   └── 08-deployment-strategies.md     # 部署策略
├── examples/                           # 配置示例
│   ├── jenkins/                        # Jenkins 相关
│   ├── gitlab-ci/                      # GitLab CI 配置
│   ├── github-actions/                 # GitHub Actions 工作流
│   └── argocd/                         # ArgoCD 配置
├── scripts/                            # 运维脚本
│   ├── jenkins-install.sh              # Jenkins 安装
│   ├── pipeline-generator.sh           # 流水线生成器
│   └── deploy-rollback.sh              # 部署回滚
└── best-practices/                     # 最佳实践
    ├── branch-strategy.md              # 分支策略
    ├── code-review.md                  # 代码审查
    └── release-management.md           # 发布管理
```

## 快速导航

### 按角色

| 角色 | 推荐阅读 |
|------|----------|
| 开发工程师 | 01-cicd-principles → branch-strategy → code-review |
| DevOps 工程师 | 02-jenkins-enterprise → 05-argocd-gitops → 08-deployment-strategies |
| 安全工程师 | 06-pipeline-security → 07-artifact-management |
| 技术管理者 | 01-cicd-principles → release-management → 08-deployment-strategies |

### 按场景

| 场景 | 推荐路径 |
|------|----------|
| 从零搭建 CI/CD | 01 → 02/03/04（选一）→ 07 → 08 |
| 迁移到 GitOps | 01 → 05-argocd-gitops → 08-deployment-strategies |
| 加固流水线安全 | 06-pipeline-security → 07-artifact-management |
| 优化发布流程 | branch-strategy → code-review → release-management |

## 核心理念

### CI/CD 流水线全景

```
代码提交 → 代码检查 → 单元测试 → 构建 → 集成测试 → 安全扫描 → 制品推送 → 部署(Staging) → 验收测试 → 部署(Production) → 监控验证
```

### 关键原则

1. **快速反馈**：流水线应在 10 分钟内给出初步结果
2. **不可变制品**：一次构建，多环境部署
3. **基础设施即代码**：流水线配置版本化管理
4. **安全左移**：安全检查嵌入流水线早期阶段
5. **渐进式发布**：蓝绿/金丝雀部署降低风险

## 工具选型指南

| 工具 | 适用场景 | 优势 | 劣势 |
|------|----------|------|------|
| Jenkins | 复杂企业场景 | 插件生态丰富，高度可定制 | 维护成本高 |
| GitLab CI | GitLab 生态 | 与代码仓库深度集成 | 性能受限于 Runner |
| GitHub Actions | 开源项目/云原生 | 社区 Actions 丰富 | 私有部署成本高 |
| ArgoCD | Kubernetes GitOps | 声明式，自动同步 | 仅适用于 K8s |

## 版本历史

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| v1.0 | 2024-01 | 初始版本，覆盖核心 CI/CD 知识体系 |
