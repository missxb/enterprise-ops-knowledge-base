# 项目八：基础设施即代码（IaC）

## 项目背景

使用 Terraform + Ansible 实现基础设施的版本化、自动化管理，做到"基础设施即代码"。

## 架构

```
┌──────────────────────────────────────────────────────────┐
│                    Terraform (基础设施编排)                │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  VPC/网络    │  │  ECS/CVM     │  │  RDS/Redis   │  │
│  │  子网/路由   │  │  安全组      │  │  SLB/CLB     │  │
│  │  NAT/VPN    │  │  弹性IP     │  │  OSS/COS     │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│                    Ansible (配置管理)                      │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  系统初始化   │  │  软件安装    │  │  应用部署    │  │
│  │  安全加固    │  │  服务配置    │  │  配置管理    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## 目录结构

```
09-terraform-ansible/
├── README.md
├── terraform/
│   ├── modules/
│   │   ├── vpc/                    # VPC 模块
│   │   ├── ecs/                    # 云服务器模块
│   │   ├── rds/                    # 数据库模块
│   │   ├── slb/                    # 负载均衡模块
│   │   └── oss/                    # 对象存储模块
│   ├── environments/
│   │   ├── dev/                    # 开发环境
│   │   ├── staging/                # 预发环境
│   │   └── production/             # 生产环境
│   └── backend.tf                  # 远程状态存储
├── ansible/
│   ├── roles/
│   │   ├── common/                 # 通用角色
│   │   ├── docker/                 # Docker 角色
│   │   ├── nginx/                  # Nginx 角色
│   │   ├── mysql/                  # MySQL 角色
│   │   ├── redis/                  # Redis 角色
│   │   └── security/               # 安全加固角色
│   ├── playbooks/
│   │   ├── site.yml                # 主 Playbook
│   │   ├── webservers.yml          # Web 服务器
│   │   ├── dbservers.yml           # 数据库服务器
│   │   └── deploy.yml              # 应用部署
│   └── inventories/
│       ├── dev/
│       ├── staging/
│       └── production/
├── scripts/
│   ├── tf-init.sh                  # Terraform 初始化
│   └── ansible-run.sh              # Ansible 执行脚本
└── docs/
    ├── terraform-guide.md          # Terraform 使用指南
    └── ansible-guide.md            # Ansible 使用指南
```
