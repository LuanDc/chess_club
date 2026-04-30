# Task 01: Oracle Cloud VM Provisioning

> RFC reference: §8.1 — Oracle Cloud VM
> Depends on: none

## Goal

Provision the Oracle Cloud Always Free ARM VM that will host both the chess application and DeployEx. This is the foundation for every subsequent task — nothing else can be completed without a running, accessible server with the correct OTP version installed.

## Checklist

- [ ] Create an Oracle Cloud account at cloud.oracle.com
- [ ] Enable Always Free resources in the account (confirm Ampere A1 quota is available)
- [ ] Create a Virtual Cloud Network (VCN) and public subnet via OCI Console
- [ ] Configure the Security List to open the following ingress ports:
  - [ ] TCP 22 (SSH)
  - [ ] TCP 80 (HTTP)
  - [ ] TCP 443 (HTTPS)
- [ ] Launch an A1 Flex instance:
  - [ ] Shape: VM.Standard.A1.Flex
  - [ ] Resources: 2 OCPUs, 4 GB RAM
  - [ ] OS: Ubuntu 22.04 LTS (ARM64)
  - [ ] Attach your SSH public key during launch
- [ ] SSH into the instance and verify connectivity
- [ ] Disable password-based SSH authentication (`PasswordAuthentication no` in `/etc/ssh/sshd_config`)
- [ ] Install ASDF version manager
  - [ ] Add ASDF to shell profile (`.bashrc` or `.zshrc`)
  - [ ] Install required ASDF plugins: `erlang`, `elixir`
- [ ] Install OTP 27 via ASDF
- [ ] Install Elixir 1.17 via ASDF
- [ ] Create a `.tool-versions` file in the deploy user's home directory pinning both versions
- [ ] Verify with `iex --version` and `elixir --version` that versions match the project
- [ ] (Optional) Create a non-root `deploy` user with limited sudo rights for running the app

## Notes / References

- Oracle Always Free limits: 4 ARM OCPUs + 24 GB RAM total — a single 2 OCPU / 4 GB instance stays well within quota
- ASDF install guide: https://asdf-vm.com/guide/getting-started.html
- OTP version must match DeployEx (see Task 05) — both must run OTP 27
- The VM's public IP is needed in Task 06 (DNS) and Task 05 (DeployEx configuration)
