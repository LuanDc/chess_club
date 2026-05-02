# Task 04: GitHub Actions CI/CD Pipeline

> RFC reference: §8.4 — GitHub Actions CI/CD
> Depends on: Task 02 (AWS secrets must be in GitHub), Task 03 (OTP release must build cleanly)

## Goal

Implement the automated CI/CD pipeline that runs quality checks on every pull request to `master` and, on success, builds an OTP release on push to `master`, uploads it to AWS S3, and updates `current.json`. Once this task is complete, every merge to `master` automatically triggers a deployment without manual intervention.

## Checklist

- [x] Create `.github/workflows/quality.yml` for pull requests (lint + tests + type checks)
- [x] Create `.github/workflows/deploy.yml` for production deployment on `master` push
- [x] Implement the `quality` job (runs on PRs, skips draft PRs)
- [x] Implement the `deploy` job (build release, archive, upload to S3, update `current.json`)
- [x] Add dependency caching (deps/ and _build/) to both workflows
- [x] Add `SECRET_KEY_BASE` as a GitHub Actions secret
- [x] Configure `mix quality` alias in mix.exs (credo + dialyzer + test)
- [x] Set branch protection on `master` (require `quality` status check from PRs)
- [x] Test the pipeline with pull requests and pushes to `master`

## Implementation Steps

### 1. Create workflow files

The pipeline is split into two workflows:

#### `.github/workflows/quality.yml` (runs on pull requests)

```yaml
name: Quality

on:
  pull_request:
    types: [opened, synchronize, ready_for_review]
    branches:
      - master

jobs:
  quality:
    name: Quality
    runs-on: ubuntu-latest
    if: github.event.pull_request.draft == false
    steps:
      - uses: actions/checkout@v4

      - uses: erlef/setup-beam@v1
        with:
          otp-version: "27.0"
          elixir-version: "1.17.0"

      - name: Cache Elixir dependencies
        uses: actions/cache@v4
        with:
          path: deps
          key: ${{ runner.os }}-deps-${{ hashFiles('**/mix.lock') }}
          restore-keys: |
            ${{ runner.os }}-deps-

      - name: Cache Elixir build
        uses: actions/cache@v4
        with:
          path: _build
          key: ${{ runner.os }}-build-${{ hashFiles('**/mix.lock') }}-otp-27-elixir-1.17
          restore-keys: |
            ${{ runner.os }}-build-

      - run: mix deps.get

      - run: mix quality
```

**Key features:**
- Runs on PR `opened`, `synchronize`, and `ready_for_review` events
- Skips draft PRs with `if: github.event.pull_request.draft == false`
- Targets `master` branch
- Uses caching for faster builds

#### `.github/workflows/deploy.yml` (runs on push to master)

```yaml
name: Deploy

on:
  push:
    branches:
      - master

jobs:
  quality:
    name: Quality
    uses: ./.github/workflows/quality.yml

  deploy:
    name: Deploy
    runs-on: ubuntu-latest
    needs: quality
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Extract versions from .tool-versions and AWS account ID
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

      - name: Cache Elixir dependencies
        uses: actions/cache@v4
        with:
          path: deps
          key: ${{ runner.os }}-deps-${{ hashFiles('**/mix.lock') }}
          restore-keys: |
            ${{ runner.os }}-deps-

      - name: Cache Elixir build
        uses: actions/cache@v4
        with:
          path: _build
          key: ${{ runner.os }}-build-${{ hashFiles('**/mix.lock', 'lib/**', 'test/**', 'mix.exs') }}-${{ steps.versions.outputs.erlang }}-${{ steps.versions.outputs.elixir }}
          restore-keys: |
            ${{ runner.os }}-build-

      - run: mix deps.get

      - run: mix assets.deploy

      - name: Build OTP release
        run: MIX_ENV=prod mix release
        env:
          SECRET_KEY_BASE: ${{ secrets.SECRET_KEY_BASE }}

      - name: Archive release
        run: tar -czf chess-${{ github.sha }}.tar.gz _build/prod/rel/chess

      - name: Upload release to S3
        run: aws s3 cp chess-${{ github.sha }}.tar.gz s3://chess-releases-${{ steps.versions.outputs.aws_account_id }}/chess-${{ github.sha }}.tar.gz

      - name: Generate current.json
        run: |
          cat > current.json <<EOF
          {
            "version": "${{ github.sha }}",
            "url": "https://chess-releases-${{ steps.versions.outputs.aws_account_id }}.s3.${{ secrets.AWS_REGION }}.amazonaws.com/chess-${{ github.sha }}.tar.gz"
          }
          EOF

      - name: Upload current.json to S3
        run: aws s3 cp current.json s3://chess-releases-${{ steps.versions.outputs.aws_account_id }}/current.json
```

