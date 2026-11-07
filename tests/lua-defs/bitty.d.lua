--- Bitty Plugin API v1 LuaLS definitions.
--- GENERATED FILE - DO NOT EDIT.
--- Source: surface/bitty-plugin-api-v1.json
--- Contract: bitty-docs:docs/decisions/adrs/ADR-0009-plugin-api-v1-lua-surface.md + bitty-docs:docs/specifications/plugin-api-v1-lua-surface-rfc.md + bitty-docs:docs/decisions/adrs/ADR-0014-workspace-core-presentation-plugins.md + bitty-docs:docs/development/overlay-input-capture-contract.md + bitty-terminal-docs:specifications/composer-architecture.md
--- Referenced (not authority): bitty-terminal-docs:specifications/search-selection-contract.md (draft) + bitty-plugins-docs:extensibility/history-and-storage-policy.md (draft) + bitty-plugins-docs:specifications/search-copy-mode-policy.md (draft)
--- Regenerate: bun scripts/generate-lua-defs.ts --write
--- Verify: just lua-defs-check
---@meta bitty

--- Opaque generation-owned handle returned by bitty.commands.register.
---@alias BittyCommandHandle integer

--- Opaque generation-owned handle returned by bitty.events.subscribe.
---@alias BittySubscriptionHandle integer

--- Opaque generation-owned handle returned by bitty.keymaps.suggest.
---@alias BittyKeymapHandle integer

--- Opaque generation-owned handle returned by bitty.services.provide.
---@alias BittyServiceHandle integer

--- Opaque generation-owned block_id returned by bitty.ui.mount and accepted by bitty.ui.update.
---@alias BittyBlockHandle integer

--- Opaque generation-owned task handle returned by bitty.tasks.spawn; invalid after generation
--- disposal.
---@alias BittyTaskHandle integer

--- Opaque generation-owned timer handle returned by bitty.timers.create; invalid after generation
--- disposal.
---@alias BittyTimerHandle integer

--- Bounded JSON Schema fragment as accepted by the CLI Contract RFC and ADR 0009: depth at most 16,
--- bounded string fields, explicit additionalProperties flag, at most CMD_SCHEMA_MAX_BYTES (16 KiB)
--- per schema, no remote $ref, and no unbounded patterns.
---@alias BittyJsonSchema table

--- Command registration definition for bitty.commands.register; valid only during init.lua
--- activation.
---@class BittyCommandDef
---@field id string Plugin-local command segment matching ^[a-z][a-z0-9-]{0,63}$; the host qualifies it to <plugin-id>:<id>.
---@field title string Bounded display text; host-rendered, never markup.
---@field description? string Bounded display text.
---@field args_schema? BittyJsonSchema Argument schema validated by the host before dispatch.
---@field result_schema? BittyJsonSchema Result schema validated by the host before the result is returned.
---@field run fun(args: table): any Command body; args is a plain table already validated against args_schema.

--- Command registration surface (L1). Registration is valid only while init.lua executes.
---@class BittyCommandsNamespace
local BittyCommandsNamespace = {}

--- Registers a plugin command; valid only during init.lua activation. The qualified name must
--- already be reserved in the manifest [lazy].commands, duplicate qualified names are rejected at
--- graph construction, and a later registration attempt is a registration error.
---@param def BittyCommandDef
---@return BittyCommandHandle
function BittyCommandsNamespace.register(def) end

--- Closed v1 event-name set; subscribing to an undeclared or unknown name is a registration error,
--- and declaring any workspace.* name requires a granted workspace.read capability at activation.
---@alias BittyEventName "plugin.activated"|"plugin.suspended"|"plugin.disposed"|"handler.violation"|"terminal.opened"|"terminal.closed"|"terminal.title-changed"|"terminal.cwd-changed"|"terminal.bell"|"focus.changed"|"selection.changed"|"process.exited"|"config.reloaded"|"workspace.created"|"workspace.closed"|"workspace.renamed"|"workspace.focused"|"workspace.changed"|"overlay.released"|"intercept.command-dispatch"|"intercept.terminal-spawn"|"intercept.paste"|"intercept.open-url"

--- Event payload with no fields for lifecycle, signal, and coalescable observation events.
---@class BittyEmptyPayload

--- terminal.opened payload delivering the accepted identity tuple.
---@class BittyTerminalOpenedPayload
---@field terminal_id integer Terminal identity.
---@field runtime_id integer Live PTY incarnation identity.
---@field generation integer Registry generation that allocated the terminal; lets consumers detect stale identities.

--- terminal.closed payload; emitted once per terminal as a cold-path event.
---@class BittyTerminalClosedPayload
---@field terminal_id integer Terminal identity.
---@field runtime_id integer Live PTY incarnation identity.
---@field reason string Bounded closed reason derived from the accepted TerminalClosed shape.

--- terminal.title-changed payload with attribution.
---@class BittyTerminalTitleChangedPayload
---@field title string Bounded title text (EVENT_MAX_BYTES).
---@field terminal_id integer Terminal identity.
---@field runtime_id integer Live PTY incarnation identity.

--- terminal.cwd-changed payload with attribution; treat cwd as sensitive-capable display data.
---@class BittyTerminalCwdChangedPayload
---@field cwd string Bounded current working directory.
---@field terminal_id integer Terminal identity.
---@field runtime_id integer Live PTY incarnation identity.

