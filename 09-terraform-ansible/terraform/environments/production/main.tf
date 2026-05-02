#============================================================================
# 生产环境 Terraform 配置
# 阿里云生产环境基础设施定义
#============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.210"
    }
  }

  # 远程状态存储（OSS）
  backend "oss" {
    bucket              = "terraform-state-prod"
    prefix              = "production"
    key                 = "terraform.tfstate"
    region              = "cn-hangzhou"
    encrypt             = true
    tablestore_endpoint = "https://tf-state-lock.cn-hangzhou.ots.aliyuncs.com"
    tablestore_table    = "terraform_lock"
  }
}

#==================== 变量定义 ====================
variable "region" {
  default = "cn-hangzhou"
}

variable "environment" {
  default = "production"
}

variable "project_name" {
  default = "enterprise"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["cn-hangzhou-h", "cn-hangzhou-i", "cn-hangzhou-j"]
}

# Web 服务器配置
variable "web_instance_type" {
  default = "ecs.c6.xlarge"  # 4C8G
}

variable "web_count" {
  default = 4
}

# App 服务器配置
variable "app_instance_type" {
  default = "ecs.c6.2xlarge"  # 8C16G
}

variable "app_count" {
  default = 4
}

# 数据库配置
variable "db_instance_type" {
  default = "rds.mysql.s3.large"  # 4C8G
}

variable "db_engine_version" {
  default = "8.0"
}

variable "db_storage" {
  default = 500  # GB
}

# Redis 配置
variable "redis_instance_type" {
  default = "redis.master.mid.default"  # 4G
}

#==================== Provider 配置 ====================
provider "alicloud" {
  region = var.region
}

#==================== 数据源 ====================
data "alicloud_zones" "default" {
  available_resource_creation = "VSwitch"
  available_instance_type     = var.web_instance_type
}

#==================== VPC 网络 ====================
module "vpc" {
  source = "../../modules/vpc"

  vpc_name        = "${var.project_name}-${var.environment}-vpc"
  vpc_cidr        = var.vpc_cidr
  environment     = var.environment
  project_name    = var.project_name
  availability_zones = var.availability_zones

  # 子网划分
  public_subnets = [
    { cidr = "10.0.1.0/24", zone = var.availability_zones[0] },
    { cidr = "10.0.2.0/24", zone = var.availability_zones[1] },
  ]

  private_subnets = [
    { cidr = "10.0.10.0/24", zone = var.availability_zones[0] },
    { cidr = "10.0.11.0/24", zone = var.availability_zones[1] },
    { cidr = "10.0.12.0/24", zone = var.availability_zones[2] },
  ]

  database_subnets = [
    { cidr = "10.0.20.0/24", zone = var.availability_zones[0] },
    { cidr = "10.0.21.0/24", zone = var.availability_zones[1] },
  ]
}

#==================== 安全组 ====================
resource "alicloud_security_group" "web" {
  name        = "${var.project_name}-${var.environment}-web-sg"
  vpc_id      = module.vpc.vpc_id
  description = "Web 服务器安全组"
}

resource "alicloud_security_group_rule" "web_http" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "80/80"
  security_group_id = alicloud_security_group.web.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "web_https" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "443/443"
  security_group_id = alicloud_security_group.web.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-app-sg"
  vpc_id      = module.vpc.vpc_id
  description = "App 服务器安全组"
}

resource "alicloud_security_group_rule" "app_from_web" {
  type                     = "ingress"
  ip_protocol              = "tcp"
  nic_type                 = "intranet"
  policy                   = "accept"
  port_range               = "8080/8080"
  security_group_id        = alicloud_security_group.app.id
  source_security_group_id = alicloud_security_group.web.id
}

resource "alicloud_security_group" "db" {
  name        = "${var.project_name}-${var.environment}-db-sg"
  vpc_id      = module.vpc.vpc_id
  description = "数据库安全组"
}

resource "alicloud_security_group_rule" "db_mysql" {
  type                     = "ingress"
  ip_protocol              = "tcp"
  nic_type                 = "intranet"
  policy                   = "accept"
  port_range               = "3306/3306"
  security_group_id        = alicloud_security_group.db.id
  source_security_group_id = alicloud_security_group.app.id
}

