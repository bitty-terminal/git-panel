# Git-panel test harness

Headless checks for the `lua/git-panel/**` implementation. `just check`
(`lint` + `fmt-check` + `manifest` + `lua` + `test`) runs them locally and in
CI; the individual suites are also available directly. `just install`
materializes the commit-pinned dependencies; every check below is offline
afterwards.

## Prerequisites

- `lua5.4` (plugin VM baseline per ADR 0005) — required for behavior tests;
  CI installs it from the Ubuntu archive before `just check`.
- `bun` — runs the test wrappers and the pinned `bitty-plugin-lint` and
  `luaparse` binaries from the locked dependencies.
- `lua-language-server` (optional) — LuaLS conformance; the check skips with
  exit 0 when it is unavailable (CI does not install it).
- `bitty-plugin-lint` from the pinned `bitty-plugin-sdk` (required) — the
  manifest wrappers and the negative-fixture gate fail closed when it is
  missing; run `just install` first.

## Commands

```sh
just test            # lua5.4 runner + LuaLS check + SDK linter + negative fixtures

# Behavior tests: allowlist, scope, listings, scenes, lifecycle, capabilities.
just test-lua

# LuaLS conformance against the vendored Plugin API v1 definitions
# (LUA_LANGUAGE_SERVER=/path/to/server overrides discovery).
just test-luals

# Authoritative SDK manifest report check (R-SDK-2, --json mode) against the
# pinned dependency; BITTY_PLUGIN_LINT=/path/to/bitty-plugin-sdk/src/cli.ts
# overrides the CLI entry.
just test-manifest

# Negative-fixture gate: the pinned SDK linter must reject every
# validator-negative/*.toml fixture (base.toml is the accepted control).
just test-negative
```

## Layout

| Path                            | Purpose                                                                                                    |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `run.lua`                       | Plain-Lua runner; exits non-zero on assertion failure.                                                     |
| `support/tap.lua`               | Assertion helper (no external test framework).                                                             |
| `support/mock_host.lua`         | Fail-closed in-process `bitty` stub modeling the used surface (commands, events, snapshot, Layer 2 spawn). |
| `spec/allowlist_spec.lua`       | `[tools.git]` spawn allowlist and bound unit tests.                                                        |
| `spec/scope_spec.lua`           | Working-tree read-scope unit tests.                                                                        |
| `spec/listing_spec.lua`         | Bounded branch/status/commit listing unit tests.                                                           |
| `spec/scene_spec.lua`           | Declarative scene composition unit tests.                                                                  |
| `spec/init_spec.lua`            | Entry-point behavior against the mock host.                                                                |
| `lua-defs/bitty.d.lua`          | Vendored LuaLS definitions from bitty-plugin-sdk (origin/main `a7fcd2b`).                                  |
| `lua-defs/negative-fixture.lua` | Excluded-surface fixture that LuaLS must reject.                                                           |
| `check-lua-luals.mjs`           | Positive/negative LuaLS workspace check.                                                                   |
| `check-manifest-lint.mjs`       | Asserts the pinned `bitty-plugin-lint` `--json` report says `bitty-plugin.toml` is valid.                  |
| `check-negative-fixtures.mjs`   | Rejects every `validator-negative/*.toml` fixture with the pinned SDK linter and checks the diagnostic.    |
| `../validator-negative/`        | Seven known-bad manifests (one SDK rule each) plus `base.toml`, the byte-identical accepted control.       |

## Known gaps

- The SDK mock host is a TypeScript test double; a Lua-facing adapter able to
  execute `init.lua` against it is a separate tooling task
  (`bitty-plugin-sdk` `docs/mock-host.md`, "Lua execution").
  `support/mock_host.lua` is this repository's bounded stand-in.
- The `bitty` Lua bridge does not yet implement `bitty.process.spawn`, so
  `init_spec.lua` exercises spawn behavior against the local mock host only;
  in-host activation fails spawn-backed commands closed with
  `E_SPAWN_UNAVAILABLE` until the surface lands.
- CI installs `lua5.4` and the pinned dependencies (including
  `bitty-plugin-lint` via `bun install`), but not `lua-language-server`, so
  only the LuaLS wrapper reports `skipped` (exit 0) in CI; install it locally
  for full conformance coverage.