**Key features:**
- Runs automatically on every push to `master` after `quality` workflow passes
- Calls `quality` workflow as a reusable workflow and depends on its success
- Extracts runtime versions from `.tool-versions` and AWS account ID dynamically
- Uses dynamic bucket name: `chess-releases-${AWS_ACCOUNT_ID}` (matches Terraform configuration)
- Caches based on extracted Erlang/Elixir versions for better cache consistency

### 2. GitHub Actions secrets (already configured)

The following secrets are already set in GitHub repository settings (Settings → Secrets and variables → Actions):

- ✓ `AWS_ACCESS_KEY_ID` — from Task 02
- ✓ `AWS_SECRET_ACCESS_KEY` — from Task 02
- ✓ `AWS_REGION` — AWS region where `chess-releases` bucket is located (e.g., `us-east-1`)
- ✓ `SECRET_KEY_BASE` — Phoenix secret key

### 3. Mix quality alias (already configured)

The `mix.exs` file defines the `quality` alias that runs Credo, Dialyzer, and ExUnit:

```elixir
defp aliases do
  [
    setup: ["deps.get", "assets.setup", "assets.build"],
    "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
    "assets.build": ["tailwind chess", "esbuild chess"],
    "assets.deploy": [
      "tailwind chess --minify",
      "esbuild chess --minify",
      "phx.digest"
    ],
    quality: ["credo --strict", "dialyzer", "cmd MIX_ENV=test mix test"]
  ]
end
```

**Note:** The test command is explicitly run with `MIX_ENV=test` to ensure proper test environment configuration.

Run locally to verify:
```bash
mix quality
```

### 4. Branch protection on master (already configured)

GitHub branch protection rules for `master` enforce:

1. ✓ Require a pull request before merging
2. ✓ Require status checks to pass before merging
   - Require: `Quality` (from the `quality.yml` workflow)
3. ✓ Require branches to be up to date before merging
4. ✓ Dismiss stale PR approvals when new commits are pushed
5. ✓ Delete branch after merge (recommended)

This ensures all PRs must pass quality checks before being merged to `master`.

### 5. Pipeline workflow (currently active)

The CI/CD pipeline operates in two stages:

#### Pull Request Stage (Quality Workflow)

1. Open a pull request against `master`
2. The `quality.yml` workflow automatically runs:
   - Checks out the code
   - Sets up Erlang/Elixir environment (OTP 27, Elixir 1.17)
   - Caches dependencies and build artifacts
   - Runs `mix quality` (credo → dialyzer → tests)
3. Must pass before merging to `master`

#### Master Push Stage (Deploy Workflow)

1. When a PR is merged to `master`, the `deploy.yml` workflow starts:
   - Checks out the code
   - Sets up Erlang/Elixir environment
   - Uses cached dependencies for faster builds
   - Runs `mix assets.deploy` (minify Tailwind + esbuild + digest)
   - Builds OTP release with `MIX_ENV=prod mix release`
   - Archives the release as `chess-<sha>.tar.gz`
   - Uploads to S3: `s3://chess-releases/chess-<sha>.tar.gz`
   - Updates `current.json` with version and S3 URL
2. Once complete, the latest release is immediately available for deployment

#### Monitoring deployments

View workflow status:
```bash
# List recent workflow runs
gh run list --workflow=deploy.yml --limit=10

# View specific run details
gh run view <run-id>

# View logs for a job
gh run view <run-id> --log
```

Check S3 releases (with account ID in bucket name):
```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# List releases in the bucket
aws s3 ls s3://chess-releases-${AWS_ACCOUNT_ID}/

# View current.json
aws s3 cp s3://chess-releases-${AWS_ACCOUNT_ID}/current.json - | jq .
```

## Status

✅ **Complete** — The CI/CD pipeline is fully implemented and active.

- Quality checks run automatically on all pull requests
- Deployments run automatically on merges to `master`
- Branch protection enforces passing quality checks before merge
- Both workflows use caching for optimized build times

## Architecture Decision Notes

- **Separate workflow files**: Split `quality.yml` and `deploy.yml` for clarity and different trigger conditions
- **Draft PR skipping**: Quality checks skip draft PRs to avoid unnecessary CI cost during development
- **No explicit dependency**: `deploy.yml` has no `needs: quality` because GitHub branch protection rules enforce the requirement
- **Master branch**: Updated from `main` to `master` per repository conventions

## References

- [erlef/setup-beam](https://github.com/erlef/setup-beam) — Erlang/Elixir environment setup
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials) — AWS credential configuration
- [GitHub Actions documentation](https://docs.github.com/en/actions)
- [GitHub CLI](https://cli.github.com/) — for monitoring workflows locally

## Important Notes

- OTP version (27.0) and Elixir version (1.17.0) must match `.tool-versions`
- `SECRET_KEY_BASE` is injected at runtime via GitHub Actions secrets — never commit it
- Cache keys include `mix.lock` hash to invalidate on dependency changes
- Deployment requires AWS credentials with S3 write permissions to `chess-releases` bucket
