terraform {
  required_version = ">= 1.5.0"
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.220"
    }
  }
  backend "oss" {
    bucket = "terraform-state-prod"
    prefix = "production"
    region = "cn-hangzhou"
  }
}

provider "alicloud" {
  region = var.region
}

module "vpc" {
  source          = "./modules/vpc"
  vpc_name        = var.project_name
  vpc_cidr        = var.vpc_cidr
  vswitch_cidrs   = var.vswitch_cidrs
  availability_zones = var.availability_zones
}

module "ecs" {
  source             = "./modules/ecs"
  project_name       = var.project_name
  vswitch_ids        = module.vpc.vswitch_ids
  security_group_ids = [module.vpc.security_group_id]
  instance_type      = var.ecs_instance_type
  instance_count     = var.ecs_instance_count
  system_disk_size   = var.system_disk_size
}

module "slb" {
  source             = "./modules/slb"
  slb_name           = "${var.project_name}-slb"
  vswitch_id         = module.vpc.vswitch_ids[0]
  internet_charge_type = "PayByTraffic"
}

module "rds" {
  source           = "./modules/rds"
  project_name     = var.project_name
  engine           = "MySQL"
  engine_version   = "8.0"
  instance_type    = var.rds_instance_type
  allocated_storage = var.rds_storage
  vswitch_ids      = module.vpc.vswitch_ids
  security_ips     = [var.vpc_cidr]
}

module "oss" {
  source      = "./modules/oss"
  bucket_name = "${var.project_name}-assets"
  acl         = "private"
}
