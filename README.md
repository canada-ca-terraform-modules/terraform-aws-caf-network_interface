# terraform-aws-caf-network_interface

CAF-compliant Terraform module for one AWS network interface (`aws_network_interface`) per module instance, with its optional standalone attachment to an instance, security group attachments and permissions for other accounts. Aligned with aws provider `~> 6.68` (tested against `6.71.0`): every argument and nested block of the four `aws_network_interface*` resources is reachable through the single `network_interface` object.

The interface is made on its own, with its subnet and security groups arriving through lookup maps, so that an appliance whose interfaces carry pinned addresses and a disabled source and destination check can have them in place before the instance starts. The typical consumer is a network appliance with three interfaces (management, private, public), attached by `terraform-aws-caf-ec2_instance` (the management interface at launch, the others as soon as the instance runs).

## Scope

| Always created | Created when the key is set |
| --- | --- |
| `aws_network_interface` | `aws_network_interface_attachment` (`attachment`), `aws_network_interface_sg_attachment` (`security_group_attachments`), `aws_network_interface_permission` (`permissions`) |

The four resources of the `aws_network_interface` prefix in provider 6.71.0 are all covered (checked with `scripts/coverage_check.sh`), so nothing is excluded inside the prefix. Three things need explaining:

- **`private_ip` is the module's pin, not the provider's argument.** The provider ignores its own `private_ip` argument when it creates an interface (it only reads the value back from AWS), so setting it would not pin anything. The module key `private_ip` sends the address as `private_ips` instead; see Pinned private addresses.
- **`private_ip_list_enabled` and `ipv6_address_list_enabled` are derived.** They only switch the provider between its set mode and its ordered list mode, so the module turns each on when `private_ip_list` or `ipv6_address_list` is given, and off otherwise.
- **The provider's `attachment` block of the interface is `inline_attachment`.** It is kept for parity, but the standalone `attachment` (`aws_network_interface_attachment`) is the one to use; the two must not be combined (a precondition says so).

Resources that share no prefix with this module but are coupled to it, and that the module does not create because they have their own lifecycle and owner:

- `aws_instance` (`terraform-aws-caf-ec2_instance`), which takes the interface at device index 0 at launch and attaches the others; `aws_security_group`, whose ids arrive through `security_group_ids`.
- `aws_eip` and `aws_eip_association`: the Elastic IP of an appliance's public interface belongs to the internet slice. An association takes this module's `id` output.
- `aws_route` (a route whose target is an interface), `aws_ec2_traffic_mirror_session` and `aws_ec2_traffic_mirror_target`: they consume an interface id and belong with routing and monitoring.
- `region`: the key `region` is passed through to all four resources; set the region on the provider unless an interface must live elsewhere.

## Which route attaches an interface to an instance

| Route | Use it for | Why |
| --- | --- | --- |
| `terraform-aws-caf-ec2_instance`, `network_interfaces` (by `device_index`), fed by this module's `id` | An appliance | The primary interface is given at launch and the others are attached by the instance module right after the instance is running, in the same apply. |
| `attachment` in this module | An interface of an instance made elsewhere | The interface is attached to an instance the caller names, after it is running (a hot-plug). |

The standalone attachment is optional and off by default. Do not set `attachment` on the interfaces of an appliance that reads them at boot.

## Usage

### ESLZ module block (`ESLZ/network_interface.tf`)

```hcl
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
```

Config is always a map keyed by name. See [`ESLZ/network_interface.tfvars`](ESLZ/network_interface.tfvars) for the full set of `network_interface` object parameters.

The lookup maps resolve foreign keys inside the module. Pass them straight from the modules that own the resources:

```hcl
subnet_ids         = { for k, v in module.vpc : k => v.subnet_ids }
security_group_ids = { for k, v in module.security_group : k => v.id }
instance_ids       = { for k, v in module.ec2_instance : k => v.id }
```

