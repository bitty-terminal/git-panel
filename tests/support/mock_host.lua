-- Minimal in-process `bitty` host stub for the git-panel behavior tests.
--
-- This is a test double, not a host implementation: it models only the
-- accepted surface the git-panel uses — Plugin API v1 commands/events/
-- settings/terminal-snapshot plus the Layer 2 `[tools.git]` spawn surface
-- (`process.spawn:git` against the seven allowlisted read-only verbs with
-- bounded output) and the W-01 focusable overlay session
-- (`bitty.ui.overlay.acquire/update/poll/release` under `ui.overlay.focus`)
-- — with fail-closed capability gates, manifest-declared command/event
-- validation, and the v1 declarative scene validation (`Text`, `Row`,
-- `Column`, `List` only, depth `16`). It performs no I/O, spawns nothing, and
-- never touches the network or the filesystem.
--
-- The real `bitty` Lua bridge exposes `bitty.process.spawn` as a
-- consent-gated extra outside the stable Plugin API v1 guarantee. It accepts
-- argv plus one option: the bridge accepts exactly `cwd = "pane"` and the
-- host resolves the globally focused view's directory itself (CTX-1715). Any
-- other `cwd` value fails with the host's exact diagnostic, so the stub
-- mirrors the real rejection and the repository gate catches the class
-- instead of a real host. `pane_cwd_available = false` models a focused view
-- without a terminal session, which the host refuses with
-- `E_SPAWN_CWD_UNAVAILABLE`.
--
-- The overlay stub mirrors the accepted W-01 single-capture invariant: one
-- session at a time (`E_UI_ALREADY_CAPTURED`), only the owning handle may be
-- updated (`E_UI_NOT_OWNER`), release is ungated and idempotent, and ending
-- the session publishes the observation-only `overlay.released` event.

local allowlist = require("git-panel.allowlist")

local MockHost = {}
MockHost.__index = MockHost

local V1_KINDS = {
  Text = true,
  Row = true,
  Column = true,
  List = true,
}

local MAX_SCENE_DEPTH = 16
local MAX_SCENE_NODES = 2048
local MAX_SCENE_TEXT_BYTES = 256 * 1024

local function fail(class, code, message)
  error({ class = class, code = code, message = message }, 0)
end

-- Validate one v1 declarative scene and count its nodes/text bytes. The
-- bridge rejects unknown kinds, excessive depth, and the accepted node/text
-- caps before the host sees the component.
local function validate_scene(node, depth, budget)
  if type(node) ~= "table" then
    fail("validation", "E_UI_COMPONENT_INVALID", "scene node must be a table")
  end
  if depth > MAX_SCENE_DEPTH then
    fail("validation", "E_UI_COMPONENT_INVALID", "scene exceeds the depth bound")
  end
  if V1_KINDS[node.kind] ~= true then
    fail("validation", "E_UI_COMPONENT_INVALID", "scene kind is not a v1 node")
  end
  budget.nodes = budget.nodes + 1
  if budget.nodes > MAX_SCENE_NODES then
    fail("validation", "E_UI_COMPONENT_INVALID", "scene exceeds the node bound")
  end
  if node.kind == "Text" then
    if type(node.text) ~= "string" then
      fail("validation", "E_UI_COMPONENT_INVALID", "Text node requires a string text field")
    end
    budget.bytes = budget.bytes + #node.text
    if budget.bytes > MAX_SCENE_TEXT_BYTES then
      fail("validation", "E_UI_COMPONENT_INVALID", "scene exceeds the text bound")
    end
    return
  end
  if type(node.children) ~= "table" then
    fail("validation", "E_UI_COMPONENT_INVALID", node.kind .. " node requires children")
  end
  for _, child in ipairs(node.children) do
    validate_scene(child, depth + 1, budget)
  end
end

local function checked_scene(node)
  validate_scene(node, 0, { nodes = 0, bytes = 0 })
  return node
end

