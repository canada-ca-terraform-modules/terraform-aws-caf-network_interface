# One run per feature, proving both presence (when configured) and absence (when not). The base object is the smallest valid
# interface: a subnet picked by key. A rejection run breaks only the rule it names and sits beside an accepting run of the same fixture.
# An argument the module passes through unchanged (description, ipv6_address_count, ...) has no absence to observe in a plan: an unset
# optional argument is unknown until the provider answers, so only the blocks and the resources test their absence.

mock_provider "aws" {}

variables {
  env               = "Dev"
  userDefinedString = "myapp"
  tags              = { environment = "test" }
  subnet_ids        = { main = { app = "subnet-0123456789abcdef0", web = "subnet-0123456789abcdef1" } }
  security_group_ids = {
    app = "sg-0123456789abcdef0"
    web = "sg-0123456789abcdef1"
  }
  instance_ids = { app = "i-0123456789abcdef0" }
  network_interface = {
    vpc_key    = "main"
    subnet_key = "app"
  }
}

# ---------------------------------------------------------------------------
# the interface and its subnet
# ---------------------------------------------------------------------------
run "interface_with_a_subnet_key" {
  command = plan

  assert {
    condition     = aws_network_interface.this.subnet_id == "subnet-0123456789abcdef0"
    error_message = "vpc_key and subnet_key must resolve through subnet_ids"
  }
  assert {
    condition     = aws_network_interface.this.tags["environment"] == "test" && aws_network_interface.this.tags["module"] == "terraform-aws-caf-network_interface"
    error_message = "The tags variable and the module tag must be set"
  }
  assert {
    condition     = length(aws_network_interface_attachment.this) == 0 && length(aws_network_interface_sg_attachment.this) == 0 && length(aws_network_interface_permission.this) == 0
    error_message = "Without attachment, security_group_attachments or permissions the module must create only the interface"
  }
}

run "subnet_literal_wins_over_the_key" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      subnet_id  = "subnet-0fedcba9876543210"
    }
  }

  assert {
    condition     = aws_network_interface.this.subnet_id == "subnet-0fedcba9876543210"
    error_message = "A literal subnet_id must win over subnet_key"
  }
}

run "subnet_literal_alone_needs_no_lookup_map" {
  command = plan

  variables {
    subnet_ids = {}
    network_interface = {
      subnet_id = "subnet-0fedcba9876543210"
    }
  }

  assert {
    condition     = aws_network_interface.this.subnet_id == "subnet-0fedcba9876543210"
    error_message = "A literal subnet_id must work with an empty subnet_ids map"
  }
}

run "subnet_unknown_key_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "missing"
    }
  }

  expect_failures = [aws_network_interface.this]
}

run "subnet_unknown_vpc_key_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "other"
      subnet_key = "app"
    }
  }

  expect_failures = [aws_network_interface.this]
}

run "description_of_255_characters_is_accepted" {
  command = plan

  variables {
    network_interface = {
      vpc_key     = "main"
      subnet_key  = "app"
      description = join("", [for i in range(255) : "d"])
    }
  }

  assert {
    condition     = length(aws_network_interface.this.description) == 255
    error_message = "A 255-character description is the AWS maximum and must be accepted"
  }
}

run "description_of_256_characters_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key     = "main"
      subnet_key  = "app"
      description = join("", [for i in range(256) : "d"])
    }
  }

  expect_failures = [aws_network_interface.this]
}

run "source_dest_check_off" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      source_dest_check = false
    }
  }

  assert {
    condition     = aws_network_interface.this.source_dest_check == false
    error_message = "source_dest_check = false must reach the interface"
  }
}

run "interface_type_and_primary_ipv6" {
  command = plan

  variables {
    network_interface = {
      vpc_key             = "main"
      subnet_key          = "app"
      interface_type      = "efa"
      enable_primary_ipv6 = true
      region              = "ca-central-1"
    }
  }

  assert {
    condition     = aws_network_interface.this.interface_type == "efa" && aws_network_interface.this.enable_primary_ipv6 == true && aws_network_interface.this.region == "ca-central-1"
    error_message = "interface_type, enable_primary_ipv6 and region must reach the interface"
  }
}

# ---------------------------------------------------------------------------
# security groups: keys resolve through security_group_ids, literal ids merge with them
# ---------------------------------------------------------------------------
run "security_groups_by_key_and_literal" {
  command = plan

  variables {
    network_interface = {
      vpc_key             = "main"
      subnet_key          = "app"
      security_group_keys = ["app", "web"]
      security_groups     = ["sg-0fedcba9876543210"]
    }
  }

  assert {
    condition     = aws_network_interface.this.security_groups == toset(["sg-0123456789abcdef0", "sg-0123456789abcdef1", "sg-0fedcba9876543210"])
    error_message = "Keys must resolve through security_group_ids and merge with the literal ids"
  }
}

