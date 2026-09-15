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

| Path                            | Purpose                                                                                                 |
| ------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `bitty-plugin.toml`             | Static manifest: identity, compatibility, capability requests, `[tools.git]`, and lazy triggers.        |
| `lua/git-panel/init.lua`        | Entry point evaluated once per activation; registers the five git commands and event handlers.          |
| `lua/git-panel/allowlist.lua`   | Host-free `[tools.git]` spawn allowlist (seven verbs, fail-closed bounds).                              |
| `lua/git-panel/scope.lua`       | Host-free working-tree read-scope checks (`~/projects/**`).                                             |
| `lua/git-panel/listing.lua`     | Host-free bounded branch/status/commit listings and filters.                                            |
| `lua/git-panel/scene.lua`       | Declarative `List`/`Text` panel composition.                                                            |
| `tests/`                        | Lua 5.4 behavior suite, LuaLS conformance, and the SDK manifest-lint wrapper.                           |
| `scripts/validate-manifest.mjs` | Transitional manifest check with `[tools.git]` support; `bitty-plugin-lint` (R-SDK-2) is authoritative. |
| `justfile`                      | Quality gates with pinned tool versions.                                                                |

## Behavior

The plugin keeps the bundled git-panel behavior and bounds (OQ-053 split,
`bitty` CTX-0400; the bundled `git_panel_manifest` plus
`bitty-runtime::git_panel` review implementation are removed from the host):

- allowlisted `git` verbs only: `status`, `diff`, `log`, `branch`, `show`,
  `rev-parse`, `ls-files`. Write verbs (`commit`, `push`, `reset`, mutating
  `checkout`, etc.) are absent; staging or commit UX needs explicit user
  action plus a broader grant;
- spawn shape fails closed on: empty args, more than `32` args, any arg over
  `256` bytes, `8 KiB` total args, null/control characters, shell
  metacharacters (semicolon, ampersand, pipe, backtick, dollar, parens,
  angle brackets, backslash, double and single quotes), a non-allowlisted
  subcommand, or risky flags (`--upload-pack`, `--receive-pack`, `--exec`);
- listings truncate deterministically after sorting and deduplication: `128`
  status entries, `64` commits, `32` branches, `64` selected items; names at
  `128` chars, commit messages at `256` chars, paths at `4096` bytes;
- panel observation payloads are bounded to `8 KiB` at the bus admission
  boundary;
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
  declaration is pinned by this package's transitional validator, but the
  `bitty` install-path TOML subset reader accepts no `[tools.*]` table yet
  (CTX-0425 records it as follow-up work under CTX-0400), and the
  authoritative SDK linter (`bitty-plugin-lint`, R-SDK-2) still rejects the
  `tools` key as unknown. Until both accept the slice, the grant binds the
  declared `process.spawn:git` capability while tool presence/version
  diagnostics stay with `bitty plugin doctor`, and `just test-manifest`
  reports the SDK failure when the linter is discoverable (it skips in CI,
  where the linter is not installed).
- **Panel mounting from Lua.** Panel creation for Lua plugins follows the
  `panel.provider`/`panel.create` grant path; command handlers return bounded
  data rows and declarative scenes for the host panel surface.

## Development

Run the same gate CI runs:

```sh
bun install --frozen-lockfile
just check
```

`just check` runs Markdown lint, Prettier format check, the transitional
manifest validator, the pinned Lua parser, and the Lua/LuaLS/SDK-manifest test
suites. `lua5.4` is required for the behavior suite; `lua-language-server` and
`bitty-plugin-lint` are optional and their checks skip with exit 0 when absent.

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
