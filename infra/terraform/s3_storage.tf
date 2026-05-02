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

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}
