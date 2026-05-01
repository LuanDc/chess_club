# Task 02: AWS S3 Bucket Setup

> RFC reference: §8.5 — AWS S3
> Depends on: Task 01 (AWS account and EC2 instance must exist)

## Goal

Create the private S3 bucket that stores versioned OTP release artefacts and the `current.json` deployment manifest. DeployEx polls this manifest to detect new releases; GitHub Actions writes to it. Both must have the correct IAM permissions before the CI/CD pipeline (Task 04) or DeployEx (Task 05) can function.

## Checklist

- [ ] Navigate to AWS Console → S3 → Buckets
- [ ] Create a new bucket named `chess-releases`:
  - [ ] Region: choose the same region as the EC2 instance
  - [ ] Block all public access: **enabled**
  - [ ] Versioning: optional (consider enabling for rollback safety)
  - [ ] Note down the bucket name and region (needed in later tasks)
- [ ] Create an IAM Role for the EC2 instance (Instance Profile):
  - [ ] Create a policy granting `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on `chess-releases` only
  - [ ] Create an IAM Role with `EC2` as the trusted entity and attach the policy above
  - [ ] Attach the IAM Role to the EC2 instance via EC2 Console → Actions → Security → Modify IAM Role
  - [ ] Verify the instance can access the bucket: `aws s3 ls s3://chess-releases`
- [ ] Create an IAM User dedicated to GitHub Actions CI (e.g. `github-actions-chess`):
  - [ ] Attach a least-privilege policy: `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` on `chess-releases` only
  - [ ] Generate an Access Key (Access Key ID + Secret Access Key) for this user
  - [ ] Note the Access Key ID and Secret Access Key
- [ ] Store secrets in GitHub Actions repository secrets:
  - [ ] `AWS_ACCESS_KEY_ID` — the IAM user's access key ID
  - [ ] `AWS_SECRET_ACCESS_KEY` — the IAM user's secret access key
  - [ ] `AWS_REGION` — AWS region identifier (e.g. `us-east-1`)
  - [ ] `AWS_S3_BUCKET` — `chess-releases`
- [ ] Verify bucket access from a local machine using the GitHub Actions credentials (dry-run of `aws s3 cp`)
- [ ] Document the following values for use in Tasks 04 and 05:
  - [ ] Bucket name: `chess-releases`
  - [ ] Region: `<region>`
  - [ ] Object base URL: `https://chess-releases.s3.<region>.amazonaws.com/`

## Notes / References

- AWS S3 Free Tier: 5 GB storage, 20,000 GET requests, 2,000 PUT requests per month for 12 months
- The `current.json` format expected by DeployEx: `{"version": "<sha>", "url": "<presigned-or-direct-url>"}`
- Artefact retention: consider keeping the last 5 releases for rollback safety; configure an S3 Lifecycle Policy to expire older objects automatically
- AWS CLI installation: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
- For tighter security, consider using GitHub's OIDC provider with AWS instead of long-lived access keys
