packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.0.0"
    }
  }
}

variable "region"        { default = "eu-west-2" }
variable "efs_dns_name"  { description = "EFS DNS name" }
variable "git_branch"    { type = string }
variable "git_tag"       { type = string }
variable "environment"   { type = string }
variable "git_commit" {
  type    = string
  default = "unknown"
}
variable "subnet_id" {
  type        = string
  description = "The subnet ID to launch the Packer builder into"
}
variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the builder instance will be launched"
}

variable "security_group_id" {
  type        = string
  description = "The security group ID for the Packer builder"
}

source "amazon-ebs" "wordpress" {
  region                      = var.region
  instance_type               = "t3.micro"
  ami_name                    = "wordpress-ami-${formatdate("YYYYMMDDhhmmss", timestamp())}-${var.git_commit}"
  subnet_id                   = var.subnet_id
  vpc_id                      = var.vpc_id
  security_group_id           = var.security_group_id
  ssh_username                = "ec2-user"
  iam_instance_profile        = "wordpress-ec2-instance-profile"
  associate_public_ip_address = false

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      architecture        = "x86_64"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["137112412989"]
    most_recent = true
  }

  tags = {
    Name        = "wordpress"
    GitCommit   = var.git_commit
    GitBranch   = var.git_branch
    GitTag      = var.git_tag
    Environment = var.environment
    BuildTime   = timestamp()
    Role        = "webserver"
  }
}

build {
  name    = "wordpress-ami"
  sources = ["source.amazon-ebs.wordpress"]

  provisioner "shell" {
    inline = [
      "echo 'DEBUG: Starting system update and installing packages...'",
      "sudo dnf update -y",
      "sudo dnf install -y httpd php php-mysqlnd php-gd php-xml php-mbstring php-curl php-zip nfs-utils rsync",

      # Ensure `nfs-utils` is fully installed and its dependencies pulled in
      "sudo systemctl enable nfs-client.target || true",
      "sudo systemctl start nfs-client.target || true",
      "sudo systemctl status nfs-client.target --no-pager || true",

      ## Check for active firewalls
      # "echo 'DEBUG: Checking firewall status...'",
      # "sudo systemctl status firewalld --no-pager || echo 'firewalld not running or installed'",
      # "sudo iptables -L -n -v || true",

      "echo 'DEBUG: Installing Amazon SSM agent...'",
      "sudo dnf install -y https://s3.${var.region}.amazonaws.com/amazon-ssm-${var.region}/latest/linux_amd64/amazon-ssm-agent.rpm",
      "sudo systemctl enable amazon-ssm-agent",

      "echo 'DEBUG: Installing CloudWatch agent...'",
      "sudo dnf install -y https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm",
      "sudo systemctl enable amazon-cloudwatch-agent",

      "echo 'DEBUG: Creating wp-content mount point...'",
      "sudo mkdir -p /var/www/html/wp-content", # Ensure mount point exists

      "echo 'DEBUG: Attempting to mount EFS: ${var.efs_dns_name}'",
      "sudo mount -t nfs4 -vvv -o rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \"${var.efs_dns_name}:/\" /var/www/html/wp-content || (echo 'ERROR: Mount failed'; exit 1)",
      "MOUNT_STATUS=$?",
      "echo \"DEBUG: Mount command exit status: $MOUNT_STATUS\"",
      "if [ $MOUNT_STATUS -ne 0 ]; then",
      "  echo 'ERROR: EFS Mount failed with status $MOUNT_STATUS. Review logs for details.'",
      "  sudo dmesg | tail -n 50 || true",
      "  exit 1",
      "fi",
      "echo 'DEBUG: EFS mounted successfully.'",

      "sudo chown -R apache:apache /var/www/html/wp-content",
      "sudo chmod -R 755 /var/www/html/wp-content",

      "echo 'DEBUG: Downloading and extracting WordPress...'",
      "curl -O https://wordpress.org/latest.tar.gz",
      "tar xzf latest.tar.gz",

      // Copy WordPress core files *excluding* wp-content.
      // The /var/www/html/wp-content directory is now the EFS mount.
      "echo 'DEBUG: Copying WordPress core files to /var/www/html/...'",
      "sudo rsync -av --exclude 'wp-content' wordpress/ /var/www/html/",

      // Copy initial wp-content files to EFS *only if EFS is empty*.
      // This ensures plugins/themes are in EFS for persistence.
      "echo 'DEBUG: Initializing wp-content on EFS if empty...'",
      "if [ -z \"$(ls -A /var/www/html/wp-content)\" ]; then",
      "  echo 'DEBUG: EFS /wp-content is empty, copying default WordPress content...'",
      "  sudo rsync -av wordpress/wp-content/ /var/www/html/wp-content/",
      "  sudo chown -R apache:apache /var/www/html/wp-content",
      "  sudo chmod -R 755 /var/www/html/wp-content",
      "else",
      "  echo 'DEBUG: EFS /wp-content already contains data, skipping initial copy.'",
      "fi",

      "sudo chown -R apache:apache /var/www/html",
      "sudo chmod -R 755 /var/www/html",
      "sudo rm -rf wordpress latest.tar.gz",

      "echo 'DEBUG: Enabling and starting services...'",
      "sudo systemctl enable httpd",
      "sudo systemctl start httpd",
      "sudo systemctl start amazon-ssm-agent",
      "sudo systemctl start amazon-cloudwatch-agent",
      "echo 'DEBUG: Provisioning complete.'",

      "sudo rm -rf /tmp/* /home/ec2-user/.bash_history || true"
    ]
  }
}