A literal ID in the object (`subnet_id`, `security_groups`, `attachment.instance_id`, `security_group_attachments.*.security_group_id`) wins over its key and stays available for a resource outside the composition. A key missing from its map fails the plan with a message naming the key. `instance_ids` is only read by `attachment`; an appliance made with the instance module does not use it.

### Feeding terraform-aws-caf-ec2_instance

`terraform-aws-caf-ec2_instance` reads its interfaces from a `network_interface_ids` map keyed by the name of each interface. This module's `id` output is that value, so a blueprint wires them with one expression and no adapter (a test run, `appliance_interfaces_wire_into_ec2_instance_without_an_adapter`, does exactly this):

```hcl
network_interface_ids = { for k, v in module.network_interface : k => v.id }
```

The instance names the same keys in its `network_interfaces`, with the device index of each. The `private_ip` and `private_ips` outputs give the addresses for anything that refers to them (a target group, a configuration file).

### Appliance with several interfaces

Three interfaces, each with its own security group. Device 0 is the management interface in the Mgmt-tier subnet. Device 1 is in the Private-tier subnet, and device 2 in the Public-tier subnet with a pinned private address, because the appliance's configuration refers to the address of its public interface. The appliance forwards traffic that is not addressed to it, so the source and destination check is off on both data interfaces:

```hcl
network_interfaces = {
  app-1a-mgmt = {
    vpc_key             = "main"
    subnet_key          = "Mgmt-1a"
    security_group_keys = ["app-1a-mgmt"]
  }
  app-1a-private = {
    vpc_key             = "main"
    subnet_key          = "Private-1a"
    security_group_keys = ["app-1a-private"]
    source_dest_check   = false
  }
  app-1a-public = {
    vpc_key             = "main"
    subnet_key          = "Public-1a"
    security_group_keys = ["app-1a-public"]
    source_dest_check   = false
    private_ip          = "10.20.0.200"
  }
}
```

The instance then takes the first at launch and attaches the other two (`terraform-aws-caf-ec2_instance`, `network_interfaces = { app-1a-mgmt = { device_index = 0 }, app-1a-private = { device_index = 1 }, app-1a-public = { device_index = 2 } }`). The test runs `appliance_*` in `tests/appliance.tftest.hcl` cover each interface and the wiring.

## Security groups

An interface made with no `security_group_keys` and no `security_groups` gets the VPC's default security group. Name its groups on the interface to avoid that. `security_group_attachments` adds groups to an interface (this one, or another by `network_interface_id`) and does not remove the default group, so use it for an interface whose groups another resource owns, and not together with `security_group_keys` or `security_groups` on the same interface (a precondition says so).

## Pinned private addresses

AWS assigns the primary private address at creation and never changes it, so a pin has to be in the first apply. Which key to use:

| Key | Meaning | Provider mode |
| --- | --- | --- |
| `private_ip` | The primary address of the interface, one address | set (`private_ips`) |
| `private_ips` | All the addresses, the primary included; an unordered set | set |
| `private_ips_count` | Secondary addresses AWS picks, beside `private_ip` or `private_ips` or alone | set |
| `private_ip_list` | All the addresses in order; the first is the primary | list (`private_ip_list_enabled` is turned on) |

Rules the module enforces with a precondition, because the provider would reject or silently ignore the combination: one of `private_ip`, `private_ips` and `private_ip_list`; `private_ip_list` not with `private_ips_count`; one of `ipv6_address_count`, `ipv6_addresses` and `ipv6_address_list`; `ipv4_prefixes` or `ipv4_prefix_count`, not both (the same for IPv6); `description` at most 255 characters.

Changing the primary address (`private_ip`, the first of `private_ips` or `private_ip_list`) replaces the interface. The address must be inside the subnet's range and not one of its first four or its last (AWS reserves them); a pinned address in a subnet that is rebuilt needs the same range.

## Naming

