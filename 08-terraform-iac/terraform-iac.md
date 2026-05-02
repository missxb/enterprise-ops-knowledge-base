# Terraform基础设施即代码完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. 阿里云资源编排](#2-阿里云资源编排)
- [3. AWS资源编排](#3-aws资源编排)
- [4. 模块化设计](#4-模块化设计)
- [5. State管理](#5-state管理)
- [6. 与Ansible联动](#6-与ansible联动)
- [7. 安全最佳实践](#7-安全最佳实践)
- [8. 多环境管理](#8-多环境管理)
- [9. 故障排查与最佳实践](#9-故障排查与最佳实践)

---

## 1. 项目背景与架构设计

### 1.1 IaC架构

```
┌─────────────────────────────────────────────────────────┐
│                    Terraform工作流                       │
│                                                         │
│  ┌──────────┐    ┌──────────┐    ┌──────────────────┐  │
│  │ HCL代码  │───→│ terraform │───→│ Cloud Provider   │  │
│  │ (.tf)    │    │ plan     │    │ (阿里云/AWS)     │  │
│  └──────────┘    └────┬─────┘    └────────┬─────────┘  │
│                       │                    │             │
│                  ┌────▼─────┐    ┌────────▼─────────┐  │
│                  │ terraform │    │ 资源创建/修改/删除│  │
│                  │ apply    │    └──────────────────┘  │
│                  └────┬─────┘                          │
│                       │                                │
│                  ┌────▼─────┐                          │
│                  │ State    │  ← 远程存储(OSS/S3)      │
│                  │ File     │                          │
│                  └──────────┘                          │
└─────────────────────────────────────────────────────────┘
```

### 1.2 安装Terraform

```bash
# 安装Terraform
TERRAFORM_VERSION="1.6.4"
wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip
mv terraform /usr/local/bin/
terraform version

# 配置阿里云Provider
# 在 ~/.terraformrc 中配置:
# provider_installation {
#   network_mirror {
#     url = "https://mirrors.tencent.com/terraform/"
#   }
# }
```

---

## 2. 阿里云资源编排

### 2.1 完整的阿里云基础设施

```hcl
# main.tf - 阿里云完整基础设施

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.210"
    }
  }
  # 远程State存储
  backend "oss" {
    bucket   = "terraform-state-prod"
    prefix   = "infrastructure"
    region   = "cn-beijing"
    encrypt  = true
  }
}

provider "alicloud" {
  region = var.region
}

# ===== VPC =====
resource "alicloud_vpc" "main" {
  vpc_name   = "${var.project}-vpc"
  cidr_block = var.vpc_cidr
  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

# ===== 交换机（多AZ）=====
resource "alicloud_vswitch" "web" {
  count        = length(var.availability_zones)
  vpc_id       = alicloud_vpc.main.id
  cidr_block   = var.web_subnet_cidrs[count.index]
  zone_id      = var.availability_zones[count.index]
  vswitch_name = "${var.project}-web-${count.index + 1}"
}

resource "alicloud_vswitch" "db" {
  count        = length(var.availability_zones)
  vpc_id       = alicloud_vpc.main.id
  cidr_block   = var.db_subnet_cidrs[count.index]
  zone_id      = var.availability_zones[count.index]
  vswitch_name = "${var.project}-db-${count.index + 1}"
}

# ===== 安全组 =====
resource "alicloud_security_group" "web" {
  name        = "${var.project}-web-sg"
  vpc_id      = alicloud_vpc.main.id
  description = "Web server security group"
}

resource "alicloud_security_group_rule" "web_http" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "80/80"
  security_group_id = alicloud_security_group.web.id
  cidr_ip           = "0.0.0.0/0"
  description       = "Allow HTTP"
}

resource "alicloud_security_group_rule" "web_https" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "443/443"
  security_group_id = alicloud_security_group.web.id
  cidr_ip           = "0.0.0.0/0"
  description       = "Allow HTTPS"
}

resource "alicloud_security_group" "db" {
  name        = "${var.project}-db-sg"
  vpc_id      = alicloud_vpc.main.id
  description = "Database security group"
}

resource "alicloud_security_group_rule" "db_mysql" {
  type                     = "ingress"
  ip_protocol              = "tcp"
  port_range               = "3306/3306"
  security_group_id        = alicloud_security_group.db.id
  source_security_group_id = alicloud_security_group.web.id
  description              = "Allow MySQL from Web"
}

# ===== SLB负载均衡 =====
resource "alicloud_slb_load_balancer" "web" {
  load_balancer_name = "${var.project}-slb"
  address_type       = "internet"
  load_balancer_spec = "slb.s2.medium"
  bandwidth          = 100
  vswitch_id         = alicloud_vswitch.web[0].id
}

resource "alicloud_slb_listener" "https" {
  load_balancer_id = alicloud_slb_load_balancer.web.id
  frontend_port    = 443
  backend_port     = 8080
  protocol         = "https"
  server_certificate_id = var.ssl_cert_id
  health_check     = "on"
  health_check_uri = "/health"
  sticky_session   = "on"
  sticky_session_type = "insert"
  cookie_timeout   = 86400
}

# ===== ECS实例 =====
resource "alicloud_instance" "web" {
  count             = var.web_instance_count
  instance_name     = "${var.project}-web-${count.index + 1}"
  host_name         = "${var.project}-web-${count.index + 1}"
  image_id          = var.image_id
  instance_type     = var.web_instance_type
  system_disk_size  = 100
  system_disk_category = "cloud_essd"
  vswitch_id        = alicloud_vswitch.web[count.index % length(alicloud_vswitch.web)].id
  security_groups   = [alicloud_security_group.web.id]
  key_name          = alicloud_key_pair.deployer.key_name
  
  tags = {
    Environment = var.environment
    Role        = "web"
    Name        = "${var.project}-web-${count.index + 1}"
  }
}

# ===== RDS MySQL =====
resource "alicloud_db_instance" "main" {
  engine              = "MySQL"
  engine_version      = "8.0"
  instance_type       = "rds.mysql.s3.large"
  instance_storage    = 200
  instance_charge_type = "Postpaid"
  instance_name       = "${var.project}-mysql"
  vswitch_id          = alicloud_vswitch.db[0].id
  security_ips        = [var.vpc_cidr]
  monitoring_period   = 60
  
  db_instance_storage_type = "cloud_essd"
  category                 = "HighAvailability"
  zone_id                  = var.availability_zones[0]
  zone_id_slave_a          = var.availability_zones[1]
  
  tags = {
    Environment = var.environment
  }
}

# ===== Redis =====
resource "alicloud_kvstore_instance" "main" {
  db_instance_name = "${var.project}-redis"
  instance_class   = "redis.master.small.default"
  instance_type    = "Redis"
  engine_version   = "7.0"
  vswitch_id       = alicloud_vswitch.db[0].id
  security_ips     = [var.vpc_cidr]
  
  tags = {
    Environment = var.environment
  }
}

# ===== OSS =====
resource "alicloud_oss_bucket" "assets" {
  bucket = "${var.project}-assets-${var.environment}"
  acl    = "private"
  
  lifecycle_rule {
    id      = "archive-old-objects"
    enabled = true
    transitions {
      days          = 90
      storage_class = "Archive"
    }
  }
  
  server_side_encryption_rule {
    sse_algorithm = "AES256"
  }
}
```

### 2.2 变量定义

```hcl
# variables.tf
variable "region" {
  description = "阿里云区域"
  type        = string
  default     = "cn-beijing"
}

variable "project" {
  description = "项目名称"
  type        = string
}

variable "environment" {
  description = "环境"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "环境必须是 dev, staging, production 之一"
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "可用区列表"
  type        = list(string)
  default     = ["cn-beijing-a", "cn-beijing-b", "cn-beijing-c"]
}

variable "web_subnet_cidrs" {
  description = "Web子网CIDR列表"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "db_subnet_cidrs" {
  description = "数据库子网CIDR列表"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "web_instance_count" {
  description = "Web实例数量"
  type        = number
  default     = 2
}

variable "web_instance_type" {
  description = "Web实例规格"
  type        = string
  default     = "ecs.c7.large"
}

variable "image_id" {
  description = "镜像ID"
  type        = string
}

variable "ssl_cert_id" {
  description = "SSL证书ID"
  type        = string
}
```

### 2.3 输出定义

```hcl
# outputs.tf
output "vpc_id" {
  description = "VPC ID"
  value       = alicloud_vpc.main.id
}

output "slb_public_ip" {
  description = "SLB公网IP"
  value       = alicloud_slb_load_balancer.web.address
}

output "web_instance_ips" {
  description = "Web实例私网IP"
  value       = alicloud_instance.web[*].private_ip
}

output "rds_connection_string" {
  description = "RDS连接地址"
  value       = alicloud_db_instance.main.connection_string
}

output "redis_connection_string" {
  description = "Redis连接地址"
  value       = alicloud_kvstore_instance.main.connection_domain
}
```

---

## 3. AWS资源编排

```hcl
# aws-main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "terraform-state-prod"
    key            = "infrastructure/terraform.tfstate"
    region         = "cn-north-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "production"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

# EC2实例
resource "aws_instance" "web" {
  count         = var.web_instance_count
  ami           = var.ami_id
  instance_type = var.web_instance_type
  subnet_id     = module.vpc.private_subnets[count.index % length(module.vpc.private_subnets)]
  
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  tags = {
    Name        = "${var.project}-web-${count.index + 1}"
    Environment = var.environment
  }
}

# RDS
resource "aws_db_instance" "main" {
  identifier     = "${var.project}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.r6g.large"
  
  allocated_storage     = 200
  max_allocated_storage = 1000
  storage_type          = "gp3"
  storage_encrypted     = true
  
  db_name  = "app"
  username = "admin"
  password = var.db_password
  
  multi_az               = var.environment == "production"
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  
  backup_retention_period = 7
  skip_final_snapshot     = var.environment != "production"
}
```

---

## 4. 模块化设计

### 4.1 模块目录结构

```
terraform/
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ecs-cluster/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rds/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── redis/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── staging/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   └── production/
│       ├── main.tf
│       ├── terraform.tfvars
│       └── backend.tf
└── README.md
```

### 4.2 模块示例

```hcl
# modules/vpc/variables.tf
variable "project" {
  type = string
}
variable "environment" {
  type = string
}
variable "vpc_cidr" {
  type = string
}
variable "availability_zones" {
  type = list(string)
}
variable "public_subnets" {
  type = list(string)
}
variable "private_subnets" {
  type = list(string)
}

# modules/vpc/main.tf
resource "alicloud_vpc" "this" {
  vpc_name   = "${var.project}-${var.environment}-vpc"
  cidr_block = var.vpc_cidr
}

resource "alicloud_vswitch" "public" {
  count      = length(var.public_subnets)
  vpc_id     = alicloud_vpc.this.id
  cidr_block = var.public_subnets[count.index]
  zone_id    = var.availability_zones[count.index]
}

resource "alicloud_vswitch" "private" {
  count      = length(var.private_subnets)
  vpc_id     = alicloud_vpc.this.id
  cidr_block = var.private_subnets[count.index]
  zone_id    = var.availability_zones[count.index]
}

# modules/vpc/outputs.tf
output "vpc_id" {
  value = alicloud_vpc.this.id
}
output "public_vswitch_ids" {
  value = alicloud_vswitch.public[*].id
}
output "private_vswitch_ids" {
  value = alicloud_vswitch.private[*].id
}

# 使用模块
# environments/production/main.tf
module "vpc" {
  source = "../../modules/vpc"
  
  project           = "myproject"
  environment       = "production"
  vpc_cidr          = "10.0.0.0/16"
  availability_zones = ["cn-beijing-a", "cn-beijing-b"]
  public_subnets    = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets   = ["10.0.11.0/24", "10.0.12.0/24"]
}
```

---

## 5. State管理

### 5.1 远程State存储

```hcl
# 阿里云OSS后端
terraform {
  backend "oss" {
    bucket   = "terraform-state-prod"
    prefix   = "infrastructure"
    region   = "cn-beijing"
    encrypt  = true
    tablestore_endpoint = "https://tf-lock.cn-beijing.ots.aliyuncs.com"
    tablestore_table    = "terraform_lock"
  }
}

# AWS S3后端
terraform {
  backend "s3" {
    bucket         = "terraform-state-prod"
    key            = "infrastructure/terraform.tfstate"
    region         = "cn-north-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### 5.2 State操作命令

```bash
# 查看State
terraform state list
terraform state show alicloud_instance.web[0]

# 移除资源（不删除实际资源）
terraform state rm alicloud_instance.web[0]

# 导入已有资源
terraform import alicloud_instance.existing i-xxxxxxxxxxxx

# 移动资源
terraform state mv alicloud_instance.web alicloud_instance.web_new

# 拉取远程State
terraform state pull > terraform.tfstate.backup

# 推送State到远程
terraform state push terraform.tfstate.backup

# 刷新State
terraform refresh
```

---

## 6. 与Ansible联动

### 6.1 Terraform输出供Ansible使用

```hcl
# outputs.tf - 输出Inventory信息
output "ansible_inventory" {
  value = {
    web = {
      hosts = [for i in alicloud_instance.web : i.private_ip]
      vars = {
        ansible_user = "ops"
        mysql_host   = alicloud_db_instance.main.connection_string
        redis_host   = alicloud_kvstore_instance.main.connection_domain
      }
    }
  }
}

# 生成Ansible Inventory文件
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    web_ips     = alicloud_instance.web[*].private_ip
    db_host     = alicloud_db_instance.main.connection_string
    redis_host  = alicloud_kvstore_instance.main.connection_domain
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}
```

```
# inventory.tpl
[web]
%{ for ip in web_ips ~}
web-${index(web_ips, ip) + 1} ansible_host=${ip}
%{ endfor ~}

[web:vars]
ansible_user=ops
mysql_host=${db_host}
redis_host=${redis_host}
```

### 6.2 完整工作流

```bash
#!/bin/bash
# deploy.sh - Terraform + Ansible 完整部署

set -e

# 1. Terraform创建基础设施
cd terraform/environments/production
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 2. 生成Ansible Inventory
terraform output -json ansible_inventory > ../../ansible/inventory/hosts.json

# 3. Ansible配置服务器
cd ../../ansible
ansible-playbook -i inventory/hosts.ini playbooks/system-init.yml
ansible-playbook -i inventory/hosts.ini playbooks/deploy-app.yml

echo "部署完成！"
```

---

## 7. 安全最佳实践

### 7.1 敏感变量管理

```hcl
# variables.tf
variable "db_password" {
  description = "数据库密码"
  type        = string
  sensitive   = true  # 标记为敏感
}

# 使用环境变量
# export TF_VAR_db_password="your_password"

# 使用terraform.tfvars（加入.gitignore）
# terraform.tfvars
# db_password = "your_password"

# 使用外部密钥管理
data "alicloud_kms_secret" "db_password" {
  secret_name = "prod/db/password"
}
```

### 7.2 最小权限原则

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:*",
        "vpc:*",
        "slb:*",
        "rds:*",
        "kvstore:*",
        "oss:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "acs:RequestedRegion": "cn-beijing"
        }
      }
    }
  ]
}
```

---

## 8. 多环境管理

### 8.1 Workspace方式

```bash
# 创建工作区
terraform workspace new dev
terraform workspace new staging
terraform workspace new production

# 切换工作区
terraform workspace select production

# 在代码中使用
# terraform.workspace 返回当前工作区名
```

```hcl
# 根据workspace选择配置
locals {
  env_config = {
    dev = {
      instance_count = 1
      instance_type  = "ecs.c7.large"
    }
    staging = {
      instance_count = 2
      instance_type  = "ecs.c7.xlarge"
    }
    production = {
      instance_count = 4
      instance_type  = "ecs.c7.2xlarge"
    }
  }
  config = local.env_config[terraform.workspace]
}
```

### 8.2 目录方式

```bash
# 每个环境独立目录
terraform/
├── modules/          # 共享模块
├── environments/
│   ├── dev/
│   │   ├── main.tf   # 引用modules
│   │   └── terraform.tfvars
│   ├── staging/
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   └── production/
│       ├── main.tf
│       └── terraform.tfvars
```

---

## 9. 故障排查与最佳实践

### 9.1 常用命令

```bash
# 格式化
terraform fmt -recursive

# 验证配置
terraform validate

# 查看执行计划
terraform plan
terraform plan -target=alicloud_instance.web[0]

# 只销毁特定资源
terraform destroy -target=alicloud_instance.web[0]

# 图形化依赖关系
terraform graph | dot -Tsvg > graph.svg

# 导入已有资源
terraform import alicloud_instance.existing i-xxxxxxxx
```

### 9.2 最佳实践

1. **远程State** - 必须使用远程State存储，启用加密和状态锁
2. **模块化** - 可复用资源封装为Module
3. **变量验证** - 使用validation块验证变量
4. **最小权限** - Provider使用最小权限的RAM用户
5. **敏感数据** - 使用sensitive=true标记敏感变量
6. **版本锁定** - 锁定Provider和Module版本
7. **代码审查** - terraform plan输出必须人工审查
8. **CI/CD集成** - 自动化plan和apply
9. **标签管理** - 所有资源打标签
10. **文档** - 模块必须有README

### 9.3 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| State锁冲突 | 其人在操作 | `terraform force-unlock <ID>` |
| 资源漂移 | 手动修改了云资源 | `terraform refresh` + `terraform apply` |
| 依赖循环 | 资源引用循环 | 使用`depends_on`打破循环 |
| Provider版本不兼容 | 版本升级 | 锁定Provider版本 |
| 超时 | API调用慢 | 增加timeout配置 |
| 权限不足 | RAM用户权限不够 | 检查RAM策略 |

---

> 📅 最后更新: 2026-05-02
