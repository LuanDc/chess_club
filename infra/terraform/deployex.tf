# DeployEx Configuration (Task 05)

# DeployEx admin password hash — generate with:
# echo "MyPassword" | htpasswd -bnBC 10 "" $(cat /dev/stdin) | tr -d ':\n'
variable "deployex_admin_password_hash" {
  description = "Bcrypt hash of the DeployEx admin password (for dashboard login)"
  type        = string
  sensitive   = true
  # Example: "$2b$10$abcdef1234567890..."
  # Generate with: htpasswd -bnBC 10 "" <password> | tr -d ':\n'
}

# Erlang distribution cookie — must match chess app's RELEASE_COOKIE
variable "release_cookie" {
  description = "Erlang distribution cookie (must match between DeployEx and chess app)"
  type        = string
  sensitive   = true
  # Generate with: openssl rand -base64 32
}

# Note: S3 bucket name is derived from aws_s3_bucket.chess_releases in s3_storage.tf
# AWS region variable (var.aws_region) is already defined in variables.tf

# Render the systemd service file for DeployEx
data "template_file" "deployex_service" {
  template = file("${path.module}/deployex.service.tpl")

  vars = {
    deployex_home              = "/opt/deployex"
    deployex_admin_hash        = var.deployex_admin_password_hash
    release_node               = "deployex@${aws_instance.chess_server.private_ip}"
    release_cookie             = var.release_cookie
    release_distribution       = "sname"
    deployex_storage_adapter   = "s3"
    aws_region                 = var.aws_region
    s3_bucket                  = aws_s3_bucket.chess_releases.id
  }
}

# Create the systemd service file on the EC2 instance
resource "aws_ssm_document" "deployex_setup" {
  name            = "deployex-setup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install and configure DeployEx"
    mainSteps = [
      {
        action = "aws:RunShellScript"
        name   = "DeployEx Setup"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "set -e",
            "",
            "# Create DeployEx home directory",
            "sudo mkdir -p /opt/deployex/releases",
            "sudo chown -R deploy:deploy /opt/deployex",
            "",
            "# Download DeployEx binary (OTP 27)",
            "DEPLOYEX_VERSION=0.8.0  # Update to match your DeployEx version",
            "DEPLOYEX_URL=\"https://github.com/thiagoesteves/deployex/releases/download/v$${DEPLOYEX_VERSION}/deployex-$${DEPLOYEX_VERSION}-otp-27-x86_64-linux.tar.gz\"",
            "cd /tmp && curl -L -o deployex.tar.gz \"$${DEPLOYEX_URL}\"",
            "tar -xzf deployex.tar.gz -C /tmp",
            "sudo cp /tmp/deployex /usr/local/bin/deployex",
            "sudo chmod +x /usr/local/bin/deployex",
            "",
            "# Write systemd service file",
            "sudo tee /etc/systemd/system/deployex.service > /dev/null << 'SYSTEMD'",
            data.template_file.deployex_service.rendered,
            "SYSTEMD",
            "",
            "# Enable and start the service",
            "sudo systemctl daemon-reload",
            "sudo systemctl enable deployex",
            "sudo systemctl start deployex",
            "",
            "# Verify the service started",
            "sleep 5",
            "sudo systemctl status deployex"
          ]
        }
      }
    ]
  })
}

# Invoke the DeployEx setup on the EC2 instance
resource "aws_ssm_command" "deployex_setup" {
  document_name       = aws_ssm_document.deployex_setup.name
  instance_ids        = [aws_instance.chess_server.id]
  service_role_arn    = aws_iam_role.ssm_role.arn
  comment             = "Install and configure DeployEx"

  depends_on = [
    aws_instance.chess_server,
    aws_ssm_document.deployex_setup,
    aws_iam_role_policy_attachment.ssm_instance_policy
  ]
}

# IAM role for SSM (Systems Manager) to execute commands on the instance
resource "aws_iam_role" "ssm_role" {
  name = "chess-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ssm.amazonaws.com"
      }
    }]
  })
}

# Attach the SSM instance policy to allow EC2 commands
resource "aws_iam_role_policy_attachment" "ssm_instance_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Update security group to allow port 5001 (DeployEx dashboard)
resource "aws_security_group_rule" "deployex_dashboard" {
  type              = "ingress"
  from_port         = 5001
  to_port           = 5001
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]  # Restrict to office IPs for security
  security_group_id = aws_security_group.chess.id
  description       = "DeployEx dashboard"
}

# Output the DeployEx dashboard URL
output "deployex_dashboard_url" {
  description = "URL to access DeployEx dashboard"
  value       = "http://${aws_instance.chess_server.public_ip}:5001"
}

output "deployex_home_directory" {
  description = "Path to DeployEx home directory on the instance"
  value       = "/opt/deployex"
}