run "security_group_unknown_key_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key             = "main"
      subnet_key          = "app"
      security_group_keys = ["app", "missing"]
    }
  }

  expect_failures = [aws_network_interface.this]
}

# ---------------------------------------------------------------------------
# pinned private addresses. The provider ignores its own private_ip argument when it creates the interface (it is read-only in
# effect), so the module's private_ip pins the primary address through private_ips.
# ---------------------------------------------------------------------------
run "private_ip_pins_the_primary_address" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      private_ip = "10.0.1.10"
    }
  }

  assert {
    condition     = aws_network_interface.this.private_ips == toset(["10.0.1.10"]) && aws_network_interface.this.private_ip_list_enabled == false
    error_message = "private_ip must be sent as private_ips with the list mode off"
  }
}

run "private_ips_with_secondary_count" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      private_ips       = ["10.0.1.10", "10.0.1.11"]
      private_ips_count = 1
    }
  }

  assert {
    condition     = aws_network_interface.this.private_ips == toset(["10.0.1.10", "10.0.1.11"]) && aws_network_interface.this.private_ips_count == 1
    error_message = "private_ips and private_ips_count must reach the interface"
  }
}

run "private_ip_list_keeps_the_order_and_turns_the_list_mode_on" {
  command = plan

  variables {
    network_interface = {
      vpc_key         = "main"
      subnet_key      = "app"
      private_ip_list = ["10.0.1.11", "10.0.1.10"]
    }
  }

  assert {
    condition     = aws_network_interface.this.private_ip_list == tolist(["10.0.1.11", "10.0.1.10"]) && aws_network_interface.this.private_ip_list_enabled == true
    error_message = "private_ip_list must keep its order (the first is the primary) and enable the list mode"
  }
}

run "private_ip_with_private_ips_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key     = "main"
      subnet_key  = "app"
      private_ip  = "10.0.1.10"
      private_ips = ["10.0.1.10"]
    }
  }

  expect_failures = [aws_network_interface.this]
}

run "private_ip_with_private_ip_list_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key         = "main"
      subnet_key      = "app"
      private_ip      = "10.0.1.10"
      private_ip_list = ["10.0.1.10"]
    }
  }

  expect_failures = [aws_network_interface.this]
}

run "private_ip_list_with_private_ips_count_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      private_ip_list   = ["10.0.1.10"]
      private_ips_count = 1
    }
  }

  expect_failures = [aws_network_interface.this]
}

# ---------------------------------------------------------------------------
# IPv6 addresses and prefixes
# ---------------------------------------------------------------------------
run "ipv6_address_count" {
  command = plan

  variables {
    network_interface = {
      vpc_key            = "main"
      subnet_key         = "app"
      ipv6_address_count = 2
    }
  }

  assert {
    condition     = aws_network_interface.this.ipv6_address_count == 2 && aws_network_interface.this.ipv6_address_list_enabled == false
    error_message = "ipv6_address_count must reach the interface with the list mode off"
  }
}

run "ipv6_addresses" {
  command = plan

  variables {
    network_interface = {
      vpc_key        = "main"
      subnet_key     = "app"
      ipv6_addresses = ["2600:1f18::10", "2600:1f18::11"]
    }
  }

  assert {
    condition     = aws_network_interface.this.ipv6_addresses == toset(["2600:1f18::10", "2600:1f18::11"])
    error_message = "ipv6_addresses must reach the interface"
  }
}

run "ipv6_address_list_turns_the_list_mode_on" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      ipv6_address_list = ["2600:1f18::11", "2600:1f18::10"]
    }
  }

  assert {
    condition     = aws_network_interface.this.ipv6_address_list == tolist(["2600:1f18::11", "2600:1f18::10"]) && aws_network_interface.this.ipv6_address_list_enabled == true
    error_message = "ipv6_address_list must keep its order and enable the list mode"
  }
}

run "ipv6_address_count_with_addresses_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key            = "main"
      subnet_key         = "app"
      ipv6_address_count = 1
      ipv6_addresses     = ["2600:1f18::10"]
    }
  }

  expect_failures = [aws_network_interface.this]
}

run "ipv6_address_list_with_addresses_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      ipv6_address_list = ["2600:1f18::10"]
      ipv6_addresses    = ["2600:1f18::10"]
    }
  }

  expect_failures = [aws_network_interface.this]
}

