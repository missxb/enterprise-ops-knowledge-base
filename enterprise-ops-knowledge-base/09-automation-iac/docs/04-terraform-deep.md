# Terraform 深入

## 一、Terraform 概述

### 1.1 核心概念

Terraform 是 HashiCorp 开发的基础设施即代码工具，使用 HCL（HashiCorp Configuration Language）声明式地定义基础设施。

**核心特性：**

- **声明式语法** — 描述期望状态，而非执行步骤
- **资源图** — 自动分析依赖关系，并行创建无依赖资源
- **State 管理** — 维护基础设施状态文件
- **Provider 生态** — 支持 3000+ Provider（AWS/Azure/GCP/K8s 等）
- **模块化** — 支持模块复用和版本管理
- **计划与执行分离** — `plan` 查看变更，`apply` 执行变更

### 1.2 工作流程

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Write      │────→│   Plan       │────→│   Apply      │
│   编写配置   │     │   预览变更   │     │   执行变更   │
└──────────────┘     └──────────────┘     └──────────────┘
       │                    │                    │
       │                    │                    │
       ▼                    ▼                    ▼
  .tf 配置文件        执行计划输出          资源创建/更新
                           │                    │
                           │                    │
                           ▼                    ▼
                      State 快照           State 更新
```

## 二、HCL 语法深入

### 2.1 基础语法

```hcl
# 块结构
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"
  
  tags = {
    Name = "web-server"
    Environment = "production"
  }
}

# 表达式
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type
  count         = var.instance_count
  
  tags = merge(var.common_tags, {
    Name = "web-${count.index + 1}"
  })
}
```

### 2.2 数据类型

```hcl
# 字符串
variable "name" {
  type    = string
  default = "web-server"
}

# 数字
variable "port" {
  type    = number
  default = 80
}

# 布尔
variable "enable_ssl" {
  type    = bool
  default = true
}

# 列表
variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# 映射
variable "instance_types" {
  type = map(string)
  default = {
    web  = "t3.micro"
    api  = "t3.small"
    db   = "r5.large"
  }
}

# 对象
variable "server_config" {
  type = object({
    name     = string
    port     = number
    replicas = number
    tags     = map(string)
  })
}

# 元组
variable "mixed_list" {
  type    = tuple([string, number, bool])
  default = ["hello", 42, true]
}
```

### 2.3 表达式与函数

```hcl
# 条件表达式
resource "aws_instance" "web" {
  instance_type = var.environment == "production" ? "t3.large" : "t3.micro"
}

# for 表达式
output "instance_ids" {
  value = [for instance in aws_instance.web : instance.id]
}

output "instance_map" {
  value = { for instance in aws_instance.web => instance.tags.Name => instance.id }
}

# 展开运算符
resource "aws_security_group_rule" "ingress" {
  for_each = var.ingress_rules
  
  type              = "ingress"
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = each.value.protocol
  cidr_blocks       = each.value.cidr_blocks
  security_group_id = aws_security_group.main.id
}

# 常用函数
locals {
  # 字符串函数
  upper_name    = upper(var.name)
  lower_name    = lower(var.name)
  formatted     = format("server-%03d", var.index)
  replaced      = replace(var.domain, ".", "-")
  
  # 集合函数
  all_zones     = concat(var.primary_zones, var.secondary_zones)
  unique_zones  = distinct(local.all_zones)
  sorted_zones  = sort(local.unique_zones)
  zone_count    = length(local.unique_zones)
  
  # 文件函数
  config        = file("${path.module}/configs/app.json")
  config_parsed = jsondecode(local.config)
  
  # 加密函数
  encrypted     = base64encode(var.secret)
  hashed        = sha256(var.password)
}
```

### 2.4 动态块

```hcl
# 动态生成重复块
resource "aws_security_group" "main" {
  name = "main-sg"
  
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }
  
  dynamic "egress" {
    for_each = var.egress_rules
    content {
      from_port   = egress.value.port
      to_port     = egress.value.port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
    }
  }
}
```

## 三、State 管理

### 3.1 State 文件

```hcl
# backend 配置 — 远程 State 存储
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

# 其他后端选项
terraform {
  # Consul
  backend "consul" {
    address = "consul.example.com:8500"
    scheme  = "https"
    path    = "terraform/state"
  }
  
  # Terraform Cloud
  backend "remote" {
    organization = "my-org"
    workspaces {
      name = "my-app-production"
    }
  }
  
  # 阿里云 OSS
  backend "oss" {
    bucket = "terraform-state-cn"
    prefix = "production"
    region = "cn-hangzhou"
  }
}
```

### 3.2 State 操作

```bash
# 查看 State 列表
terraform state list

# 查看资源详情
terraform state show aws_instance.web

# 移除资源（不删除实际资源）
terraform state rm aws_instance.old_server

# 移动/重命名资源
terraform state mv aws_instance.web aws_instance.web_server

# 导入已有资源
terraform import aws_instance.web i-1234567890abcdef0
terraform import 'aws_instance.web[0]' i-1234567890abcdef0

# 拉取远程 State
terraform state pull > terraform.tfstate

