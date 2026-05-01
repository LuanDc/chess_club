# Task 01: AWS EC2 VM Provisioning via Terraform

> RFC reference: §8.1 — AWS EC2 VM
> Depends on: none

## Goal

Provision the AWS EC2 instance (VPC, subnet, security group, and bootstrap tooling) that will host both the chess application and DeployEx using Terraform. This is the foundation for every subsequent task — nothing else can be completed without a running, accessible server with the correct OTP version installed. Terraform automatically configures SSH hardening, ASDF, Erlang, Elixir, and the deploy user via cloud-init.

## Checklist

- [x] Create or configure an AWS account at console.aws.amazon.com
- [x] Gather SSH public key (`cat ~/.ssh/id_rsa.pub` or generate one with `ssh-keygen -t ed25519`)
- [x] Create `terraform/terraform.tfvars` with:
  - [x] `ssh_public_key = "ssh-ed25519 ..."`
  - [x] `aws_region = "us-east-1"` (or preferred region)
  - [x] `instance_type = "t3.small"` (or t3.micro for Free Tier)
  - [x] `erlang_version` and `elixir_version` (defaults: OTP 27.3.4, Elixir 1.17.3-otp-27)
- [x] Initialize Terraform: `terraform init`
- [x] Review the plan: `terraform plan`
- [x] Apply the configuration: `terraform apply`
- [x] Retrieve instance details from outputs:
  - [x] Instance ID
  - [x] Public IP
  - [x] SSH command (ubuntu user)
  - [x] SSH command (deploy user)
- [x] SSH into the instance as `ubuntu` user and verify connectivity
- [x] Verify version-check marker: `cat /home/deploy/version-check.txt`
  - [x] Check that Elixir version matches project requirements
  - [x] Check that Erlang/OTP version matches project requirements
- [x] Switch to `deploy` user: `su - deploy`
- [x] Verify tools are available: `elixir --version` and `iex --version`

## Terraform Configuration

The infrastructure is fully defined in `terraform/` directory. Key files:

### variables.tf

```hcl
variable "aws_region" {
  description = "AWS region to deploy resources (e.g. us-east-1, sa-east-1)"
  type        = string
  default     = "us-east-1"
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
  description = "EC2 instance type (e.g. t3.small, t3.micro)"
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
```

### network.tf — VPC, Subnet, Security Group

```hcl
resource "aws_vpc" "chess" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "chess-vpc"
  }
}

resource "aws_internet_gateway" "chess" {
  vpc_id = aws_vpc.chess.id

  tags = {
    Name = "chess-igw"
  }
}

resource "aws_route_table" "chess_public" {
  vpc_id = aws_vpc.chess.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.chess.id
  }

  tags = {
    Name = "chess-rt-public"
  }
}

resource "aws_route_table_association" "chess_public" {
  subnet_id      = aws_subnet.chess_public.id
  route_table_id = aws_route_table.chess_public.id
}

resource "aws_subnet" "chess_public" {
  vpc_id                  = aws_vpc.chess.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true

  tags = {
    Name = "chess-public-subnet"
  }
}

resource "aws_security_group" "chess" {
  name        = "chess-sg"
  description = "Security group for chess server"
  vpc_id      = aws_vpc.chess.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "chess-sg"
  }
}
```

### main.tf — EC2 Instance + Cloud-Init

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.6"
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "cloudinit_config" "chess_server" {
  gzip          = false
  base64_encode = true

  part {
    filename     = "cloud-init.yaml"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init.yaml", {
      erlang_version = var.erlang_version
      elixir_version = var.elixir_version
    })
  }
}

resource "aws_key_pair" "chess" {
  key_name   = "chess-deploy"
  public_key = var.ssh_public_key
}

