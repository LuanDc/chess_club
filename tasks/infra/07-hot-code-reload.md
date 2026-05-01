# Task 07: Hot Code Reload

> RFC reference: §9 — Hot Code Reload Strategy
> Depends on: Task 05 (DeployEx must be managing the chess application), Task 06 (full deployment pipeline must be working end-to-end)

## Goal

Enable hot code upgrades so that active chess games survive deployments without interruption. DeployEx performs a hot upgrade when the release package includes an `appup` file. This task adds the tooling to generate `appup` files and implements the `code_change/3` callback in `Chess.GameServer` so that in-progress game state is correctly migrated when the module is reloaded.

## Checklist

- [ ] Add `mix_appup` to `mix.exs` as a dev/runtime-false dependency:
  - [ ] `{:mix_appup, "~> 0.3", runtime: false}`
  - [ ] Run `mix deps.get` to install
- [ ] Verify `mix help appup` shows the available `mix_appup` tasks
- [ ] Make a small code change to a non-state-carrying module (e.g. a view helper)
- [ ] Generate an `appup` file for the change:
  - [ ] Bump the application version in `mix.exs`
  - [ ] Run `MIX_ENV=prod mix release` to build the new version
  - [ ] Run `mix appup.generate` (or the equivalent `mix_appup` task) to produce the `appup` file
  - [ ] Verify the `appup` file appears in `_build/prod/rel/chess/releases/<version>/`
- [ ] Implement the `code_change/3` callback in `Chess.GameServer`:
  - [ ] Add `@impl true` and `def code_change(_old_vsn, state, _extra), do: {:ok, state}` as the baseline
  - [ ] If the state struct shape ever changes between versions, add a clause that transforms the old state map/struct into the new one
- [ ] Write a test for `code_change/3` (TDD — write the test first):
  - [ ] Test that `code_change/3` returns `{:ok, state}` for the current state shape
  - [ ] If a state migration exists, test that old-shape state is correctly transformed
- [ ] Push a release that includes an `appup` file
- [ ] In DeployEx dashboard, observe that the deployment is a **hot upgrade** (not a full restart)
- [ ] Verify an active game survives the hot upgrade:
  - [ ] Open a game in a browser
  - [ ] Push a new release with an `appup` file while the game is in progress
  - [ ] Confirm the game board remains responsive after the upgrade completes
  - [ ] Check DeployEx logs for `hot_upgrade` confirmation (no process restart)
- [ ] Document the hot upgrade procedure in `docs/ARCHITECTURE.md`:
  - [ ] When to write a `code_change/3` clause (state struct changes only)
  - [ ] How to generate and include the `appup` file in a release
  - [ ] What happens if no `appup` is present (full restart — known limitation)

## Notes / References

- `mix_appup` hex package: https://hex.pm/packages/mix_appup
- BEAM hot upgrades work at the module level: only changed modules are reloaded; running processes are not restarted
- `code_change/3` is called by the VM on each running `GenServer` process when its module is hot-upgraded; returning `{:ok, new_state}` is sufficient when the state shape is unchanged
- If a full restart is unavoidable (no `appup` file), active games are lost — this is a documented and accepted trade-off for this personal project (RFC §9)
- Future: when multi-node clustering is added (Phase 2 RFC), rolling hot upgrades become possible — one node upgraded at a time while others serve traffic
