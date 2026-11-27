# The three interfaces of a network appliance: device 0 management in a Mgmt-tier subnet, device 1 in a Private-tier subnet with the
# source and destination check off, device 2 in a Public-tier subnet with the check off and a pinned private address (the appliance
# configuration refers to the public interface's address). Each has its own security group. They are given to
# terraform-aws-caf-ec2_instance (network_interfaces, by device index), which takes device 0 as the primary interface and attaches the
# others, so no attachment key is used here.

mock_provider "aws" {}

variables {
  env               = "G3Pg"
  userDefinedString = "app-1a-mgmt"
  tags              = { environment = "prod" }
  subnet_ids = {
    main = {
      Mgmt-1a    = "subnet-0aaaaaaaaaaaaaaa0"
      Private-1a = "subnet-0aaaaaaaaaaaaaaa1"
      Public-1a  = "subnet-0aaaaaaaaaaaaaaa2"
    }
  }
  security_group_ids = {
    app-1a-mgmt    = "sg-0bbbbbbbbbbbbbbb0"
    app-1a-private = "sg-0bbbbbbbbbbbbbbb1"
    app-1a-public  = "sg-0bbbbbbbbbbbbbbb2"
  }
  network_interface = {
    vpc_key             = "main"
    subnet_key          = "Mgmt-1a"
    security_group_keys = ["app-1a-mgmt"]
    description         = "app-1a management (device 0)"
  }
}

run "appliance_management_interface" {
  command = plan

  assert {
    condition     = aws_network_interface.this.subnet_id == "subnet-0aaaaaaaaaaaaaaa0" && aws_network_interface.this.security_groups == toset(["sg-0bbbbbbbbbbbbbbb0"])
    error_message = "The management interface must sit in the Mgmt-tier subnet with its own security group"
  }
  assert {
    condition     = aws_network_interface.this.description == "app-1a management (device 0)" && aws_network_interface.this.tags["Name"] == "G3Pg-app-1a-mgmt-eni"
    error_message = "The management interface must carry its description and derived Name tag"
  }
}

run "appliance_private_interface" {
  command = plan

  variables {
    userDefinedString = "app-1a-private"
    network_interface = {
      vpc_key             = "main"
      subnet_key          = "Private-1a"
      security_group_keys = ["app-1a-private"]
      source_dest_check   = false
      description         = "app-1a private (device 1)"
    }
  }

  assert {
    condition     = aws_network_interface.this.subnet_id == "subnet-0aaaaaaaaaaaaaaa1" && aws_network_interface.this.security_groups == toset(["sg-0bbbbbbbbbbbbbbb1"])
    error_message = "The private interface must sit in the Private-tier subnet with its own security group"
  }
  assert {
    condition     = aws_network_interface.this.source_dest_check == false
    error_message = "The source and destination check must be off on the private arm"
  }
}

run "appliance_public_interface_with_a_pinned_address" {
  command = plan

  variables {
    userDefinedString = "app-1a-public"
    network_interface = {
      vpc_key             = "main"
      subnet_key          = "Public-1a"
      security_group_keys = ["app-1a-public"]
      source_dest_check   = false
      private_ip          = "10.20.0.200"
      description         = "app-1a public (device 2)"
    }
  }

  assert {
    condition     = aws_network_interface.this.subnet_id == "subnet-0aaaaaaaaaaaaaaa2" && aws_network_interface.this.security_groups == toset(["sg-0bbbbbbbbbbbbbbb2"])
    error_message = "The public interface must sit in the Public-tier subnet with its own security group"
  }
  assert {
    condition     = aws_network_interface.this.source_dest_check == false && aws_network_interface.this.private_ips == toset(["10.20.0.200"])
    error_message = "The public arm must have the check off and its private address pinned"
  }
}

# The module's id output is what ec2_instance reads from network_interface_ids, so a blueprint wires them with one for expression.
run "appliance_interfaces_wire_into_ec2_instance_without_an_adapter" {
  command = plan

  module {
    source = "./tests/wiring"
  }

  variables {
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
    ec2_instances = {
      app-1a = {
        ami           = "ami-0123456789abcdef0"
        instance_type = "m5.large"
        network_interfaces = {
          app-1a-mgmt    = { device_index = 0 }
          app-1a-private = { device_index = 1 }
          app-1a-public  = { device_index = 2 }
        }
      }
    }
  }

  assert {
    condition     = output.interface_names == { app-1a-mgmt = "G3Pg-app-1a-mgmt-eni", app-1a-private = "G3Pg-app-1a-private-eni", app-1a-public = "G3Pg-app-1a-public-eni" }
    error_message = "The three interfaces must be made, named from their keys"
  }
  assert {
    condition     = output.instance_primary_ids["app-1a"] == output.interface_ids["app-1a-mgmt"]
    error_message = "The management interface must be the primary interface (device index 0) of the instance through the lookup map"
  }
  assert {
    condition     = output.instance_attachment_indexes["app-1a"] == { app-1a-private = 1, app-1a-public = 2 } && output.instance_attachment_ids["app-1a"] == { app-1a-private = output.interface_ids["app-1a-private"], app-1a-public = output.interface_ids["app-1a-public"] }
    error_message = "The private and public interfaces must attach at device index 1 and 2 through the lookup map"
  }
}
