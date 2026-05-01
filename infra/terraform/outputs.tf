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
