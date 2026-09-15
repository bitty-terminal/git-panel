# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Initial independent package (OQ-053, `bitty` CTX-0400):**
  `bitty-terminal.git-panel` extracted from the `bitty` bundled-disabled
  catalog into this repository with no identity change (id, capabilities,
  commands, events). Ships the `[tools.git]` allowlist (`status`, `diff`,
  `log`, `branch`, `show`, `rev-parse`, `ls-files`), bounded listings
  (`128`/`64`/`32`), the `~/projects/**` read scope, five commands, three
  observation events, and a headless Lua behavior suite (160 assertions).
- **Negative-fixture gate (R24):** `just test-negative` checks the
  transitional manifest validator against `validator-negative/*.toml`,
  requiring every known-bad fixture to be rejected and the `base.toml`
  control to be accepted; it is wired into `just check` via `just test` and
  fails when the fixtures are missing.

### Fixed

- **Nil-hole spawn allowlist bypass:** `is_allowed_args` now enforces a dense
  string sequence (all of `1..n` present, every member a string), so a sparse
  table such as `{ "status", nil, "--output" }` cannot hide a denied trailing
  flag behind the `nil` where `ipairs` stopped.
- **Truncation phantom half-line (R17):** raw `git` output truncated at the
  `8 KiB` bound now drops the trailing partial line before parsing, so a cut
  that lands mid-line never presents a fragment as an entry. The `8 KiB`
  bound and `last_spawn_truncated` semantics are unchanged.
