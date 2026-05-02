variable "aws_region" {
  description = "AWS region to deploy resources (e.g. us-east-1, sa-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the subnet (e.g. us-east-1a, us-east-1b). If unspecified, AWS chooses automatically."
  type        = string
  default     = "us-east-1a"
}

variable "ssh_public_key" {
  description = "SSH public key content to authorize on the instance (paste the full key string)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type (e.g. t3.small, t3.medium)"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "erlang_version" {
  description = "OTP/Erlang version to install via ASDF (must match DeployEx)"
  type        = string
  default     = "27.3.4"
}

variable "elixir_version" {
  description = "Elixir version to install via ASDF"
  type        = string
  default     = "1.17.3-otp-27"
}
