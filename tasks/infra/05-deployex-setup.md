# Task 05: DeployEx Installation and Configuration

> RFC reference: §8.2 — DeployEx
> Depends on: Task 01 (VM must be running), Task 02 (S3 bucket must exist), Task 04 (at least one release artefact must be in the bucket)

## Goal

Configure DeployEx on the VM as a systemd service via Terraform and set it to poll AWS S3 for `current.json`. Once running, DeployEx manages the full lifecycle of the chess application: downloading releases, performing hot upgrades when possible, monitoring health, and rolling back on failure. After this task, deployments are fully automated — every merge to `master` triggers a build, and DeployEx detects and deploys the new version within seconds.

## Checklist

- [ ] Update Terraform configuration with DeployEx deployment unit:
  - [ ] Create `deployex.tf` with systemd service resource
  - [ ] Define environment variables for DeployEx (admin password hash, S3 bucket, Erlang node, cookie)
  - [ ] Attach EC2 Instance Profile (from Task 02) if not already attached
  - [ ] Generate initial admin password hash for DeployEx dashboard
- [ ] Create Terraform outputs for DeployEx dashboard access:
  - [ ] DeployEx dashboard URL: `http://<vm-ip>:5001`
- [ ] Update EC2 Security Group to allow port 5001 (DeployEx dashboard, can be restricted to local/office IPs)
- [ ] Run Terraform apply to create the systemd service
- [ ] SSH into the VM and verify:
  - [ ] Service file exists at `/etc/systemd/system/deployex.service`
  - [ ] Service is enabled: `sudo systemctl is-enabled deployex`
  - [ ] Service is running: `sudo systemctl is-active deployex`
  - [ ] Systemd journal shows no errors: `sudo journalctl -u deployex -n 50`
- [ ] Verify DeployEx binary downloaded and started:
  - [ ] Check if the DeployEx process is running: `ps aux | grep deployex`
  - [ ] Verify the DeployEx home directory exists: `ls -la /opt/deployex/`
- [ ] Access the DeployEx web dashboard:
  - [ ] Navigate to `http://<vm-ip>:5001` in a browser
  - [ ] Dashboard loads and shows the application list (chess app should appear)
  - [ ] Log in with the admin password set in Terraform
- [ ] Trigger the first automated deployment:
  - [ ] Ensure `current.json` in S3 points to a valid release artefact (from Task 04)
  - [ ] Monitor the DeployEx dashboard; within ~30 seconds, it should:
    - [ ] Detect the new version in `current.json`
    - [ ] Download the release from S3
    - [ ] Extract and start the chess application
  - [ ] Verify the chess app responds: `curl http://localhost:4000`
    - [ ] Returns 200 OK with HTML content
- [ ] Verify version consistency:
  - [ ] SSH to the VM and get the chess app's OTP version:
    ```bash
    ssh deploy@<vm-ip>
    /opt/deployex/releases/chess-*/bin/chess remote_console
    # In the remote console: :erlang.system_info(:otp_release)
    ```
  - [ ] Confirm OTP version matches DeployEx binary (both OTP 27)
- [ ] Verify health monitoring and auto-rollback:
  - [ ] Stop the chess application manually: `sudo systemctl stop chess-app`
  - [ ] Observe DeployEx detects the failure within 60 seconds (check dashboard)
  - [ ] Verify DeployEx automatically restarts the application

## Terraform Configuration

Add the following to your Terraform configuration to manage DeployEx via IaC.

### deployex.tf

```hcl
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

# S3 bucket name (from Task 02 outputs)
variable "s3_bucket_name" {
  description = "S3 bucket name for chess release artifacts"
  type        = string
}

# AWS region (from Task 02)
variable "aws_region" {
  description = "AWS region where S3 bucket resides"
  type        = string
}

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
    s3_bucket                  = var.s3_bucket_name
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
```

### deployex.service.tpl

Create `deployex.service.tpl` in your Terraform module directory:

```systemd
[Unit]
Description=DeployEx Release Manager
After=network.target
StartLimitInterval=120s
StartLimitBurst=3

[Service]
Type=exec
User=deploy
WorkingDirectory=${deployex_home}

Environment="DEPLOYEX_ADMIN_HASHED_PASSWORD=${deployex_admin_hash}"
Environment="RELEASE_NODE=${release_node}"
Environment="RELEASE_DISTRIBUTION=${release_distribution}"
Environment="RELEASE_COOKIE=${release_cookie}"
Environment="DEPLOYEX_STORAGE_ADAPTER=${deployex_storage_adapter}"
Environment="AWS_REGION=${aws_region}"
Environment="DEPLOYEX_S3_BUCKET=${s3_bucket}"

# Inherit IAM instance profile credentials
ExecStart=/usr/local/bin/deployex start

# Restart policy
Restart=on-failure
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=deployex

[Install]
WantedBy=multi-user.target
```