resource "alicloud_security_group_rule" "db_redis" {
  type                     = "ingress"
  ip_protocol              = "tcp"
  nic_type                 = "intranet"
  policy                   = "accept"
  port_range               = "6379/6379"
  security_group_id        = alicloud_security_group.db.id
  source_security_group_id = alicloud_security_group.app.id
}

#==================== Web 服务器 ====================
module "web_servers" {
  source = "../../modules/ecs"

  instance_name   = "${var.project_name}-${var.environment}-web"
  instance_count  = var.web_count
  instance_type   = var.web_instance_type
  security_groups = [alicloud_security_group.web.id]
  vswitch_ids     = module.vpc.public_subnet_ids
  environment     = var.environment

  # 系统盘
  system_disk_category = "cloud_essd"
  system_disk_size     = 100

  # 数据盘
  data_disk_category = "cloud_essd"
  data_disk_size     = 200

  # 镜像
  image_id = "centos_7_9_x64_20G_alibase_20230816.vhd"

  # 公网带宽
  internet_max_bandwidth_out = 100

  # 标签
  tags = {
    Environment = var.environment
    Project     = var.project_name
    Role        = "web"
  }
}

#==================== App 服务器 ====================
module "app_servers" {
  source = "../../modules/ecs"

  instance_name   = "${var.project_name}-${var.environment}-app"
  instance_count  = var.app_count
  instance_type   = var.app_instance_type
  security_groups = [alicloud_security_group.app.id]
  vswitch_ids     = module.vpc.private_subnet_ids
  environment     = var.environment

  system_disk_category = "cloud_essd"
  system_disk_size     = 100
  data_disk_category   = "cloud_essd"
  data_disk_size       = 500
  image_id             = "centos_7_9_x64_20G_alibase_20230816.vhd"

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Role        = "app"
  }
}

#==================== RDS MySQL ====================
module "mysql" {
  source = "../../modules/rds"

  db_name           = "${var.project_name}-${var.environment}-mysql"
  engine            = "MySQL"
  engine_version    = var.db_engine_version
  instance_type     = var.db_instance_type
  instance_storage  = var.db_storage
  security_group_id = alicloud_security_group.db.id
  vswitch_id        = module.vpc.database_subnet_ids[0]
  environment       = var.environment

  # 高可用
  zone_id               = var.availability_zones[0]
  zone_id_slave         = var.availability_zones[1]
  ha_mode               = "ZoneRedundant"

  # 备份
  backup_time           = "02:00Z-03:00Z"
  backup_retention_period = 30

  # 参数
  parameters = [
    { name = "innodb_buffer_pool_size", value = "6442450944" },  # 6G
    { name = "max_connections",         value = "2000" },
    { name = "slow_query_log",          value = "ON" },
    { name = "long_query_time",         value = "1" },
  ]

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

#==================== Redis ====================
module "redis" {
  source = "../../modules/redis"

  redis_name        = "${var.project_name}-${var.environment}-redis"
  instance_type     = var.redis_instance_type
  security_group_id = alicloud_security_group.db.id
  vswitch_id        = module.vpc.database_subnet_ids[0]
  environment       = var.environment

  zone_id         = var.availability_zones[0]
  instance_class  = "redis.master.mid.default"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

#==================== SLB 负载均衡 ====================
resource "alicloud_slb_load_balancer" "web" {
  load_balancer_name = "${var.project_name}-${var.environment}-slb"
  address_type       = "internet"
  load_balancer_spec = "slb.s3.large"
  bandwidth          = 100
  internet_charge_type = "PayByBandwidth"
  vswitch_id         = module.vpc.public_subnet_ids[0]

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "alicloud_slb_listener" "https" {
  load_balancer_id = alicloud_slb_load_balancer.web.id
  frontend_port    = 443
  backend_port     = 8080
  protocol         = "https"
  bandwidth        = 100
  server_certificate_id = var.ssl_certificate_id
  health_check          = "on"
  health_check_uri      = "/health"
  health_check_connect_port = 8080
}

resource "alicloud_slb_server_group" "web" {
  load_balancer_id = alicloud_slb_load_balancer.web.id
  name             = "web-server-group"
}

#==================== 输出 ====================
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "web_public_ips" {
  value = module.web_servers.public_ips
}

output "slb_address" {
  value = alicloud_slb_load_balancer.web.address
}

output "mysql_connection_string" {
  value     = module.mysql.connection_string
  sensitive = true
}

output "redis_connection_string" {
  value     = module.redis.connection_string
  sensitive = true
}
