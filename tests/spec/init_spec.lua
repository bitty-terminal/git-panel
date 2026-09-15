-- Entry-point behavior tests for `git-panel.init` against the mock host.

local MockHost = require("support.mock_host")

local PLUGIN_ID = "bitty-terminal.git-panel"

local COMMANDS = {
  PLUGIN_ID .. ":open",
  PLUGIN_ID .. ":status",
  PLUGIN_ID .. ":diff",
  PLUGIN_ID .. ":log",
  PLUGIN_ID .. ":branch",
}

local EVENTS = {
  "terminal.cwd-changed",
  "terminal.title-changed",
  "focus.changed",
}

local GRANTS = {
  "panel.provider",
  "panel.create",
  "terminal.semantic-read",
  "process.spawn:git",
}

local function activate(host)
  _G.bitty = host.bitty
  package.loaded["git-panel.init"] = nil
  package.loaded["git-panel.allowlist"] = nil
  package.loaded["git-panel.scope"] = nil
  package.loaded["git-panel.listing"] = nil
  package.loaded["git-panel.scene"] = nil
  return require("git-panel.init")
end

local function full_host(overrides)
  overrides = overrides or {}
  overrides.grants = overrides.grants or GRANTS
  overrides.commands = overrides.commands or COMMANDS
  overrides.events = overrides.events or EVENTS
  overrides.snapshot = overrides.snapshot
    or { title = "git-panel", zones = { { metadata = { cwd = "~/projects/foo" } } } }
  return MockHost.new(overrides)
end

local function run(context)
  local tap = context.tap

  -- Activation registers the five manifest commands and the three declared
  -- observation events.
  do
    local host = full_host()
    activate(host)
    for _, qualified in ipairs(COMMANDS) do
      tap.ok(host.commands[qualified] ~= nil, "registered " .. qualified)
    end
    tap.equal(#host.subscriptions, 3, "three subscriptions")
    for _, kind in ipairs(EVENTS) do
      local found = false
      for _, subscription in ipairs(host.subscriptions) do
        if subscription.kind == kind then
          found = true
        end
      end
      tap.ok(found, "subscribed " .. kind)
    end
  end

  -- Undeclared event fails closed at activation.
  do
    local host = full_host({ events = {} })
    local ok, err = pcall(activate, host)
    tap.ok(not ok, "undeclared event fails activation")
    tap.equal(type(err) == "table" and err.code or nil, "E_EVENT_UNDECLARED", "undeclared event code")
  end

  -- The status command serves bounded, scope-checked entries from the
  -- allowlisted spawn output.
  do
    local host = full_host({
      spawn_outputs = {
        ["status\0--porcelain"] = " M ~/projects/foo.txt\nA  ~/projects/bar.rs\n?? ~/projects/new.txt\n",
      },
    })
    activate(host)
    local entries = host:run("status", {})
    tap.equal(#entries, 3, "three in-scope entries")
    tap.equal(entries[1].path, "~/projects/bar.rs", "entries sorted")
    tap.equal(#host.spawn_calls, 1, "one spawn issued")
    tap.equal(host.spawn_calls[1][1], "status", "spawned verb is status")
  end

  -- Out-of-scope spawn output never reaches the panel (fail-closed filter).
  do
    local host = full_host({
      spawn_outputs = {
        ["status\0--porcelain"] = " M ~/projects/ok.txt\n M /etc/passwd\n",
      },
    })
    activate(host)
    local entries = host:run("status", {})
    tap.equal(#entries, 1, "outside-scope line dropped")
    tap.equal(entries[1].path, "~/projects/ok.txt", "in-scope line kept")
  end

  -- Denied snapshot capability fails closed instead of serving empty data.
  do
    local host = full_host({ grants = { "panel.provider", "panel.create", "process.spawn:git" } })
    activate(host)
    local ok, err = pcall(function()
      return host:run("status", {})
    end)
    tap.ok(not ok, "denied snapshot fails the command")
    tap.equal(type(err) == "table" and err.code or nil, "E_CAPABILITY_DENIED", "denied capability code")
  end

  -- Missing host spawn surface fails closed with a diagnostic (the real
  -- bridge does not expose bitty.process yet; see README Known gaps).
  do
    local host = full_host()
    host.bitty.process = nil
    activate(host)
    tap.ok(host.commands[PLUGIN_ID .. ":status"] ~= nil, "commands still register")
    local ok, err = pcall(function()
      return host:run("status", {})
    end)
    tap.ok(not ok, "missing spawn surface fails the command")
    tap.equal(type(err) == "table" and err.code or nil, "E_SPAWN_UNAVAILABLE", "unavailable spawn code")
  end

  -- Denied spawn grant fails closed at the host gate.
  do
    local host = full_host({ grants = { "panel.provider", "panel.create", "terminal.semantic-read" } })
    activate(host)
    local ok, err = pcall(function()
      return host:run("status", {})
    end)
    tap.ok(not ok, "denied spawn grant fails the command")
    tap.equal(type(err) == "table" and err.code or nil, "E_CAPABILITY_DENIED", "denied spawn code")
  end

  -- The log command serves bounded commits from allowlisted output.
  do
    local host = full_host({
      spawn_outputs = {
        ["log\0--oneline\0-n\0" .. "10"] = "abc1234 fix bug\ndef5678 add feature\n",
      },
    })
    activate(host)
    local commits = host:run("log", {})
    tap.equal(#commits, 2, "two commits served")
    tap.equal(commits[1].short_hash, "abc1234", "short hash derived")
  end

  -- The branch command serves sorted branches with current tracking.
  do
    local host = full_host({
      spawn_outputs = {
        ["branch\0-a"] = "* main\n  feature/foo\n",
      },
    })
    activate(host)
    local branches = host:run("branch", {})
    tap.equal(#branches, 2, "two branches served")
    tap.equal(branches[2].name, "main", "main sorted second")
    tap.ok(branches[2].is_current, "current tracked")
  end

  -- Observation events refresh the cached cwd without spawning.
  do
    local host = full_host()
    local plugin = activate(host)
    tap.equal(#host.spawn_calls, 0, "activation spawns nothing")
    host.snapshot_value = { title = "moved", zones = { { metadata = { cwd = "~/projects/other" } } } }
    host:publish("terminal.cwd-changed", {})
    tap.equal(plugin.cached_cwd(), "~/projects/other", "cwd cache refreshed")
    tap.equal(#host.spawn_calls, 0, "event handler spawns nothing")
  end
end

return { run = run }