--- focus.changed payload; coalescable.
---@class BittyFocusChangedPayload
---@field view_id integer Focused view identity.
---@field terminal_id? integer Attached terminal identity when the focused view has one.

--- selection.changed payload; coalescable and carries no selection text in v1.
---@class BittySelectionChangedPayload
---@field view_id integer View identity.
---@field terminal_id? integer Attached terminal identity when the view has one.

--- process.exited payload carrying the accepted exit-status field.
---@class BittyProcessExitedPayload
---@field terminal_id integer Terminal identity.
---@field runtime_id integer Live PTY incarnation identity.
---@field exit_code integer Process exit status.

--- workspace.closed, workspace.changed, and workspace.focused payload: identity only, never
--- terminal content; delivered only to workspace.read holders and coalesced per host tick.
---@class BittyWorkspaceEventPayload
---@field id BittyWorkspaceId Stable workspace id.

--- workspace.created and workspace.renamed payload: identity plus the bounded display name;
--- delivered only to workspace.read holders.
---@class BittyWorkspaceNamedEventPayload
---@field id BittyWorkspaceId Stable workspace id.
---@field name string Display name, bounded by Core to 32 characters.

--- Interception payload with bounded sanitized metadata; rewriting content is not expressible.
---@class BittyInterceptPayload
---@field action string Bounded action label.
---@field origin string Bounded origin label.
---@field preview string Bounded sanitized preview; intercept.paste never carries paste text without clipboard.read.

--- Union of the closed v1 event payload shapes.
---@alias BittyEventPayload BittyEmptyPayload|BittyTerminalOpenedPayload|BittyTerminalClosedPayload|BittyTerminalTitleChangedPayload|BittyTerminalCwdChangedPayload|BittyFocusChangedPayload|BittySelectionChangedPayload|BittyProcessExitedPayload|BittyWorkspaceEventPayload|BittyWorkspaceNamedEventPayload|BittyOverlayReleasedPayload|BittyInterceptPayload

--- Immutable bounded event envelope delivered to subscribed handlers.
---@class BittyEvent
---@field kind BittyEventName Event name from the closed v1 set.
---@field sequence integer Monotonic delivery sequence.
---@field payload BittyEventPayload Immutable payload copy, never a live core object.

--- Observation and lifecycle return values are ignored; interception handlers return the literal
--- false to veto and any other value (including nil) to approve, so the shared handler result
--- domain is any.
---@alias BittyEventHandler fun(event: BittyEvent): any

--- Event subscription surface (L1). Subscriptions must match manifest-declared event types.
---@class BittyEventsNamespace
local BittyEventsNamespace = {}

--- Subscribes to one closed v1 event name; the type must be declared for the plugin. Observation
--- and lifecycle handler results are ignored; interception handlers return false to veto, anything
--- else to approve.
---@param name BittyEventName
---@param handler BittyEventHandler
---@return BittySubscriptionHandle
function BittyEventsNamespace.subscribe(name, handler) end

--- Key-binding suggestion for bitty.keymaps.suggest; suggestions never override user or workspace
--- mappings.
---@class BittyKeymapSuggestion
---@field chord string Chord in the shipped configuration grammar: trimmed, case-insensitive modifiers joined with + (ctrl, alt, shift, super); single-character keys require a modifier.
---@field command string Qualified name of a command registered by the same generation.
---@field when? "global" v1 context; must be absent or "global", any other value is a registration error.

--- Key-binding suggestion surface (L1); suggestions are declarations with no forced mutation.
---@class BittyKeymapsNamespace
local BittyKeymapsNamespace = {}

--- Suggests a key binding for a command registered by the same generation; the accepted precedence
--- user > workspace > first-party/default > plugin always applies and conflicts produce diagnostics
--- for user resolution.
---@param def BittyKeymapSuggestion
---@return BittyKeymapHandle
function BittyKeymapsNamespace.suggest(def) end

--- Plugin settings value; typed schema, merge, and reload semantics are owned by the accepted
--- Configuration Model RFC.
---@alias BittySettingsValue boolean|number|string|table

--- Plugin settings surface (L1); keys are dot paths relative to plugins.<owner>.<name> only.
---@class BittySettingsNamespace
local BittySettingsNamespace = {}

--- Reads a key relative to plugins.<owner>.<name>; plugins cannot read outside their own namespace.
---@param key string
---@return BittySettingsValue
function BittySettingsNamespace.get(key) end

--- Writes a key relative to plugins.<owner>.<name>; plugins cannot write outside their own
--- namespace.
---@param key string
---@param value BittySettingsValue
---@return boolean
function BittySettingsNamespace.set(key, value) end

--- JSON-compatible plain data: depth at most 8, at most 1024 nodes, at most 8 KiB serialized
--- (STORE_MAX_VALUE_BYTES); functions, metatables, cycles, and non-finite numbers are rejected.
---@alias BittyStoreValue boolean|number|string|table

--- Quota-bounded persistent key-value area scoped to the plugin id and persisted across
--- generations; STORE_QUOTA_BYTES default 256 KiB.
---@class BittyStoreNamespace
local BittyStoreNamespace = {}

