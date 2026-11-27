## Names follow Documentation/Standards/AWS-Naming-and-Tagging-Suffixes.md: <env>-<userDefinedString>-<suffix>
## (eni for a network interface, added to the standard with this module), letters, digits and hyphens, case kept.
## aws_network_interface has no name argument: the name is its Name tag, a value of at most 256 characters with no begin/end rule.
## The base is capped at 252 so that "<base>-eni" fits 256. The attachment, the security group attachment and the permission
## have no name and no tags: nothing is derived for them, so there is nothing to truncate.
locals {
  name-regex     = "/[^0-9A-Za-z-]/"
  env-compliant  = replace(var.env, local.name-regex, "")
  name-compliant = replace(var.userDefinedString, local.name-regex, "")

  # Truncate, then trim: the cut (or an empty env) can leave a leading/trailing hyphen.
  base-name-auto = trim(substr("${local.env-compliant}-${local.name-compliant}", 0, 252), "-")

  interface-name-custom = trim(substr(replace(try(var.network_interface.name, null) != null ? var.network_interface.name : "", local.name-regex, ""), 0, 256), "-")
  interface-name        = local.interface-name-custom != "" ? local.interface-name-custom : trim("${local.base-name-auto}-eni", "-")
}
