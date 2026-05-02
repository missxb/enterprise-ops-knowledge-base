variable "region" {
  description = "阿里云地域"
  type        = string
  default     = "cn-hangzhou"
}

variable "project_name" {
  description = "项目名称"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vswitch_cidrs" {
  description = "交换机 CIDR 列表"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "availability_zones" {
  description = "可用区列表"
  type        = list(string)
  default     = ["cn-hangzhou-h", "cn-hangzhou-i", "cn-hangzhou-j"]
}

variable "ecs_instance_type" {
  description = "ECS 实例规格"
  type        = string
  default     = "ecs.c7.xlarge"
}

variable "ecs_instance_count" {
  description = "ECS 实例数量"
  type        = number
  default     = 3
}

variable "system_disk_size" {
  description = "系统盘大小 (GB)"
  type        = number
  default     = 100
}

variable "rds_instance_type" {
  description = "RDS 实例规格"
  type        = string
  default     = "rds.mysql.s3.large"
}

variable "rds_storage" {
  description = "RDS 存储大小 (GB)"
  type        = number
  default     = 200
}