### Update terraform.tfvars

Add the required DeployEx variables to `terraform.tfvars`:

```hcl
# DeployEx admin password hash (generate with: echo "your-password" | htpasswd -bnBC 10 "" - | tr -d ':\n')
deployex_admin_password_hash = "$2b$10$YourBcryptHashHere..."

# Erlang distribution cookie (must match chess app's RELEASE_COOKIE)
# Generate with: openssl rand -base64 32
release_cookie = "YourSecureRandomCookieHere"

# S3 bucket name from Task 02
s3_bucket_name = "chess-releases-123456789012"

# AWS region
aws_region = "us-east-1"
```

## Deployment Steps

### Step 1: Generate Required Secrets

Before running Terraform, generate the required hashed password and cookie:

```bash
# Generate bcrypt hash for DeployEx admin password
# Replace "my-password" with your desired dashboard password
echo "my-password" | htpasswd -bnBC 10 "" - | tr -d ':\n'
# Output: $2b$10$...

# Generate a random Erlang cookie (must be the same for both DeployEx and chess app)
openssl rand -base64 32
# Output: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6...
```

Save both values — you'll paste them into `terraform.tfvars`.

### Step 2: Update terraform.tfvars

```bash
cat >> terraform/terraform.tfvars << 'EOF'

# DeployEx Configuration
deployex_admin_password_hash = "<paste-bcrypt-hash-from-step-1>"
release_cookie = "<paste-random-cookie-from-step-1>"
s3_bucket_name = "chess-releases-$(aws sts get-caller-identity --query Account --output text)"
EOF
```

### Step 3: Create the systemd service template

```bash
# Copy the systemd template to your Terraform module directory
cp tasks/infra/deployex.service.tpl infra/terraform/deployex.service.tpl
```

### Step 4: Run Terraform

```bash
cd infra/terraform
terraform plan
terraform apply
```

Terraform will:
- Create the systemd service file on the EC2 instance
- Download and install the DeployEx binary
- Start the DeployEx service
- Open port 5001 in the security group

### Step 5: Verify Deployment

```bash
# Get the DeployEx dashboard URL
terraform output deployex_dashboard_url

# SSH into the instance and verify the service
ssh deploy@<instance-ip>

# Check service status
sudo systemctl status deployex

# View recent logs
sudo journalctl -u deployex -n 50 -f

# Verify DeployEx home directory
ls -la /opt/deployex/
```

### Step 6: Access the Dashboard

```bash
# Get the dashboard URL
DEPLOYEX_URL=$(terraform output -raw deployex_dashboard_url)

# Open in browser or curl
curl $DEPLOYEX_URL
```

The dashboard should load showing:
- Application list (chess app should appear)
- Login prompt with your admin password
- Current deployment status

### Step 7: Trigger First Deployment

Once `current.json` exists in S3 (from Task 04), DeployEx will:

1. Detect the new version within ~30 seconds
2. Download the release from S3
3. Extract and start the chess application
4. Begin health monitoring

To manually trigger a deployment update:

```bash
# SSH to the instance
ssh deploy@<instance-ip>

# Verify the chess app is running
curl http://localhost:4000

# Check the running version
ps aux | grep chess
```

## Verification Checklist

- [ ] DeployEx service is running: `sudo systemctl status deployex`
- [ ] Dashboard is accessible at `http://<vm-ip>:5001`
- [ ] Admin login works with the password set in Terraform
- [ ] Chess application appears in the dashboard
- [ ] Chess app is running on port 4000: `curl http://localhost:4000` returns 200
- [ ] OTP versions match between DeployEx and chess app (both OTP 27)
- [ ] DeployEx automatically detects and deploys new releases from S3
- [ ] Health checks are active (dashboard shows "healthy" status)

## Notes / References

- **DeployEx releases**: https://github.com/thiagoesteves/deployex/releases — download the binary matching OTP 27
- **DeployEx documentation**: https://github.com/thiagoesteves/deployex — configuration and S3 adapter details
- **Bcrypt hash generation**: `echo "password" | htpasswd -bnBC 10 "" - | tr -d ':\n'` or use online tools
- **Erlang cookie generation**: Must be identical on DeployEx and the chess app (set via `RELEASE_COOKIE` env var)
- **S3 access**: Uses EC2 Instance Profile from Task 02; no additional AWS credentials needed in the service file
- **Health monitoring**: DeployEx monitors the chess app for 10 minutes after deployment; auto-rollback triggers on health failures
- **Port 5001**: DeployEx dashboard port; restrict to office IPs in production via the security group rule
- **Single-node Phase 1**: `RELEASE_DISTRIBUTION=sname` is appropriate for this phase; clustering will be handled in Phase 2
- **Restart policy**: `Restart=on-failure` ensures DeployEx recovers from crashes; `StartLimitBurst=3` prevents rapid restart loops
