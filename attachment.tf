## Attachment of the interface to an instance made elsewhere, and the security group attachments. The interfaces of an instance made
## with terraform-aws-caf-ec2_instance are given to it instead (network_interfaces, by device index), fed by this module's id output.
locals {
  # A literal instance_id wins; otherwise instance_key resolves through instance_ids.
  attachment              = try(var.network_interface.attachment, null)
  attachment-instance-key = try(local.attachment.instance_key, null)
  attachment-instance-id  = try(local.attachment.instance_id, null) != null ? local.attachment.instance_id : try(var.instance_ids[local.attachment-instance-key], null)

  # A literal security_group_id wins; otherwise security_group_key resolves through security_group_ids. Without a
  # network_interface_id an entry targets this interface.
  security-group-attachments = {
    for k, v in try(var.network_interface.security_group_attachments, {}) : k => {
      security_group_id    = try(v.security_group_id, null) != null ? v.security_group_id : try(var.security_group_ids[v.security_group_key], null)
      network_interface_id = try(v.network_interface_id, null)
      timeouts             = try(v.timeouts, null)
    }
  }
  security-group-attachments-missing = [
    for k, v in try(var.network_interface.security_group_attachments, {}) : k
    if try(v.security_group_id, null) == null && !contains(keys(var.security_group_ids), try(v.security_group_key, ""))
  ]
}

resource "aws_network_interface_attachment" "this" {
  for_each = local.attachment != null ? { this = local.attachment } : {}

  network_interface_id = aws_network_interface.this.id
  instance_id          = local.attachment-instance-id
  device_index         = each.value.device_index
  network_card_index   = try(each.value.network_card_index, null)
  region               = try(var.network_interface.region, null)

  lifecycle {
    precondition {
      condition     = local.attachment-instance-id != null
      error_message = "network_interface.attachment needs a literal instance_id, or an instance_key present in instance_ids (known: ${join(", ", keys(var.instance_ids))})."
    }
  }
}

resource "aws_network_interface_sg_attachment" "this" {
  for_each = local.security-group-attachments

  network_interface_id = each.value.network_interface_id != null ? each.value.network_interface_id : aws_network_interface.this.id
  security_group_id    = each.value.security_group_id
  region               = try(var.network_interface.region, null)

  dynamic "timeouts" {
    for_each = each.value.timeouts != null ? [each.value.timeouts] : []
    content {
      create = try(timeouts.value.create, null)
      delete = try(timeouts.value.delete, null)
      read   = try(timeouts.value.read, null)
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.security-group-attachments-missing) == 0
      error_message = "network_interface.security_group_attachments entries without a security_group_id need a security_group_key present in security_group_ids: ${join(", ", local.security-group-attachments-missing)} (known: ${join(", ", keys(var.security_group_ids))})."
    }
    precondition {
      condition     = each.value.network_interface_id != null || length(local.security-group-ids) == 0
      error_message = "network_interface.security_group_attachments on this interface cannot be combined with security_group_keys or security_groups: the interface would claim the whole set of groups and the plan would differ forever. Use one or the other."
    }
  }
}
