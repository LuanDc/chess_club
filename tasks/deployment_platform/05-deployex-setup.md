# Task 05: DeployEx Installation and Configuration

> RFC reference: §8.2 — DeployEx
> Depends on: Task 01 (VM must be running), Task 02 (S3 bucket must exist), Task 04 (at least one release artefact must be in the bucket)

## Goal

Install DeployEx on the VM as a systemd service and configure it to poll AWS S3 for `current.json`. Once running, DeployEx manages the full lifecycle of the chess application: downloading releases, performing hot upgrades when possible, monitoring health, and rolling back on failure. After this task, deployments are fully automated — pushing to `main` is the only manual step required.

## Checklist

- [ ] SSH into the VM
- [ ] Download the DeployEx binary from GitHub releases:
  - [ ] Select the release that matches **OTP 27** (the version string is part of the binary filename)
  - [ ] Place it at `/usr/local/bin/deployex` and make it executable (`chmod +x`)
- [ ] Create the DeployEx home directory (e.g. `/opt/deployex`) and a `releases/` subdirectory
- [ ] Create the systemd service file at `/etc/systemd/system/deployex.service`:
  - [ ] `ExecStart` points to the DeployEx binary
  - [ ] `Restart=on-failure` to auto-recover from crashes
  - [ ] `EnvironmentFile` or inline `Environment=` directives for required variables (see below)
- [ ] Set the required environment variables in the service file:
  - [ ] `DEPLOYEX_ADMIN_HASHED_PASSWORD` — bcrypt hash of the dashboard password
  - [ ] `RELEASE_NODE` — Erlang node name for DeployEx (e.g. `deployex@<hostname>`)
  - [ ] `RELEASE_DISTRIBUTION` — set to `sname` (short names, single-node Phase 1)
  - [ ] `DEPLOYEX_STORAGE_ADAPTER` — set to the S3 adapter (see DeployEx docs for the exact value)
  - [ ] `AWS_ACCESS_KEY_ID` — AWS credentials for accessing the S3 bucket (or rely on the EC2 Instance Profile)
  - [ ] `AWS_SECRET_ACCESS_KEY` — (omit if using the EC2 IAM Instance Profile)
  - [ ] `AWS_REGION` — AWS region where the S3 bucket resides (e.g. `us-east-1`)
  - [ ] `DEPLOYEX_S3_BUCKET` — `chess-releases` (or the equivalent DeployEx env var for the bucket name)
- [ ] Reload systemd, enable, and start DeployEx:
  - [ ] `sudo systemctl daemon-reload`
  - [ ] `sudo systemctl enable deployex`
  - [ ] `sudo systemctl start deployex`
- [ ] Verify the service is healthy: `sudo systemctl status deployex`
- [ ] Access the DeployEx web dashboard at `http://<vm-ip>:5001` in a browser:
  - [ ] Dashboard loads and shows the application list
  - [ ] Log in with the admin password
- [ ] Trigger the first deployment:
  - [ ] Confirm `current.json` in the bucket points to a valid release artefact (from Task 04)
  - [ ] DeployEx detects the version change and downloads the artefact
  - [ ] DeployEx starts the chess application on port 4000
  - [ ] `curl http://localhost:4000` returns a 200 response
- [ ] Verify DeployEx dashboard shows the chess application as running with the correct version
- [ ] Confirm the OTP version of the running chess app matches DeployEx (both OTP 27):
  - [ ] `:erlang.system_info(:otp_release)` via a remote shell

## Notes / References

- DeployEx releases: https://github.com/thiagoesteves/deployex/releases — download the asset labelled for OTP 27
- DeployEx documentation: https://github.com/thiagoesteves/deployex — check the S3 storage adapter configuration
- bcrypt hash for the admin password can be generated with: `htpasswd -bnBC 10 "" <password> | tr -d ':\n'`
- If the EC2 IAM Instance Profile (Task 02) grants S3 access, AWS credentials do not need to be set explicitly in the service file — the AWS SDK picks them up automatically
- DeployEx monitors the new version for 10 minutes after deploy; automatic rollback triggers if health checks fail
- The chess app and DeployEx **must share the same Erlang cookie** — set `RELEASE_COOKIE` consistently in both service files