# 推送本地 State
terraform state push terraform.tfstate

# 替换 Provider
terraform state replace-provider hashicorp/aws registry.terraform.io/hashicorp/aws
```

### 3.3 State 锁定

```hcl
# DynamoDB 表用于 State 锁定（AWS S3 后端）
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  
  attribute {
    name = "LockID"
    type = "S"
  }
}
```

```bash
# 强制解锁（谨慎使用）
terraform force-unlock LOCK_ID
```

## 四、Provider

### 4.1 Provider 配置

```hcl
# 多 Provider 配置
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.200"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.5.0"
}

# AWS Provider
provider "aws" {
  region  = "us-east-1"
  profile = "production"
  
  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
    }
  }
}

# 阿里云 Provider
provider "alicloud" {
  region     = "cn-hangzhou"
  access_key = var.alicloud_access_key
  secret_key = var.alicloud_secret_key
}

# 多区域 Provider（别名）
provider "aws" {
  alias  = "us_west"
  region = "us-west-2"
}

resource "aws_instance" "west_server" {
  provider      = aws.us_west
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"
}
```

### 4.2 Data Source

```hcl
# 查询已有资源
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_vpc" "main" {
  tags = {
    Name = "main-vpc"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  
  tags = {
    Type = "private"
  }
}

# 使用数据源
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = data.aws_subnets.private.ids[0]
}
```

## 五、Lifecycle 管理

### 5.1 Resource Lifecycle

```hcl
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type
  
  lifecycle {
    # 创建新资源后再销毁旧资源
    create_before_destroy = true
    
    # 防止意外销毁
    prevent_destroy = true
    
    # 忽略某些属性变化
    ignore_changes = [
      tags,
      user_data,
    ]
    
    # 替换触发条件
    replace_triggered_by = [
      aws_security_group.main.id
    ]
    
    # 前置条件
    precondition {
      condition     = data.aws_ami.ubuntu.architecture == "x86_64"
      error_message = "AMI 必须是 x86_64 架构"
    }
    
    # 后置条件
    postcondition {
      condition     = self.public_ip != ""
      error_message = "实例必须有公网 IP"
    }
  }
}
```

### 5.2 Moved 块（重构）

```hcl
# 重命名资源（避免删除重建）
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

# 移动到模块
moved {
  from = aws_instance.web
  to   = module.web_servers.aws_instance.this
}
```

### 5.3 Import 块

```hcl
# 声明式导入（Terraform 1.5+）
import {
  to = aws_instance.web
  id = "i-1234567890abcdef0"
}

import {
  to = aws_s3_bucket.data
  id = "my-data-bucket"
}
```

## 六、工作区与环境管理

### 6.1 Workspace

```bash
# 创建工作区
terraform workspace new production
terraform workspace new staging
terraform workspace new development

# 切换工作区
terraform workspace select production

# 列出工作区
terraform workspace list

# 显示当前工作区
terraform workspace show

# 删除工作区
terraform workspace delete staging
```

```hcl
# 在配置中使用工作区
locals {
  env_config = {
    production = {
      instance_type = "t3.large"
      instance_count = 3
    }
    staging = {
      instance_type = "t3.medium"
      instance_count = 1
    }
    development = {
      instance_type = "t3.micro"
      instance_count = 1
    }
  }
  
  current_config = local.env_config[terraform.workspace]
}

resource "aws_instance" "web" {
  count         = local.current_config.instance_count
  instance_type = local.current_config.instance_type
  ami           = var.ami_id
}
```

### 6.2 环境分离（目录结构）

```
terraform/
├── modules/
│   ├── vpc/
│   ├── ec2/
│   └── rds/
├── environments/
│   ├── production/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars
│   └── development/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars
└── README.md
```

## 七、最佳实践

### 7.1 代码组织

```hcl
# variables.tf — 所有变量定义
# outputs.tf — 所有输出定义
# main.tf — 主要资源定义
# locals.tf — 本地值
# data.tf — 数据源
# providers.tf — Provider 配置
# versions.tf — 版本约束
# backend.tf — 后端配置
```

### 7.2 安全最佳实践

```hcl
# 1. 不要硬编码敏感值
variable "db_password" {
  type      = string
  sensitive = true
}

# 2. 使用 SSM Parameter Store 或 Secrets Manager
data "aws_ssm_parameter" "db_password" {
  name            = "/production/database/password"
  with_decryption = true
}

# 3. 限制 State 文件访问
terraform {
  backend "s3" {
    encrypt = true
  }
}

# 4. 使用 IAM 角色而非 Access Key
provider "aws" {
  region = "us-east-1"
  # 使用环境变量或 shared credentials
}
```

### 7.3 CI/CD 集成

```yaml
# .github/workflows/terraform.yml
---
name: Terraform
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0
      
      - name: Terraform Init
        run: terraform init
      
      - name: Terraform Format
        run: terraform fmt -check
      
      - name: Terraform Plan
        run: terraform plan -no-color
        if: github.event_name == 'pull_request'
      
      - name: Terraform Apply
        run: terraform apply -auto-approve
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```
