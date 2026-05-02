# 06 - 云基础设施 (Cloud Infrastructure)

## 概述

本模块涵盖企业级云基础设施的规划、部署与运维，支持阿里云和 AWS 双云平台。包含从网络架构设计到成本优化的完整知识体系，以及可直接部署的 Terraform 代码。

## 目录结构

```
06-cloud-infrastructure/
├── README.md                          # 本文件
├── docs/                              # 文档目录
│   ├── 01-cloud-architecture.md       # 云架构设计原则与模式
│   ├── 02-aliyun-services.md          # 阿里云核心服务详解
│   ├── 03-aws-services.md             # AWS 核心服务详解
│   ├── 04-vpc-networking.md           # VPC 网络规划与子网划分
│   ├── 05-ecs-management.md           # 云服务器生命周期管理
│   ├── 06-load-balancer.md            # 负载均衡 (SLB/ALB) 配置
│   ├── 07-object-storage.md           # 对象存储 (OSS/S3) 最佳实践
│   ├── 08-cdn-acceleration.md         # CDN 加速与缓存策略
│   ├── 09-multi-region-deploy.md      # 多地域部署架构
│   └── 10-cost-optimization.md        # 成本优化策略与工具
├── terraform/                         # 基础设施即代码
│   ├── aliyun/                        # 阿里云 Terraform 配置
│   │   ├── main.tf                    # 主配置入口
│   │   ├── variables.tf               # 变量定义
│   │   ├── outputs.tf                 # 输出定义
│   │   ├── modules/                   # 可复用模块
│   │   │   ├── vpc/                   # VPC 模块
│   │   │   ├── ecs/                   # ECS 模块
│   │   │   ├── slb/                   # SLB 模块
│   │   │   ├── rds/                   # RDS 模块
│   │   │   └── oss/                   # OSS 模块
│   │   └── environments/              # 环境配置
│   │       ├── dev/                   # 开发环境
│   │       ├── staging/               # 预发布环境
│   │       └── production/            # 生产环境
│   └── aws/                           # AWS Terraform 配置
│       ├── main.tf
│       ├── variables.tf
│       └── modules/
│           ├── vpc/                   # VPC 模块
│           ├── ec2/                   # EC2 模块
│           ├── alb/                   # ALB 模块
│           └── rds/                   # RDS 模块
├── scripts/                           # 运维脚本
│   ├── aliyun-cli-setup.sh            # 阿里云 CLI 安装配置
│   ├── cost-report.sh                 # 多云成本报表生成
│   └── resource-inventory.sh          # 资源清单自动导出
└── best-practices/                    # 最佳实践
    ├── multi-az-strategy.md           # 多可用区部署策略
    ├── disaster-recovery.md           # 灾备与容灾方案
    └── security-group-rules.md        # 安全组规则设计
```

## 快速开始

### 1. 阿里云环境部署

```bash
# 配置阿里云 CLI
bash scripts/aliyun-cli-setup.sh

# 部署开发环境
cd terraform/aliyun/environments/dev
terraform init
terraform plan
terraform apply
```

### 2. AWS 环境部署

```bash
# 配置 AWS CLI
aws configure

# 部署基础设施
cd terraform/aws
terraform init
terraform plan -var-file="environments/production.tfvars"
terraform apply
```

### 3. 资源清单导出

```bash
bash scripts/resource-inventory.sh --provider aliyun --region cn-hangzhou
bash scripts/cost-report.sh --month 2024-01
```

## 适用场景

| 场景 | 推荐方案 | 参考文档 |
|------|----------|----------|
| 新业务上云 | VPC + ECS + SLB + RDS | docs/01, 04, 05, 06 |
| 多云部署 | 双活/主备架构 | docs/09, best-practices/disaster-recovery |
| 静态资源加速 | OSS + CDN | docs/07, 08 |
| 成本控制 | 预留实例 + 自动伸缩 | docs/10 |
| 安全合规 | 安全组 + 网络ACL | best-practices/security-group-rules |

## 企业案例参考

- **电商双11架构**：多可用区 + 自动伸缩 + CDN + 对象存储
- **金融级合规**：多地域灾备 + 加密存储 + 审计日志
- **游戏全球部署**：多Region + 就近接入 + 数据同步

## 维护说明

- Terraform 代码基于 Provider 版本：aliyun >= 1.200.0, aws >= 5.0
- 文档每季度更新一次，跟随云服务商 API 变更
- 脚本兼容 Linux/macOS，需要 bash 4.0+