--- Reads a persisted value by key; keys match ^[a-z0-9][a-z0-9._-]{0,127}$ and the store survives
--- suspension, reload, and generation disposal.
---@param key string
---@return BittyStoreValue|nil
function BittyStoreNamespace.get(key) end

--- Writes or, with nil, deletes a persisted value; writes are synchronous and fail closed on value
--- invalidity or quota overflow without partial writes.
--- Errors: E_STORE_VALUE_INVALID, E_STORE_QUOTA.
---@param key string
---@param value BittyStoreValue|nil
---@return boolean
function BittyStoreNamespace.set(key, value) end

--- Notification payload gated by platform.notify and subject to host rate policy.
---@class BittyNotifyPayload
---@field title string Bounded title text.
---@field body? string Bounded body text.
---@field urgency? "low"|"normal"|"critical" Urgency level.

--- Notification surface (L1) gated by platform.notify.
---@class BittyNotifyNamespace
local BittyNotifyNamespace = {}

--- Shows a host-rendered notification via the platform.notify capability, subject to host rate
--- policy.
--- Capabilities: platform.notify.
--- Errors: E_CAPABILITY_DENIED.
---@param payload BittyNotifyPayload
---@return boolean
function BittyNotifyNamespace.show(payload) end

--- Environment read surface (L1) accepted by ADR 0006. This sub-table is absent unless the manifest
--- declares an env.read:<KEY> capability; when declared but not granted its functions fail closed
--- with E_CAPABILITY_DENIED and never enumerate keys.
---@class BittyEnvNamespace
local BittyEnvNamespace = {}

--- Reads a desensitized environment value for a bounded ASCII key matching ^[A-Z_][A-Z0-9_]*$
--- (1..64); keys outside the allowlist return nil, indistinguishable from an unset variable.
--- Available only when the namespace is declared.
--- Capabilities: env.read:<KEY>.
--- Host status: deferred - always fails with E_NOT_IMPLEMENTED (runtime) until the host backend lands.
--- Errors: E_NOT_IMPLEMENTED.
---@param name string
---@return string|nil
function BittyEnvNamespace.get(name) end

--- Reports presence without exposing the value beyond the trace surface. Available only when the
--- namespace is declared.
--- Capabilities: env.read:<KEY>.
--- Host status: deferred - always fails with E_NOT_IMPLEMENTED (runtime) until the host backend lands.
--- Errors: E_NOT_IMPLEMENTED.
---@param name string
---@return boolean
function BittyEnvNamespace.has(name) end

--- Consumer-side service resolution options for bitty.services.get.
---@class BittyServiceGetOpts
---@field version string Version requirement in the accepted grammar, for example ">=2.0". Required: the accepted RFC defines no default requirement.
---@field optional? boolean When true, a missing provider returns nil instead of failing with E_SERVICE_RESOLUTION.

--- Plain service table whose members are functions; calls are schema-validated by the host and
--- return plain values, never cross-VM handles.
---@alias BittyService table<string, fun(...): any>

--- Service consumer and provider surface (L1); provider declarations live in the manifest
--- [services.provided] table form.
---@class BittyServicesNamespace
local BittyServicesNamespace = {}

--- Resolves a provider before activation; a missing provider fails closed with E_SERVICE_RESOLUTION
--- unless opts.optional is true, and provider disappearance makes in-flight calls fail closed with
--- E_SERVICE_GONE.
--- Errors: E_DEF_INVALID, E_SERVICE_VERSION_INVALID, E_SERVICE_RESOLUTION.
---@param iface string
---@param opts BittyServiceGetOpts
---@return BittyService|nil
function BittyServicesNamespace.get(iface, opts) end

--- Provides an interface implementation during activation; the interface, version, and bounded
--- schemas must already be declared in the manifest [services.provided] table form, and arguments
--- and results are schema-validated by the host.
--- Errors: E_DEF_INVALID, E_SERVICE_UNDECLARED.
---@param iface string
---@param impl BittyService
---@return BittyServiceHandle
function BittyServicesNamespace.provide(iface, impl) end

--- Accepted closed slot set. tabline is an exclusive claim; status components compose; overlay is
--- non-focusable presentation content. The host presents top, bottom, left, right, and statusline;
--- tabline, overlay, and terminal have no host surface yet and ui.mount rejects them with
--- E_UI_UNAVAILABLE.
---@alias BittyUiSlot "terminal"|"top"|"bottom"|"left"|"right"|"tabline"|"statusline"|"overlay"

--- Bounded declarative component table shaped by the accepted SceneNode contract; v1 accepts Text,
--- Row, Column, and List subtrees only. Exact table encoding is owned by the accepted Rich
--- Presentation RFC.
---@alias BittySceneNode table

--- Declarative UI contribution surface (L2); rich content requires ui.rich, the overlay slot
--- requires ui.overlay, and the focusable overlay session requires ui.overlay.focus.
---@class BittyUiNamespace
---@field overlay BittyUiOverlayNamespace Focusable overlay and transient input-capture sub-table (W-01); requires ui.overlay.focus.
local BittyUiNamespace = {}

