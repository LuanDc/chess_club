# Task 04: GitHub Actions CI/CD Pipeline

> RFC reference: §8.4 — GitHub Actions CI/CD
> Depends on: Task 02 (AWS secrets must be in GitHub), Task 03 (OTP release must build cleanly)

## Goal

Implement the automated CI/CD pipeline that runs quality checks on every push to `main` and, on success, builds an OTP release, uploads it to AWS S3, and updates `current.json`. Once this task is complete, every merge to `main` automatically triggers a deployment without manual intervention.

## Checklist

- [x] Create `.github/workflows/deploy.yml` with `quality` and `deploy` jobs
- [x] Implement the `quality` job (lint + tests + type checks)
- [x] Implement the `deploy` job (build release, archive, upload to S3, update `current.json`)
- [x] Add dependency caching (deps/ and _build/)
- [x] Add `SECRET_KEY_BASE` as a GitHub Actions secret
- [x] Set branch protection on `main` (require `quality` status check)
- [x] Test the pipeline with a push to `main` and verify all steps

## Implementation Steps

### 1. Create the workflow file structure

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches:
      - main

jobs:
  quality:
    name: Quality
    runs-on: ubuntu-latest
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

  deploy:
    name: Deploy
    runs-on: ubuntu-latest
    needs: quality
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

      - run: mix assets.deploy

      - name: Build OTP release
        run: MIX_ENV=prod mix release
        env:
          SECRET_KEY_BASE: ${{ secrets.SECRET_KEY_BASE }}

      - name: Archive release
        run: tar -czf chess-${{ github.sha }}.tar.gz _build/prod/rel/chess

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Upload release to S3
        run: aws s3 cp chess-${{ github.sha }}.tar.gz s3://chess-releases/chess-${{ github.sha }}.tar.gz

      - name: Generate current.json
        run: |
          cat > current.json <<EOF
          {
            "version": "${{ github.sha }}",
            "url": "https://chess-releases.s3.${{ secrets.AWS_REGION }}.amazonaws.com/chess-${{ github.sha }}.tar.gz"
          }
          EOF

      - name: Upload current.json to S3
        run: aws s3 cp current.json s3://chess-releases/current.json
```

### 2. Add GitHub Actions secrets

Set these secrets in your GitHub repository settings (Settings → Secrets and variables → Actions):

- `AWS_ACCESS_KEY_ID` — from Task 02
- `AWS_SECRET_ACCESS_KEY` — from Task 02
- `AWS_REGION` — AWS region where `chess-releases` bucket is located (e.g., `us-east-1`)
- `SECRET_KEY_BASE` — Phoenix secret key, generated with:
  ```bash
  mix phx.gen.secret
  ```

### 3. Verify mix quality alias

Before running the pipeline, ensure `mix.exs` defines the `quality` alias. It should run Credo, Dialyzer, and ExUnit:

```elixir
def project do
  [
    # ... existing config ...
    aliases: [
      quality: [
        "credo --strict",
        "dialyzer",
        "test"
      ]
    ]
  ]
end
```

Run locally to verify:
```bash
mix quality
```

### 4. Set branch protection on main

In your GitHub repository settings:

1. Go to Settings → Branches
2. Under "Branch protection rules", click "Add rule"
3. Branch name pattern: `main`
4. Enable:
   - ✓ Require a pull request before merging
   - ✓ Require status checks to pass before merging
   - Under "Status checks that are required", add: `quality`
   - ✓ Require branches to be up to date before merging (optional but recommended)

### 5. Test the pipeline

1. Create a test branch locally:
   ```bash
   git checkout -b test-pipeline
   ```

2. Make a small test commit:
   ```bash
   echo "# Test" >> README.md
   git add README.md
   git commit -m "test: verify CI/CD pipeline"
   ```

3. Push to `main`:
   ```bash
   git push origin test-pipeline:main
   ```

4. Monitor the workflow:
   - Go to Actions tab in GitHub
   - Watch the `quality` job run first
   - Once it passes, the `deploy` job should start automatically
   - Verify that:
     - ✓ `quality` job completes successfully
     - ✓ `deploy` job runs after `quality` passes
     - ✓ Release tar archive appears in S3: `s3://chess-releases/chess-<sha>.tar.gz`
     - ✓ `current.json` is updated in S3 with the new version and URL

5. Verify S3 contents:
   ```bash
   aws s3 ls s3://chess-releases/
   aws s3 cp s3://chess-releases/current.json - | jq .
   ```

## Notes / References

- `erlef/setup-beam` action: https://github.com/erlef/setup-beam
- `aws-actions/configure-aws-credentials` action: https://github.com/aws-actions/configure-aws-credentials
- GitHub Actions documentation: https://docs.github.com/en/actions
- The `mix quality` alias must be defined in `mix.exs` and run Credo strict + Dialyzer + ExUnit
- OTP version in the workflow file must exactly match the `.tool-versions` file (must be OTP 27 and Elixir 1.17)
- `SECRET_KEY_BASE` should never be committed — it is injected via GitHub Actions secrets at runtime
