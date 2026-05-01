# Production Deployment Guide

This guide takes you from zero — no AWS account, no local tooling — to a fully provisioned EC2 instance inside a VPC running Erlang 27.3.4 and Elixir 1.17.3, ready to receive the chess application.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [AWS Account Setup](#2-aws-account-setup)
3. [IAM Credentials](#3-iam-credentials)
4. [Configure terraform.tfvars](#4-configure-terraformtfvars)
5. [Run Terraform](#5-run-terraform)
6. [Verify cloud-init Completion](#6-verify-cloud-init-completion)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Prerequisites

Install the following tools on your local machine before proceeding.

### Terraform (>= 1.6)

**macOS:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version   # must show >= 1.6.0
```

**Linux (Debian/Ubuntu):**
```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
terraform version
```

### AWS CLI (v2)

**macOS:**
```bash
brew install awscli
aws --version   # must show aws-cli/2.x.x
```

**Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

### SSH key pair (for instance access)

```bash
# Generate a new key (skip if you already have one to reuse)
ssh-keygen -t ed25519 -C "chess-deploy" -f ~/.ssh/chess_deploy

# Print the public key — you will paste this into terraform.tfvars later
cat ~/.ssh/chess_deploy.pub
```

If you prefer to reuse an existing key (`~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`), that is fine.

---

## 2. AWS Account Setup

### 2.1 Create an AWS account

1. Go to `https://aws.amazon.com` and click **"Create an AWS Account"**.
2. Enter your email, choose an account name, and follow the verification steps.
3. AWS requires a credit card for identity verification. The `t3.small` instance used here is **not** free-tier eligible — you will be charged for running time. To minimize cost, destroy the infrastructure when not in use (`terraform destroy`).

> **Free tier note:** If this is a new AWS account (within the first 12 months), you can use `t2.micro` (1 vCPU, 1 GB RAM) to stay within the free tier. Set `instance_type = "t2.micro"` in `terraform.tfvars`. Keep in mind that compiling Erlang from source on a `t2.micro` will take significantly longer (~40-60 minutes).

### 2.2 Choose a region

Select a region close to your users. Common options:

| Region | Identifier | Notes |
|---|---|---|
| US East (N. Virginia) | `us-east-1` | Lowest cost, widest service availability |
| US West (Oregon) | `us-west-2` | Good alternative for US West |
| South America (São Paulo) | `sa-east-1` | Best latency for South America |
| Europe (Frankfurt) | `eu-central-1` | Best latency for Europe |

### 2.3 Enable MFA

Before doing anything else, secure your root account. In the AWS Console, click your account name (top-right) → **"Security credentials"** → **"Assign MFA device"**.

---

## 3. IAM Credentials

Terraform authenticates to AWS using an IAM user's access key. **Do not use your root account credentials.**

### 3.1 Create an IAM user

1. In the AWS Console, navigate to **IAM** → **Users** → **Create user**.
2. Enter a username (e.g. `terraform-chess`).
3. On the permissions step, select **"Attach policies directly"** and attach **`AdministratorAccess`** (or a more restrictive policy that covers EC2, VPC, and Key Pairs).
4. Complete the wizard. Do not grant console access — this user is for programmatic use only.

### 3.2 Generate an access key

1. Click the newly created user → **"Security credentials"** tab.
2. Under "Access keys", click **"Create access key"**.
3. Choose **"Command Line Interface (CLI)"** as the use case.
4. Copy the **Access key ID** and **Secret access key** — the secret is only shown once.

### 3.3 Configure the AWS CLI

```bash
aws configure
```

Enter the values when prompted:

```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: json
```

This writes credentials to `~/.aws/credentials` and config to `~/.aws/config`. Terraform's AWS provider reads these files automatically — no credentials go into `terraform.tfvars`.

Verify the configuration:
```bash
aws sts get-caller-identity
```

You should see your account ID and the `terraform-chess` user ARN.

---

## 4. Configure terraform.tfvars

All Terraform commands are run from the `infra/terraform/` directory.

```bash
cd infra/terraform

# Create your local config from the example (gitignored — never commit this file)
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in your values:

```hcl
# AWS region (must match the region you configured with aws configure)
aws_region = "us-east-1"

# Full contents of your SSH public key
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... chess-deploy"

# Runtime versions — must stay in sync with DeployEx (Task 05)
erlang_version = "27.3.4"
elixir_version = "1.17.3-otp-27"
```

### Variable reference

| Variable | Description | Where to find it |
|---|---|---|
| `aws_region` | AWS region for all resources | The region you chose in Section 2.2 |
| `ssh_public_key` | SSH public key for instance access | `cat ~/.ssh/chess_deploy.pub` |
| `instance_type` | EC2 instance type | Default: `t3.small`. Use `t2.micro` for free tier |
| `root_volume_size_gb` | EBS root volume size | Default: `20` GB |
| `erlang_version` | OTP version for cloud-init | Must match DeployEx (Task 05) |
| `elixir_version` | Elixir version for cloud-init | Must match DeployEx (Task 05) |

---

## 5. Run Terraform

All commands run from `infra/terraform/`.

### 5.1 Initialize

Downloads the AWS provider plugin. Run once per checkout.

```bash
terraform init
```

Expected output ends with:
```
Terraform has been successfully initialized!
```

### 5.2 Review the plan

Dry-run that shows every resource to be created. Review it before applying.

```bash
terraform plan
```

You should see the following resources listed for creation:
- `aws_vpc.chess` — VPC with CIDR 10.0.0.0/16
- `aws_internet_gateway.chess`
- `aws_route_table.chess_public`
- `aws_route_table_association.chess_public`
- `aws_subnet.chess_public` — subnet 10.0.1.0/24
- `aws_security_group.chess` — ports 22, 80, 443 open
- `aws_key_pair.chess` — SSH public key
- `aws_instance.chess_server` — Ubuntu 22.04, t3.small, 20 GB gp3

A plan showing **"0 to destroy"** is expected on a fresh run. If you see unexpected destroys, review `terraform.tfvars` before proceeding.

### 5.3 Apply

```bash
terraform apply
```

Type `yes` when prompted. Provisioning takes **1-2 minutes**. The cloud-init script (which compiles Erlang from source) runs after the instance boots and takes an additional **15-25 minutes** on `t3.small` (longer on `t2.micro`).

### 5.4 Capture the outputs

After apply completes, Terraform prints:

```
Outputs:

instance_id        = "i-0abc123def456gh78"
instance_public_ip = "54.123.xxx.xxx"
ssh_command        = "ssh ubuntu@54.123.xxx.xxx"
ssh_command_deploy = "ssh deploy@54.123.xxx.xxx"
subnet_id          = "subnet-0abc123def456gh78"
vpc_id             = "vpc-0abc123def456gh78"
```

Save the public IP. You can retrieve outputs at any time with:
```bash
terraform output
terraform output instance_public_ip
```

> **State file**: Terraform writes `terraform.tfstate` in the working directory. This file is gitignored. Do not delete it — it is required to update or destroy the infrastructure later. Back it up somewhere safe (e.g. an S3 bucket with versioning).

---

## 6. Verify cloud-init Completion

cloud-init runs at first boot and compiles Erlang/OTP 27.3.4 from source. This takes **15-25 minutes** on `t3.small`. Do not attempt to deploy the application until it finishes.

### 6.1 SSH into the instance

```bash
# Using the default key
ssh ubuntu@<instance_public_ip>

# If you generated a named key in Section 1
ssh -i ~/.ssh/chess_deploy ubuntu@<instance_public_ip>
```

If you see "Connection refused", the instance is still booting — wait 60-90 seconds and retry.

### 6.2 Check cloud-init status

```bash
# On the instance
cloud-init status
# status: running  (still in progress)
# status: done     (finished successfully)
# status: error    (failed — check logs)
```

To stream progress in real time:
```bash
sudo tail -f /var/log/cloud-init-output.log
```

You will see apt installations, ASDF setup, and a long stream of C compiler output during the Erlang build. The process ends with a line like:
```
Cloud-init v. X.X finished at ...
```

### 6.3 Check the version marker file

The cloud-init script writes `/home/deploy/version-check.txt` as its final step. Its presence confirms both runtimes installed successfully.

```bash
cat /home/deploy/version-check.txt
```

Expected contents:
```
Erlang/OTP 27 [erts-15.x.x] [source] [64-bit] [smp:2:2] [...]
Elixir 1.17.3 (compiled with Erlang/OTP 27)
```

### 6.4 Verify as the deploy user

```bash
# From the ubuntu user, switch to deploy
sudo su - deploy

# Load ASDF and check versions
. ~/.asdf/asdf.sh
elixir --version   # Elixir 1.17.3 (compiled with Erlang/OTP 27)
iex --version      # IEx 1.17.3 (compiled with Erlang/OTP 27)
cat ~/.tool-versions
# erlang 27.3.4
# elixir 1.17.3-otp-27
```

You can also SSH directly as the deploy user from your local machine:
```bash
ssh -i ~/.ssh/chess_deploy deploy@<instance_public_ip>
```

At this point the server is ready to receive the application.

---

## 7. Troubleshooting

### "Error: configuring Terraform AWS Provider: no valid credential sources found"

Terraform cannot find AWS credentials. Run `aws configure` and provide your access key ID and secret access key, then retry. Alternatively, export them as environment variables:

```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"
```

### "Error: InvalidKeyPair.Duplicate: The keypair 'chess-deploy' already exists"

A key pair named `chess-deploy` already exists in your AWS account for this region. Either delete it in the AWS Console (EC2 → Key Pairs) before running `terraform apply`, or import the existing key pair into the Terraform state:

```bash
terraform import aws_key_pair.chess chess-deploy
```

### SSH "Connection refused" after apply

1. Wait 2-3 minutes after apply completes — sshd takes time to start on first boot.
2. Verify the instance is in **Running** state: AWS Console → EC2 → Instances.
3. Confirm the security group allows port 22 from `0.0.0.0/0`: EC2 → Security Groups → chess-sg → Inbound rules.
4. Confirm the subnet has `map_public_ip_on_launch = true` and the instance received a public IP (`terraform output instance_public_ip`).

### cloud-init appears stuck

Compiling Erlang on a `t3.small` (2 vCPU) takes 15-25 minutes. This is normal — the build should be actively consuming CPU.

To confirm it is still running (not frozen):
```bash
cloud-init status         # should show: running
top                       # should show cc1 or make processes consuming CPU
```

### cloud-init status: error

If `cloud-init status` returns `error`, follow these steps to diagnose and fix:

**Step 1: Check the cloud-init logs**

```bash
# View the full output log
sudo tail -100 /var/log/cloud-init-output.log

# Or search for errors/warnings
sudo grep -i "error\|failed\|exception" /var/log/cloud-init-output.log | tail -30

# If you see "scripts_user" failed, check the user script output
sudo cat /var/log/cloud-init-output.log | grep -A 50 "scripts_user"
```

**Step 2: Check the detailed cloud-init result**

```bash
# Shows which stage failed (init, config, final)
sudo cat /run/cloud-init/result.json | jq '.'
```

**Step 3: Common causes and fixes**

**A. Transient apt mirror failure**

Error pattern: `E: Unable to locate package` or `E: Failed to fetch`

Fix:
```bash
sudo apt update
sudo apt upgrade -y
```

**B. GitHub rate limit on ASDF clone**

Error pattern: `api.github.com.*denied` or `fatal: unable to access`

Wait 30-60 minutes for the rate limit to reset, then re-run ASDF setup:
```bash
sudo su - deploy
rm -rf ~/.asdf
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. ~/.asdf/asdf.sh' >> ~/.bashrc
source ~/.asdf/asdf.sh
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang 27.3.4
asdf install elixir 1.17.3-otp-27
```

**C. Disk space exhaustion**

Error pattern: `No space left on device` or `Write failed`

Check:
```bash
df -h
sudo du -sh /* | sort -hr | head -10
```

**D. Permission issues on /home/deploy**

Error pattern: `Permission denied` when creating `.asdf` or writing to `.bashrc`

This happens when the `deploy` user's home directory doesn't have correct ownership. Fix it:

```bash
# SSH as ubuntu
ssh ubuntu@<instance_public_ip>

# Fix ownership
sudo chown -R deploy:deploy /home/deploy
sudo chmod 755 /home/deploy

# Fix bashrc if it exists but is unreadable
sudo chmod 644 /home/deploy/.bashrc 2>/dev/null || true

# Verify
sudo su - deploy
pwd  # should show /home/deploy
```

If `/home/deploy` is completely missing or corrupted, recreate it:

```bash
# As ubuntu user
sudo userdel -r deploy 2>/dev/null || true
sudo useradd -m -s /bin/bash deploy
sudo chown -R deploy:deploy /home/deploy
```

**Step 4: Verify the fix**

```bash
# Check version file
cat /home/deploy/version-check.txt

# Test as deploy user
sudo su - deploy
. ~/.asdf/asdf.sh
erlang --version
elixir --version
iex --version
```

Once all versions print correctly, you can proceed with deploying the application.

### version-check.txt missing or shows errors

If the file does not exist, cloud-init has not finished (or failed). If it exists but contains errors like `iex: command not found`, ASDF was not sourced. Fix manually:

```bash
sudo su - deploy
. ~/.asdf/asdf.sh
elixir --version > /home/deploy/version-check.txt
iex --version >> /home/deploy/version-check.txt
cat /home/deploy/version-check.txt
```

### Destroying and recreating the infrastructure

```bash
# Inside infra/terraform/
terraform destroy
```

Type `yes` when prompted. This removes all resources (EC2 instance, VPC, subnet, security group, internet gateway, key pair). The local `terraform.tfstate` is preserved so you can re-run `terraform apply` to recreate everything. Note that a new public IP address will be assigned.
