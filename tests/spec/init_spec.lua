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

  -- H-GP-01: real porcelain vectors are repo-root-relative and resolve
  -- against the cached cwd, including renames.
  do
    local host = full_host({
      spawn_outputs = {
        ["status\0--porcelain"] = " M src/lib.rs\n?? README.md\nR  old.lua -> new.lua\n",
      },
    })
    activate(host)
    local entries = host:run("status", {})
    tap.equal(#entries, 3, "real porcelain all kept")
    tap.equal(entries[1].path, "~/projects/foo/README.md", "relative resolved and sorted first")
    tap.equal(entries[2].path, "~/projects/foo/new.lua", "rename tracks post-image")
    tap.equal(entries[2].status, "renamed", "rename status carried")
    tap.equal(entries[3].path, "~/projects/foo/src/lib.rs", "relative resolved")
  end

  -- H-GP-01: repositories rooted anywhere resolve; traversal still drops.
  do
    local host = full_host({
      snapshot = { title = "git-panel", zones = { { metadata = { cwd = "/srv/git/repo" } } } },
      spawn_outputs = {
        ["status\0--porcelain"] = " M src/lib.rs\n M ../evil.txt\n M /etc/passwd\n",
      },
    })
    activate(host)
    local entries = host:run("status", {})
    tap.equal(#entries, 1, "arbitrary root keeps only in-root line")
    tap.equal(entries[1].path, "/srv/git/repo/src/lib.rs", "arbitrary root joined")
  end

  -- R18: quote-wrapped paths unwrap (spaces, renames with spaces).
  do
    local host = full_host({
      spawn_outputs = {
        ["status\0--porcelain"] = ' M "my file.txt"\nR  "old name.lua" -> "new name.lua"\n',
      },
    })
    activate(host)
    local entries = host:run("status", {})
    tap.equal(#entries, 2, "quoted lines kept")
    tap.equal(entries[1].path, "~/projects/foo/my file.txt", "quoted spaces unwrapped")
    tap.equal(entries[2].path, "~/projects/foo/new name.lua", "quoted rename post-image")
  end

  -- R18: XY two-column semantics (unmerged pairs report conflicted).
  do
    local host = full_host()
    local plugin = activate(host)
    local parsed = plugin.parse_porcelain("UU clash.txt\nAA both.txt\nDD gone.txt\n M work.txt\nA  staged.txt\n")
    local by_path = {}
    for _, item in ipairs(parsed) do
      by_path[item.path] = item.status
    end
    tap.equal(by_path["clash.txt"], "conflicted", "UU conflicted")
    tap.equal(by_path["both.txt"], "conflicted", "AA conflicted")
    tap.equal(by_path["gone.txt"], "conflicted", "DD conflicted")
    tap.equal(by_path["work.txt"], "modified", "worktree column read")
    tap.equal(by_path["staged.txt"], "added", "staged column read")
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
  -- R19: reverse-chronological input order is preserved (input is
  -- deliberately not hash-sorted here).
  do
    local host = full_host({
      spawn_outputs = {
        ["log\0--oneline\0-n\0" .. "10"] = "def5678 add feature\nabc1234 fix bug\n",
      },
    })
    activate(host)
    local commits = host:run("log", {})
    tap.equal(#commits, 2, "two commits served")
    tap.equal(commits[1].short_hash, "def5678", "input order preserved")
    tap.equal(commits[2].short_hash, "abc1234", "second input second")
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

  -- H-GP-02: every spawn runs in the pane's repository cwd.
  do
    local host = full_host()
    activate(host)
    local seen_cwds = {}
    host.bitty.process.spawn = function(args, opts)
      seen_cwds[#seen_cwds + 1] = opts ~= nil and opts.cwd or nil
      return { status = 0, output = "" }
    end
    host:run("status", {})
    host:run("branch", {})
    host:run("log", {})
    tap.equal(#seen_cwds, 3, "three spawns observed")
    for _, cwd in ipairs(seen_cwds) do
      tap.equal(cwd, "~/projects/foo", "spawn carries pane cwd")
    end
  end

  -- R17: oversized spawn output truncates to 8 KiB before parsing, with
  -- the truncation bit set; small outputs leave it clear.
  do
    local host = full_host()
    local plugin = activate(host)
    tap.equal(plugin.MAX_SPAWN_OUTPUT_BYTES, 8192, "spawn bound pins 8 KiB")
    local lines = {}
    for i = 1, 600 do
      lines[#lines + 1] = " M ~/projects/file" .. i .. ".txt"
    end
    host.bitty.process.spawn = function(_args, _opts)
      return { status = 0, output = table.concat(lines, "\n") .. "\n" }
    end
    local entries = host:run("status", {})
    tap.ok(plugin.last_spawn_truncated(), "oversized output sets truncation bit")
    tap.le(#entries, 128, "entries still display-bounded after truncation")
    host.bitty.process.spawn = function(_args, _opts)
      return { status = 0, output = " M ~/projects/foo.txt\n" }
    end
    host:run("status", {})
    tap.ok(not plugin.last_spawn_truncated(), "small output clears truncation bit")
  end

  -- M-GP-06: open snapshots exactly once and shares it between the branch
  -- and status derivations.
  do
    local host = full_host({
      spawn_outputs = {
        ["branch\0-a"] = "* main\n  feature/foo\n",
        ["status\0--porcelain"] = " M src/lib.rs\n",
      },
    })
    activate(host)
    local snapshots = 0
    local base_snapshot = host.bitty.terminal.snapshot
    host.bitty.terminal.snapshot = function(opts)
      snapshots = snapshots + 1
      return base_snapshot(opts)
    end
    local summary = host:run("open", {})
    tap.equal(snapshots, 1, "open takes one snapshot")
    tap.equal(summary.cwd, "~/projects/foo", "open reports cached cwd")
    tap.equal(summary.branches, 2, "open shares snapshot with branches")
    tap.equal(summary.entries, 1, "open shares snapshot with status")
  end
end

return { run = run }
