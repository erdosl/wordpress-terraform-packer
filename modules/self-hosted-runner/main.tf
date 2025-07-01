resource "aws_instance" "runner" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]

  iam_instance_profile = var.instance_profile_name

  associate_public_ip_address = false

  root_block_device {
    volume_size = var.root_block_volume_size
    volume_type = "gp3"
  }

  tags = merge(var.common_tags, {
    Name = "github-self-hosted-runner"
    Role = "ci"
  })

  user_data = var.user_data
}
