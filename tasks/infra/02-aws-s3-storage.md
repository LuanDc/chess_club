# Task 02: AWS S3 Bucket Setup

> RFC reference: §8.5 — AWS S3
> Depends on: Task 01 (AWS account and EC2 instance must exist)

## Goal

Provision the private S3 bucket (and associated IAM roles/users) that stores versioned OTP release artefacts and the `current.json` deployment manifest using Terraform. DeployEx polls this manifest to detect new releases; GitHub Actions writes to it. Both must have the correct IAM permissions before the CI/CD pipeline (Task 04) or DeployEx (Task 05) can function.

## Checklist

- [x] Create Terraform configuration file `s3_storage.tf`:
  - [x] Define S3 bucket `chess-releases` with versioning and public access blocked
  - [x] Create IAM Role for EC2 instance with S3 read/write policy
  - [x] Create IAM User for GitHub Actions with least-privilege S3 policy
  - [x] Generate Access Keys for GitHub Actions user
- [x] Initialize Terraform: `terraform init`
- [x] Review the plan: `terraform plan`
- [x] Apply the configuration: `terraform apply`
- [x] Store GitHub Actions credentials in GitHub repository secrets:
  - [x] `AWS_ACCESS_KEY_ID` — the IAM user's access key ID
  - [x] `AWS_SECRET_ACCESS_KEY` — the IAM user's secret access key
  - [x] `AWS_REGION` — AWS region from Terraform outputs
  - [x] `AWS_S3_BUCKET` — `chess-releases`
- [x] Verify bucket access from the EC2 instance: `aws s3 ls s3://chess-releases`
- [x] Document the following values for use in Tasks 04 and 05:
  - [x] Bucket name: (from Terraform output)
  - [x] Region: (from Terraform output)
  - [x] Object base URL: (from Terraform output)

## Terraform Configuration

Create `s3_storage.tf` in your Terraform module directory:

```hcl
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
```

## Deployment Steps

1. **Update EC2 instance with new Instance Profile** (from Task 01):
   ```hcl
   resource "aws_instance" "chess_server" {
     # ... existing configuration ...
     iam_instance_profile = aws_iam_instance_profile.ec2_chess_profile.name
   }
   ```

2. **Run Terraform**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Retrieve GitHub Actions secrets**:
   ```bash
   terraform output github_actions_access_key_id
   terraform output github_actions_secret_access_key
   terraform output s3_bucket_region
   ```

4. **Attach the Instance Profile to EC2** (if not done via Terraform update):
   ```bash
   aws ec2 associate_iam_instance_profile \
     --iam-instance-profile Name=$(terraform output -raw ec2_instance_profile_name) \
     --instance-id <your-instance-id>
   ```

5. **Verify bucket access from EC2**:
   ```bash
   ssh -i <key> ec2-user@<instance-ip>
   aws s3 ls s3://$(terraform output -raw s3_bucket_name)
   ```

6. **Store secrets in GitHub**:
   - Go to Repository Settings → Secrets and variables → Actions
   - Add `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_S3_BUCKET`

## Notes / References

- AWS S3 Free Tier: 5 GB storage, 20,000 GET requests, 2,000 PUT requests per month for 12 months
- The `current.json` format expected by DeployEx: `{"version": "<sha>", "url": "<presigned-or-direct-url>"}`
- Artefact retention: lifecycle policy set to expire objects older than 60 days (adjust as needed)
- AWS CLI installation: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
- For tighter security, consider using GitHub's OIDC provider with AWS instead of long-lived access keys: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
