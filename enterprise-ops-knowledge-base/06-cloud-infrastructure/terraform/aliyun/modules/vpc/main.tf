resource "alicloud_vpc" "this" {
  vpc_name   = var.vpc_name
  cidr_block = var.vpc_cidr
  tags = {
    Name = var.vpc_name
  }
}

resource "alicloud_vswitch" "this" {
  count        = length(var.vswitch_cidrs)
  vpc_id       = alicloud_vpc.this.id
  cidr_block   = var.vswitch_cidrs[count.index]
  zone_id      = var.availability_zones[count.index]
  vswitch_name = "${var.vpc_name}-vsw-${count.index}"
}

resource "alicloud_security_group" "this" {
  name   = "${var.vpc_name}-sg"
  vpc_id = alicloud_vpc.this.id
}

resource "alicloud_security_group_rule" "allow_ssh" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "22/22"
  security_group_id = alicloud_security_group.this.id
  cidr_ip           = "0.0.0.0/0"
  description       = "Allow SSH"
}

resource "alicloud_security_group_rule" "allow_http" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "80/80"
  security_group_id = alicloud_security_group.this.id
  cidr_ip           = "0.0.0.0/0"
  description       = "Allow HTTP"
}

resource "alicloud_security_group_rule" "allow_https" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "443/443"
  security_group_id = alicloud_security_group.this.id
  cidr_ip           = "0.0.0.0/0"
  description       = "Allow HTTPS"
}

variable "vpc_name" { type = string }
variable "vpc_cidr" { type = string }
variable "vswitch_cidrs" { type = list(string) }
variable "availability_zones" { type = list(string) }

output "vpc_id" { value = alicloud_vpc.this.id }
output "vswitch_ids" { value = alicloud_vswitch.this[*].id }
output "security_group_id" { value = alicloud_security_group.this.id }
