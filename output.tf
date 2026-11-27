output "object" {
  description = "Returns the full aws_network_interface resource object"
  value       = aws_network_interface.this
}

output "id" {
  description = "Returns the ID of the network interface; the value to put in the network_interface_ids map of terraform-aws-caf-ec2_instance, keyed by the module key"
  value       = aws_network_interface.this.id
}

output "arn" {
  description = "Returns the ARN of the network interface"
  value       = aws_network_interface.this.arn
}

output "name" {
  description = "Returns the Name tag of the network interface"
  value       = local.interface-name
}

# --- resource-specific outputs below this line ---

output "private_ip" {
  description = "Primary private IPv4 address of the interface"
  value       = aws_network_interface.this.private_ip
}

output "private_ips" {
  description = "All private IPv4 addresses of the interface (the primary and the secondary ones), in the order the provider reports them"
  value       = aws_network_interface.this.private_ip_list
}

output "ipv6_addresses" {
  description = "IPv6 addresses of the interface"
  value       = tolist(aws_network_interface.this.ipv6_addresses)
}

output "mac_address" {
  description = "MAC address of the interface"
  value       = aws_network_interface.this.mac_address
}

output "private_dns_name" {
  description = "Private DNS name of the interface"
  value       = aws_network_interface.this.private_dns_name
}

output "subnet_id" {
  description = "ID of the subnet the interface is in"
  value       = aws_network_interface.this.subnet_id
}

output "security_groups" {
  description = "IDs of the security groups of the interface"
  value       = tolist(aws_network_interface.this.security_groups)
}

output "owner_id" {
  description = "AWS account ID of the owner of the interface"
  value       = aws_network_interface.this.owner_id
}

output "attachment_id" {
  description = "ID of the standalone attachment to an instance (null when the module has no attachment)"
  value       = one([for a in aws_network_interface_attachment.this : a.attachment_id])
}

output "attachment_status" {
  description = "Status of the standalone attachment to an instance (null when the module has no attachment)"
  value       = one([for a in aws_network_interface_attachment.this : a.status])
}

output "permission_ids" {
  description = "Map of permission key to its network_interface_permission_id"
  value       = { for k, v in aws_network_interface_permission.this : k => v.network_interface_permission_id }
}
