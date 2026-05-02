# Terraform 模块开发

## 一、模块基础

### 1.1 模块结构

```
modules/
└── vpc/
    ├── main.tf          # 主要资源定义
    ├── variables.tf     # 输入变量
    ├── outputs.tf       # 输出值
    ├── versions.tf      # 版本约束
    ├── locals.tf        # 本地值
    ├── data.tf          # 数据源
    ├── README.md        # 模块文档
    └── examples/
        └── complete/
            ├── main.tf
            └── outputs.tf
```

### 1.2 模块定义

```hcl
# modules/vpc/variables.tf
variable "name" {
  description = "VPC 名称"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR 块"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "必须是有效的 CIDR 块"
  }
}

variable "availability_zones" {
  description = "可用区列表"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "是否启用 NAT Gateway"
  type        = bool
  default     = true
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

# modules/vpc/main.tf
resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr_block, 4, count.index)
  availability_zone = var.availability_zones[count.index]
  
  map_public_ip_on_launch = true
  
  tags = merge(var.tags, {
    Name = "${var.name}-public-${var.availability_zones[count.index]}"
    Type = "public"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr_block, 4, count.index + length(var.availability_zones))
  availability_zone = var.availability_zones[count.index]
  
  tags = merge(var.tags, {
    Name = "${var.name}-private-${var.availability_zones[count.index]}"
    Type = "private"
  })
}

resource "aws_internet_gateway" "this" {
  count  = 1
  vpc_id = aws_vpc.this.id
  
  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? length(var.availability_zones) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  
  tags = merge(var.tags, {
    Name = "${var.name}-nat-${count.index}"
  })
  
  depends_on = [aws_internet_gateway.this]
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? length(var.availability_zones) : 0
  domain = "vpc"
  
  tags = merge(var.tags, {
    Name = "${var.name}-nat-eip-${count.index}"
  })
}

# modules/vpc/outputs.tf
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR 块"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "公有子网 ID 列表"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "私有子网 ID 列表"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "NAT Gateway 公网 IP"
  value       = aws_eip.nat[*].public_ip
}
```

### 1.3 使用模块

```hcl
# environments/production/main.tf
module "vpc" {
  source = "../../modules/vpc"
  
  name               = "production-vpc"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  enable_nat_gateway = true
  
  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

# 引用模块输出
resource "aws_instance" "web" {
  subnet_id = module.vpc.private_subnet_ids[0]
  # ...
}
```

## 二、模块设计模式

### 2.1 for_each 模式

```hcl
# modules/ec2-instances/main.tf
variable "instances" {
  description = "实例配置映射"
  type = map(object({
    instance_type = string
    ami_id        = string
    subnet_id     = string
    tags          = map(string)
  }))
}

resource "aws_instance" "this" {
  for_each = var.instances
  
  ami           = each.value.ami_id
  instance_type = each.value.instance_type
  subnet_id     = each.value.subnet_id
  
  tags = merge(each.value.tags, {
    Name = each.key
  })
}

output "instance_ids" {
  description = "实例 ID 映射"
  value       = { for k, v in aws_instance.this : k => v.id }
}
```

### 2.2 嵌套模块模式

```
modules/
├── infrastructure/
│   ├── main.tf          # 组合子模块
│   ├── variables.tf
│   ├── outputs.tf
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── compute/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
```

```hcl
# modules/infrastructure/main.tf
module "vpc" {
  source = "./vpc"
  
  name               = var.name
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "security" {
  source = "./security"
  
  vpc_id     = module.vpc.vpc_id
  allowed_ips = var.allowed_ips
}

module "compute" {
  source = "./compute"
  
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security.app_security_group_id
  instance_config   = var.instance_config
}
```

### 2.3 可组合模块模式

```hcl
# 标准化输出接口
# 任何模块实现相同接口即可互换

# modules/storage/aws-s3/main.tf
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  value = aws_s3_bucket.this.bucket_domain_name
}

# modules/storage/alicloud-oss/main.tf
resource "alicloud_oss_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

output "bucket_id" {
  value = alicloud_oss_bucket.this.id
}

output "bucket_arn" {
  value = alicloud_oss_bucket.this.arn
}

output "bucket_domain_name" {
  value = alicloud_oss_bucket.this.bucket_domain_name
}
```