run "ipv4_and_ipv6_prefixes" {
  command = plan

  variables {
    network_interface = {
      vpc_key       = "main"
      subnet_key    = "app"
      ipv4_prefixes = ["10.0.2.16/28"]
      ipv6_prefixes = ["2600:1f18:1::/80"]
    }
  }

  assert {
    condition     = aws_network_interface.this.ipv4_prefixes == toset(["10.0.2.16/28"]) && aws_network_interface.this.ipv6_prefixes == toset(["2600:1f18:1::/80"])
    error_message = "ipv4_prefixes and ipv6_prefixes must reach the interface"
  }
}

run "prefix_counts" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      ipv4_prefix_count = 1
      ipv6_prefix_count = 2
    }
  }

  assert {
    condition     = aws_network_interface.this.ipv4_prefix_count == 1 && aws_network_interface.this.ipv6_prefix_count == 2
    error_message = "ipv4_prefix_count and ipv6_prefix_count must reach the interface"
  }
}

run "ipv4_prefixes_with_count_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      ipv4_prefixes     = ["10.0.2.16/28"]
      ipv4_prefix_count = 1
    }
  }

  expect_failures = [aws_network_interface.this]
}

run "ipv6_prefixes_with_count_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      ipv6_prefixes     = ["2600:1f18:1::/80"]
      ipv6_prefix_count = 1
    }
  }

  expect_failures = [aws_network_interface.this]
}

# ---------------------------------------------------------------------------
# nested blocks: connection tracking, ENA Express, the inline attachment
# ---------------------------------------------------------------------------
run "connection_tracking_specification_present" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      connection_tracking_specification = {
        tcp_established_timeout = 600
        udp_stream_timeout      = 120
        udp_timeout             = 40
      }
    }
  }

  assert {
    condition     = length(aws_network_interface.this.connection_tracking_specification) == 1 && aws_network_interface.this.connection_tracking_specification[0].tcp_established_timeout == 600 && aws_network_interface.this.connection_tracking_specification[0].udp_stream_timeout == 120 && aws_network_interface.this.connection_tracking_specification[0].udp_timeout == 40
    error_message = "connection_tracking_specification must reach the interface with its three timeouts"
  }
}

run "connection_tracking_specification_absent" {
  command = plan

  assert {
    condition     = length(aws_network_interface.this.connection_tracking_specification) == 0
    error_message = "Without connection_tracking_specification the block must be absent"
  }
}

run "ena_srd_specification_present" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      ena_srd_specification = {
        ena_srd_enabled           = true
        ena_srd_udp_specification = { ena_srd_udp_enabled = true }
      }
    }
  }

  assert {
    condition     = length(aws_network_interface.this.ena_srd_specification) == 1 && aws_network_interface.this.ena_srd_specification[0].ena_srd_enabled == true && aws_network_interface.this.ena_srd_specification[0].ena_srd_udp_specification[0].ena_srd_udp_enabled == true
    error_message = "ena_srd_specification must reach the interface with its UDP specification"
  }
}

run "ena_srd_specification_absent" {
  command = plan

  assert {
    condition     = length(aws_network_interface.this.ena_srd_specification) == 0
    error_message = "Without ena_srd_specification the block must be absent"
  }
}

run "inline_attachment_present" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      inline_attachment = { instance = "i-0123456789abcdef0", device_index = 1 }
    }
  }

  assert {
    condition     = length(aws_network_interface.this.attachment) == 1 && one(aws_network_interface.this.attachment).instance == "i-0123456789abcdef0" && one(aws_network_interface.this.attachment).device_index == 1
    error_message = "inline_attachment must reach the attachment block of the interface"
  }
}

# ---------------------------------------------------------------------------
# the standalone attachment (aws_network_interface_attachment): optional, the instance by key or literal
# ---------------------------------------------------------------------------
run "attachment_by_instance_key" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      attachment = { instance_key = "app", device_index = 1 }
    }
  }

  assert {
    condition     = length(aws_network_interface_attachment.this) == 1 && aws_network_interface_attachment.this["this"].instance_id == "i-0123456789abcdef0" && aws_network_interface_attachment.this["this"].device_index == 1
    error_message = "instance_key must resolve through instance_ids and device_index must be set"
  }
}

run "attachment_by_literal_instance_with_network_card" {
  command = plan

  variables {
    instance_ids = {}
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      attachment = { instance_id = "i-0fedcba9876543210", device_index = 2, network_card_index = 1 }
    }
  }

  assert {
    condition     = aws_network_interface_attachment.this["this"].instance_id == "i-0fedcba9876543210" && aws_network_interface_attachment.this["this"].network_card_index == 1
    error_message = "A literal instance_id must work with an empty instance_ids map, and network_card_index must be set"
  }
}

