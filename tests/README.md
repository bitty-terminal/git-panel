# Git-panel test harness

Headless checks for the `lua/git-panel/**` implementation. `just check`
(`lint` + `fmt-check` + `manifest` + `lua` + `test`) runs them locally and in
CI; the individual suites are also available directly.

## Prerequisites

- `lua5.4` (plugin VM baseline per ADR 0005) — required for behavior tests;
  CI installs it from the Ubuntu archive before `just check`.
- `bun` — the manifest validator and the LuaLS/SDK-linter wrapper scripts.
- `lua-language-server` (optional) — LuaLS conformance; the check skips with
  exit 0 when it is unavailable (CI does not install it).
- `bitty-plugin-lint` from `bitty-plugin-sdk` (optional) — authoritative
  manifest check; skipped unless discoverable (CI does not install it).

## Commands

```sh
just test            # lua5.4 runner + LuaLS check + SDK linter wrapper

# Behavior tests: allowlist, scope, listings, scenes, lifecycle, capabilities.
just test-lua

# LuaLS conformance against the vendored Plugin API v1 definitions
# (LUA_LANGUAGE_SERVER=/path/to/server overrides discovery).
just test-luals

# Authoritative manifest check (SDK R-SDK-2);
# BITTY_PLUGIN_LINT=/path/to/bitty-plugin-sdk/src/cli.ts forces the SDK CLI.
just test-manifest
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
| `check-manifest-lint.mjs`       | Runs `bitty-plugin-lint` when discoverable.                                                                |

## Known gaps

- The SDK mock host is a TypeScript test double; a Lua-facing adapter able to
  execute `init.lua` against it is a separate tooling task
  (`bitty-plugin-sdk` `docs/mock-host.md`, "Lua execution").
  `support/mock_host.lua` is this repository's bounded stand-in.
- The `bitty` Lua bridge does not yet implement `bitty.process.spawn`, so
  `init_spec.lua` exercises spawn behavior against the local mock host only;
  in-host activation fails spawn-backed commands closed with
  `E_SPAWN_UNAVAILABLE` until the surface lands.
- CI installs `lua5.4` but not `lua-language-server` or `bitty-plugin-lint`,
  so those two wrappers report `skipped` (exit 0) in CI; install them locally,
  or pin them into the workflow later, for full conformance coverage.
