terraform {
  required_version = ">= 1.9"
}

variable "network_interfaces" {
  description = "Network interfaces to deploy, keyed by name"
  type        = any
  default     = {}
}

variable "subnet_ids" {
  description = "Map of VPC config-name to a map of subnet config-name to its ID, e.g. { for k, v in module.vpc : k => v.subnet_ids }. An interface picks a subnet with vpc_key and subnet_key."
  type        = map(map(string))
  default     = {}
}

variable "security_group_ids" {
  description = "Map of security group config-name to its ID, e.g. { for k, v in module.security_group : k => v.id }. An interface picks groups with security_group_keys."
  type        = map(string)
  default     = {}
}

variable "instance_ids" {
  description = "Map of EC2 instance config-name to its ID, e.g. { for k, v in module.ec2_instance : k => v.id }. An interface picks the instance of a standalone attachment with attachment.instance_key."
  type        = map(string)
  default     = {}
}

module "network_interface" {
  source   = "github.com/canada-ca-terraform-modules/terraform-aws-caf-network_interface.git?ref=v1.0.0"
  for_each = var.network_interfaces

  userDefinedString  = each.key
  env                = var.env
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
  instance_ids       = var.instance_ids
  network_interface  = each.value
  tags               = var.tags
}