## 三、模块版本管理

### 3.1 版本约束

```hcl
# 从 Registry 引用
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
}

# 版本约束语法
# =  1.0.0    精确版本
# != 1.0.0    排除版本
# >  1.0.0    大于
# >= 1.0.0    大于等于
# <  2.0.0    小于
# ~> 1.0      >= 1.0 且 < 2.0（悲观约束）
# >= 1.0, < 2.0  多约束

# 从 Git 引用
module "custom" {
  source = "git::https://github.com/company/terraform-modules.git//vpc?ref=v1.2.0"
}

# 从本地引用
module "local" {
  source = "../../modules/vpc"
}
```

### 3.2 语义化版本

```
v1.2.3
│ │ │
│ │ └── 补丁版本（Bug 修复，向后兼容）
│ └──── 次版本（新功能，向后兼容）
└────── 主版本（破坏性变更）

版本约束策略：
- 生产环境：~> 1.2（锁定次版本）
- 开发环境：>= 1.0（允许最新版本）
- 引用 Git：使用 tag 而非 branch
```

## 四、模块发布

### 4.1 发布到 Registry

```bash
# 1. 准备模块
# 确保有 main.tf, variables.tf, outputs.tf
# 添加 README.md（Registry 会渲染）
# 添加 examples/

# 2. 推送到 GitHub
git tag v1.0.0
git push origin v1.0.0

# 3. 在 Terraform Cloud/Registry 发布
# 访问 https://app.terraform.io
# → Registry → Publish → 选择 GitHub 仓库

# 4. 使用发布的模块
module "vpc" {
  source  = "my-org/vpc/aws"
  version = "1.0.0"
}
```

### 4.2 私有 Registry

```hcl
# 使用 Terraform Cloud 私有 Registry
module "internal_vpc" {
  source  = "app.terraform.io/my-org/vpc/aws"
  version = "1.0.0"
}

# 使用 Git 私有仓库
module "internal_vpc" {
  source = "git::ssh://git@github.com/company/terraform-modules.git//vpc?ref=v1.0.0"
}
```

### 4.3 模块文档生成

```bash
# 使用 terraform-docs 自动生成文档
# 安装
# brew install terraform-docs

# 生成 Markdown
terraform-docs markdown table ./modules/vpc > ./modules/vpc/README.md

# 生成 JSON
terraform-docs json ./modules/vpc > ./modules/vpc/docs.json

# 配置文件 .terraform-docs.yml
formatter: markdown table
output:
  file: README.md
  mode: replace
content: |-
  {{ .Header }}

  ## 使用方法

  ```hcl
  {{ include "examples/complete/main.tf" }}
  ```

  ## 输入变量

  {{ .Inputs }}

  ## 输出值

  {{ .Outputs }}
```

## 五、模块测试

### 5.1 Terratest

```go
// test/vpc_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestVpcModule(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../modules/vpc",
        Vars: map[string]interface{}{
            "name":               "test-vpc",
            "cidr_block":         "10.0.0.0/16",
            "availability_zones": []string{"us-east-1a"},
            "enable_nat_gateway": false,
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    vpcId := terraform.Output(t, terraformOptions, "vpc_id")
    assert.NotEmpty(t, vpcId)

    publicSubnets := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
    assert.Equal(t, 1, len(publicSubnets))
}
```

### 5.2 检查工具

```bash
# terraform validate — 语法验证
terraform validate

# terraform fmt — 格式化
terraform fmt -check -recursive

# tflint — 静态分析
tflint --recursive

# checkov — 安全扫描
checkov -d .

# infracost — 成本估算
infracost breakdown --path .
```

## 六、最佳实践

1. **单一职责** — 每个模块只管理一类资源
2. **接口清晰** — 变量有描述、类型、验证；输出有描述
3. **向后兼容** — 使用语义化版本，破坏性变更升主版本
4. **文档完善** — README 包含用法示例
5. **测试覆盖** — 使用 Terratest 或类似工具
6. **安全扫描** — 使用 checkov 或 tfsec
7. **成本估算** — 使用 infracost 评估成本影响
