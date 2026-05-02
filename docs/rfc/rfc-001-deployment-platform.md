# RFC-001: Deployment Platform for the Chess Application

| Field | Value |
|---|---|
| Status | Draft |
| Author | Luan Fellipe |
| Created | 2026-04-30 |
| Last updated | 2026-04-30 |

---

## 1. Overview

This RFC proposes the adoption of [DeployEx](https://github.com/thiagoesteves/deployex) as the deployment platform for the chess application. The goal is to establish a production-grade, zero-downtime deployment pipeline that leverages BEAM-native capabilities — specifically hot code upgrades — while keeping infrastructure costs at zero for this personal project.

---

## 2. Problem Statement

The chess application currently has no production deployment infrastructure:

- No CI/CD pipeline
- No OTP release configuration
- No server provisioning
- No reverse proxy or TLS termination

Beyond the missing infrastructure, the application is **stateful by design**: each active chess match lives as an in-memory `GenServer` (`Chess.GameServer`). A naive full-restart deployment would terminate all ongoing games. This makes hot code upgrades a first-class requirement, not a nice-to-have.

---

## 3. Goals

- Deploy the chess application to a **free cloud infrastructure** with no expiry
- Enable **zero-downtime deployments** through hot code upgrades when possible
- Provide a **simple, reproducible setup** — no Kubernetes, no Docker
- Architect the system to be **ready for future Erlang distribution / multi-node clustering** (libcluster integration is planned for a future phase)
- Establish a **CI/CD pipeline** that runs the full quality suite before every deployment

---

## 4. Non-Goals

- Multi-region or multi-node clustering (planned future RFC)
- Database persistence of game state (the application is intentionally in-memory)
- Containerisation (Docker / Kubernetes) — DeployEx eliminates this need
- High-availability setup (single VM is acceptable for a personal project)

---

## 5. Why DeployEx

Traditional deployment approaches for web applications rely on Docker containers orchestrated by Kubernetes or similar platforms. For BEAM applications this adds unnecessary abstraction: the VM already provides process isolation, supervision trees, hot code reloading, and distribution.

DeployEx is a lightweight deployment orchestrator **built specifically for BEAM applications** (Elixir, Erlang, Gleam). It:

- Works directly with **OTP releases** (`mix release`) — no container images required
- Automatically detects whether to perform a **full deploy or a hot upgrade** by analysing the release package
- **Monitors application health** and triggers automatic rollback if the new version is unstable for more than 10 minutes
- Connects to the managed application via **OTP distribution with mTLS** for secure inter-node control
- Provides a **web dashboard** for visibility into deployment history and node status

For a stateful application like this chess server, the hot upgrade capability is the decisive factor: active games survive a deployment.

---

## 6. Cloud Provider Decision

Because this is a personal project, the infrastructure must be free (or minimal cost) with no time limit.

| Provider | Free VM | RAM | Storage | Expiry | Notes |
|---|---|---|---|---|---|
| **AWS** | 1 t2.micro → t3.small | 1 GB → 2 GB | 5 GB S3 | 12 months → unlimited | Free tier suitable for 12 months; micro adequate for chess app alone |
| Oracle Cloud | 4 ARM VMs (Ampere A1) | **24 GB total** | 20 GB Object Storage | **Never** | Better long-term, higher learning curve |
| GCP | 1 e2-micro | 0.6 GB | 5 GB | Never | RAM too tight for BEAM |
| Fly.io | 3 shared VMs | 256 MB each | — | Never | RAM insufficient |

**Decision: AWS EC2 + S3**

AWS provides a **t3.small** (2 vCPU, 4 GB RAM) EC2 instance and S3 bucket via the free tier (750 hours/month for 12 months on t2.micro; t3.small has minimal hourly cost outside free tier). For phase 1, AWS offers:
- Better integration with GitHub Actions (native AWS credential support)
- Simpler Terraform configuration and wider documentation
- S3 lifecycle policies for automatic release artifact retention
- Straightforward migration path to on-demand if needed

Post-free-tier cost: t3.small (~$0.02/hour) + minimal S3 storage (~$0.01/month) = ~$15/month. Acceptable for a personal project with mature tooling support.

---

## 7. Architecture

### 7.1 Components

| Component | Role |
|---|---|
| **Oracle Cloud ARM VM** | Host for DeployEx and the chess application |
| **DeployEx** | OTP release lifecycle manager — deploys, monitors, and rolls back |
| **nginx** | Reverse proxy: TLS termination, routes public traffic to the chess app and DeployEx dashboard |
| **GitHub Actions** | CI/CD pipeline: quality checks → build release → upload artefact → update manifest |
| **Oracle Object Storage** | Stores versioned release tarballs and the `current.json` deployment manifest |

### 7.2 Architecture Diagram

```
                          Internet
                              │
                    ┌─────────▼──────────┐
                    │   AWS EC2 VM       │
                    │  t3.small — Ubuntu │
                    │     (via IaC)      │
                    │                    │
                    │  ┌──────────────┐  │
  HTTPS (:443) ────►│  │    nginx     │  │
  HTTP  (:80)  ────►│  │              │  │  ← TLS via Let's Encrypt
                    │  │ /  → :4000   │  │  ← managed by Certbot
                    │  │ /d → :5001   │  │
                    │  └──────┬───────┘  │
                    │         │          │
                    │  ┌──────▼───────┐  │
                    │  │  Chess App   │  │
                    │  │  (:4000)     │  │
                    │  │              │  │
                    │  │ GameServer   │  │  ← stateful GenServers
                    │  │ LiveView WS  │  │  ← Phoenix WebSocket
                    │  │ PubSub       │  │  ← in-memory
                    │  └──────────────┘  │
                    │                    │
                    │  ┌──────────────┐  │
                    │  │  DeployEx    │  │
                    │  │  (:5001)     │  │
                    │  │              │  │  ← Phase 2: polls S3 for
                    │  │ Instance      │  │    current.json manifest
                    │  │ Profile w/    │  │
                    │  │ S3 IAM Role   │  │
                    │  └──────────────┘  │
                    └────────────────────┘

  ┌─────────────────────────────────────┐
  │      GitHub Actions (CI/CD)         │
  │                                     │
  │  push to master                     │
  │    │                                │
  │    ├─ quality workflow               │
  │    │  (credo+dialyzer+tests)        │
  │    │                                │
  │    ├─ deploy workflow (needs: quality)
  │    │  ├─ Mix deps.get                │
  │    │  ├─ mix assets.deploy           │
  │    │  ├─ MIX_ENV=prod mix release   │
  │    │  ├─ tar.gz release artefact    │
  │    │  │                              │
  │    │  └─ upload to AWS S3            │
  │    │     s3://chess-releases-<ID>/   │
  │    │     └─ update current.json ─────┼──► DeployEx detects → deploys
  │                                     │    (Phase 2)
  └─────────────────────────────────────┘
```

### 7.3 Deployment Flow

1. A push to `main` triggers the GitHub Actions workflow.
2. The pipeline runs `mix quality` (Credo strict + Dialyzer + ExUnit). Any failure stops the pipeline.
3. On success: `mix assets.deploy && MIX_ENV=prod mix release` produces an OTP release.
4. The release directory is compressed as `chess-<version>.tar.gz`.
5. The artefact is uploaded to Oracle Object Storage.
6. `current.json` is updated with the new version and artefact URL.
7. DeployEx, polling Object Storage, detects the version change.
8. DeployEx downloads the artefact and decides:
   - If an `appup` file is present → **hot upgrade** (state preserved in GenServers).
   - Otherwise → **full restart** (active games interrupted — documented limitation).
9. DeployEx monitors the new version for 10 minutes. If it stays healthy, the deployment is confirmed. If not, it rolls back to the previous version automatically.

---

## 8. Component Setup

### 8.1 AWS EC2 Instance (via Terraform)

The EC2 instance and all supporting infrastructure are provisioned using Terraform.

- **Instance type:** t3.small (2 vCPU, 4 GB RAM) — suitable for chess app + DeployEx
  - Free tier eligible: t2.micro for 12 months; t3.small has per-hour cost post-free-tier
  - Override in `terraform.tfvars` if cost is a concern
- **OS:** Ubuntu 22.04 LTS (x86_64 HVM)
- **Storage:** 20 GB gp3 EBS root volume
- **Network:** VPC (10.0.0.0/16) with public subnet (10.0.1.0/24); security group opens ports 22, 80, 443
- **Cloud-init:** Automatically installs ASDF, Erlang, Elixir, and creates `deploy` user

**Provisioning (automatic via Terraform):**
```bash
cd infra/terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your SSH key, region, and instance type
terraform init
terraform plan
terraform apply
```

This single command provisions the entire EC2 + VPC + security infrastructure. See `tasks/infra/01-aws-ec2-vm.md` for detailed steps.

### 8.2 DeployEx

DeployEx is installed as a systemd service on the VM.

**Key environment variables:**

| Variable | Purpose |
|---|---|
| `DEPLOYEX_ADMIN_HASHED_PASSWORD` | bcrypt-hashed password for the dashboard |
| `RELEASE_NODE` | Erlang node name for DeployEx (e.g. `deployex@hostname`) |
| `RELEASE_DISTRIBUTION` | Set to `sname` for single-node distribution |
| `ELIXIR_ERL_OPTIONS` | TLS distribution options (for future multi-node phase) |

**OTP version requirement:** DeployEx and the chess application must run on the **same OTP major version** (e.g. both OTP 27). This must be enforced in the CI pipeline and the VM setup.

### 8.3 nginx

nginx acts as the TLS termination point and routes traffic:

```nginx
server {
    listen 443 ssl;
    server_name chess.example.com;

    ssl_certificate     /etc/letsencrypt/live/chess.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/chess.example.com/privkey.pem;

    # Chess application (Phoenix LiveView — WebSocket support required)
    location / {
        proxy_pass         http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
    }

    # DeployEx dashboard (restricted access recommended)
    location /deployex/ {
        proxy_pass http://127.0.0.1:5001/;
    }
}

server {
    listen 80;
    server_name chess.example.com;
    return 301 https://$host$request_uri;
}
```

TLS certificates are obtained and auto-renewed via **Certbot** (Let's Encrypt), installed as a systemd timer.

### 8.4 GitHub Actions CI/CD

The pipeline is split across two workflow files:

#### quality.yml (runs on pull requests)

Executes on every PR targeting `master` (including when marking a draft PR as ready for review). Skips draft PRs to reduce CI cost.

```yaml
on:
  pull_request:
    types: [opened, synchronize, ready_for_review]
    branches:
      - master

jobs:
  quality:
    if: github.event.pull_request.draft == false
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          otp-version: '27'
          elixir-version: '1.17'
      - run: mix deps.get
      - run: mix quality   # credo strict + dialyzer + tests
```

#### deploy.yml (runs on push to master)

Runs only after `quality` passes (enforced via GitHub branch protection rules and workflow dependency).

```yaml
on:
  push:
    branches:
      - master

jobs:
  quality:
    uses: ./.github/workflows/quality.yml

  deploy:
    needs: quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}
      - name: Extract versions and AWS account ID
        id: versions
        run: |
          erlang_version=$(grep 'erlang' .tool-versions | awk '{print $2}')
          elixir_version=$(grep 'elixir' .tool-versions | awk '{print $2}')
          aws_account_id=$(aws sts get-caller-identity --query Account --output text)
          echo "erlang=$erlang_version" >> $GITHUB_OUTPUT
          echo "elixir=$elixir_version" >> $GITHUB_OUTPUT
          echo "aws_account_id=$aws_account_id" >> $GITHUB_OUTPUT
      - uses: erlef/setup-beam@v1
        with:
          otp-version: ${{ steps.versions.outputs.erlang }}
          elixir-version: ${{ steps.versions.outputs.elixir }}
      - run: mix deps.get
      - run: mix assets.deploy
      - run: MIX_ENV=prod mix release
      - run: tar -czf chess-${{ github.sha }}.tar.gz _build/prod/rel/chess
      - name: Upload to AWS S3
        run: aws s3 cp chess-${{ github.sha }}.tar.gz s3://chess-releases-${{ steps.versions.outputs.aws_account_id }}/chess-${{ github.sha }}.tar.gz
      - name: Update current.json
        run: |
          cat > current.json <<EOF
          {"version":"${{ github.sha }}","url":"https://chess-releases-${{ steps.versions.outputs.aws_account_id }}.s3.${{ secrets.AWS_REGION }}.amazonaws.com/chess-${{ github.sha }}.tar.gz"}
          EOF
          aws s3 cp current.json s3://chess-releases-${{ steps.versions.outputs.aws_account_id }}/current.json
```

**Secrets stored in GitHub Actions:**
- `AWS_ACCESS_KEY_ID` — IAM user access key
- `AWS_SECRET_ACCESS_KEY` — IAM user secret key  
- `AWS_REGION` — S3 bucket region
- `SECRET_KEY_BASE` — Phoenix secret key (used in Build OTP release step)

**Key improvements:**
- Versions are extracted at runtime from `.tool-versions`, ensuring CI always matches the project's configured OTP/Elixir
- AWS account ID is queried dynamically via `aws sts get-caller-identity`, making the bucket name self-discovering
- Reusable workflow pattern for `quality` allows both PR checks and deploy workflow to use the same test suite

### 8.5 AWS S3 Bucket (previously Oracle Object Storage)

The deployment architecture uses **AWS S3** for release artifact storage (not Oracle Object Storage as originally proposed in §6 — AWS S3 provides better free-tier economics and wider tooling support).

- **Bucket name:** `chess-releases-<aws-account-id>` (includes AWS account ID for global uniqueness)
- **Contents:**
  - `current.json` — manifest pointing to the latest version
  - `chess-<sha>.tar.gz` — versioned release artefacts (retained for rollback per lifecycle policy)
- **Access:**
  - **GitHub Actions**: IAM user (`github-actions-chess`) with S3 put/get/list permissions + `sts:GetCallerIdentity`
  - **EC2 instance** (future DeployEx integration): IAM instance profile with S3 read permissions
- **Lifecycle policy:** Expires object versions older than 60 days (keeps last ~5 releases)

---

## 9. Hot Code Reload Strategy

Hot upgrades are the primary mechanism for preserving active game state across deployments.

**How it works with DeployEx:**
1. DeployEx compares the new release package against the running version.
2. If the package includes an `appup` file (generated by tools like `mix_appup` or `rebar3_appup_plugin`), DeployEx performs a **hot upgrade** — BEAM loads the new module bytecode while existing processes continue running.
3. Without an `appup`, DeployEx performs a **full restart** — processes are terminated and restarted with the new code.

**Jellyfish library:**
Adding `{:jellyfish, "~> 0.2"}` to `mix.exs` enables hot code reloading for libraries and umbrella applications. This is especially useful for iterative changes to modules that do not carry state.

**Impact on stateful `GameServer` processes:**
- During a hot upgrade, `GenServer` processes receive a `code_change/3` callback. If the state struct changes between versions, this callback transforms the old state into the new shape — games continue uninterrupted.
- If no `code_change` is needed (module logic changes, not state shape), processes keep running transparently.
- If a full restart is unavoidable, active games are lost. This is an **accepted limitation** for a personal project and is documented as a known trade-off.

---

## 10. Erlang Distribution Strategy

### Phase 1 — Single Node (this RFC)

The chess application runs as a single BEAM node on the VM. DeployEx manages it via OS process control (systemd) and monitors its health via the DeployEx-to-app OTP connection.

No `libcluster` or `dns_cluster` setup is active in production at this time. The `DNS_CLUSTER_QUERY` env var in `runtime.exs` is left unconfigured.

### Phase 2 — Multi-Node (future RFC)

When multi-node clustering is implemented via `libcluster`:

- Multiple chess nodes run on the VM (or across VMs)
- DeployEx connects to all nodes via OTP distribution (short-name mode, `sname`)
- Inter-node traffic is secured with mTLS (`inet_tls` protocol, certificates managed on the VM)
- Shared cookie stored in OCI Vault and injected via environment variable at runtime
- DeployEx dashboard shows all connected nodes and their deployment status
- Rolling hot upgrades become possible: upgrade one node at a time, keeping others serving traffic

---

## 11. Security Considerations

| Concern | Mitigation |
|---|---|
| SSH access | Key-based auth only; password auth disabled |
| TLS | Let's Encrypt certificate, auto-renewed by Certbot systemd timer |
| DeployEx dashboard | Protected by admin password (bcrypt); consider IP allowlist via nginx |
| Erlang cookie | Not committed to source; injected via env var from OCI Vault (Phase 2) |
| OCI credentials | API key stored as GitHub Actions secret; least-privilege IAM policy |
| Release artefacts | Object Storage bucket is private; pre-signed URLs for downloads |

---

## 12. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Full restart drops active games | Medium | Medium | Hot upgrades preferred; document as known limitation |
| AWS free tier expires (12 months) | Medium | Medium | t3.small post-free-tier cost ~$15/month; acceptable for personal project; can migrate to Oracle Always Free if needed |
| OTP version mismatch between DeployEx and chess | Medium | High | Extract OTP/Elixir versions at runtime from `.tool-versions` in CI; enforce in Terraform cloud-init |
| Let's Encrypt certificate renewal fails | Low | High | Certbot systemd timer + monitoring; manual renewal documented |
| S3 bucket access denied during deploy | Low | Medium | GitHub Actions IAM user has explicit S3 + STS permissions; permissions defined in Terraform |
| AWS credentials leaked in GitHub logs | Low | High | Secrets are GitHub Actions secrets (masked in logs); long-term: migrate to OIDC provider authentication |

---

## 13. Open Questions

1. Should the DeployEx dashboard be exposed via nginx (with auth) or only accessible via SSH tunnel?
2. When planning the multi-node phase, should `libcluster` use DNS-based discovery or gossip-based discovery?
3. How should we handle scaling beyond the free tier if user load increases? (Migration to multi-node clustering, increased instance type, additional regions)

---

## 14. Acceptance Criteria

- [ ] Chess application is reachable at a public HTTPS URL
- [ ] A push to `main` triggers the CI pipeline automatically
- [ ] A passing pipeline results in a deployment without manual intervention
- [ ] DeployEx dashboard is accessible and shows the current deployed version
- [ ] TLS certificate is valid and auto-renews
- [ ] A hot upgrade deployment does not interrupt an active game in progress
- [ ] A failed deployment triggers automatic rollback within 10 minutes
