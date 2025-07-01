resource "aws_security_group" "self_hosted_runner" {
  name_prefix = "self-hosted-runner-sg-"
  description = "Security group for GitHub Actions self-hosted runner"
  vpc_id      = var.vpc_id

  # Allow SSH within the VPC only (for debugging or Packer)
  ingress {
    description     = "Allow SSH from private subnet"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = [var.vpc_cidr]
  }

  # Allow all outbound traffic (for internet via NAT, GitHub, EFS, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "self-hosted-runner-sg"
  })
}