--- Mounts declarative component content into an accepted semantic slot; rich content requires
--- ui.rich, the overlay slot additionally requires ui.overlay, and the exclusive tabline slot
--- requires a matching [lazy].claims entry (E_UI_CLAIM_REQUIRED). After those gates, an accepted
--- slot the host does not present (tabline, overlay, terminal) fails closed with E_UI_UNAVAILABLE
--- (runtime). Host layout owns placement and decoration, and there are no global coordinates,
--- shaders, pipelines, glyph injection, native windows, or renderer handles.
--- Capabilities: ui.rich.
--- Conditional capabilities: ui.overlay (when slot == "overlay").
--- Errors: E_CAPABILITY_DENIED, E_UI_CLAIM_REQUIRED, E_UI_UNAVAILABLE, E_UI_COMPONENT_INVALID.
---@param slot BittyUiSlot
---@param component BittySceneNode
---@return BittyBlockHandle
function BittyUiNamespace.mount(slot, component) end

--- Replaces a block's scene subtree under the same block_id with an incremented version; returns
--- false for a stale or foreign handle and raises E_UI_COMPONENT_INVALID for a component that
--- violates the scene contract.
--- Capabilities: ui.rich.
--- Errors: E_CAPABILITY_DENIED, E_UI_COMPONENT_INVALID.
---@param handle BittyBlockHandle
---@param component BittySceneNode
---@return boolean
function BittyUiNamespace.update(handle, component) end

--- Opaque generation-owned handle returned by bitty.ui.overlay.acquire; invalid after generation
--- disposal.
---@alias BittyOverlayHandle integer

--- Presentation hints for bitty.ui.overlay.acquire; every field is optional and unknown fields are
--- ignored.
---@class BittyOverlaySpec
---@field title? string Bounded overlay title text.
---@field placeholder? string Bounded placeholder text.

--- One queued input event with a decided type tag; field-level key, pointer, and IME encodings stay
--- parked.
---@class BittyOverlayEvent
---@field seq integer Monotonic event sequence within the session.
---@field type "key"|"text"|"pointer"|"paste" Decided input-event tag.
---@field data? table Opaque tag payload within the per-event byte ceiling.

--- Owner-initiated drain of already-queued input events; never a Core-driven callback.
---@class BittyOverlayPollResult
---@field status "active"|"released" Whether the session holds capture or is terminal per handle.
---@field seq integer Monotonic sequence of the last event delivered to this owner in this session.
---@field events BittyOverlayEvent[] Input events in order; empty when there is nothing new.
---@field overflowed boolean Sticky flag; true once queue overflow has dropped an older event.
---@field reason? string Present only with released; one of released, submitted, cancelled, focus_switched, unloaded, crashed, timeout.

--- overlay.released payload; observation only, never intercepted.
---@class BittyOverlayReleasedPayload
---@field owner string Owning plugin id.
---@field reason string Terminal reason: released, submitted, cancelled, focus_switched, unloaded, crashed, or timeout.

--- Focusable overlay and transient input-capture surface (L2, W-01); the single coupled grant
--- ui.overlay.focus covers acquire, update, poll, and release.
---@class BittyUiOverlayNamespace
local BittyUiOverlayNamespace = {}

--- Requests the focusable overlay and the single transient input-capture session in one Core-owned
--- switch; spec carries optional bounded title and placeholder hints with unknown fields ignored.
--- Without ui.overlay.focus fails E_CAPABILITY_DENIED, a second acquire while active fails
--- E_UI_ALREADY_CAPTURED, and safe mode fails E_UI_UNAVAILABLE.
--- Capabilities: ui.overlay.focus.
--- Errors: E_CAPABILITY_DENIED, E_UI_ALREADY_CAPTURED, E_UI_UNAVAILABLE, E_DEF_INVALID.
---@param spec? BittyOverlaySpec
---@return BittyOverlayHandle
function BittyUiOverlayNamespace.acquire(spec) end

--- Replaces the overlay content for a session the caller owns; the scene uses the accepted v1 node
--- set under the v1 scene budgets. An update on a handle the caller does not own, or on a released
--- handle, fails E_UI_NOT_OWNER and keeps the previous content.
--- Capabilities: ui.overlay.focus.
--- Errors: E_CAPABILITY_DENIED, E_UI_NOT_OWNER, E_UI_COMPONENT_INVALID.
---@param handle BittyOverlayHandle
---@param scene BittySceneNode
---@return boolean
function BittyUiOverlayNamespace.update(handle, scene) end

--- Drains the session queue as an owner-initiated synchronous read of already-queued events; never
--- a Core-driven callback and never on the input hot path. Returns status, seq, ordered events,
--- sticky overflowed, and reason only with released.
--- Capabilities: ui.overlay.focus.
--- Errors: E_CAPABILITY_DENIED, E_UI_NOT_OWNER.
---@param handle BittyOverlayHandle
---@return BittyOverlayPollResult
function BittyUiOverlayNamespace.poll(handle) end

--- Ends a session the caller owns; idempotent on an already-released handle within the owning
--- generation. The optional reason is submitted or cancelled and defaults to released; an invalid
--- reason is E_DEF_INVALID and Core-reported reasons overwrite on involuntary terminal causes.
--- Capabilities: ui.overlay.focus.
--- Errors: E_CAPABILITY_DENIED, E_UI_NOT_OWNER, E_DEF_INVALID.
---@param handle BittyOverlayHandle
---@param reason? string
---@return boolean
function BittyUiOverlayNamespace.release(handle, reason) end

