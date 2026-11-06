-- Minimal in-process `bitty` host stub for the git-panel behavior tests.
--
-- This is a test double, not a host implementation: it models only the
-- accepted surface the git-panel uses — Plugin API v1 commands/events/
-- settings/terminal-snapshot plus the Layer 2 `[tools.git]` spawn surface
-- (`process.spawn:git` against the seven allowlisted read-only verbs with
-- bounded output) — with fail-closed capability gates, manifest-declared
-- command/event validation, and the v1 declarative scene validation
-- (`Text`, `Row`, `Column`, `List` only, depth `16`). It performs no I/O,
-- spawns nothing, and never touches the network or the filesystem.
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

local allowlist = require("git-panel.allowlist")

local MockHost = {}
MockHost.__index = MockHost

local function fail(class, code, message)
  error({ class = class, code = code, message = message }, 0)
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

function MockHost:run(command_id, args)
  local qualified = self.plugin_id .. ":" .. command_id
  local def = self.commands[qualified]
  if def == nil then
    fail("validation", "E_COMMAND_UNDECLARED", "command is not registered: " .. qualified)
  end
  return def.run(args or {})
end

return MockHost
