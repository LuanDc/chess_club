# S3 Bucket for release artefacts
resource "aws_s3_bucket" "chess_releases" {
  bucket = "chess-releases-${data.aws_caller_identity.current.account_id}"
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "chess_releases" {
  bucket = aws_s3_bucket.chess_releases.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for rollback safety
resource "aws_s3_bucket_versioning" "chess_releases" {
  bucket = aws_s3_bucket.chess_releases.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle policy: expire objects older than 60 days (keep last 5 releases)
resource "aws_s3_bucket_lifecycle_configuration" "chess_releases" {
  bucket = aws_s3_bucket.chess_releases.id

  rule {
    id     = "expire-old-releases"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 60
    }
  }
}

# IAM Role for EC2 instance
resource "aws_iam_role" "ec2_chess_role" {
  name = "ec2-chess-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# IAM Policy for EC2 instance S3 access
resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "ec2-chess-s3-policy"
  role = aws_iam_role.ec2_chess_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.chess_releases.arn,
        "${aws_s3_bucket.chess_releases.arn}/*"
      ]
    }]
  })
}

# Instance Profile for EC2
resource "aws_iam_instance_profile" "ec2_chess_profile" {
  name = "ec2-chess-s3-profile"
  role = aws_iam_role.ec2_chess_role.name
}

# IAM User for GitHub Actions
resource "aws_iam_user" "github_actions" {
  name = "github-actions-chess"
}

# IAM Policy for GitHub Actions S3 access
resource "aws_iam_user_policy" "github_actions_s3_policy" {
  name = "github-actions-chess-s3-policy"
  user = aws_iam_user.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.chess_releases.arn,
        "${aws_s3_bucket.chess_releases.arn}/*"
      ]
    }]
  })
}

# Access Keys for GitHub Actions
resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Outputs
output "s3_bucket_name" {
  value       = aws_s3_bucket.chess_releases.id
  description = "Name of the S3 bucket"
}

output "s3_bucket_region" {
  value       = aws_s3_bucket.chess_releases.region
  description = "AWS region of the S3 bucket"
}

output "s3_bucket_url" {
  value       = "https://${aws_s3_bucket.chess_releases.id}.s3.${aws_s3_bucket.chess_releases.region}.amazonaws.com/"
  description = "Base URL for S3 bucket objects"
}

output "ec2_instance_profile_name" {
  value       = aws_iam_instance_profile.ec2_chess_profile.name
  description = "Instance Profile name for EC2"
}

output "github_actions_access_key_id" {
  value       = aws_iam_access_key.github_actions.id
  sensitive   = true
  description = "AWS Access Key ID for GitHub Actions"
}

output "github_actions_secret_access_key" {
  value       = aws_iam_access_key.github_actions.secret
  sensitive   = true
  description = "AWS Secret Access Key for GitHub Actions"
}
