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

  # Prevent accidental replacement of a live server
  lifecycle {
    ignore_changes = [ami]
  }
}