`aws_network_interface` has no name argument: the name is the `Name` tag, `<env>-<userDefinedString>-<suffix>` with the suffix `eni`, added to `Documentation/Standards/AWS-Naming-and-Tagging-Suffixes.md` with this module (the ARN resource type is `network-interface`, and the id starts with `eni-`). Letters, digits and hyphens are kept with their case, anything else is stripped. A tag value holds at most 256 characters with no begin or end rule; the base is cut at 252 characters so the suffix fits, and a hyphen the cut or an empty `env` leaves is trimmed. Set `network_interface.name` to replace the whole name (same sanitizing, cut at 256). The `Name` tag always wins over a `Name` in `tags` or `network_interface.tags`. The attachment, the security group attachment and the permission have no name and no tags. The boundaries (minimum, maximum, the cut, a hyphen at the cut, an empty `env`, a custom name) are test runs in `tests/naming.tftest.hcl`. The description is not derived: it is at most 255 characters, and the module rejects a longer one instead of cutting it.

## TFVars Parameters

### Interface (`network_interface`)

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| name | string, custom Name tag (letters, digits, hyphens; case kept) | No | `<env>-<userDefinedString>-eni` |
| vpc_key | key in `subnet_ids` | With `subnet_key` | n/a |
| subnet_key | key of a subnet under `vpc_key` in `subnet_ids` | One of `subnet_key` or `subnet_id` | n/a |
| subnet_id | literal subnet ID, wins over `subnet_key`; fixed at creation | See above | n/a |
| security_group_keys | list of keys of `security_group_ids`; with no group at all, AWS gives the interface the VPC default security group | No | [] (the VPC default group) |
| security_groups | list of literal SG IDs, merged with the keys | No | [] |
| description | string, at most 255 characters | No | none |
| source_dest_check | bool; `false` for a forwarding appliance (a router or a NAT, for example) | No | `true` (provider) |
| private_ip | string, pins the primary address (see Pinned private addresses) | No | AWS picks |
| private_ips | list of addresses, the primary included | No | AWS picks |
| private_ips_count | number of secondary addresses | No | provider default |
| private_ip_list | ordered list of addresses, the first is the primary | No | AWS picks |
| ipv4_prefixes, ipv4_prefix_count | list of CIDRs, or a number; not both | No | none |
| ipv6_address_count, ipv6_addresses, ipv6_address_list | a number, a set or an ordered list; one of them | No | none |
| ipv6_prefixes, ipv6_prefix_count | list of CIDRs, or a number; not both | No | none |
| enable_primary_ipv6 | bool; cannot be turned off again without replacing the interface | No | provider default |
| interface_type | `efa`, `efa-only`, `branch` or `trunk`; fixed at creation | No | a standard interface |
| region | string | No | provider region |
| tags | map of strings, merged with the `tags` variable | No | {} |
| connection_tracking_specification | `tcp_established_timeout` (60 to 432000), `udp_stream_timeout` (60 to 180), `udp_timeout` (30 to 60), in seconds | No | absent |
| ena_srd_specification | `ena_srd_enabled`, `ena_srd_udp_specification.ena_srd_udp_enabled`; AWS applies it only to an interface attached to an instance | No | absent |
| inline_attachment | `instance`, `device_index` (required), `network_card_index`; the provider's block of the interface, not with `attachment` | No | absent |

### Standalone attachment, security group attachments and permissions

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| attachment | `device_index` (required), `instance_key` (key of `instance_ids`) or `instance_id` (literal, wins), `network_card_index` | No | absent: no attachment |
| security_group_attachments | map of name to `{ security_group_key (key of security_group_ids) or security_group_id (literal, wins), network_interface_id (literal; this interface when absent), timeouts }`; not with `security_group_keys` or `security_groups` on the same interface; an interface with no groups has the VPC default group, and an attachment adds a group without removing it | No | {} |
| permissions | map of name to `{ aws_account_id, permission (INSTANCE-ATTACH or EIP-ASSOCIATE), timeouts }` | No | {} |

### Variables

| Variable | Type | Resolves |
| --- | --- | --- |
| env, userDefinedString | string | the Name tag |
| tags | map of strings | tags of the interface |
| subnet_ids | map of VPC key to a map of subnet key to ID | `vpc_key` and `subnet_key` |
| security_group_ids | map of key to ID | `security_group_keys` and `security_group_attachments.*.security_group_key` |
| instance_ids | map of key to ID | `attachment.instance_key` |

