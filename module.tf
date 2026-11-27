## The core, always-created resource: the network interface (ENI). The standalone attachment, the security group attachments and the
## permissions are in attachment.tf and permission.tf. The subnet and the security groups are made elsewhere and arrive through
## the lookup maps (variables.tf) or as literal ids.
locals {
  # A literal subnet_id wins; otherwise vpc_key and subnet_key resolve through subnet_ids.
  vpc-key         = try(var.network_interface.vpc_key, null)
  subnet-key      = try(var.network_interface.subnet_key, null)
  subnet-literal  = try(var.network_interface.subnet_id, null)
  subnet-resolved = try(var.subnet_ids[local.vpc-key][local.subnet-key], null)
  subnet-id       = local.subnet-literal != null ? local.subnet-literal : local.subnet-resolved

  # Security group keys resolve through security_group_ids and merge with the literal ids.
  security-group-keys    = tolist(try(var.network_interface.security_group_keys, []))
  security-group-missing = [for k in local.security-group-keys : k if !contains(keys(var.security_group_ids), k)]
  security-group-ids = concat(
    tolist(try(var.network_interface.security_groups, [])),
    [for k in local.security-group-keys : var.security_group_ids[k] if contains(keys(var.security_group_ids), k)]
  )

  # The provider ignores its own private_ip argument when it creates the interface, so private_ip pins the primary address
  # through private_ips. private_ip_list (ordered, the first is the primary) switches the provider to its list mode.
  private-ip      = try(var.network_interface.private_ip, null)
  private-ips     = try(var.network_interface.private_ips, null)
  private-ip-list = try(var.network_interface.private_ip_list, null)
  private-ips-set = local.private-ip != null ? [local.private-ip] : local.private-ips
  ipv6-list       = try(var.network_interface.ipv6_address_list, null)

  connection-tracking = try(var.network_interface.connection_tracking_specification, null)
  ena-srd             = try(var.network_interface.ena_srd_specification, null)
  inline-attachment   = try(var.network_interface.inline_attachment, null)
}

