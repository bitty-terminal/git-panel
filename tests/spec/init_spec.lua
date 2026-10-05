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
  -- allowlisted spawn output. Status resolves the repository root first
  -- (`rev-parse --show-toplevel`), then the status payload.
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
    tap.equal(#host.spawn_calls, 2, "root plus status spawns issued")
    tap.equal(host.spawn_calls[1][1], "rev-parse", "first spawn resolves root")
    tap.equal(host.spawn_calls[2][1], "status", "second spawn is status")
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

  -- H-GP-01 / PLUG-APP-005: real porcelain vectors are repo-root-relative
  -- and resolve against the resolved repository root, including renames.
  do
    local host = full_host({
      spawn_outputs = {
        ["rev-parse\0--show-toplevel"] = "~/projects/foo\n",
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
        ["rev-parse\0--show-toplevel"] = "/srv/git/repo\n",
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
        ["rev-parse\0--show-toplevel"] = "~/projects/foo\n",
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

  -- H-GP-02: every spawn runs in the pane cwd (not the host root).
  -- Status first resolves the repository root, so four spawns are
  -- observed: rev-parse, status, branch, log.
  do
    local host = full_host()
    activate(host)
    local seen_cwds = {}
    local seen_verbs = {}
    host.bitty.process.spawn = function(args, opts)
      seen_cwds[#seen_cwds + 1] = opts ~= nil and opts.cwd or nil
      seen_verbs[#seen_verbs + 1] = args[1]
      if args[1] == "rev-parse" then
        return { status = 0, output = "~/projects/foo\n" }
      end
      return { status = 0, output = "" }
    end
    host:run("status", {})
    host:run("branch", {})
    host:run("log", {})
    tap.equal(#seen_cwds, 4, "four spawns observed (root plus three)")
    tap.equal(seen_verbs[1], "rev-parse", "root resolves first")
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
    host.bitty.process.spawn = function(args, _opts)
      if args[1] == "rev-parse" then
        return { status = 0, output = "~/projects/foo\n" }
      end
      return { status = 0, output = table.concat(lines, "\n") .. "\n" }
    end
    local entries = host:run("status", {})
    tap.ok(plugin.last_spawn_truncated(), "oversized output sets truncation bit")
    tap.le(#entries, 128, "entries still display-bounded after truncation")
    host.bitty.process.spawn = function(args, _opts)
      if args[1] == "rev-parse" then
        return { status = 0, output = "~/projects/foo\n" }
      end
      return { status = 0, output = " M ~/projects/foo.txt\n" }
    end
    host:run("status", {})
    tap.ok(not plugin.last_spawn_truncated(), "small output clears truncation bit")
  end

  -- R17 half-line: a truncation that lands mid-line must drop the partial
  -- trailing line so the fragment is never served as an entry.
  do
    local host = full_host()
    local plugin = activate(host)
    local bound = plugin.MAX_SPAWN_OUTPUT_BYTES
    local phantom_line = " M ~/projects/phantom.txt"
    -- Bytes of the phantom line left before the cut: enough for ` M ` plus a
    -- partial in-scope `~/projects/` path to look like a real entry.
    local keep = 24
    tap.ok(keep < #phantom_line, "fixture keeps a parseable phantom prefix")
    local function fill_to(length)
      local chunk = " M ~/projects/fill.txt\n"
      local out = string.rep(chunk, math.floor(length / #chunk))
      local rest = length - #out
      if rest > 0 then
        out = out .. string.rep("a", rest - 1) .. "\n"
      end
      return out
    end
    local head = fill_to(bound - keep)
    tap.equal(#head, bound - keep, "head fills exactly to the cut margin")
    local output = head .. phantom_line .. "\n"
    tap.ok(#output > bound, "fixture exceeds the 8 KiB bound")
    host.bitty.process.spawn = function(args, _opts)
      if args[1] == "rev-parse" then
        return { status = 0, output = "~/projects/foo\n" }
      end
      return { status = 0, output = output }
    end
    local entries = host:run("status", {})
    tap.ok(plugin.last_spawn_truncated(), "mid-line truncation sets the truncation bit")
    local phantom_served = false
    for _, entry in ipairs(entries) do
      if string.find(entry.path, "phantom", 1, true) ~= nil then
        phantom_served = true
      end
    end
    tap.ok(not phantom_served, "partial trailing line is not served")
  end

  -- M-GP-06: open snapshots exactly once and shares it between the branch
  -- and status derivations.
  do
    local host = full_host({
      spawn_outputs = {
        ["rev-parse\0--show-toplevel"] = "~/projects/foo\n",
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
    tap.equal(summary.cwd, "~/projects/foo", "open reports pane cwd")
    tap.equal(summary.repo_root, "~/projects/foo", "open reports resolved root")
    tap.equal(summary.branches, 2, "open shares snapshot with branches")
    tap.equal(summary.entries, 1, "open shares snapshot with status")
  end

  -- PLUG-APP-004: the cache binds the focused terminal identity. A
  -- successful snapshot with missing cwd clears the stale root instead of
  -- retaining the previous pane's value.
  do
    local host = full_host({
      snapshot = {
        title = "one",
        terminal_id = 1,
        runtime_id = 11,
        generation = 100,
        zones = { { metadata = { cwd = "~/projects/foo" } } },
      },
      spawn_outputs = {
        ["rev-parse\0--show-toplevel"] = "~/projects/foo\n",
        ["status\0--porcelain"] = " M src/a.txt\n",
      },
    })
    local plugin = activate(host)
    local entries = host:run("status", {})
    tap.equal(#entries, 1, "first pane serves one entry")
    tap.equal(plugin.cached_cwd(), "~/projects/foo", "first cwd cached")
    host.snapshot_value = {
      title = "two",
      terminal_id = 2,
      runtime_id = 22,
      generation = 100,
      zones = {},
    }
    host:publish("focus.changed", { terminal_id = 2 })
    tap.equal(plugin.cached_cwd(), nil, "missing cwd clears stale root")
    local tid, rid, gen = plugin.cached_identity()
    tap.equal(tid, 2, "identity tracks focused terminal")
    tap.equal(rid, 22, "runtime tracks focused terminal")
    tap.equal(gen, 100, "generation tracked")
  end

  -- PLUG-APP-004: a focus change naming a different terminal
  -- pre-invalidates, so an unavailable snapshot yields unavailable results
  -- rather than the previous pane's root. Pure mock focus-change case.
  do
    local host = full_host({
      snapshot = {
        title = "one",
        terminal_id = 1,
        runtime_id = 11,
        generation = 100,
        zones = { { metadata = { cwd = "~/projects/foo" } } },
      },
      spawn_outputs = {
        ["rev-parse\0--show-toplevel"] = "~/projects/foo\n",
        ["status\0--porcelain"] = " M src/a.txt\n",
      },
    })
    local plugin = activate(host)
    host:run("status", {})
    tap.equal(plugin.cached_cwd(), "~/projects/foo", "pane one cached")
    host.snapshot_value = nil
    host:publish("focus.changed", { terminal_id = 2, runtime_id = 22 })
    tap.equal(plugin.cached_cwd(), nil, "stale root pre-invalidated on focus change")
    local ok, err = pcall(function()
      return host:run("status", {})
    end)
    tap.ok(not ok, "status after unavailable snapshot fails")
    tap.equal(type(err) == "table" and err.code or nil, "E_SNAPSHOT_UNAVAILABLE", "unavailable, not stale")
  end

  -- PLUG-APP-005: the repository root stays separate from a nested pane
  -- cwd. In-memory adapter fixture only: no Git, no filesystem.
  do
    local host = full_host({
      snapshot = {
        title = "nested",
        terminal_id = 7,
        runtime_id = 70,
        generation = 3,
        zones = { { metadata = { cwd = "~/projects/foo/subdir" } } },
      },
      spawn_outputs = {
        ["rev-parse\0--show-toplevel"] = "~/projects/foo\n",
        ["status\0--porcelain"] = " M src/lib.rs\n",
      },
    })
    activate(host)
    local entries = host:run("status", {})
    tap.equal(#entries, 1, "nested cwd still serves one entry")
    tap.equal(entries[1].path, "~/projects/foo/src/lib.rs", "relative joins against root, not nested cwd")
    tap.equal(#host.spawn_calls, 2, "root plus status spawns")
    tap.equal(host.spawn_cwds[1], "~/projects/foo/subdir", "rev-parse runs in nested pane cwd")
    tap.equal(host.spawn_cwds[2], "~/projects/foo/subdir", "status runs in nested pane cwd")
  end

  -- PLUG-APP-005: an unresolvable root drops relatives fail-closed while
  -- explicit-root headless use keeps working.
  do
    local host = full_host({
      spawn_outputs = {
        ["rev-parse\0--show-toplevel"] = "",
        ["status\0--porcelain"] = " M src/lib.rs\n",
      },
    })
    local plugin = activate(host)
    local entries = host:run("status", {})
    tap.equal(#entries, 0, "relatives without a root drop")
    tap.equal(plugin.cached_repo_root(), nil, "unresolvable root stays nil")
    local headless = plugin.parse_porcelain(" M src/lib.rs\n")
    tap.equal(#headless, 1, "pure parser still works headless")
    tap.equal(headless[1].path, "src/lib.rs", "headless parse preserves relative bytes")
  end

  -- PLUG-APP-006: quote-aware rename splitting preserves a ` -> ` inside
  -- the new name. The greedy textual split would cut inside the quotes.
  do
    local host = full_host()
    local plugin = activate(host)
    local parsed = plugin.parse_porcelain('R  old.lua -> "a -> b.lua"\n')
    tap.equal(#parsed, 1, "quoted rename parses once")
    tap.equal(parsed[1].path, "a -> b.lua", "post-image keeps inner separator")
    tap.equal(parsed[1].status, "renamed", "rename status carried")
    local quoted_old = plugin.parse_porcelain('R  "a -> b.txt" -> "c.txt"\n')
    tap.equal(#quoted_old, 1, "quoted old name parses once")
    tap.equal(quoted_old[1].path, "c.txt", "quoted old separator ignored")
  end

  -- PLUG-APP-006: single-pass C-quote decoding preserves a literal
  -- backslash before octal digits and UTF-8 bytes. The two-pass decoder
  -- turned `"a\\303b"` into backslash plus U+00C3 instead of the literal.
  do
    local host = full_host()
    local plugin = activate(host)
    local literal = plugin.parse_porcelain(' M "a\\\\303b"\n')
    tap.equal(#literal, 1, "backslash fixture parses once")
    tap.equal(literal[1].path, "a\\303b", "literal backslash plus digits preserved")
    local utf8 = plugin.parse_porcelain(' M "caf\\303\\251.txt"\n')
    tap.equal(#utf8, 1, "octal UTF-8 parses once")
    tap.equal(utf8[1].path, "caf\195\169.txt", "octal bytes decode to UTF-8")
  end

  -- PLUG-APP-006: trailing spaces and malformed wrappings stay
  -- fail-closed without trimming supported bytes.
  do
    local host = full_host()
    local plugin = activate(host)
    local trailing = plugin.parse_porcelain(" M foo \n")
    tap.equal(#trailing, 1, "trailing-space line kept")
    tap.equal(trailing[1].path, "foo ", "trailing space preserved")
    local malformed = plugin.parse_porcelain(' M "unterminated\n')
    tap.equal(#malformed, 0, "malformed quote drops")
  end
end

return { run = run }
