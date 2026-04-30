# Task 05: DeployEx Installation and Configuration

> RFC reference: §8.2 — DeployEx
> Depends on: Task 01 (VM must be running), Task 02 (Object Storage bucket must exist), Task 04 (at least one release artefact must be in the bucket)

## Goal

Install DeployEx on the VM as a systemd service and configure it to poll Oracle Object Storage for `current.json`. Once running, DeployEx manages the full lifecycle of the chess application: downloading releases, performing hot upgrades when possible, monitoring health, and rolling back on failure. After this task, deployments are fully automated — pushing to `main` is the only manual step required.

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
  - [ ] `DEPLOYEX_STORAGE_ADAPTER` — set to the OCI/S3-compatible adapter
  - [ ] Object Storage credentials (region, bucket, namespace) for polling `current.json`
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
- DeployEx documentation: https://github.com/thiagoesteves/deployex
- bcrypt hash for the admin password can be generated with: `htpasswd -bnBC 10 "" <password> | tr -d ':\n'`
- DeployEx monitors the new version for 10 minutes after deploy; automatic rollback triggers if health checks fail
- The chess app and DeployEx **must share the same Erlang cookie** — set `RELEASE_COOKIE` consistently in both service files