--- Terminal snapshot options; only the semantic scope is accepted in v1.
---@class BittySnapshotOpts
---@field scope? "semantic" The only accepted v1 scope.
---@field terminal_id? integer Target terminal; defaults to the focused view's attached terminal and requires terminal.semantic-read.

--- Color value: "default", a palette index 0..255, or an "#RRGGBB" string.
---@alias BittyCellColor "default"|integer|string

--- Non-default cell attributes carried by a snapshot span; false boolean flags are omitted.
---@class BittyCellAttrs
---@field bold? boolean Bold attribute.
---@field faint? boolean Faint attribute.
---@field italic? boolean Italic attribute.
---@field blink? boolean Blink attribute.
---@field inverse? boolean Inverse attribute.
---@field invisible? boolean Invisible attribute.
---@field strikethrough? boolean Strikethrough attribute.
---@field underline? "none"|"single"|"double"|"curly"|"dotted"|"dashed" Underline style.
---@field fg? BittyCellColor Foreground color.
---@field bg? BittyCellColor Background color.
---@field underline_color? BittyCellColor Underline color.

--- Half-open column range [start, end) carrying only non-default attributes.
---@class BittyCellSpan
---@field start integer Inclusive start column.
---@field end integer Exclusive end column.
---@field attrs BittyCellAttrs Non-default attributes for the range.

--- One visible snapshot row with its semantic spans.
---@class BittySnapshotRow
---@field text string Visible row text as UTF-8.
---@field spans BittyCellSpan[] Attribute spans over the row.

--- Cursor position within the snapshot region.
---@class BittySnapshotCursor
---@field row integer Cursor row.
---@field col integer Cursor column.
---@field visible boolean Whether the cursor is visible.

--- Bounded mode flags reflected by the snapshot.
---@class BittySnapshotModes
---@field alternate_screen boolean Whether the alternate screen is active; zones may be absent while true.

--- Semantic zone kinds derived from committed terminal state (OSC 7/133); unknown covers terminals
--- without shell integration.
---@alias BittyZoneKind "prompt"|"input"|"command"|"output"|"unknown"

--- Line range of a semantic zone.
---@class BittyZoneRange
---@field start_line integer First line of the zone.
---@field end_line integer Last line of the zone.

--- Bounded untrusted zone metadata; values are never expanded or executed.
---@class BittyZoneMetadata
---@field cwd? string Zone working directory.
---@field host? string Zone host name.
---@field command? string Command text.
---@field exit_code? integer Command exit status.

--- Semantic zone in a terminal snapshot.
---@class BittySemanticZone
---@field kind BittyZoneKind Zone kind.
---@field range BittyZoneRange Zone line range.
---@field metadata? BittyZoneMetadata Bounded zone metadata.

--- Read-only semantic snapshot of the visible viewport; a serialized snapshot over
--- SNAPSHOT_MAX_BYTES (256 KiB) is rejected with E_SNAPSHOT_TOO_LARGE rather than truncated.
---@class BittyTerminalSnapshot
---@field version integer Snapshot contract version (1).
---@field terminal_id integer Terminal identity.
---@field runtime_id integer Live PTY incarnation identity.
---@field generation integer Registry generation.
---@field snapshot_generation integer Terminal damage generation reflected by the snapshot.
---@field width integer Grid columns in the snapshot region.
---@field height integer Grid rows in the snapshot region.
---@field rows BittySnapshotRow[] Visible rows, top-down.
---@field cursor BittySnapshotCursor Cursor state.
---@field modes BittySnapshotModes Mode flags.
---@field title string Bounded title text.
---@field zones? BittySemanticZone[] Semantic zones; may be absent.

--- Terminal observation plus the capability-gated PTY submit path (L2); submit writes only through
--- the Core paste pipeline and never touches grid, cursor, modes, or scrollback.
---@class BittyTerminalNamespace
local BittyTerminalNamespace = {}

--- Returns a read-only semantic snapshot of the visible viewport; only the semantic scope is
--- accepted in v1 and there is no raw scope, scrollback, or full-grid selection.
--- Capabilities: terminal.semantic-read.
--- Errors: E_CAPABILITY_DENIED, E_SNAPSHOT_TOO_LARGE.
---@param opts BittySnapshotOpts
---@return BittyTerminalSnapshot
function BittyTerminalNamespace.snapshot(opts) end

--- Submits text to the focused panel PTY through the capability-gated paste pipeline as one
--- byte-exact bracketed-paste frame; over-cap, lease, and budget refusals return a denied outcome
--- and emit nothing, and a frame that only buffers reports unavailable without charging the budget.
--- Capabilities: terminal.input.submit.
--- Errors: E_CAPABILITY_DENIED, E_DEF_INVALID.
---@param text string
---@return BittySubmitOutcome
function BittyTerminalNamespace.submit(text) end

--- terminal.submit outcome tag; mirrors TerminalSubmitOutcome at bitty 1df0459e (CTX-0929, W-103
--- S-1b).
---@alias BittySubmitStatus "accepted"|"denied"|"unavailable"

