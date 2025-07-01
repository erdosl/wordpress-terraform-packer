# (root)/providers.tf
terraform {
  required_version = ">= 1.12.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.98"
    }
  }

  cloud {
    organization = "my-cloud-org"
    workspaces {
      name = "wordpress-terraform-packer"
    }
  }
}

provider "aws" {
  region = var.aws_region # Set in Terraform Cloud as TF_VAR_aws_region
}