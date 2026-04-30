# Task 04: GitHub Actions CI/CD Pipeline

> RFC reference: §8.4 — GitHub Actions CI/CD
> Depends on: Task 02 (OCI secrets must be in GitHub), Task 03 (OTP release must build cleanly)

## Goal

Implement the automated CI/CD pipeline that runs quality checks on every push to `main` and, on success, builds an OTP release, uploads it to Oracle Object Storage, and updates `current.json`. Once this task is complete, every merge to `main` automatically triggers a deployment without manual intervention.

## Checklist

- [ ] Create `.github/workflows/deploy.yml`
- [ ] Implement the `quality` job:
  - [ ] Trigger: `push` to `main`
  - [ ] Runner: `ubuntu-latest`
  - [ ] Steps: checkout → `erlef/setup-beam@v1` (OTP 27, Elixir 1.17) → `mix deps.get` → `mix quality`
- [ ] Implement the `deploy` job:
  - [ ] Declare `needs: quality` so it only runs after a passing quality check
  - [ ] Steps: checkout → `erlef/setup-beam@v1` → `mix deps.get` → `mix assets.deploy` → `MIX_ENV=prod mix release`
  - [ ] Archive the release: `tar -czf chess-${{ github.sha }}.tar.gz _build/prod/rel/chess`
  - [ ] Install OCI CLI in the runner
  - [ ] Configure OCI CLI using the GitHub Actions secrets from Task 02
  - [ ] Upload the tar artefact to the `chess-releases` bucket
  - [ ] Generate `current.json`: `{"version": "${{ github.sha }}", "url": "<object-storage-url>/chess-${{ github.sha }}.tar.gz"}`
  - [ ] Upload `current.json` to the `chess-releases` bucket (overwrite in place)
- [ ] Add dependency caching to speed up runs:
  - [ ] Cache `deps/` keyed on `mix.lock` hash
  - [ ] Cache `_build/` keyed on OTP + Elixir version + `mix.lock` hash
- [ ] Add `SECRET_KEY_BASE` as a GitHub Actions secret (used during `mix release` compilation if needed)
- [ ] Set branch protection on `main`:
  - [ ] Require the `quality` status check to pass before merging
- [ ] Push a test commit to `main` and verify:
  - [ ] The `quality` job runs and passes
  - [ ] The `deploy` job runs after `quality` succeeds
  - [ ] The tar artefact appears in Oracle Object Storage under the commit SHA name
  - [ ] `current.json` in the bucket reflects the new version and URL

## Notes / References

- `erlef/setup-beam` action: https://github.com/erlef/setup-beam
- OCI CLI in GitHub Actions: install via `pip install oci-cli` or the official script; configure with a dedicated config file written from secrets
- The `mix quality` alias must be defined in `mix.exs` (Credo strict + Dialyzer + ExUnit) — verify it exists before running the pipeline
- OTP version in the workflow file must exactly match the VM's `.tool-versions` and the DeployEx binary OTP version (all three must be OTP 27)
