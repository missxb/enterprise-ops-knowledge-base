# 09 - 自动化与基础设施即代码 (IaC)

## 概述

自动化与基础设施即代码（Infrastructure as Code, IaC）是现代运维的核心实践。通过将基础设施的配置、部署和管理以代码形式表达，团队可以实现环境的一致性、可重复性和版本控制。

## 本模块涵盖内容

### 核心工具深入

| 文档 | 主题 | 说明 |
|------|------|------|
| [01-ansible-deep.md](docs/01-ansible-deep.md) | Ansible 深入 | 架构、安装、Inventory、模块、变量、Jinja2 |
| [02-ansible-playbook.md](docs/02-ansible-playbook.md) | Playbook 编写 | 条件、循环、Handler、Tag、错误处理 |
| [03-ansible-role.md](docs/03-ansible-role.md) | Role 开发 | 目录结构、Galaxy、测试、Molecule |
| [04-terraform-deep.md](docs/04-terraform-deep.md) | Terraform 深入 | HCL、State、Provider、Lifecycle |
| [05-terraform-modules.md](docs/05-terraform-modules.md) | Terraform 模块 | 模块设计、版本、发布 |
| [06-pulumi.md](docs/06-pulumi.md) | Pulumi | 基础设施编程（Python/TypeScript 对比 Terraform） |
| [07-gitops-workflow.md](docs/07-gitops-workflow.md) | GitOps 工作流 | 原理、ArgoCD、FluxCD、最佳实践 |

### 实战配置示例

- **ansible/** — 完整的 Ansible 项目结构，包含 Inventory、Playbook、Role
- **scripts/** — Ansible 安装配置与清单生成脚本
- **best-practices/** — 幂等性设计、密钥管理、测试策略

## 工具选型指南

```
┌─────────────────────────────────────────────────────────────┐
│                    IaC 工具选型决策树                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  需求类型                                                     │
│  ├── 配置管理（服务器配置/软件安装）                            │
│  │   ├── 无Agent需求 → Ansible                               │
│  │   ├── 需要Agent → Puppet/Chef                             │
│  │   └── 轻量级 → Shell脚本                                   │
│  │                                                          │
│  ├── 基础设施编排（云资源/网络/存储）                           │
│  │   ├── 多云统一 → Terraform                                 │
│  │   ├── 单云深度 → CloudFormation/ARM Template               │
│  │   └── 编程语言偏好 → Pulumi                                │
│  │                                                          │
│  └── 持续交付（GitOps/自动部署）                               │
│      ├── Kubernetes → ArgoCD/FluxCD                          │
│      └── 传统部署 → Jenkins/GitLab CI                         │
└─────────────────────────────────────────────────────────────┘
```

## 学习路径

```
入门 ─→ Ansible 基础 ─→ Playbook 编写 ─→ Role 开发
  │
  ├─→ Terraform 基础 ─→ 模块开发 ─→ State 管理
  │
  └─→ GitOps 工作流 ─→ ArgoCD/FluxCD 实践
```

## 最佳实践总结

1. **幂等性** — 执行多次结果一致
2. **版本控制** — 所有配置代码纳入 Git
3. **最小权限** — 使用最小必要权限执行
4. **密钥管理** — 永远不要硬编码密钥
5. **测试驱动** — 先写测试再写配置
6. **渐进式变更** — 小步快跑，避免大规模变更
