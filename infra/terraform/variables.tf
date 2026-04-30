variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the OCI API signing key"
  type        = string
}

variable "private_key_path" {
  description = "Path to the OCI API private key file"
  type        = string
}

variable "region" {
  description = "OCI region (e.g. us-ashburn-1, sa-saopaulo-1)"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment to deploy resources into (use tenancy OCID for root)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content to authorize on the instance (paste the full key string)"
  type        = string
}

variable "availability_domain_index" {
  description = "Zero-based index of the availability domain to use (0 = AD-1)"
  type        = number
  default     = 0
}

variable "vcn_cidr" {
  description = "CIDR block for the Virtual Cloud Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_ocpus" {
  description = "Number of OCPUs for the A1 Flex instance (Always Free limit: 4 total)"
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "RAM in GB for the A1 Flex instance (Always Free limit: 24 GB total)"
  type        = number
  default     = 4
}

variable "boot_volume_size_gb" {
  description = "Boot volume size in GB"
  type        = number
  default     = 50
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
