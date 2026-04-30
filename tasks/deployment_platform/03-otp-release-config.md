# Task 03: OTP Release Configuration

> RFC reference: §8.4 (build side) — GitHub Actions CI/CD
> Depends on: none (can be done locally before the VM exists)

## Goal

Configure the chess application to build correctly as a self-contained OTP release via `mix release`. This includes production runtime configuration, static asset compilation, and a local smoke-test of the release binary. A passing local build is a prerequisite for the CI/CD pipeline (Task 04).

## Checklist

- [ ] Verify or create `config/runtime.exs` with the following runtime env bindings:
  - [ ] `PHX_HOST` — sets the endpoint host for URL generation
  - [ ] `SECRET_KEY_BASE` — Phoenix secret key (never committed; injected at runtime)
  - [ ] `PORT` — HTTP port (default `4000`)
  - [ ] `DATABASE_URL` — not applicable (in-memory app), but leave placeholder if template requires it
- [ ] Ensure `config/prod.exs` sets `server: true` in the `Chess.Endpoint` config
- [ ] Confirm `DNS_CLUSTER_QUERY` is not set in `runtime.exs` (Phase 1 is single-node; clustering is disabled)
- [ ] Verify `mix.exs` has a `:chess` release block under `def project` or `def releases`:
  - [ ] Release name matches the application name
  - [ ] `include_executables_for: [:unix]` is set
- [ ] Run asset compilation locally:
  - [ ] `mix assets.deploy` completes without errors
  - [ ] Static files appear under `priv/static/`
- [ ] Build the OTP release locally:
  - [ ] `MIX_ENV=prod mix release` completes without errors
  - [ ] Release directory exists at `_build/prod/rel/chess/`
- [ ] Smoke-test the release binary:
  - [ ] `SECRET_KEY_BASE=<test-key> PHX_HOST=localhost PORT=4000 ./_build/prod/rel/chess/bin/chess start`
  - [ ] Application starts and responds on port 4000
  - [ ] `Ctrl+C` to stop
- [ ] (Optional) Add `rel/env.sh.eex` if any environment variable defaults need to be baked into the release
- [ ] Verify the `.tool-versions` file in the project root pins OTP 27 and Elixir 1.17 (must match the CI and VM)

## Notes / References

- `mix release` docs: https://hexdocs.pm/mix/Mix.Tasks.Release.html
- `config/runtime.exs` is evaluated at runtime (not compile time) — correct place for env var bindings
- `SECRET_KEY_BASE` can be generated with `mix phx.gen.secret`
- The release tar produced in Task 04 will be: `tar -czf chess-<sha>.tar.gz _build/prod/rel/chess`