resource "aws_instance" "chess_server" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.chess_public.id
  vpc_security_group_ids = [aws_security_group.chess.id]
  key_name               = aws_key_pair.chess.key_name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  user_data = data.cloudinit_config.chess_server.rendered

  tags = {
    Name = "chess-server"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
```

### outputs.tf

```hcl
output "instance_public_ip" {
  description = "Public IP address of the chess server"
  value       = aws_instance.chess_server.public_ip
}

output "instance_id" {
  description = "ID of the chess server EC2 instance"
  value       = aws_instance.chess_server.id
}

output "ssh_command" {
  description = "SSH command to connect as the ubuntu user"
  value       = "ssh ubuntu@${aws_instance.chess_server.public_ip}"
}

output "ssh_command_deploy" {
  description = "SSH command to connect as the deploy user"
  value       = "ssh deploy@${aws_instance.chess_server.public_ip}"
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.chess.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.chess_public.id
}
```

### cloud-init.yaml — Automated Bootstrap

The cloud-init configuration automatically handles:
- User creation: `deploy` user with passwordless sudo
- SSH hardening: Disables password auth, root login, challenge-response
- System packages: Build tools, dependencies for compiling Erlang from source
- ASDF setup: Installed for `deploy` user with plugins for Erlang and Elixir
- OTP & Elixir: Compiled/installed with pinned versions in `.tool-versions`
- Version verification: Output written to `/home/deploy/version-check.txt`

(Full contents in `terraform/cloud-init.yaml`)

## Deployment Steps

1. **Prepare SSH key** (if you don't have one):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_rsa -N ""
   ```

2. **Create `terraform/terraform.tfvars`**:
   ```bash
   cat > terraform/terraform.tfvars << 'EOF'
   ssh_public_key = "$(cat ~/.ssh/id_rsa.pub)"
   aws_region     = "us-east-1"
   instance_type  = "t3.small"
   erlang_version = "27.3.4"
   elixir_version = "1.17.3-otp-27"
   EOF
   ```

3. **Initialize and apply Terraform**:
   ```bash
   cd terraform/
   terraform init
   terraform plan
   terraform apply
   ```

4. **Retrieve instance details**:
   ```bash
   terraform output instance_public_ip
   terraform output ssh_command
   terraform output ssh_command_deploy
   terraform output instance_id
   ```

5. **SSH into the instance** (as ubuntu user):
   ```bash
   ssh ubuntu@<public-ip>
   ```

6. **Verify cloud-init completion** (watch logs while instance boots):
   ```bash
   sudo tail -f /var/log/cloud-init-output.log
   ```

7. **Verify version check marker** (after cloud-init completes):
   ```bash
   cat /home/deploy/version-check.txt
   ```
   Expected output:
   ```
   Elixir 1.17.3 (compiled with Erlang/OTP 27)
   Erlang/OTP 27 [erts-27.x]
   ```

8. **Switch to deploy user and verify**:
   ```bash
   su - deploy
   elixir --version
   iex --version
   asdf list
   ```

9. **Document output values for later tasks**:
   - Instance ID: save from `terraform output instance_id`
   - Public IP: save from `terraform output instance_public_ip`
   - VPC ID: save from `terraform output vpc_id`
   - Subnet ID: save from `terraform output subnet_id`

## Notes / References

- AWS Free Tier: t3.micro is free for 12 months (750 hours/month); t3.small provides more resources
- ASDF documentation: https://asdf-vm.com/guide/getting-started.html
- OTP version must match DeployEx (Task 05) — currently pinned to 27.3.4
- Elixir version must match project requirements — currently pinned to 1.17.3-otp-27
- Cloud-init builds Erlang from source with minimal features (`--without-wx --without-debugger`) to reduce build time (~20-30 mins on t3.small)
- SSH hardening applied automatically: `PasswordAuthentication no`, `PermitRootLogin no`, `ChallengeResponseAuthentication no`
- Deploy user has passwordless sudo for deployment flexibility
- The VM's public IP is needed in Task 06 (DNS) and Task 05 (DeployEx configuration)
- Terraform ignores AMI changes after first apply to prevent unintended instance replacement
