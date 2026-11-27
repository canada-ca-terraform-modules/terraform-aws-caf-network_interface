## One example interface per key; the key becomes userDefinedString (Name tag: <env>-<key>-eni) and the key of the id in
## { for k, v in module.network_interface : k => v.id }, which terraform-aws-caf-ec2_instance reads as network_interface_ids.
## The first three are the interfaces of a network appliance. The
## appliance is given them by device index, with ec2_instance (network_interfaces = { app-1a-mgmt = { device_index = 0 }, ... }), which
## attaches them, so none of them sets `attachment` (that one is for an instance made elsewhere). Every optional key of the last one is
## listed commented out; group headings match the README.

network_interfaces = {
  app-1a-mgmt = {
    vpc_key             = "main"                         # key of subnet_ids
    subnet_key          = "Mgmt-1a"                      # device 0, management: key of that VPC's subnets, Mgmt tier
    security_group_keys = ["app-1a-mgmt"]                # keys of security_group_ids
    description         = "app-1a management (device 0)" # shown in the console; at most 255 characters
  }

  app-1a-private = {
    vpc_key             = "main"                      # the VPC of the appliance
    subnet_key          = "Private-1a"                # device 1: Private tier
    security_group_keys = ["app-1a-private"]          # GENEVE 6081 and the health check port from the GWLB
    source_dest_check   = false                       # the appliance forwards traffic that is not addressed to it
    description         = "app-1a private (device 1)" # shown in the console
  }

  app-1a-public = {
    vpc_key             = "main"            # the VPC of the appliance
    subnet_key          = "Public-1a"       # device 2: Public tier
    security_group_keys = ["app-1a-public"] # no inbound
    source_dest_check   = false             # the appliance forwards traffic that is not addressed to it
    # Public-1a range, not one of the subnet's first four addresses or its last (AWS reserves them)
    private_ip  = "10.20.0.200"              # example address, pinned because the appliance's configuration refers to it
    description = "app-1a public (device 2)" # shown in the console
  }

  example01 = {
    # --- subnet: ONE of subnet_key (with vpc_key) or a literal subnet_id ---
    vpc_key    = "client1" # key of subnet_ids
    subnet_key = "app-1a"  # key of that VPC's subnets
    # subnet_id = "subnet-0123456789abcdef0" # wins over the keys

    # --- security groups ---
    # security_group_keys = ["app"]                    # keys of security_group_ids
    # security_groups     = ["sg-0123456789abcdef0"]   # literal ids, merged with the keys

    # --- addresses: ONE of private_ip, private_ips or private_ip_list (private_ip_list not with private_ips_count) ---
    # private_ip        = "10.0.1.10"                  # pins the primary address (sent as private_ips: the provider ignores its own private_ip when it creates the interface)
    # private_ips       = ["10.0.1.10", "10.0.1.11"]   # pins all the addresses, the primary included; an unordered set
    # private_ips_count = 1                            # secondary addresses AWS picks
    # private_ip_list   = ["10.0.1.10", "10.0.1.11"]   # ordered, the first is the primary; turns the provider's list mode on
    # ONE of ipv6_address_count, ipv6_addresses or ipv6_address_list
    # ipv6_address_count = 1 / ipv6_addresses = ["2600:1f18::10"] / ipv6_address_list = ["2600:1f18::10"]
    # ipv4_prefixes = ["10.0.2.16/28"] or ipv4_prefix_count = 1 (not both); ipv6_prefixes = ["2600:1f18:1::/80"] or ipv6_prefix_count = 1 (not both)
    # enable_primary_ipv6 = true

    # --- behaviour ---
    # source_dest_check = false                        # default true
    # description       = "text, at most 255 characters"
    # interface_type    = "efa"                        # efa, efa-only, branch or trunk; fixed at creation
    # connection_tracking_specification = { tcp_established_timeout = 432000, udp_stream_timeout = 60, udp_timeout = 30 } # seconds
    # ena_srd_specification = { ena_srd_enabled = true, ena_srd_udp_specification = { ena_srd_udp_enabled = true } } # needs the interface attached to an instance
    # region = "ca-central-1"

    # --- standalone attachment to an existing instance (not for an appliance that reads its interfaces at boot: see the README) ---
    # attachment = { instance_key = "app", device_index = 1, network_card_index = 0 } # instance_key in instance_ids; instance_id (literal) wins
    # inline_attachment = { instance = "i-0123456789abcdef0", device_index = 1, network_card_index = 0 } # provider block of the interface; not with attachment

    # --- security group attachments (not with security_group_keys or security_groups on this interface) ---
    # An interface with no security groups gets the VPC default group; an attachment adds a group and does not remove it.
    # security_group_attachments = {
    #   app   = { security_group_key = "app" }                                                          # this interface
    #   other = { security_group_id = "sg-0123456789abcdef0", network_interface_id = "eni-0123456789abcdef0", timeouts = { create = "5m", delete = "5m", read = "5m" } }
    # }

    # --- permissions for another account ---
    # permissions = { partner = { aws_account_id = "123456789012", permission = "INSTANCE-ATTACH", timeouts = { create = "5m", delete = "5m" } } } # or EIP-ASSOCIATE

    # name = "custom-name" # replaces <env>-<key>-eni (letters, digits and hyphens kept, at most 256 characters)
    tags = { workload = "example" } # merged with the ESLZ-level tags
  }
}