function MockHost.new(options)
  options = options or {}
  local self = setmetatable({}, MockHost)
  self.plugin_id = options.plugin_id or "bitty-terminal.git-panel"
  self.grants = {}
  for _, name in ipairs(options.grants or {}) do
    self.grants[name] = true
  end
  self.declared_commands = {}
  for _, name in ipairs(options.commands or {}) do
    self.declared_commands[name] = true
  end
  self.declared_events = {}
  for _, name in ipairs(options.events or {}) do
    self.declared_events[name] = true
  end
  self.settings = options.settings or {}
  self.snapshot_value = options.snapshot
  self.spawn_outputs = options.spawn_outputs or {}
  self.spawn_calls = {}
  self.spawn_dirs = {}
  -- Whether the focused view has a terminal session for `cwd = "pane"`.
  self.pane_cwd_available = options.pane_cwd_available ~= false
  self.commands = {}
  self.subscriptions = {}
  self.handle_counter = 0
  self.sequence = 1
  -- W-01 focusable overlay session state.
  self.overlay = {
    active = nil,
    scene = nil,
    spec = nil,
    acquires = 0,
    updates = 0,
    releases = 0,
    visible = false,
  }
  self.next_overlay_handle = 1000
  self.bitty = self:build_bitty()
  return self
end

function MockHost:grant(name)
  self.grants[name] = true
end

function MockHost:next_handle()
  self.handle_counter = self.handle_counter + 1
  return self.handle_counter
end

function MockHost:assert_capability(surface, capability)
  if not self.grants[capability] then
    fail("runtime", "E_CAPABILITY_DENIED", surface .. " requires capability " .. capability)
  end
end

