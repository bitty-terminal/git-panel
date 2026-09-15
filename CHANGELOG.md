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
