# EC2 IAM Role for S3 access
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

# EC2 IAM Policy for S3 access
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

# EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2_chess_profile" {
  name = "ec2-chess-s3-profile"
  role = aws_iam_role.ec2_chess_role.name
}

# GitHub Actions IAM User
resource "aws_iam_user" "github_actions" {
  name = "github-actions-chess"
}

# GitHub Actions IAM Policy for S3 access
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

# GitHub Actions Access Keys
resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}