run "attachment_literal_wins_over_the_key" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      attachment = { instance_key = "app", instance_id = "i-0fedcba9876543210", device_index = 1 }
    }
  }

  assert {
    condition     = aws_network_interface_attachment.this["this"].instance_id == "i-0fedcba9876543210"
    error_message = "A literal instance_id must win over instance_key"
  }
}

run "attachment_absent" {
  command = plan

  assert {
    condition     = length(aws_network_interface_attachment.this) == 0
    error_message = "Without attachment there must be no aws_network_interface_attachment"
  }
}

run "attachment_unknown_instance_key_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      attachment = { instance_key = "missing", device_index = 1 }
    }
  }

  expect_failures = [aws_network_interface_attachment.this]
}

run "attachment_with_inline_attachment_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key           = "main"
      subnet_key        = "app"
      attachment        = { instance_key = "app", device_index = 1 }
      inline_attachment = { instance = "i-0123456789abcdef0", device_index = 1 }
    }
  }

  expect_failures = [aws_network_interface.this]
}

# ---------------------------------------------------------------------------
# security group attachments (aws_network_interface_sg_attachment), keyed by name
# ---------------------------------------------------------------------------
run "security_group_attachments_default_to_this_interface" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      security_group_attachments = {
        app = { security_group_key = "app" }
        web = { security_group_id = "sg-0fedcba9876543210" }
      }
    }
  }

  assert {
    condition     = length(aws_network_interface_sg_attachment.this) == 2 && aws_network_interface_sg_attachment.this["app"].security_group_id == "sg-0123456789abcdef0" && aws_network_interface_sg_attachment.this["web"].security_group_id == "sg-0fedcba9876543210"
    error_message = "Each entry must resolve its group by key or literal id"
  }
}

run "security_group_attachment_to_another_interface" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      security_group_attachments = {
        app = { security_group_key = "app", network_interface_id = "eni-0123456789abcdef9", timeouts = { create = "5m", delete = "5m", read = "1m" } }
      }
      security_group_keys = ["web"]
    }
  }

  assert {
    condition     = aws_network_interface_sg_attachment.this["app"].network_interface_id == "eni-0123456789abcdef9"
    error_message = "A literal network_interface_id must target another interface"
  }
  assert {
    condition     = aws_network_interface_sg_attachment.this["app"].timeouts.create == "5m" && aws_network_interface_sg_attachment.this["app"].timeouts.read == "1m"
    error_message = "timeouts must reach the security group attachment"
  }
}

run "security_group_attachments_absent" {
  command = plan

  assert {
    condition     = length(aws_network_interface_sg_attachment.this) == 0
    error_message = "Without security_group_attachments there must be no aws_network_interface_sg_attachment"
  }
}

run "security_group_attachment_unknown_key_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      security_group_attachments = {
        app = { security_group_key = "missing" }
      }
    }
  }

  expect_failures = [aws_network_interface_sg_attachment.this]
}

run "security_group_attachment_beside_security_groups_is_rejected" {
  command = plan

  variables {
    network_interface = {
      vpc_key             = "main"
      subnet_key          = "app"
      security_group_keys = ["web"]
      security_group_attachments = {
        app = { security_group_key = "app" }
      }
    }
  }

  expect_failures = [aws_network_interface_sg_attachment.this]
}

# ---------------------------------------------------------------------------
# permissions (aws_network_interface_permission), keyed by name
# ---------------------------------------------------------------------------
run "permissions_present" {
  command = plan

  variables {
    network_interface = {
      vpc_key    = "main"
      subnet_key = "app"
      permissions = {
        partner = { aws_account_id = "123456789012", permission = "INSTANCE-ATTACH" }
        eip     = { aws_account_id = "210987654321", permission = "EIP-ASSOCIATE", timeouts = { create = "5m", delete = "5m" } }
      }
    }
  }

  assert {
    condition     = length(aws_network_interface_permission.this) == 2 && aws_network_interface_permission.this["partner"].aws_account_id == "123456789012" && aws_network_interface_permission.this["eip"].permission == "EIP-ASSOCIATE"
    error_message = "Each permission must reach its own resource"
  }
  assert {
    condition     = aws_network_interface_permission.this["eip"].timeouts.create == "5m" && aws_network_interface_permission.this["eip"].timeouts.delete == "5m"
    error_message = "timeouts must reach the permission"
  }
}

run "permissions_absent" {
  command = plan

  assert {
    condition     = length(aws_network_interface_permission.this) == 0
    error_message = "Without permissions there must be no aws_network_interface_permission"
  }
}
