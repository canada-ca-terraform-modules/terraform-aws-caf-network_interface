# Naming: <env>-<userDefinedString>-eni in the Name tag (aws_network_interface has no name argument): letters, digits and hyphens,
# case kept, at most 256 characters (a tag value), no begin/end rule beyond the hyphen the cut can leave. The base is capped at 252
# so that "<base>-eni" fits 256. The runs below cover the minimum and maximum length, the 252-character boundary and one below it,
# a cut landing on a hyphen, an empty env and name, and the custom name (sanitized, cut and trimmed the same way).
# The other resources of the module (attachment, security group attachment, permission) have no name and no tags: nothing to derive.

mock_provider "aws" {}

variables {
  env               = "Dev"
  userDefinedString = "myapp"
  tags              = { environment = "test" }
  network_interface = {
    subnet_id = "subnet-0123456789abcdef0"
  }
}

run "naming_convention" {
  command = plan

  assert {
    condition     = aws_network_interface.this.tags["Name"] == "Dev-myapp-eni"
    error_message = "Name tag must default to <env>-<userDefinedString>-eni and keep its case"
  }
  assert {
    condition     = output.name == "Dev-myapp-eni"
    error_message = "The name output must be the Name tag"
  }
}

run "naming_convention_minimum_length" {
  command = plan

  variables {
    env               = "a"
    userDefinedString = "b"
  }

  assert {
    condition     = aws_network_interface.this.tags["Name"] == "a-b-eni"
    error_message = "A one-character env and userDefinedString must still produce a Name tag"
  }
}

run "naming_convention_strips_disallowed_characters" {
  command = plan

  variables {
    env               = "G3Pg"
    userDefinedString = "Main app_1!"
  }

  assert {
    condition     = aws_network_interface.this.tags["Name"] == "G3Pg-Mainapp1-eni"
    error_message = "Characters outside letters, digits and hyphens must be stripped"
  }
}

run "naming_convention_maximum_length" {
  command = plan

  variables {
    userDefinedString = join("", [for i in range(300) : "x"])
  }

  assert {
    condition     = length(aws_network_interface.this.tags["Name"]) == 256 && endswith(aws_network_interface.this.tags["Name"], "-eni")
    error_message = "Name tag must be cut to exactly 256 characters and keep its suffix"
  }
}

run "naming_convention_truncation_boundary" {
  command = plan

  # "Dev-" is 4 characters: 248 characters of name fill the 252-character base exactly (256 with the suffix), 247 leave one free.
  variables {
    userDefinedString = join("", [for i in range(248) : "x"])
  }

  assert {
    condition     = length(aws_network_interface.this.tags["Name"]) == 256
    error_message = "A base that fills the cap exactly must give a 256-character name"
  }
}

run "naming_convention_one_below_the_boundary" {
  command = plan

  variables {
    userDefinedString = join("", [for i in range(247) : "x"])
  }

  assert {
    condition     = length(aws_network_interface.this.tags["Name"]) == 255
    error_message = "A base one below the cap must give a 255-character name"
  }
}

run "naming_convention_cut_landing_on_a_hyphen" {
  command = plan

  # The base is "Dev-" + 247 x + "-" + "yyyy": the 252-character cut ends on the hyphen at position 252, which is trimmed.
  variables {
    userDefinedString = "${join("", [for i in range(247) : "x"])}-yyyy"
  }

  assert {
    condition     = !strcontains(aws_network_interface.this.tags["Name"], "--") && length(aws_network_interface.this.tags["Name"]) == 255
    error_message = "A hyphen left at the end of the cut must be trimmed before the suffix, not doubled"
  }
}

run "naming_convention_empty_env_and_name" {
  command = plan

  variables {
    env               = "-"
    userDefinedString = "!"
  }

  assert {
    condition     = aws_network_interface.this.tags["Name"] == "eni"
    error_message = "A base that sanitizes to nothing must not leave a leading hyphen"
  }
}

run "naming_custom_name_override" {
  command = plan

  variables {
    network_interface = {
      subnet_id = "subnet-0123456789abcdef0"
      name      = "G3Cg-Security-app1 mgmt!"
    }
  }

  assert {
    condition     = aws_network_interface.this.tags["Name"] == "G3Cg-Security-app1mgmt"
    error_message = "A custom name replaces the derived one, sanitized and with its case kept"
  }
}

run "naming_custom_name_is_capped_and_trimmed" {
  command = plan

  # 255 characters then a hyphen: the 256-character cut ends on the hyphen, which is trimmed.
  variables {
    network_interface = {
      subnet_id = "subnet-0123456789abcdef0"
      name      = "${join("", [for i in range(255) : "z"])}-y"
    }
  }

  assert {
    condition     = length(aws_network_interface.this.tags["Name"]) == 255 && !endswith(aws_network_interface.this.tags["Name"], "-")
    error_message = "A custom name goes through the same cut and trim as the derived one"
  }
}

run "naming_custom_name_null_falls_back_to_the_derived_name" {
  command = plan

  variables {
    network_interface = {
      subnet_id = "subnet-0123456789abcdef0"
      name      = null
    }
  }

  assert {
    condition     = aws_network_interface.this.tags["Name"] == "Dev-myapp-eni"
    error_message = "A null name must give the derived name"
  }
}

run "name_tag_follows_the_naming_standard_not_the_object_tags" {
  command = plan

  variables {
    tags = { Name = "from-wrapper", environment = "test" }
    network_interface = {
      subnet_id = "subnet-0123456789abcdef0"
      tags      = { Name = "from-object", workload = "app" }
    }
  }

  assert {
    condition     = aws_network_interface.this.tags["Name"] == "Dev-myapp-eni" && aws_network_interface.this.tags["workload"] == "app" && aws_network_interface.this.tags["environment"] == "test"
    error_message = "The Name tag follows the naming standard; the other tags of the wrapper and the object are merged"
  }
  assert {
    condition     = aws_network_interface.this.tags["module"] == "terraform-aws-caf-network_interface"
    error_message = "The module tag must be set"
  }
}
