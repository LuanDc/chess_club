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