function MockHost:build_bitty()
  local self = self
  return {
    api_version = "1.0.0",
    commands = {
      register = function(def)
        if type(def) ~= "table" or type(def.id) ~= "string" then
          fail("validation", "E_DEF_INVALID", "command definition is invalid")
        end
        if def.title == nil or def.title == "" or type(def.run) ~= "function" then
          fail("validation", "E_DEF_INVALID", "command requires title and run")
        end
        local qualified = self.plugin_id .. ":" .. def.id
        if not self.declared_commands[qualified] then
          fail("validation", "E_COMMAND_UNDECLARED", "command is not reserved in the manifest: " .. qualified)
        end
        if self.commands[qualified] ~= nil then
          fail("validation", "E_COMMAND_DUPLICATE", "duplicate command: " .. qualified)
        end
        self.commands[qualified] = def
        return self:next_handle()
      end,
    },
    events = {
      subscribe = function(name, handler)
        if type(name) ~= "string" or type(handler) ~= "function" then
          fail("validation", "E_DEF_INVALID", "event subscription is invalid")
        end
        if not self.declared_events[name] then
          fail("validation", "E_EVENT_UNDECLARED", "event is not declared in the manifest: " .. name)
        end
        self.subscriptions[#self.subscriptions + 1] = { kind = name, handler = handler }
        return self:next_handle()
      end,
    },
    settings = {
      get = function(key)
        if type(key) ~= "string" then
          fail("validation", "E_SETTINGS_KEY_INVALID", "settings key must be a string")
        end
        return self.settings[key]
      end,
    },
    terminal = {
      snapshot = function(_opts)
        self:assert_capability("bitty.terminal.snapshot", "terminal.semantic-read")
        if type(self.snapshot_value) ~= "table" then
          fail("runtime", "E_SNAPSHOT_UNAVAILABLE", "no semantic snapshot staged")
        end
        return self.snapshot_value
      end,
    },
    ui = {
      overlay = {
        acquire = function(spec)
          self:assert_capability("bitty.ui.overlay.acquire", "ui.overlay.focus")
          if spec ~= nil and type(spec) ~= "table" then
            fail("validation", "E_DEF_INVALID", "ui.overlay.acquire spec must be a table")
          end
          if self.overlay.active ~= nil then
            fail(
              "runtime",
              "E_UI_ALREADY_CAPTURED",
              "another overlay capture session is already active"
            )
          end
          self.next_overlay_handle = self.next_overlay_handle + 1
          local handle = self.next_overlay_handle
          local children = {}
          if type(spec) == "table" then
            if type(spec.title) == "string" and spec.title ~= "" then
              children[#children + 1] = { kind = "Text", text = spec.title }
            end
            if type(spec.placeholder) == "string" and spec.placeholder ~= "" then
              children[#children + 1] = { kind = "Text", text = spec.placeholder }
            end
          end
          if #children == 0 then
            children[1] = { kind = "Text", text = "" }
          end
          self.overlay.active = handle
          self.overlay.scene = checked_scene({ kind = "Column", children = children })
          self.overlay.spec = spec
          self.overlay.visible = true
          self.overlay.acquires = self.overlay.acquires + 1
          return handle
        end,
        update = function(handle, component)
          self:assert_capability("bitty.ui.overlay.update", "ui.overlay.focus")
          if type(handle) ~= "number" or handle ~= self.overlay.active then
            fail(
              "runtime",
              "E_UI_NOT_OWNER",
              "no focusable-overlay input capture is held for this handle"
            )
          end
          self.overlay.scene = checked_scene(component)
          self.overlay.updates = self.overlay.updates + 1
          return true
        end,
        poll = function(handle)
          self:assert_capability("bitty.ui.overlay.poll", "ui.overlay.focus")
          if type(handle) ~= "number" or handle ~= self.overlay.active then
            fail("runtime", "E_UI_NOT_OWNER", "no capture session for this handle")
          end
          return { status = "captured", seq = 0, events = {}, overflowed = false }
        end,
        release = function(handle, reason)
          if type(handle) ~= "number" or handle ~= self.overlay.active then
            return false
          end
          self.overlay.active = nil
          self.overlay.visible = false
          self.overlay.releases = self.overlay.releases + 1
          self:publish("overlay.released", {
            owner = self.plugin_id,
            reason = reason or "released",
          })
          return true
        end,
      },
    },
    process = {
-- In-memory adapter for the accepted `[tools.git]` argv contract and the
-- host-resolved pane cwd (CTX-1715). Exactly like Core, the only accepted
-- option is `cwd = "pane"`; any other value fails with the host's
-- `E_DEF_INVALID` diagnostic, so a regression that reintroduces a
-- plugin-supplied path is caught by the repo gate rather than only on a real
-- host. Staged output is keyed by the git args alone
-- (`spawn_outputs["status\0--porcelain"]`).
      spawn = function(args, opts)
        self:assert_capability("bitty.process.spawn", "process.spawn:git")
        if opts ~= nil and type(opts) ~= "table" then
          fail("validation", "E_DEF_INVALID", "process.spawn options must be a table")
        end
        local pane_cwd = false
        if type(opts) == "table" then
          for key, value in pairs(opts) do
            if key ~= "cwd" then
              fail(
                "validation",
                "E_DEF_INVALID",
                "process.spawn does not support option '" .. tostring(key) .. "'"
              )
            end
            if value ~= "pane" then
              fail(
                "validation",
                "E_DEF_INVALID",
                "process.spawn cwd must be the literal string 'pane'"
              )
            end
            pane_cwd = true
          end
        end
        if type(args) ~= "table" or #args == 0 then
          fail("runtime", "E_SPAWN_FAILED", "test double requires a non-empty argv")
        end
        if not pane_cwd then
          fail(
            "runtime",
            "E_SPAWN_CWD_UNAVAILABLE",
            "test double requires cwd = 'pane': the host resolves the focused view's directory"
          )
        end
        if self.pane_cwd_available == false then
          fail("runtime", "E_SPAWN_CWD_UNAVAILABLE", "the focused view has no terminal session")
        end
        local git_args = args
        if not allowlist.is_allowed_args(git_args) then
          fail("runtime", "E_SPAWN_DENIED", "git invocation is outside the [tools.git] allowlist")
        end
        self.spawn_calls[#self.spawn_calls + 1] = args
        self.spawn_dirs[#self.spawn_dirs + 1] = "pane"
        local key = table.concat(git_args, "\0")
        local output = self.spawn_outputs[key]
        if output == nil then
          output = ""
        end
        if #output > 8192 then
          output = string.sub(output, 1, 8192)
        end
        return { status = 0, output = output }
      end,
    },
  }
end

function MockHost:publish(kind, payload)
  local delivered = 0
  for _, subscription in ipairs(self.subscriptions) do
    if subscription.kind == kind then
      delivered = delivered + 1
      subscription.handler({
        kind = kind,
        sequence = self.sequence,
        payload = payload or {},
      })
      self.sequence = self.sequence + 1
    end
  end
  return delivered
end

-- Simulate a Core-owned session end (Esc, focus switch, idle timeout) and
-- deliver the observation-only `overlay.released` event.
function MockHost:dismiss_overlay(reason)
  if self.overlay.active == nil then
    return false
  end
  self.overlay.active = nil
  self.overlay.visible = false
  self:publish("overlay.released", {
    owner = self.plugin_id,
    reason = reason or "cancelled",
  })
  return true
end

function MockHost:run(command_id, args)
  local qualified = self.plugin_id .. ":" .. command_id
  local def = self.commands[qualified]
  if def == nil then
    fail("validation", "E_COMMAND_UNDECLARED", "command is not registered: " .. qualified)
  end
  return def.run(args or {})
end

return MockHost
