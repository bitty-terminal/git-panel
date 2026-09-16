# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Repository-metadata baseline:** added `.github/workflows/ci.yml`
  (`Quality gates` plus `Lint GitHub Actions workflows`),
  `.github/workflows/codeql.yml` (`actions` and `javascript-typescript`),
  `.github/workflows/snapshot-source.yml`, `.github/dependabot.yml`,
  `.github/codeql/codeql-config.yml`, and `.editorconfig`, mirroring the sibling
  plugin repositories. The repository had no `.github/` before. Branch
  protection is unchanged.
- **Initial independent package (OQ-053, `bitty` CTX-0400):**
  `bitty-terminal.git-panel` extracted from the `bitty` bundled-disabled
  catalog into this repository with no identity change (id, capabilities,
  commands, events). Ships the `[tools.git]` allowlist (`status`, `diff`,
  `log`, `branch`, `show`, `rev-parse`, `ls-files`), bounded listings
  (`128`/`64`/`32`), the `~/projects/**` read scope, five commands, three
  observation events, and a headless Lua behavior suite (160 assertions).
- **Negative-fixture gate (R24):** `just test-negative` checks the manifest
  linter against `validator-negative/*.toml`, requiring every known-bad
  fixture to be rejected and the `base.toml` control to be accepted; it is
  wired into `just check` via `just test` and fails when the fixtures are
  missing.

### Changed

- **Manifest validation switched to the pinned SDK lint:** `just manifest`
  now runs `bitty-plugin-lint` from `bitty-plugin-sdk` (R-SDK-2), pinned by
  commit `c3fa9b0` in `package.json` and `bun.lock`, instead of the vendored
  validator. `just install` (`bun install --frozen-lockfile`) is the only
  network step and `just deps` guards every gate fail-closed; the gates use
  the locked binaries (`bun run <bin>`) instead of `bunx <tool>@pin`, so
  `just check`/`just test` are fully offline after install.
- **Negative-fixture gate (R24) rewired to the SDK lint:** the gate now runs
  the pinned `bitty-plugin-lint` on `validator-negative/*.toml`, still
  requiring the byte-identical `base.toml` control to be accepted and every
  negative fixture to be rejected with its expected diagnostic code
  (fail-closed on a missing linter, fixture directory, control, or required
  fixture). Three fixtures were replaced because the authoritative linter
  accepts the former shapes: `bad-param` now carries a whitespace parameter,
  and `double-colon`/`fs-bool` became `param-forbidden`
  (`panel.provider:x`) and `fs-traversal` (`fs.read:~/../x`).

### Removed

- **Vendored manifest validator:** `scripts/validate-manifest.mjs` and its
  transitional notes are removed; the pinned SDK lint is authoritative.
  `bitty-plugin.toml`, the fixtures, and the README describe the SDK check
  instead.

### Fixed

- **Nil-hole spawn allowlist bypass:** `is_allowed_args` now enforces a dense
  string sequence (all of `1..n` present, every member a string), so a sparse
  table such as `{ "status", nil, "--output" }` cannot hide a denied trailing
  flag behind the `nil` where `ipairs` stopped.
- **Truncation phantom half-line (R17):** raw `git` output truncated at the
  `8 KiB` bound now drops the trailing partial line before parsing, so a cut
  that lands mid-line never presents a fragment as an entry. The `8 KiB`
  bound and `last_spawn_truncated` semantics are unchanged.
