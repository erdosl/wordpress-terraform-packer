# (root)/variables.tf
variable "aws_region" {
  type        = string
  description = "AWS region to run in"
  default     = "eu-west-2"
}

/*variable "environment" {
  type        = string
  description = "Deployment environment label"
  default     = "dev"
}*/

variable "env" {
  type = map(string)
  default = {
    Environment = "dev"
  }
}

variable "cost" {
  type        = map(string)
  description = "Cost Center Number"
  default = {
    "CostCenter" = "12345"
  }
}

variable "ami_id" {
  type        = string
  description = "The ID of the AMI to use for the WordPress instances."
  default     = "ami-0c2ba8b542fafe5d8" # TODO: Review if we can avoid hardcoding this
}