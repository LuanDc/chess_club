# DeployEx Configuration (Task 05)

# DeployEx admin password hash — generate with:
# echo "MyPassword" | htpasswd -bnBC 10 "" $(cat /dev/stdin) | tr -d ':\n'
variable "deployex_admin_password_hash" {
  description = "Bcrypt hash of the DeployEx admin password (for dashboard login)"
  type        = string
  sensitive   = true
}

# Erlang distribution cookie — must match chess app's RELEASE_COOKIE
variable "release_cookie" {
  description = "Erlang distribution cookie (must match between DeployEx and chess app)"
  type        = string
  sensitive   = true
}

# Store DeployEx secrets in AWS Secrets Manager
resource "aws_secretsmanager_secret" "deployex" {
  name                    = "deployex-chess-secrets"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "deployex" {
  secret_id = aws_secretsmanager_secret.deployex.id
  secret_string = jsonencode({
    erlang_cookie           = var.release_cookie
    admin_hashed_password   = var.deployex_admin_password_hash
  })
}

# Upload deployex.yaml config to S3 so the instance can download it
resource "aws_s3_object" "deployex_config" {
  bucket = aws_s3_bucket.chess_releases.id
  key    = "deployex.yaml"
  content = templatefile("${path.module}/deployex.yaml.tpl", {
    aws_region   = var.aws_region
    s3_bucket    = aws_s3_bucket.chess_releases.id
    secrets_path = aws_secretsmanager_secret.deployex.name
  })
}

# Allow EC2 instance to read the DeployEx secret
resource "aws_iam_role_policy" "ec2_secrets_policy" {
  name = "ec2-chess-secrets-policy"
  role = aws_iam_role.ec2_chess_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.deployex.arn
    }]
  })
}

# Allow EC2 instance to register with SSM and receive commands
resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.ec2_chess_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# SSM Document: installs DeployEx via the official deployex.sh script
resource "aws_ssm_document" "deployex_setup" {
  name            = "deployex-setup"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install and configure DeployEx 0.9.0"
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "DeployExSetup"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "set -e",
            "export PATH=$PATH:/usr/local/bin",
            "apt-get install -y -q unzip curl",
            "curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq",
            "chmod +x /usr/local/bin/yq",
            "if ! aws --version &>/dev/null; then",
            "  curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip",
            "  unzip -q /tmp/awscliv2.zip -d /tmp",
            "  /tmp/aws/install",
            "fi",
            "aws s3 cp s3://${aws_s3_bucket.chess_releases.id}/deployex.yaml /tmp/deployex.yaml --region ${var.aws_region}",
            "curl -fsSL https://github.com/thiagoesteves/deployex/releases/download/0.9.0/deployex.sh -o /tmp/deployex.sh",
            "chmod +x /tmp/deployex.sh",
            "bash /tmp/deployex.sh --install /tmp/deployex.yaml",
            "sleep 5",
            "systemctl status deployex"
          ]
        }
      }
    ]
  })

  depends_on = [
    aws_s3_object.deployex_config,
    aws_secretsmanager_secret_version.deployex
  ]
}

# Invoke the DeployEx setup on the EC2 instance via AWS CLI
resource "null_resource" "deployex_setup" {
  triggers = {
    document_version = aws_ssm_document.deployex_setup.default_version
    config_etag      = aws_s3_object.deployex_config.etag
    instance_id      = aws_instance.chess_server.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      INSTANCE_ID="${aws_instance.chess_server.id}"
      REGION="${var.aws_region}"
      echo "Waiting for SSM agent to register on $INSTANCE_ID..."
      for i in $(seq 1 40); do
        STATUS=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
          --region "$REGION" \
          --query 'InstanceInformationList[0].PingStatus' \
          --output text 2>/dev/null || echo "None")
        if [ "$STATUS" = "Online" ]; then
          echo "SSM agent is online."
          break
        fi
        echo "Attempt $i/40: SSM status=$STATUS, retrying in 15s..."
        sleep 15
      done
      aws ssm send-command \
        --document-name "${aws_ssm_document.deployex_setup.name}" \
        --instance-ids "$INSTANCE_ID" \
        --service-role-arn "${aws_iam_role.ssm_role.arn}" \
        --region "$REGION"
    EOT
  }

  depends_on = [
    aws_instance.chess_server,
    aws_ssm_document.deployex_setup,
    aws_iam_role_policy_attachment.ssm_instance_policy,
    aws_iam_role_policy_attachment.ec2_ssm_policy,
    aws_iam_role_policy.ec2_secrets_policy
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

# Attach the SSM policy to the SSM execution role
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

output "deployex_dashboard_url" {
  description = "URL to access DeployEx dashboard"
  value       = "http://${aws_instance.chess_server.public_ip}:5001"
}

output "deployex_home_directory" {
  description = "Path to DeployEx home directory on the instance"
  value       = "/opt/deployex"
}
