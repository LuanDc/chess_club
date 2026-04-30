# Production Deployment Guide

This guide takes you from zero — no Oracle Cloud account, no local tooling — to a fully provisioned OCI ARM server running Erlang 27.3.4 and Elixir 1.17.3, ready to receive the chess application.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Oracle Cloud Account Creation](#2-oracle-cloud-account-creation)
3. [OCI API Key Setup](#3-oci-api-key-setup)
4. [Collect Required OCIDs](#4-collect-required-ocids)
5. [Configure terraform.tfvars](#5-configure-terraformtfvars)
6. [Run Terraform](#6-run-terraform)
7. [Verify cloud-init Completion](#7-verify-cloud-init-completion)
8. [Next Steps](#8-next-steps)
9. [Troubleshooting](#9-troubleshooting)

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

### SSH key pair (for instance access)

This key is used to SSH into the server. It is separate from the OCI API key generated in Section 3.

```bash
# Generate a new key (skip if you already have one to reuse)
ssh-keygen -t ed25519 -C "chess-deploy" -f ~/.ssh/chess_deploy

# Print the public key — you will paste this into terraform.tfvars later
cat ~/.ssh/chess_deploy.pub
```

If you prefer to reuse an existing key (`~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`), that is fine.

---

## 2. Oracle Cloud Account Creation

### 2.1 Register for Always Free tier

1. Go to `https://cloud.oracle.com` and click **"Start for free"**.
2. Enter your email and follow the verification link.
3. Complete identity verification. Oracle requires a credit card for identity purposes — **you will not be charged** as long as you stay within Always Free limits.

### 2.2 Choose your Home Region

During registration you are asked to choose a Home Region. **This choice is permanent and cannot be changed.** Choose a region where A1 ARM capacity is reliably available:

| Region | Identifier | Notes |
|---|---|---|
| US East (Ashburn) | `us-ashburn-1` | Highest capacity — recommended default |
| US West (Phoenix) | `us-phoenix-1` | Good alternative |
| Brazil (São Paulo) | `sa-saopaulo-1` | Best latency for South America |
| Germany (Frankfurt) | `eu-frankfurt-1` | Best latency for Europe |

If A1 capacity is exhausted in your chosen region at time of registration, you will not be able to provision the instance. Prefer `us-ashburn-1` unless you have a specific regional reason.

### 2.3 Enable MFA

Before doing anything else, secure your account. Navigate to your profile icon (top-right) → **"My profile"** → **"More actions"** → **"Enable multi-factor verification"**.

---

## 3. OCI API Key Setup

Terraform authenticates to OCI via an RSA key pair. You generate the pair locally, upload the public half to OCI, and reference the private half in `terraform.tfvars`.

### 3.1 Generate the RSA key pair

```bash
mkdir -p ~/.oci

# Generate 4096-bit private key
openssl genrsa -out ~/.oci/oci_api_key.pem 4096

# Restrict permissions (required by OCI)
chmod 600 ~/.oci/oci_api_key.pem

# Extract the public key
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

### 3.2 Upload the public key to OCI Console

1. Log in to the OCI Console.
2. Click your profile icon (top-right) → **"My profile"**.
3. In the left sidebar under "Resources", click **"API keys"**.
4. Click **"Add API key"** → **"Paste a public key"**.
5. Print your public key and paste the full output (including the header/footer lines):
   ```bash
   cat ~/.oci/oci_api_key_public.pem
   ```
6. Click **"Add"**.

### 3.3 Copy the fingerprint

After adding the key, OCI displays a confirmation dialog with the **fingerprint** — a colon-separated hex string like `a1:b2:c3:d4:...:f0`. Copy it now. It is also permanently visible in the API Keys table.

You can verify it locally:
```bash
openssl rsa -pubout -outform DER -in ~/.oci/oci_api_key.pem 2>/dev/null | openssl md5 -c
```

---

## 4. Collect Required OCIDs

OCIDs (Oracle Cloud Identifiers) uniquely identify each resource. You need three.

### Tenancy OCID

Identifies your entire Oracle Cloud account.

1. Click the profile icon → **"Tenancy: \<your-name\>"**.
2. On the Tenancy Details page, click **"Copy"** next to the OCID field.
3. Format: `ocid1.tenancy.oc1..aaaaaa...`

### User OCID

Identifies the IAM user whose API key you uploaded in Section 3.

1. Click your profile icon → **"My profile"**.
2. Click **"Copy"** next to the OCID field.
3. Format: `ocid1.user.oc1..aaaaaa...`

### Compartment OCID

Compartments are logical containers for OCI resources. For a personal project, using the **root compartment** is simplest — its OCID is identical to your Tenancy OCID.

To create a dedicated compartment for isolation:
1. Hamburger menu → **"Identity & Security"** → **"Compartments"**.
2. Click **"Create Compartment"**, name it `chess`.
3. After creation, click the compartment name and copy its OCID.

---

## 5. Configure terraform.tfvars

All Terraform commands are run from the `infra/terraform/` directory.

```bash
cd infra/terraform

# Create your local config from the example (gitignored — never commit this file)
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in every value:

```hcl
# OCI API credentials — from Sections 3 and 4
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
user_ocid        = "ocid1.user.oc1..aaaaaaaXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
fingerprint      = "xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx"
private_key_path = "~/.oci/oci_api_key.pem"

# Your home region (must match what you chose during account creation)
region = "us-ashburn-1"

# Compartment: use tenancy OCID for root, or a dedicated compartment OCID
compartment_ocid = "ocid1.tenancy.oc1..aaaaaaaXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Full contents of your SSH public key (Section 1)
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... chess-deploy"

# Availability domain index — start with 0 (AD-1)
# If terraform apply fails with "Out of host capacity", increment to 1 or 2
availability_domain_index = 0

# Runtime versions — must stay in sync with DeployEx (Task 05)
erlang_version = "27.3.4"
elixir_version = "1.17.3-otp-27"
```

### Variable reference

| Variable | Where to find it |
|---|---|
| `tenancy_ocid` | OCI Console → Profile icon → Tenancy Details |
| `user_ocid` | OCI Console → Profile icon → My Profile |
| `fingerprint` | OCI Console → My Profile → API Keys table |
| `private_key_path` | Local path created in Section 3.1 |
| `region` | The home region you chose during registration |
| `compartment_ocid` | Same as `tenancy_ocid` (root), or Compartments page |
| `ssh_public_key` | `cat ~/.ssh/chess_deploy.pub` (or your existing key) |

---

## 6. Run Terraform

All commands run from `infra/terraform/`.

### 6.1 Initialize

Downloads the OCI provider plugin (~60 MB). Run once per checkout.

```bash
terraform init
```

Expected output ends with:
```
Terraform has been successfully initialized!
```

### 6.2 Review the plan

Dry-run that shows every resource to be created. Review it before applying.

```bash
terraform plan
```

You should see the following resources listed for creation:
- `oci_core_vcn.chess` — VCN with CIDR 10.0.0.0/16
- `oci_core_internet_gateway.chess`
- `oci_core_route_table.chess`
- `oci_core_security_list.chess` — ports 22, 80, 443 open
- `oci_core_subnet.chess_public` — subnet 10.0.1.0/24
- `oci_core_instance.chess_server` — VM.Standard.A1.Flex, Ubuntu 22.04 ARM64, 2 OCPUs, 4 GB RAM

A plan showing **"0 to destroy"** is expected on a fresh run. If you see unexpected destroys, review `terraform.tfvars` before proceeding.

### 6.3 Apply

```bash
terraform apply
```

Type `yes` when prompted. Provisioning takes **2-4 minutes**. The cloud-init script (which compiles Erlang from source) runs after the instance boots and takes an additional **15-25 minutes**.

### 6.4 Capture the outputs

After apply completes, Terraform prints:

```
Outputs:

instance_id          = "ocid1.instance.oc1.iad.aaaaaa..."
instance_public_ip   = "132.145.xxx.xxx"
ssh_command          = "ssh ubuntu@132.145.xxx.xxx"
ssh_command_deploy   = "ssh deploy@132.145.xxx.xxx"
subnet_id            = "ocid1.subnet.oc1.iad.aaaaaa..."
vcn_id               = "ocid1.vcn.oc1.iad.aaaaaa..."
```

Save the public IP. You can retrieve outputs at any time with:
```bash
terraform output
terraform output instance_public_ip
```

> **State file**: Terraform writes `terraform.tfstate` in the working directory. This file is gitignored. Do not delete it — it is required to update or destroy the infrastructure later. Back it up somewhere safe.

---

## 7. Verify cloud-init Completion

cloud-init runs at first boot and compiles Erlang/OTP 27.3.4 from source. This takes **15-25 minutes**. Do not attempt to deploy the application until it finishes.

### 7.1 SSH into the instance

```bash
# Using the default key
ssh ubuntu@<instance_public_ip>

# If you generated a named key in Section 1
ssh -i ~/.ssh/chess_deploy ubuntu@<instance_public_ip>
```

If you see "Connection refused", the instance is still booting — wait 60-90 seconds and retry.

### 7.2 Check cloud-init status

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

### 7.3 Check the version marker file

The cloud-init script writes `/home/deploy/version-check.txt` as its final step. Its presence confirms both runtimes installed successfully.

```bash
cat /home/deploy/version-check.txt
```

Expected contents:
```
Erlang/OTP 27 [erts-15.x.x] [source] [64-bit] [smp:2:2] [...]
Elixir 1.17.3 (compiled with Erlang/OTP 27)
```

### 7.4 Verify as the deploy user

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

## 8. Next Steps

The following tasks complete the production setup. They are documented in `tasks/deployment_platform/`.

| Task | File | Description |
|---|---|---|
| 02 | `02-oracle-object-storage.md` | Create the `chess-releases` OCI bucket for release tarballs |
| 03 | `03-otp-release-config.md` | Configure `mix release`, `SECRET_KEY_BASE`, `runtime.exs` |
| 04 | `04-github-actions-cicd.md` | GitHub Actions pipeline: build → upload to bucket → deploy |
| 05 | `05-deployex-setup.md` | Install DeployEx on the VM as a systemd service |
| 06 | `06-nginx-tls.md` | nginx reverse proxy + Let's Encrypt TLS via Certbot |
| 07 | `07-hot-code-reload.md` | `appup` generation for zero-downtime hot upgrades |

---

## 9. Troubleshooting

### "Out of host capacity" during terraform apply

```
Error: 500-InternalError, Out of host capacity.
```

A1 ARM capacity in Always Free regions is sometimes exhausted. Try in order:

1. Increment `availability_domain_index` in `terraform.tfvars` from `0` to `1`, then `2`, and re-run `terraform apply`.
2. Retry the same AD at off-peak hours (early morning UTC tends to have more capacity).
3. If all three ADs remain exhausted for days, create a new account in a different region.

### "401 - NotAuthenticated" during terraform apply

Checklist:
- `private_key_path` points to the correct `.pem` file and the file has permissions `600`.
- `fingerprint` exactly matches the value in OCI Console → My Profile → API Keys (copy-paste, do not retype).
- `user_ocid` is the OCID of the user who owns that API key.
- `region` matches your tenancy's home region.

### "403 - NotAuthorized / Go to your home region"

The `region` in `terraform.tfvars` does not match the home region of your tenancy. Check OCI Console → Profile icon → Tenancy Details for the correct home region identifier.

### SSH "Connection refused" after apply

1. Wait 2-3 minutes after apply completes — sshd takes time to start on first boot.
2. Verify the instance is in **Running** state in OCI Console → Compute → Instances.
3. Verify the Security List shows port 22 open for `0.0.0.0/0`: OCI Console → Networking → Virtual Cloud Networks → chess-vcn → Security Lists.
4. Confirm you are connecting to the correct IP from `terraform output instance_public_ip`.

### cloud-init appears stuck

Compiling Erlang on a 2-OCPU ARM VM takes 15-25 minutes. This is normal — the build should be actively consuming CPU.

To confirm it is still running (not frozen):
```bash
cloud-init status         # should show: running
top                       # should show cc1 or make processes consuming CPU
```

If `cloud-init status` returns `error`:
```bash
sudo grep -i "error\|failed" /var/log/cloud-init-output.log | tail -30
```

Common causes: transient apt mirror failure, GitHub rate limit on the ASDF clone. Fix the failed step manually as the `deploy` user and re-run it.

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

Type `yes` when prompted. This removes all resources (VM, VCN, subnet, security list, gateway). The local `terraform.tfstate` is preserved so you can re-run `terraform apply` to recreate everything. Note that a new IP address will be assigned.
