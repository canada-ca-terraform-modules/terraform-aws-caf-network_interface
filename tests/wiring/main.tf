## Test harness for appliance.tftest.hcl: the interface module and terraform-aws-caf-ec2_instance wired as an ESLZ blueprint does, with only
## the lookup map between them (no adapter). Not a deployable module.
terraform {
  required_version = ">= 1.9"
}

variable "env" {
  type = string
}

variable "subnet_ids" {
  type = map(map(string))
}

variable "security_group_ids" {
  type = map(string)
}

variable "network_interfaces" {
  type = any
}

variable "ec2_instances" {
  type = any
}

module "network_interface" {
  source   = "../.."
  for_each = var.network_interfaces

  userDefinedString  = each.key
  env                = var.env
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
  network_interface  = each.value
}

module "ec2_instance" {
  source   = "github.com/canada-ca-terraform-modules/terraform-aws-caf-ec2_instance.git?ref=v1.0.0"
  for_each = var.ec2_instances

  userDefinedString     = each.key
  env                   = var.env
  network_interface_ids = { for k, v in module.network_interface : k => v.id }
  ec2_instance          = each.value
}

output "interface_names" {
  value = { for k, v in module.network_interface : k => v.name }
}

output "interface_ids" {
  value = { for k, v in module.network_interface : k => v.id }
}

output "instance_primary_ids" {
  value     = { for k, v in module.ec2_instance : k => one(v.object.primary_network_interface).network_interface_id }
  sensitive = true # the instance object output is sensitive (user data)
}

output "instance_attachment_indexes" {
  value = { for k, v in module.ec2_instance : k => { for n, a in v.network_interface_attachments : n => a.device_index } }
}

output "instance_attachment_ids" {
  value = { for k, v in module.ec2_instance : k => { for n, a in v.network_interface_attachments : n => a.network_interface_id } }
}
