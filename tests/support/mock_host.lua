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
-- argv only: a plugin-supplied `cwd` option fails with `E_DEF_INVALID`
-- (CTX-1345), and the stub mirrors that rejection so the repository gate
-- catches the class instead of a real host. The pane directory therefore
-- travels on argv as the leading `git -C <dir>` pair, with a validated
-- absolute operand passed as a distinct element.
--
-- `-C` is itself a repository-escape vector in Core's current `[tools.git]`
-- allowlist, so the stub rejects it by default. Success fixtures opt into
-- `git_dir_policy = "confined"`, which models the pending host seam (a
-- confined pane directory); a test that forgets the opt-in fails instead of
-- assuming a host behavior that does not exist.

local allowlist = require("git-panel.allowlist")
local scope = require("git-panel.scope")

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
  -- `denied` mirrors Core's current `[tools.git]` policy (`-C` is a
  -- repository-escape vector); `confined` models the pending host seam.
  self.git_dir_policy = options.git_dir_policy or "denied"
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
-- In-memory adapter for the accepted `[tools.git]` argv contract. The bridge
-- accepts argv only: exactly like Core (CTX-1345), an options table carrying
-- `cwd` fails with the host's `E_DEF_INVALID` diagnostic, so a regression
-- that reintroduces the unsupported option is caught by the repo gate rather
-- than only on a real host. The pane directory must travel as the leading
-- `git -C <dir>` pair, with `<dir>` a validated absolute path passed as a
-- distinct argv element; staged output is keyed by the git args alone
-- (`spawn_outputs["status\0--porcelain"]`).
      spawn = function(args, opts)
        self:assert_capability("bitty.process.spawn", "process.spawn:git")
        if opts ~= nil and type(opts) ~= "table" then
          fail("validation", "E_DEF_INVALID", "process.spawn options must be a table")
        end
        if type(opts) == "table" then
          for key in pairs(opts) do
            if key == "cwd" then
              fail(
                "validation",
                "E_DEF_INVALID",
                "process.spawn cwd is not supported: a plugin-controlled working directory cannot be confined to the plugin filesystem grant"
              )
            end
            fail(
              "validation",
              "E_DEF_INVALID",
              "process.spawn does not support option '" .. tostring(key) .. "'"
            )
          end
        end
        if type(args) ~= "table" or args[1] ~= "-C" or not scope.is_absolute_dir(args[2]) then
          fail(
            "runtime",
            "E_SPAWN_FAILED",
            "test double requires the pane directory as -C <absolute dir>"
          )
        end
        local dir = args[2]
        local git_args = {}
        for index = 3, #args do
          git_args[#git_args + 1] = args[index]
        end
        if self.git_dir_policy ~= "confined" then
          -- Core parity: `-C` / `-C<path>` is denied for every verb
          -- (`is_allowed_git_args`, CTX-0465) and no host-derived cwd exists
          -- yet, so the pane directory cannot be selected at all.
          fail("runtime", "E_SPAWN_DENIED", "git invocation is outside the [tools.git] allowlist")
        end
        if not allowlist.is_allowed_args(git_args) then
          fail("runtime", "E_SPAWN_DENIED", "git invocation is outside the [tools.git] allowlist")
        end
        self.spawn_calls[#self.spawn_calls + 1] = args
        self.spawn_dirs[#self.spawn_dirs + 1] = dir
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
