# (root)/outputs.tf
output "subnet_id" {
  value       = data.terraform_remote_state.infra.outputs.subnet_for_packer
  description = "Subnet ID for launching the Packer builder"
}

output "security_group_id" {
  value       = data.terraform_remote_state.infra.outputs.packer_sg_id
  description = "Security group ID for the Packer instance"
}

output "efs_dns_name" {
  value       = data.terraform_remote_state.infra.outputs.efs_dns_name
  description = "EFS DNS name for mounting during baking"
}

output "runner_private_ip" {
  value       = module.self_hosted_runner.private_ip
  description = "Private IP of the self-hosted GitHub runner"
}
