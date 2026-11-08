# Bitty Git Panel

Git branch/status/diff/log presentation for the
[Bitty terminal](https://github.com/bitty-terminal/bitty), served through the
allowlisted Layer 2 `[tools.git]` system-CLI reuse contract and presented
through the W-01 focusable overlay.

- Plugin id: `bitty-terminal.git-panel`
- Lua module: `lua/git-panel/`
- Capabilities: `ui.overlay.focus`, `terminal.semantic-read`,
  `process.spawn:git`, `fs.read:**` (rootless, anchored at the requested
  directory)
- System tool: `[tools.git]` (`required = true`, `version = ">=2.30"`)
- Lazy commands: `bitty-terminal.git-panel:open`, `:status`, `:diff`,
  `:log`, `:branch`
- Lazy events: `terminal.cwd-changed`, `terminal.title-changed`,
  `focus.changed`, `overlay.released`

This repository is the independent first-party package created by the bundled
plugin split decision (OQ-053, `bitty-plugins-docs`
`product/bundled-plugin-split-decision.md`), owned by `bitty` `CTX-0400`. It
was scaffolded from
[bitty-plugin-template](https://github.com/bitty-terminal/bitty-plugin-template).

## Overview

Git Panel shows the git state of the repository behind the focused terminal
pane: branch, working-tree status, diff stat, and recent commits. It runs a
fixed set of read-only `git` commands through the host's `[tools.git]` spawn
grant, so it never stages, commits, or otherwise writes to the repository.
Output is bounded and rendered as panel content, not injected into the
terminal.

`open` presents a panel overlay with the current branch, bounded status rows,
and recent-log rows. The repository is resolved from the focused pane's
directory, so a checkout outside `~/projects` works. A pane that is not inside
a git repository raises the typed `E_NOT_A_GIT_REPO` error instead of showing
an empty panel.

Open it with `bitty-terminal.git-panel:open`; the plugin installs no default
chord. For example, focus a pane inside a git checkout, run
`bitty-terminal.git-panel:open`, and the panel overlay shows the current branch,
up to 12 status rows, and up to 8 recent commits; `Esc` closes it. `status`,
`diff`, `log`, and `branch` return their bounded listings as separate command
results.

## Install

Prerequisites:

- Bitty `>=0.0.24` with Plugin API `^1.0` (the manifest `[compat]` minimum;
  no upper bound is declared).
- `git >= 2.30` on `PATH`; the manifest declares
  `[tools.git] required = true`. `bitty plugin doctor` reports tool presence
  and version.
- A working tree you can read. The manifest requests the rootless read-only
  `fs.read:**` grant; the host anchors it at the directory a call requests, so
  a checkout rooted anywhere is in scope.

Install from a local checkout:

```sh
git clone https://github.com/bitty-terminal/git-panel.git
cd git-panel
bitty plugin install "$PWD"
bitty plugin enable bitty-terminal.git-panel
bitty plugin list
```

`bitty plugin install <path>` stages the package under the XDG data store and
records the capabilities you consent to; it executes no plugin code. Approval
for `ui.overlay.focus`, `process.spawn:git`, `terminal.semantic-read`, and the
filesystem scope is required before activation (`--yes` approves
non-interactively). `ui.overlay.focus` is the coupled W-01 grant: the panel
overlay holds transient input capture while it is open (see Known gaps).
Verify activation with `bitty plugin list`: the entry must show
`bitty-terminal.git-panel`, version `0.1.0`, source `local-path`, enabled, and
the grants above. `bitty plugin info bitty-terminal.git-panel` prints the
recorded grant set.

## Commands

Every command id is qualified with the plugin id. All five take no arguments
and have no default keybinding.

| Command                           | What it does                                                                                                              | Arguments | Default keybinding |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | --------- | ------------------ |
| `bitty-terminal.git-panel:open`   | Opens the panel overlay with branch, bounded status rows, and recent-log rows; returns the cwd, root, branch, and counts. | None      | None               |
| `bitty-terminal.git-panel:status` | Shows bounded working-tree entries from `git status --porcelain`.                                                         | None      | None               |
| `bitty-terminal.git-panel:diff`   | Shows bounded `git diff --stat` lines.                                                                                    | None      | None               |
| `bitty-terminal.git-panel:log`    | Shows recent commits from `git log --oneline -n 10`.                                                                      | None      | None               |
| `bitty-terminal.git-panel:branch` | Shows local and remote branches from `git branch -a`.                                                                     | None      | None               |

Listings are capped after sorting and deduplication: 128 status entries, 64
commits, 32 branches, and 64 selected items. Names are cut at 128 characters,
commit messages at 256 characters, and paths at 4096 bytes.

## Configuration

This plugin declares no settings.

There is no settings file to create. Two manifest requirements gate activation
instead:

| Requirement             | Declared value                                      | Notes                                                                                                                                |
| ----------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `git` on `PATH`         | `[tools.git] required = true`, `version = ">=2.30"` | Declared requirement. The pinned SDK linter enforces the declaration; host-side `[tools.*]` enforcement is tracked under Known gaps. |
| Working-tree read scope | `fs.read` for `**`                                  | Rootless read grant; the host anchors it at the requested directory (bitty #2971), so a checkout rooted anywhere is in scope.        |

No declared settings are read or written; the two manifest requirements above
are the only activation inputs.

## Keybindings

Git Panel registers no default keybindings. Bind a chord yourself in
`$XDG_CONFIG_HOME/bitty/init.lua`:

```lua
return {
  keymaps = {
    {
      chord = "ctrl+shift+g",
      action = "command:bitty-terminal.git-panel:open",
      context = "global",
    },
  },
}
```

The `command:` prefix is the accepted keymap action form for a plugin command.
User keymaps own the binding: a user entry with the same `context + chord`
replaces a shipped entry, and the plugin never binds a chord on its own.

While the overlay is open it owns transient input capture (W-01), so `Esc`
closes it; Core also ends the session on focus switch, idle timeout, and
unload. The plugin observes `overlay.released` and clears its local session,
so the next `open` presents a fresh panel. Run `open` again after the overlay
is closed to reopen it.

## Troubleshooting

| Code                      | Class                | Cause                                                                                                             | Remedy                                                                                                                                                 |
| ------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `E_INCOMPATIBLE`          | `validation`         | The running host does not satisfy `>=0.0.24`, or Plugin API is not `^1.0`.                                        | Upgrade Bitty or install a Git Panel release whose `[compat]` minimum covers your host.                                                                |
| `E_CAPABILITY_DENIED`     | `runtime`            | The `process.spawn:git`, `terminal.semantic-read`, or `ui.overlay.focus` grant is missing, expired, or revoked.   | Re-run `bitty plugin install <path>` and approve the current grant set; `bitty plugin list` shows what is recorded.                                    |
| `E_NOT_A_GIT_REPO`        | `runtime`            | The focused pane's directory is not inside a git repository.                                                      | `cd` into a repository in the focused pane, then run `open` again. The plugin never fabricates an empty listing.                                       |
| `E_UI_UNAVAILABLE`        | `runtime`            | The host has no overlay surface, safe mode is active, or the update was rejected.                                 | Use a Bitty build that wires the W-01 overlay bridge; safe mode never presents plugin surfaces.                                                        |
| `E_UI_ALREADY_CAPTURED`   | `runtime`            | Another plugin already owns the single focusable overlay capture session.                                         | Close the other overlay (usually `Esc`) and retry. The plugin never steals or queues behind a foreign session.                                         |
| `E_UI_NOT_OWNER`          | `runtime`            | The previous overlay session ended but its `overlay.released` observation has not been delivered yet.             | Run `open` again; the next dispatch acquires a fresh session. The plugin never orphans a replacement surface.                                          |
| `E_SPAWN_CWD_UNAVAILABLE` | `runtime`            | The focused view has no terminal session, so the host cannot resolve `cwd = "pane"`.                              | Focus a terminal pane and retry; the plugin never supplies or falls back to a path of its own.                                                         |
| `E_SPAWN_DENIED`          | `runtime` / `budget` | The argv shape is invalid, the subcommand is outside the `[tools.git]` allowlist, or a spawn budget was exceeded. | Only the seven read-only verbs are admitted. The plugin issues only those; report the message if it appears for a normal command.                      |
| `E_SPAWN_FAILED`          | `runtime`            | `git` exited non-zero, the spawn or host failed, or tool confinement refused the spawn.                           | Check that `git` works in the pane's directory. A confinement refusal is fail-closed and is not retried; see the note below.                           |
| `E_SPAWN_UNAVAILABLE`     | `runtime`            | The host build has no `process.spawn` bridge, so every spawn-backed command fails closed.                         | Use a Bitty build that wires the Layer 2 spawn bridge. Until then `open` cannot resolve a repository and the listing commands cannot run.              |
| `E_SPAWN_TIMEOUT`         | `runtime`            | `git` did not finish inside the host's spawn deadline; the child was killed and reaped.                           | Retry after the repository stops blocking (large checkout, slow filesystem, or a hung hook).                                                           |
| `E_SNAPSHOT_UNAVAILABLE`  | `runtime`            | The host has no `terminal.snapshot` surface, or the semantic snapshot is not a table.                             | Use a compatible Bitty build. The snapshot is read-only observation; a pane without an `OSC 7` cwd is still resolved through the host spawn directory. |

### Confinement refusals

On a host with the Layer 2 spawn bridge, every admitted `git` call also runs
under inherited OS exec confinement: on Linux a Landlock execute ruleset that
permits only the `git` binary and its loaders. Platforms without their
confinement mechanism refuse admitted spawns instead of running unconfined.
When confinement setup fails, the host refuses the spawn before any process
starts and Lua sees `E_SPAWN_FAILED` with a message beginning
`tool spawn confinement refused 'git':` or
`spawn failed for 'git' under tool confinement (fail-closed):`. This is a
host/sandbox condition, not a missing plugin grant, and the plugin never
retries the call unconfined.

## Status

The plugin package, manifest, and policy are implemented and tested headlessly
against the Layer 2 `[tools.git]` spawn bridge and the W-01 focusable overlay
session. Nothing here is a compatibility promise beyond the manifest
`[compat]` ranges.

## Layout

| Path                          | Purpose                                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `bitty-plugin.toml`           | Static manifest: identity, compatibility, capability requests, `[tools.git]`, and lazy triggers. |
| `lua/git-panel/init.lua`      | Entry point evaluated once per activation; registers the five git commands and event handlers.   |
| `lua/git-panel/allowlist.lua` | Host-free `[tools.git]` spawn allowlist (seven verbs, fail-closed bounds).                       |
| `lua/git-panel/scope.lua`     | Host-free path validation and root-relative containment checks.                                  |
| `lua/git-panel/listing.lua`   | Host-free bounded branch/status/commit listings and filters.                                     |
| `lua/git-panel/scene.lua`     | Declarative panel composition: branch, status rows, recent-log rows.                             |
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
- raw `git` output is truncated to `8 KiB` before parsing; a cut that lands
  mid-line drops the partial trailing line so a fragment is never parsed as
  an entry (`last_spawn_truncated` still records that truncation happened);
- `git` outputs are piped to panel UI, never raw PTY injection; reflected
  terminal bytes are untrusted surfaces counted under the requesting
  generation;
- observation event handlers refresh only the cached snapshot-derived state
  and never spawn; a denied `terminal.semantic-read` propagates instead of
  serving empty data;
- cached roots bind the focused terminal identity (`terminal_id`,
  `runtime_id`, `generation`): an identity change or a successful snapshot
  with missing cwd/title clears the stale value, and a focus change naming
  a different terminal pre-invalidates so unavailable snapshots yield
  unavailable results rather than another pane's root;
- repository root stays separate from the pane cwd: status resolves
  `git rev-parse --show-toplevel` (allowlisted read-only) in the pane cwd
  and joins root-relative porcelain records against that root, so a nested
  pane cwd never mis-joins; a pane outside a git repository raises the typed
  `E_NOT_A_GIT_REPO` error instead of serving an empty listing, and the
  cached snapshot cwd is display data rather than a resolution gate, so a
  pane without an `OSC 7` zone still resolves through the host-resolved spawn
  directory;
- `open` presents a W-01 focusable overlay with the current branch, bounded
  status rows (`12`), and bounded recent-log rows (`8`); the overlay owns
  transient input capture while open, `Esc` closes it, and `overlay.released`
  clears the local session so the next open acquires a fresh surface;
- porcelain v1 parses quote-aware in a single pass: only a `->` outside
  C-quote wrapping splits renames/copies, `\\` decodes before octal so a
  literal backslash before digits is preserved, UTF-8 octal bytes are kept,
  trailing spaces are preserved, and malformed wrappings drop.

## Capability identity with the bundled realization

The plugin id, commands, and events keep the former bundled identity. The
capability set changed for bitty#2966: the deferred `panel.provider` and
`panel.create` candidates were replaced by the accepted W-01
`ui.overlay.focus` grant, because `bitty.panel.create` only allocates an inert
host-owned `Created` record and has no Lua content surface. The filesystem
request moved from the rooted `~/projects/**` pattern to the rootless `**`
grant anchored at the requested directory (bitty #2971).

## Known gaps

- **No plugin content panel API.** `bitty.panel.create` allocates an inert
  host-owned `Created` panel record; the host mounts it and there is no Lua
  surface for plugin content. The panel is therefore a W-01 focusable overlay,
  the closest accepted surface. A non-focusable presentation-only overlay
  (`bitty.ui.overlay.show`) exists in Core but requires the `ui.present`
  grant, which the pinned `bitty-plugin-sdk` capability set does not accept
  yet; this package does not declare a capability its own manifest gate would
  reject.
- **Overlay input capture.** The W-01 focusable overlay owns transient input
  while open, so the panel is not click-through and the terminal does not
  receive keys until the session ends (`Esc`, focus switch, idle timeout, or
  unload). A presentation-only surface would remove this tradeoff once
  `ui.present` is accepted by the SDK.
- **Confined pane cwd for spawns.** The plugin passes `cwd = "pane"` and the
  host resolves the globally focused view's directory itself (Core CTX-1715,
  shipped in 0.0.33); the plugin never supplies a path. A focused view without
  a terminal session is refused with `E_SPAWN_CWD_UNAVAILABLE`, so the five
  spawn-backed commands fail closed instead of running git in the host cwd.
  Core's `[tools.git]` allowlist still denies a plugin-supplied `-C`, so the
  directory cannot be selected through argv.

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
the pinned Lua parser, the Lua/LuaLS/SDK-manifest/negative-fixture test
suites, and `just docs-check` (the README configuration table must match the
manifest `[settings]` declarations). `lua5.4` is required for the behavior
suite; `lua-language-server` is optional and its check skips with exit 0 when
absent; the manifest gate and the negative-fixture gate (`just test-negative`)
always run and fail closed through `just deps` when the pinned linter is not
installed.

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

## Security

Only `ui.overlay.focus`, `terminal.semantic-read`, `process.spawn:git`, and
the rootless `fs.read:**` grant are requested. `ui.overlay.focus` is the
coupled W-01 grant for the focusable overlay and its transient input capture;
there is no ambient spawn authority, no shell interpolation, no raw PTY
injection, and no network, clipboard, or persistent terminal-input authority.
Spawn goes through the host-provided surface only, never through `os.execute`,
`io.popen`, or a Lua-loaded native module (denied by the Lua Runtime
restricted library). Report vulnerabilities through the process in the
umbrella project's security policy rather than a public issue.
