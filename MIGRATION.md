# Migration notes

Notes for the bundled-to-independent migration of `bitty-terminal.git-panel`
and the pending host follow-ups. This file is the target of the `MIGRATION.md`
reference in the `bitty-plugin.toml` header and the
`validator-negative/*.toml` fixture headers: host-side `[tools.*]` table
enforcement in the `bitty` install path is follow-up work recorded here.

## Bundled to independent

This repository is the independent first-party package created by the
bundled-plugin split decision (OQ-053, `bitty-plugins-docs`
`product/bundled-plugin-split-decision.md`), owned by `bitty` `CTX-0400`. It
was scaffolded from `bitty-plugin-template`.

The split changes no identity: the plugin id, capabilities, commands, and
events are unchanged from the former bundled manifest. File name, keys, and
limits of the manifest are the accepted v1 contract in `bitty-plugins-docs`
`specifications/plugin-platform-rfc.md` (OQ-012); the plugin manager and
the host parse the manifest independently before any plugin code runs.

## Accepted versus draft: the `[tools.git]` slice

The `[tools.git]` declaration is the accepted Layer 2 slice (CTX-0425;
canonical record in `bitty-plugins-docs`
`specifications/plugin-reuse-and-providers.md`, accepted `[tools.git]`
contract v1). The rest of that reuse RFC stays draft: only this table is
accepted.

## Pending host follow-ups

### Host-side `[tools.*]` table enforcement in the install path

Status: pending, owned by the `bitty` host. The install-path TOML subset
reader accepts no `[tools.*]` table yet (CTX-0425 records it as follow-up
work under CTX-0400). Until it does, the grant binds the declared
`process.spawn:git` capability while tool presence and version diagnostics
stay with `bitty plugin doctor`.

No tracking issue number in the `bitty` repository is confirmed here. When
one exists, link it in this section.

Enforcement-definition dependency: SDK-side `[tools.git]` activation
conformance is blocked for lack of a host-bridge decision
(`bitty-plugin-sdk#82`, CTX-0040: no activation-environment input for tool
presence, no stable diagnostic code). Host enforcement cannot be specified
until that decision lands.

### Host spawn bridge

The `bitty` Lua bridge implements commands, events, settings, store,
terminal snapshots, notifications, and timers, but not
`bitty.process.spawn`. Spawn-backed commands fail closed with
`E_SPAWN_UNAVAILABLE` until that surface lands. This is tracked as a
follow-up task in `bitty`.

## What this repository enforces today

The pinned SDK linter (`bitty-plugin-lint` from `bitty-plugin-sdk`, R-SDK-2,
pinned by commit in `package.json` and `bun.lock`) enforces the manifest
shape fail-closed:

- `just manifest` validates `bitty-plugin.toml` against the accepted
  contract;
- `just test-manifest` asserts the linter's machine-readable report says
  valid;
- `just test-negative` requires every known-bad `validator-negative/*.toml`
  fixture to be rejected and the `base.toml` control to be accepted.

Every gate fails closed when the pinned linter is not installed (`just
deps`; run `just install` first).
