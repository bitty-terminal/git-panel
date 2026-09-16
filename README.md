# Bitty Git Panel

Tiled Panel git branch/status/diff/log presentation for the
[Bitty terminal](https://github.com/bitty-terminal/bitty), served through the
allowlisted Layer 2 `[tools.git]` system-CLI reuse contract.

- Plugin id: `bitty-terminal.git-panel`
- Lua module: `lua/git-panel/`
- Capabilities: `panel.provider`, `panel.create`, `terminal.semantic-read`,
  `process.spawn:git`, `fs.read:~/projects/**`
- System tool: `[tools.git]` (`required = true`, `version = ">=2.30"`)
- Lazy commands: `bitty-terminal.git-panel:open`, `:status`, `:diff`,
  `:log`, `:branch`
- Lazy events: `terminal.cwd-changed`, `terminal.title-changed`,
  `focus.changed`

This repository is the independent first-party package created by the bundled
plugin split decision (OQ-053, `bitty-plugins-docs`
`product/bundled-plugin-split-decision.md`), owned by `bitty` `CTX-0400`. It
was scaffolded from
[bitty-plugin-template](https://github.com/bitty-terminal/bitty-plugin-template).

## Status

Pre-implementation ecosystem: the plugin package, manifest, and policy are
implemented and tested headlessly; the Bitty host is still landing the Layer 2
spawn bridge. Nothing here is a compatibility promise beyond the manifest
`[compat]` ranges.

## Layout

| Path                          | Purpose                                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `bitty-plugin.toml`           | Static manifest: identity, compatibility, capability requests, `[tools.git]`, and lazy triggers. |
| `lua/git-panel/init.lua`      | Entry point evaluated once per activation; registers the five git commands and event handlers.   |
| `lua/git-panel/allowlist.lua` | Host-free `[tools.git]` spawn allowlist (seven verbs, fail-closed bounds).                       |
| `lua/git-panel/scope.lua`     | Host-free working-tree read-scope checks (`~/projects/**`).                                      |
| `lua/git-panel/listing.lua`   | Host-free bounded branch/status/commit listings and filters.                                     |
| `lua/git-panel/scene.lua`     | Declarative `List`/`Text` panel composition.                                                     |
| `tests/`                      | Lua 5.4 behavior suite, LuaLS conformance, and the SDK-lint and negative-fixture wrappers.       |
| `package.json`                | Pinned dev dependencies: the authoritative `bitty-plugin-lint` (by commit) plus the gate tools.  |
| `bun.lock`                    | Locked dependency graph installed by `just install`; the only network step.                      |
| `validator-negative/`         | Known-bad manifests the pinned SDK linter must reject; `base.toml` is the accepted control.      |
| `justfile`                    | Quality gates with pinned tool versions.                                                         |

## Behavior

The plugin keeps the bundled git-panel behavior and bounds (OQ-053 split,
`bitty` CTX-0400; the bundled `git_panel_manifest` plus
`bitty-runtime::git_panel` review implementation are removed from the host):

- allowlisted `git` verbs only: `status`, `diff`, `log`, `branch`, `show`,
  `rev-parse`, `ls-files`. Write verbs (`commit`, `push`, `reset`, mutating
  `checkout`, etc.) are absent; staging or commit UX needs explicit user
  action plus a broader grant;
- spawn shape fails closed on: empty args, a sparse argument table or any
  non-string member (a `nil` hole must not hide a later flag), more than `32`
  args, any arg over `256` bytes, `8 KiB` total args, null/control
  characters, shell metacharacters (semicolon, ampersand, pipe, backtick,
  dollar, parens, angle brackets, backslash, double and single quotes), a
  non-allowlisted subcommand, or risky flags (`--upload-pack`,
  `--receive-pack`, `--exec`);
- listings truncate deterministically after sorting and deduplication: `128`
  status entries, `64` commits, `32` branches, `64` selected items; names at
  `128` chars, commit messages at `256` chars, paths at `4096` bytes;
- panel observation payloads are bounded to `8 KiB` at the bus admission
  boundary;
- raw `git` output is truncated to `8 KiB` before parsing; a cut that lands
  mid-line drops the partial trailing line so a fragment is never parsed as
  an entry (`last_spawn_truncated` still records that truncation happened);
- `git` outputs are piped to panel UI, never raw PTY injection; reflected
  terminal bytes are untrusted surfaces counted under the requesting
  generation;
- observation event handlers refresh only the cached snapshot-derived state
  and never spawn; a denied `terminal.semantic-read` propagates instead of
  serving empty data.

## Capability identity with the bundled realization

The plugin id, capabilities, commands, and events are unchanged from the
former bundled manifest — the split changes no identity. There is no
`ui.rich`-style adapter difference here (unlike the palette split): the
bundled Rust realization already declared exactly this set.

## Known gaps

- **Host spawn bridge.** The current `bitty` Lua bridge
  (`crates/bitty-lua/src/host.rs`) implements commands, events, settings,
  store, terminal snapshots, notifications, and timers, but not
  `bitty.process.spawn`. Spawn-backed commands fail closed with
  `E_SPAWN_UNAVAILABLE` until that surface lands. Tracked as a follow-up
  task in `bitty`.
- **Host `[tools.*]` manifest-table enforcement.** The accepted `[tools.git]`
  declaration is enforced by the pinned SDK linter (`bitty-plugin-lint`,
  R-SDK-2), but the `bitty` install-path TOML subset reader accepts no
  `[tools.*]` table yet (CTX-0425 records it as follow-up work under
  CTX-0400). Until it does, the grant binds the declared `process.spawn:git`
  capability while tool presence/version diagnostics stay with
  `bitty plugin doctor`.
- **Panel mounting from Lua.** Panel creation for Lua plugins follows the
  `panel.provider`/`panel.create` grant path; command handlers return bounded
  data rows and declarative scenes for the host panel surface.

## Development

Run the same gate CI runs:

```sh
just install
just check
```

`just install` materializes the commit-pinned dependencies from `bun.lock` and
is the only network step; every gate then runs offline. `just check` runs
Markdown lint, Prettier format check, the manifest gate (`bitty-plugin-lint`
from the pinned [bitty-plugin-sdk](https://github.com/bitty-terminal/bitty-plugin-sdk)),
the pinned Lua parser, and the Lua/LuaLS/SDK-manifest/negative-fixture test
suites. `lua5.4` is required for the behavior suite; `lua-language-server` is
optional and its check skips with exit 0 when absent; the manifest gate and
the negative-fixture gate (`just test-negative`) always run and fail closed
through `just deps` when the pinned linter is not installed.

## Continuous integration

GitHub Actions runs the repository gates on pushes to `main` and pull requests:

- `.github/workflows/ci.yml` — job `Quality gates` (Bun 1.4.0, Lua 5.4,
  `just check`) plus a separate `Lint GitHub Actions workflows` job running the
  pinned `actionlint`.
- `.github/workflows/codeql.yml` — CodeQL `Analyze (actions)` and
  `Analyze (javascript-typescript)` jobs; Lua has no CodeQL extractor.
- `.github/workflows/snapshot-source.yml` — job `Snapshot source matches main`,
  checking the in-repo CarryCtx publication at `refs/heads/carryctx-snapshots`
  against `main`.

`.github/dependabot.yml`, `.github/codeql/codeql-config.yml`, and
`.editorconfig` complete the shared repository baseline. The metadata baseline
is **Proposed** in the umbrella documentation and is not yet accepted; this
adoption follows the repository-metadata task and does not assert acceptance.
Branch protection is unchanged (this is the repository's first CI).

## Install

An external package is installed from a local checkout with the Bitty CLI:

```sh
bitty plugin install /path/to/git-panel
```

The registry entry in
[bitty-plugins](https://github.com/bitty-terminal/bitty-plugins) points at this
repository; this plugin previously shipped as a bundled (staged, disabled by
default) `bitty-terminal.git-panel`.

## Security

Only `panel.provider`, `panel.create`, `terminal.semantic-read`,
`process.spawn:git`, and `fs.read:~/projects/**` are requested. There is no
ambient spawn authority, no shell interpolation, no raw PTY injection, and no
network, clipboard, or terminal-input authority. Spawn goes through the
host-provided surface only, never through `os.execute`, `io.popen`, or a
Lua-loaded native module (denied by the Lua Runtime restricted library).
Report vulnerabilities through the process in the umbrella project's security
policy rather than a public issue.
