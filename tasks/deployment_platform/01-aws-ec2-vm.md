# Task 01: AWS EC2 VM Provisioning

> RFC reference: §8.1 — AWS EC2 VM
> Depends on: none

## Goal

Provision the AWS EC2 instance that will host both the chess application and DeployEx using Terraform. This is the foundation for every subsequent task — nothing else can be completed without a running, accessible server with the correct OTP version installed.

## Checklist

- [x] Create or configure an AWS account at console.aws.amazon.com
- [x] Write Terraform configuration to provision the EC2 instance (see `terraform/`)
- [x] Configure a Security Group via Terraform to open the following ingress ports:
  - [x] TCP 22 (SSH)
  - [x] TCP 80 (HTTP)
  - [x] TCP 443 (HTTPS)
- [x] Apply the Terraform configuration (`terraform apply`):
  - [x] Instance type: t4g.small (ARM64) or t3.micro (x86_64, Free Tier eligible)
  - [x] OS: Ubuntu 22.04 LTS
  - [x] SSH public key attached to the instance
  - [x] Public IP / Elastic IP assigned
- [x] SSH into the instance and verify connectivity
- [x] Disable password-based SSH authentication (`PasswordAuthentication no` in `/etc/ssh/sshd_config`)
- [x] Install ASDF version manager
  - [x] Add ASDF to shell profile (`.bashrc` or `.zshrc`)
  - [x] Install required ASDF plugins: `erlang`, `elixir`
- [x] Install OTP 27 via ASDF
- [x] Install Elixir 1.17 via ASDF
- [x] Create a `.tool-versions` file in the deploy user's home directory pinning both versions
- [x] Verify with `iex --version` and `elixir --version` that versions match the project
- [x] Create a non-root `deploy` user with limited sudo rights for running the app

## Notes / References

- Infrastructure is managed via Terraform — see the `terraform/` directory for resource definitions
- AWS Free Tier: t3.micro is free for 12 months (750 hours/month); t4g.small (ARM64) also has Free Tier coverage
- ASDF install guide: https://asdf-vm.com/guide/getting-started.html
- OTP version must match DeployEx (see Task 05) — both must run OTP 27
- The VM's public IP is needed in Task 06 (DNS) and Task 05 (DeployEx configuration)