--- terminal.submit denial detail; mirrors SubmitDeny at bitty 1df0459e (CTX-0929, W-103 S-1b) and
--- never carries payload.
---@alias BittySubmitDeny "too-large"|"lease-denied"|"budget-exceeded"

--- terminal.submit unavailability detail; mirrors TerminalSubmitUnavailable at bitty 1df0459e
--- (CTX-0929, W-103 S-1b).
---@alias BittySubmitUnavailableReason "no-focused-view"|"buffered-only"

--- terminal.submit typed outcome; mirrors TerminalSubmitOutcome at bitty 1df0459e (CTX-0929, W-103
--- S-1b): denials emit nothing and leave the budget untouched.
---@class BittySubmitOutcome
---@field status BittySubmitStatus Outcome tag.
---@field bytes? integer Present only with accepted; framed bytes delivered in one PTY write.
---@field deny? BittySubmitDeny Present only with denied.
---@field wanted? integer Present only with denied too-large; content bytes refused.
---@field used? integer Present only with denied budget-exceeded; window bytes already charged.
---@field cap? integer Present only with denied budget-exceeded; per-plugin window cap in bytes.
---@field reason? BittySubmitUnavailableReason Present only with unavailable.

--- Constrained process surface (L2); only the allowlisted external-editor round trip is wired and
--- unconstrained process.spawn stays v1-OUT.
---@class BittyProcessNamespace
---@field editor BittyProcessEditorNamespace Allowlisted external-editor round trip (W-82); requires process.editor.
local BittyProcessNamespace = {}

--- Allowlisted external-editor round trip (L2, W-82); the single grant process.editor covers start
--- and the temp file never leaves Core.
---@class BittyProcessEditorNamespace
local BittyProcessEditorNamespace = {}

--- Runs one allowlisted external-editor round trip (nvim, vim, or vi matched exactly from $VISUAL
--- then $EDITOR with no fallback) on a Core-owned 0600 temp file that is always removed; returns
--- the typed outcome and never the temp path.
--- Capabilities: process.editor.
--- Errors: E_CAPABILITY_DENIED, E_DEF_INVALID.
---@param opts? BittyEditorStartOpts
---@return BittyEditorOutcome
function BittyProcessEditorNamespace.start(opts) end

--- Options for bitty.process.editor.start; every field is optional and unknown fields are ignored.
---@class BittyEditorStartOpts
---@field draft? string Initial draft text handed to the editor; defaults to empty and past the 64 KiB bound the round trip is unavailable with the file removed.
---@field timeout_ms? integer Bounded editor wait in milliseconds; defaults to 120000 and larger requests clamp to 300000.

--- process.editor.start outcome tag; mirrors EditorOutcome at bitty 1df0459e (CTX-0929, W-103 S-1b)
--- minus the hosted-only Signal variant, which has no Lua spelling.
---@alias BittyEditorStatus "edited"|"cancelled"|"denied"|"timeout"|"spawn-failed"|"non-zero"|"unavailable"

--- process.editor.start denial detail; mirrors EditorDeny at bitty 1df0459e (CTX-0929, W-103 S-1b):
--- no-editor when neither $VISUAL nor $EDITOR names an editor, not-allowed off the bare-name
--- allowlist.
---@alias BittyEditorDeny "no-editor"|"not-allowed"

--- process.editor.start unavailability detail; SDK kebab-case projection of the static
--- EditorOutcome::Unavailable reasons at bitty 1df0459e (CTX-0929, W-103 S-1b), never a path or
--- payload.
---@alias BittyEditorUnavailableReason "temp-unavailable"|"read-unavailable"|"too-large"|"invalid-utf8"|"wait-unavailable"

--- process.editor.start typed outcome; mirrors EditorOutcome at bitty 1df0459e (CTX-0929, W-103
--- S-1b): denials land before any temp file or child and failures preserve the previous draft.
---@class BittyEditorOutcome
---@field status BittyEditorStatus Outcome tag.
---@field content? string Present only with edited; bounded UTF-8 text read back from the removed temp file.
---@field deny? BittyEditorDeny Present only with denied.
---@field detail? string Present only with spawn-failed; bounded host detail, never a path.
---@field code? integer Present only with non-zero and only when the exit code is known.
---@field reason? BittyEditorUnavailableReason Present only with unavailable.

--- Host-owned task surface (L1) capped at 64 live tasks per plugin; exceeding the cap fails with
--- E_BUDGET_TASK and never queues silently.
---@class BittyTasksNamespace
local BittyTasksNamespace = {}

--- Spawns a host-owned task wrapping a Lua continuation; handles are generation-owned and all
--- generation N handles fail closed after disposal.
--- Errors: E_BUDGET_TASK.
---@param fn fun(): any
---@return BittyTaskHandle
function BittyTasksNamespace.spawn(fn) end

--- Cancels a task cooperatively at the next host slice; cancellation releases the cap slot and
--- there is no Lua-visible abort hook in v1.
---@param task_id BittyTaskHandle
---@return boolean
function BittyTasksNamespace.cancel(task_id) end

--- Host-owned one-shot timer surface (L1) capped at 32 live timers per plugin; exceeding the cap
--- fails with E_BUDGET_TIMER.
---@class BittyTimersNamespace
local BittyTimersNamespace = {}

