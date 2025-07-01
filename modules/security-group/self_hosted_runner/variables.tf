variable "vpc_id" {
  type        = string
  description = "VPC ID to attach the security group to"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block of the VPC for internal SSH access"
}

variable "common_tags" {
  type        = map(string)
  default     = {}
  description = "Common tags to apply to the security group"
}