resource "aws_network_interface" "this" {
  subnet_id   = local.subnet-id
  description = try(var.network_interface.description, null)

  # Addresses
  private_ips               = local.private-ips-set != null ? toset(local.private-ips-set) : null
  private_ips_count         = try(var.network_interface.private_ips_count, null)
  private_ip_list           = local.private-ip-list
  private_ip_list_enabled   = local.private-ip-list != null
  ipv4_prefixes             = try(var.network_interface.ipv4_prefixes, null) != null ? toset(var.network_interface.ipv4_prefixes) : null
  ipv4_prefix_count         = try(var.network_interface.ipv4_prefix_count, null)
  ipv6_addresses            = try(var.network_interface.ipv6_addresses, null) != null ? toset(var.network_interface.ipv6_addresses) : null
  ipv6_address_count        = try(var.network_interface.ipv6_address_count, null)
  ipv6_address_list         = local.ipv6-list
  ipv6_address_list_enabled = local.ipv6-list != null
  ipv6_prefixes             = try(var.network_interface.ipv6_prefixes, null) != null ? toset(var.network_interface.ipv6_prefixes) : null
  ipv6_prefix_count         = try(var.network_interface.ipv6_prefix_count, null)
  enable_primary_ipv6       = try(var.network_interface.enable_primary_ipv6, null)

  # Behaviour
  security_groups   = length(local.security-group-ids) > 0 ? toset(local.security-group-ids) : null
  source_dest_check = try(var.network_interface.source_dest_check, null)
  interface_type    = try(var.network_interface.interface_type, null)
  region            = try(var.network_interface.region, null)

  dynamic "connection_tracking_specification" {
    for_each = local.connection-tracking != null ? [local.connection-tracking] : []
    content {
      tcp_established_timeout = try(connection_tracking_specification.value.tcp_established_timeout, null)
      udp_stream_timeout      = try(connection_tracking_specification.value.udp_stream_timeout, null)
      udp_timeout             = try(connection_tracking_specification.value.udp_timeout, null)
    }
  }

  dynamic "ena_srd_specification" {
    for_each = local.ena-srd != null ? [local.ena-srd] : []
    content {
      ena_srd_enabled = try(ena_srd_specification.value.ena_srd_enabled, null)

      dynamic "ena_srd_udp_specification" {
        for_each = try(ena_srd_specification.value.ena_srd_udp_specification, null) != null ? [ena_srd_specification.value.ena_srd_udp_specification] : []
        content {
          ena_srd_udp_enabled = try(ena_srd_udp_specification.value.ena_srd_udp_enabled, null)
        }
      }
    }
  }

  # The provider supports an attachment inside the interface, but the standalone aws_network_interface_attachment (key
  # `attachment`) is the one to use: the two must not be combined.
  dynamic "attachment" {
    for_each = local.inline-attachment != null ? [local.inline-attachment] : []
    content {
      instance           = attachment.value.instance
      device_index       = attachment.value.device_index
      network_card_index = try(attachment.value.network_card_index, null)
    }
  }

  # Tags - Merging tags provided by ESLZ with tags provided by the user. Name is last so the naming standard wins.
  tags = merge(var.tags, try(var.network_interface.tags, {}), local.module_tag, { Name = local.interface-name })

  lifecycle {
    precondition {
      condition     = local.subnet-id != null
      error_message = "network_interface needs a subnet: a literal subnet_id, or vpc_key and subnet_key present in subnet_ids (known VPCs: ${join(", ", keys(var.subnet_ids))}; subnets of ${coalesce(local.vpc-key, "<no vpc_key>")}: ${join(", ", keys(try(var.subnet_ids[local.vpc-key], {})))})."
    }
    precondition {
      condition     = length(local.security-group-missing) == 0
      error_message = "network_interface.security_group_keys not found in security_group_ids: ${join(", ", local.security-group-missing)}."
    }
    precondition {
      condition     = length([for v in [local.private-ip, local.private-ips, local.private-ip-list] : v if v != null]) <= 1
      error_message = "network_interface takes one of private_ip, private_ips or private_ip_list, not several: private_ip and private_ips pin the addresses in the provider's set mode, private_ip_list in its ordered list mode."
    }
    precondition {
      condition     = local.private-ip-list == null || try(var.network_interface.private_ips_count, null) == null
      error_message = "network_interface.private_ips_count cannot be combined with private_ip_list (the list already says how many addresses the interface has)."
    }
    precondition {
      condition     = length([for v in [try(var.network_interface.ipv6_address_count, null), try(var.network_interface.ipv6_addresses, null), local.ipv6-list] : v if v != null]) <= 1
      error_message = "network_interface takes one of ipv6_address_count, ipv6_addresses or ipv6_address_list, not several."
    }
    precondition {
      condition     = try(var.network_interface.ipv4_prefixes, null) == null || try(var.network_interface.ipv4_prefix_count, null) == null
      error_message = "network_interface takes ipv4_prefixes or ipv4_prefix_count, not both."
    }
    precondition {
      condition     = try(var.network_interface.ipv6_prefixes, null) == null || try(var.network_interface.ipv6_prefix_count, null) == null
      error_message = "network_interface takes ipv6_prefixes or ipv6_prefix_count, not both."
    }
    precondition {
      condition     = try(length(var.network_interface.description), 0) <= 255
      error_message = "network_interface.description is at most 255 characters (the AWS limit); this one has ${try(length(var.network_interface.description), 0)}."
    }
    precondition {
      condition     = local.inline-attachment == null || try(var.network_interface.attachment, null) == null
      error_message = "network_interface takes attachment (a standalone aws_network_interface_attachment) or inline_attachment (a block of the interface), not both: combining them makes the plan differ forever."
    }
  }
}
