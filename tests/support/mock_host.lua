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
-- The real `bitty` Lua bridge does not expose `bitty.process` yet; the
-- plugin degrades to snapshot-and-cache mode until it lands (see the package
-- README "Known gaps"). The stub exposes it so the allowlist wiring is
-- proven before the host surface ships.

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
      spawn = function(args)
        self:assert_capability("bitty.process.spawn", "process.spawn:git")
        if not allowlist.is_allowed_args(args) then
          fail("runtime", "E_SPAWN_DENIED", "git invocation is outside the [tools.git] allowlist")
        end
        self.spawn_calls[#self.spawn_calls + 1] = args
        local key = table.concat(args, "\0")
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
