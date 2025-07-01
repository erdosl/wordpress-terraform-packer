# (root)/main.tf
locals {
  original_arn = data.aws_caller_identity.current.arn

  # Remove dynamic suffix from aws-go-sdk-*
  truncated_arn = replace(local.original_arn, "-${join("", slice(split("aws-go-sdk-", local.original_arn), 1, length(split("aws-go-sdk-", local.original_arn))))}", "")

  common_tags = {
    ManagedBy   = local.truncated_arn
    Environment = var.env["Environment"]
    CostCenter  = var.cost["CostCenter"]
  }
}

module "security_group_runner" {
  source      = "./modules/security-group/self_hosted_runner"
  # vpc_id    = module.network.id
  vpc_id      = data.terraform_remote_state.infra.outputs.vpc_id
  # vpc_cidr  = module.network.cidr_block
  vpc_cidr    = data.terraform_remote_state.infra.outputs.vpc_cidr_block
  common_tags = local.common_tags
}

module "self_hosted_runner" {
  source = "./modules/self-hosted-runner"
  ami_id                 = data.aws_ami.al.id
  instance_type          = "t2.micro"
  # subnet_id              = module.subnets.private_subnet_ids[0]
  subnet_id              = data.terraform_remote_state.infra.outputs.subnet_for_packer
  security_group_id      = module.security_group_runner.id
  instance_profile_name  = data.terraform_remote_state.iam.outputs.self_hosted_runner_instance_profile

  # user_data              = base64encode(file("${path.module}/userdata_runner.tpl"))
  user_data              = base64encode(local.userdata_runner_tpl_replaced)
  root_block_volume_size = 30
  common_tags            = local.common_tags
}

locals {
  raw_template = file("${path.module}/userdata_runner.tpl")

  userdata_runner_tpl_replaced = replace(
    replace(
      replace(
        replace(local.raw_template,
          "__GH_OWNER__", "erdosl"
        ),
        "__GH_REPO__", "wordpress-terraform-packer"
      ),
      "__RUNNER_USER__", "ec2-user"
    ),
    "__ARCH__", "x64"
  )
}