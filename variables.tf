variable "tags" {
  description = "Tags applied to the interface (merged with network_interface.tags)"
  type        = map(string)
  default     = {}
}

variable "env" {
  description = "(Required) env value used in name generation"
  type        = string
}

variable "userDefinedString" {
  description = "(Required) UserDefinedString part of the name of the network interface"
  type        = string
}

variable "subnet_ids" {
  description = "Optional map of VPC key to a map of subnet key to its ID. Resolves network_interface.subnet_key within network_interface.vpc_key. e.g. { for k, v in module.vpc : k => v.subnet_ids }"
  type        = map(map(string))
  default     = {}
}

variable "security_group_ids" {
  description = "Optional map of security group key to its ID. Resolves network_interface.security_group_keys and the security_group_key of network_interface.security_group_attachments. e.g. { for k, v in module.security_group : k => v.id }"
  type        = map(string)
  default     = {}
}

variable "instance_ids" {
  description = "Optional map of EC2 instance key to its ID. Resolves network_interface.attachment.instance_key. e.g. { for k, v in module.ec2_instance : k => v.id }"
  type        = map(string)
  default     = {}
}

variable "network_interface" {
  description = "(Required) Object describing the network interface (see TFVars Parameters in the README). Optional `name` key overrides the auto-derived \"<env>-<userDefinedString>-eni\" Name tag value."
  type        = any
  default     = {}
}
