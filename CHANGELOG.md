# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This file must be updated as part of every change to this module.

## [Unreleased]

### Changed

- The README, the tfvars example, the comments and the tests describe a network appliance with three interfaces, with no product or design
  document named; the test file is `tests/appliance.tftest.hcl` and its runs are `appliance_*`. No behaviour changes. The examples use the neutral VPC key `main`.
- The documentation and the wiring test follow `terraform-aws-caf-ec2_instance`, which now gives the interface at device index 0 as the
  primary interface and attaches the others (the provider deprecates the `network_interface` block); no argument or output of this module
  changes. The comments of the tfvars example and of the appliance test say the same.

## [1.0.0]

### Added

- Initial release: one `aws_network_interface` per module instance, declared with a single `network_interface = each.value`, for an
  interface made on its own and attached to an instance elsewhere. Every argument and nested block of the four resources of the
  `aws_network_interface` prefix is reachable: `aws_network_interface`, `aws_network_interface_attachment`,
  `aws_network_interface_sg_attachment` and `aws_network_interface_permission`. `scripts/coverage_check.sh` reports full parity, with
  nothing excluded inside the prefix.
- Pinned private addresses: `private_ip` (the primary address), `private_ips`, `private_ips_count` and the ordered `private_ip_list`,
  with the same for IPv6 (`ipv6_address_count`, `ipv6_addresses`, `ipv6_address_list`) and for prefixes. The provider ignores its own
  `private_ip` argument when it creates an interface, so the module sends the key as `private_ips`; the list modes
  (`private_ip_list_enabled`, `ipv6_address_list_enabled`) are derived from the list being given. Preconditions reject the
  combinations the provider rejects or silently ignores, and a description over 255 characters.
- `source_dest_check`, `description`, `interface_type`, `enable_primary_ipv6`, `connection_tracking_specification`,
  `ena_srd_specification` and the provider's `inline_attachment` block.
- Foreign keys through lookup maps with literal escape hatches: `subnet_key` with `vpc_key` (`subnet_ids`), `security_group_keys`
  (`security_group_ids`), `attachment.instance_key` (`instance_ids`). A precondition names a missing key.
- The standalone attachment (`attachment`) is optional and off by default; the README says to attach an appliance's interfaces at launch
  with `terraform-aws-caf-ec2_instance` (`network_interfaces`, by device index), fed by this module's `id` output
  (`network_interface_ids = { for k, v in module.network_interface : k => v.id }`), because an attachment after launch is not there at
  boot. A test run wires the module into `ec2_instance` with no adapter.
- Provider `~> 6.68`, tested against `6.71.0`. Test runs cover each feature (present and absent), each rejected combination, the three
  three interfaces of an appliance (management, private with the check off, public with the check off and a
  pinned address) and the Name tag limits. The Name tag is `<env>-<userDefinedString>-eni` (the suffix `eni` is added to
  `Documentation/Standards/AWS-Naming-and-Tagging-Suffixes.md` with this module), letters, digits and hyphens with the case kept, at
  most 256 characters.