### Outputs

| Output | Meaning |
| --- | --- |
| id | The interface ID: the value of `network_interface_ids` in `terraform-aws-caf-ec2_instance`, keyed by the module key |
| private_ip, private_ips | The primary address, and every address of the interface |
| arn, name, object, ipv6_addresses, mac_address, private_dns_name, subnet_id, security_groups, owner_id | Attributes of the interface |
| attachment_id, attachment_status | Of the standalone attachment, null without one |
| permission_ids | Map of permission key to its ID |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.68 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.71.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_network_interface.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface) | resource |
| [aws_network_interface_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface_attachment) | resource |
| [aws_network_interface_permission.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface_permission) | resource |
| [aws_network_interface_sg_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface_sg_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | (Required) env value used in name generation | `string` | n/a | yes |
| <a name="input_instance_ids"></a> [instance\_ids](#input\_instance\_ids) | Optional map of EC2 instance key to its ID. Resolves network\_interface.attachment.instance\_key. e.g. { for k, v in module.ec2\_instance : k => v.id } | `map(string)` | `{}` | no |
| <a name="input_network_interface"></a> [network\_interface](#input\_network\_interface) | (Required) Object describing the network interface (see TFVars Parameters in the README). Optional `name` key overrides the auto-derived "<env>-<userDefinedString>-eni" Name tag value. | `any` | `{}` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Optional map of security group key to its ID. Resolves network\_interface.security\_group\_keys and the security\_group\_key of network\_interface.security\_group\_attachments. e.g. { for k, v in module.security\_group : k => v.id } | `map(string)` | `{}` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Optional map of VPC key to a map of subnet key to its ID. Resolves network\_interface.subnet\_key within network\_interface.vpc\_key. e.g. { for k, v in module.vpc : k => v.subnet\_ids } | `map(map(string))` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the interface (merged with network\_interface.tags) | `map(string)` | `{}` | no |
| <a name="input_userDefinedString"></a> [userDefinedString](#input\_userDefinedString) | (Required) UserDefinedString part of the name of the network interface | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | Returns the ARN of the network interface |
| <a name="output_attachment_id"></a> [attachment\_id](#output\_attachment\_id) | ID of the standalone attachment to an instance (null when the module has no attachment) |
| <a name="output_attachment_status"></a> [attachment\_status](#output\_attachment\_status) | Status of the standalone attachment to an instance (null when the module has no attachment) |
| <a name="output_id"></a> [id](#output\_id) | Returns the ID of the network interface; the value to put in the network\_interface\_ids map of terraform-aws-caf-ec2\_instance, keyed by the module key |
| <a name="output_ipv6_addresses"></a> [ipv6\_addresses](#output\_ipv6\_addresses) | IPv6 addresses of the interface |
| <a name="output_mac_address"></a> [mac\_address](#output\_mac\_address) | MAC address of the interface |
| <a name="output_name"></a> [name](#output\_name) | Returns the Name tag of the network interface |
| <a name="output_object"></a> [object](#output\_object) | Returns the full aws\_network\_interface resource object |
| <a name="output_owner_id"></a> [owner\_id](#output\_owner\_id) | AWS account ID of the owner of the interface |
| <a name="output_permission_ids"></a> [permission\_ids](#output\_permission\_ids) | Map of permission key to its network\_interface\_permission\_id |
| <a name="output_private_dns_name"></a> [private\_dns\_name](#output\_private\_dns\_name) | Private DNS name of the interface |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | Primary private IPv4 address of the interface |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | All private IPv4 addresses of the interface (the primary and the secondary ones), in the order the provider reports them |
| <a name="output_security_groups"></a> [security\_groups](#output\_security\_groups) | IDs of the security groups of the interface |
| <a name="output_subnet_id"></a> [subnet\_id](#output\_subnet\_id) | ID of the subnet the interface is in |
<!-- END_TF_DOCS -->
