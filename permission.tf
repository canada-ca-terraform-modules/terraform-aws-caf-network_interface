## Permissions that let another AWS account attach the interface to its instance or associate an Elastic IP with it.
resource "aws_network_interface_permission" "this" {
  for_each = try(var.network_interface.permissions, {})

  network_interface_id = aws_network_interface.this.id
  aws_account_id       = each.value.aws_account_id
  permission           = each.value.permission
  region               = try(var.network_interface.region, null)

  dynamic "timeouts" {
    for_each = try(each.value.timeouts, null) != null ? [each.value.timeouts] : []
    content {
      create = try(timeouts.value.create, null)
      delete = try(timeouts.value.delete, null)
    }
  }
}
