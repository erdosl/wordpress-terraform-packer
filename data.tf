# (root)/data.tf
data "terraform_remote_state" "infra" {
  backend = "remote"
  config = {
    organization = "my-cloud-org"
    workspaces = {
      name = "infra"
    }
  }
}

data "terraform_remote_state" "iam" {
  backend = "remote"
  config = {
    organization = "my-cloud-org"
    workspaces = {
      name = "wordpress-terraform-iam-policies"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_ami" "al" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["137112412989"] # Amazon
}