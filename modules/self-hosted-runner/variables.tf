variable "instance_type" {
  type        = string
  description = "EC2 instance type"
}

variable "subnet_id" {
  type        = string
  description = "Private subnet ID"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID for the runner"
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name"
}

variable "user_data" {
  type        = string
  description = "User data script for bootstrapping"
  default     = ""
}

variable "common_tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the instance"
}

variable "ami_id" {
  type        = string
  description = "AMI ID to use for the runner EC2 instance"
}

variable "root_block_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 16
}