--- Creates a generation-owned one-shot timer; repeating timers are a 1.x minor addition.
--- Errors: E_BUDGET_TIMER.
---@param delay_ms integer
---@param callback fun(): any
---@return BittyTimerHandle
function BittyTimersNamespace.create(delay_ms, callback) end

--- Cancels a timer and releases the cap slot; handles from a disposed generation fail closed.
---@param timer_id BittyTimerHandle
---@return boolean
function BittyTimersNamespace.cancel(timer_id) end

--- bitty.debug.inspect target; panels is reserved and fails closed with E_NOT_IMPLEMENTED, and any
--- other string is E_DEF_INVALID.
---@alias BittyDebugInspectTarget "plugins"|"commands"|"events"|"grants"|"panels"

--- Stable lowercase lifecycle label; failed never carries the failure message.
---@alias BittyDebugPluginState "unloaded"|"loading"|"activating"|"active"|"suspended"|"disposing"|"disposed"|"failed"

--- One plugins inspect row, sorted by id.
---@class BittyDebugPluginRow
---@field id string Owner-qualified plugin id.
---@field version string Manifest version.
---@field state BittyDebugPluginState Lifecycle label.
---@field generation integer Activation generation (0 before the first activation).

--- One commands inspect row, sorted by plugin, id, title.
---@class BittyDebugCommandRow
---@field plugin string Owning plugin id.
---@field id string Command id as registered (unqualified).
---@field title string Bounded command title.

--- One events inspect row (an event subscription), sorted by plugin, kind.
---@class BittyDebugEventRow
---@field plugin string Owning plugin id.
---@field kind string Subscribed event kind.

--- bitty.debug.inspect result; never includes settings values, store contents, secrets, or terminal
--- content.
---@class BittyDebugInspectResult
---@field target BittyDebugInspectTarget Echoed inspect target.
---@field items BittyDebugPluginRow[]|BittyDebugCommandRow[]|BittyDebugEventRow[]|string[] Rows for the target, capped at 1024 items; grants yields the caller's own sorted capability ids only.
---@field truncated boolean Whether rows were cut at the item cap.

--- Positive monotonic trace handle returned by bitty.debug.trace; never reused, dropped with the
--- owning generation.
---@alias BittyDebugTraceHandle integer

--- bitty.debug.trace options; unknown keys, wrong types, and out-of-range values are E_DEF_INVALID.
---@class BittyDebugTraceOpts
---@field enabled? boolean true (default) opens a new trace; false closes the trace named by handle.
---@field filter? string Exact topic, or a prefix when the pattern ends with a single *; 1..128 printable ASCII bytes; rejected with enabled = false.
---@field max_events? integer Drop-oldest ring size, 1..10000 (default 1000); rejected with enabled = false.
---@field handle? BittyDebugTraceHandle Required with enabled = false and rejected otherwise.

--- One recorded event, redacted for the trace owner's own grants.
---@class BittyDebugTraceRecord
---@field topic string Event kind.
---@field sequence integer Runtime event sequence.
---@field timestamp integer Milliseconds on a monotonic host clock (no wall clock).
---@field payload table Event payload, replaced by { truncated = true, bytes = <n> } when its encoded size exceeds 4096 bytes.

--- Drained trace buffer returned by bitty.debug.trace_get; draining empties the buffer.
---@class BittyDebugTraceDrain
---@field records BittyDebugTraceRecord[] Records in arrival order.
---@field dropped integer Records lost to drop-oldest since the previous drain; resets after being reported.

--- Devtools inspection surface; each entry point needs its own grant (debug.inspect, debug.trace,
--- debug.control) with no implication between them. Host-implemented spellings; not part of the ADR
--- 0009 v1 guarantee.
---@class BittyDebugNamespace
local BittyDebugNamespace = {}

--- Read-only runtime inspection returning { target, items, truncated }; a non-string target is
--- E_DEF_INVALID before the grant check, the reserved panels target fails closed with
--- E_NOT_IMPLEMENTED, and other plugins' grants are never exposed.
--- Capabilities: debug.inspect.
--- Errors: E_DEF_INVALID, E_CAPABILITY_DENIED.
---@param target BittyDebugInspectTarget
---@return BittyDebugInspectResult
function BittyDebugNamespace.inspect(target) end

--- Opens (nil or enabled = true) or closes (enabled = false with handle) an event trace; a trace
--- records only event kinds the plugin declares in [lazy].events, intersected with filter, at most
--- 4 traces per plugin (E_DEF_LIMIT), and closing an unknown or foreign handle is E_DEF_INVALID.
--- Capabilities: debug.trace.
--- Errors: E_DEF_INVALID, E_DEF_LIMIT, E_CAPABILITY_DENIED.
---@param opts? BittyDebugTraceOpts
---@return BittyDebugTraceHandle
function BittyDebugNamespace.trace(opts) end

--- Drains a trace owned by this plugin; a non-integer handle is E_DEF_INVALID, and an unknown or
--- foreign handle returns nil so other plugins' traces cannot be probed.
--- Capabilities: debug.trace.
--- Errors: E_DEF_INVALID, E_CAPABILITY_DENIED.
---@param handle BittyDebugTraceHandle
---@return BittyDebugTraceDrain|nil
function BittyDebugNamespace.trace_get(handle) end

