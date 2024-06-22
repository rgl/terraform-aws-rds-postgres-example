# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.8.5"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    # see https://github.com/hashicorp/terraform-provider-random
    random = {
      source  = "hashicorp/random"
      version = "3.6.2"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    # see https://github.com/hashicorp/terraform-provider-cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.4"
    }
    # see https://registry.terraform.io/providers/hashicorp/aws
    # see https://github.com/hashicorp/terraform-provider-aws
    aws = {
      source  = "hashicorp/aws"
      version = "5.55.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Owner   = var.owner
      Project = var.name_prefix
    }
  }
}
