# Task 03: OTP Release Configuration

> RFC reference: §8.4 (build side) — GitHub Actions CI/CD
> Depends on: none (can be done locally before the VM exists)

## Goal

Configure the chess application to build correctly as a self-contained OTP release via `mix release`. This includes production runtime configuration, static asset compilation, and a local smoke-test of the release binary. A passing local build is a prerequisite for the CI/CD pipeline (Task 04).

## Checklist

- [x] Verify or create `config/runtime.exs` with runtime environment variable bindings:
  - [x] `PHX_HOST` — sets the endpoint host for URL generation
  - [x] `SECRET_KEY_BASE` — Phoenix secret key (never committed; injected at runtime)
  - [x] `PORT` — HTTP port (default `4000`)
  - [x] `DATABASE_URL` — placeholder if template requires it (not used in Phase 1)
- [x] Update `config/prod.exs`:
  - [x] `Chess.Endpoint` has `server: true`
  - [x] Verify no `DNS_CLUSTER_QUERY` (clustering disabled in Phase 1)
- [x] Update `mix.exs`:
  - [x] `:chess` release block exists under `def releases`
  - [x] Release name matches application name
  - [x] `include_executables_for: [:unix]` is set
- [x] Verify `.tool-versions` pins OTP 27 and Elixir 1.17
- [x] Run asset compilation locally:
  - [x] `mix assets.deploy` completes without errors
  - [x] Static files appear under `priv/static/` (regenerated per build, not committed)
- [x] Build the OTP release locally:
  - [x] `MIX_ENV=prod mix release` completes without errors
  - [x] Release directory exists at `_build/prod/rel/chess/`
- [x] Smoke-test the release binary:
  - [x] Start with `SECRET_KEY_BASE=<test-key> PHX_HOST=localhost PORT=4000 ./_build/prod/rel/chess/bin/chess start`
  - [x] Application responds on port 4000
  - [x] Stop with `Ctrl+C`
- [x] (Optional) Add `rel/env.sh.eex` for custom environment defaults

## Configuration Steps

1. **Configure runtime environment bindings** in `config/runtime.exs`:
   ```elixir
   import Config

   config :chess, Chess.Endpoint,
     host: System.fetch_env!("PHX_HOST"),
     port: String.to_integer(System.get_env("PORT", "4000")),
     secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
     server: true

   # Optional: clustering disabled for Phase 1
   # config :phoenix_cluster, :topology, []
   ```

2. **Update production config** in `config/prod.exs`:
   ```elixir
   import Config

   config :chess, Chess.Endpoint,
     server: true,
     code_reloader: false,
     check_origin: false
   ```

3. **Define release configuration** in `mix.exs`:
   ```elixir
   def project do
     [
       # ... existing config ...
       releases: [
         chess: [
           include_executables_for: [:unix],
           applications: [runtime_tools: :permanent]
         ]
       ]
     ]
   end
   ```

4. **Verify `.tool-versions`**:
   ```
   erlang 27.0
   elixir 1.17.0
   ```

5. **Compile assets**:
   ```bash
   mix assets.deploy
   ```
   Files in `/priv/static/` are generated and **not committed** (ignored in `.gitignore`). Regenerated on each build.

6. **Build the release**:
   ```bash
   MIX_ENV=prod mix release
   ```

7. **Smoke-test locally**:
   ```bash
   export SECRET_KEY_BASE=$(mix phx.gen.secret)
   export PHX_HOST=localhost
   export PORT=4000
   ./_build/prod/rel/chess/bin/chess start
   # Test: curl http://localhost:4000
   # Stop: Ctrl+C
   ```

## Notes / References

- `mix release` docs: https://hexdocs.pm/mix/Mix.Tasks.Release.html
- `config/runtime.exs` is evaluated at runtime (not compile time) — correct place for environment variable bindings
- `SECRET_KEY_BASE` can be generated with `mix phx.gen.secret`
- Generated assets in `/priv/static/` are ignored in `.gitignore` — regenerated on each build/deploy
- The release tar produced in Task 04 will be: `tar -czf chess-<sha>.tar.gz _build/prod/rel/chess` and uploaded to S3