--- High-risk lifecycle control (reload_plugin, suspend_plugin, resume_plugin, clear_state by plugin
--- id); non-string arguments are E_DEF_INVALID, and the host fails closed before reading the grant
--- or the target.
--- Capabilities: debug.control.
--- Host status: deferred - always fails with E_NOT_IMPLEMENTED (runtime) until the host backend lands.
--- Errors: E_NOT_IMPLEMENTED.
---@param action string
---@param target string
---@return any
function BittyDebugNamespace.control(action, target) end

--- Positive stable workspace id (Core creation sequence); survives index shifts and is never reused
--- for another workspace.
---@alias BittyWorkspaceId integer

--- Attention flags of one workspace; the host reports every flag false until Core grows a
--- per-workspace attention source.
---@class BittyWorkspaceAttention
---@field bell boolean A bell rang since the workspace was last focused.
---@field activity boolean Output arrived while the workspace was inactive.
---@field exited boolean A panel process in the workspace exited.

--- One bitty.workspace.list row: identity, order, and structure only, never terminal content.
---@class BittyWorkspaceInfo
---@field id BittyWorkspaceId Stable workspace id.
---@field name string Display name, truncated to 32 characters.
---@field active boolean Whether this is the active workspace.
---@field panel_count integer Number of panels (layout leaves).
---@field attention BittyWorkspaceAttention Attention flags.

--- Positional bitty.workspace.focus target.
---@class BittyWorkspaceIndexTarget
---@field index integer 1-based position, clamped to the last workspace like the Alt+N binding.

--- Workspace domain (L1, ADR 0014): list is gated on workspace.read; every mutation is gated on
--- workspace.control only (read never implies control), enqueues into a bounded host queue (32
--- requests per tick), and returns whether it was queued, not applied. Spellings are host
--- candidates pending OQ-056.
---@class BittyWorkspaceNamespace
local BittyWorkspaceNamespace = {}

--- Lists workspaces in order, at most 16 rows (the Core MAX_WORKSPACES bound); names are truncated
--- to 32 characters and rows never carry terminal content.
--- Capabilities: workspace.read.
--- Errors: E_CAPABILITY_DENIED.
---@return BittyWorkspaceInfo[]
function BittyWorkspaceNamespace.list() end

--- Queues focusing a workspace by positive stable id or by { index = n } (1-based); an id that no
--- longer exists at apply time is dropped fail-closed.
--- Capabilities: workspace.control.
--- Errors: E_DEF_INVALID, E_CAPABILITY_DENIED.
---@param target BittyWorkspaceId|BittyWorkspaceIndexTarget
---@return boolean
function BittyWorkspaceNamespace.focus(target) end

--- Queues creating a workspace and switching to it, subject to the Core capacity bound.
--- Capabilities: workspace.control.
--- Errors: E_CAPABILITY_DENIED.
---@return boolean
function BittyWorkspaceNamespace.new() end

--- Queues switching to the next workspace (wraps).
--- Capabilities: workspace.control.
--- Errors: E_CAPABILITY_DENIED.
---@return boolean
function BittyWorkspaceNamespace.next() end

--- Queues closing a workspace (nil closes the active one) through the kill-confirm gate: idle
--- workspaces close immediately and live ones arm the user confirmation.
--- Capabilities: workspace.control.
--- Errors: E_DEF_INVALID, E_CAPABILITY_DENIED.
---@param id? BittyWorkspaceId
---@return boolean
function BittyWorkspaceNamespace.close(id) end

--- Queues renaming a workspace; name must be a non-blank UTF-8 string without control characters
--- and at most 256 bytes (E_DEF_LIMIT), and Core truncates accepted names to 32 characters.
--- Capabilities: workspace.control.
--- Errors: E_DEF_INVALID, E_DEF_LIMIT, E_CAPABILITY_DENIED.
---@param id BittyWorkspaceId
---@param name string
---@return boolean
function BittyWorkspaceNamespace.rename(id, name) end

--- Queues moving the focused panel of the active workspace into the workspace with this stable id.
--- Capabilities: workspace.control.
--- Errors: E_DEF_INVALID, E_CAPABILITY_DENIED.
---@param id BittyWorkspaceId
---@return boolean
function BittyWorkspaceNamespace.move_panel(id) end

--- Host-injected read-only module table; it is not loaded through require.
---@class bitty
---@field api_version string Host bridge API version (1.0.0); minor versions are additive only.
---@field commands BittyCommandsNamespace
---@field events BittyEventsNamespace
---@field keymaps BittyKeymapsNamespace
---@field settings BittySettingsNamespace
---@field store BittyStoreNamespace
---@field notify BittyNotifyNamespace
---@field env? BittyEnvNamespace
---@field services BittyServicesNamespace
---@field ui BittyUiNamespace
---@field terminal BittyTerminalNamespace
---@field process BittyProcessNamespace
---@field tasks BittyTasksNamespace
---@field timers BittyTimersNamespace
---@field debug BittyDebugNamespace
---@field workspace BittyWorkspaceNamespace
bitty = {}
