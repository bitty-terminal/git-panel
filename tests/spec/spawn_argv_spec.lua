-- Spawn-argv contract tests for `git-panel.init`.
--
-- Three guards for the class where a command passed an unsupported
-- `process.spawn` option and failed on a real host while the mock accepted it:
--
-- 1. a static scan proves `process_ns.spawn` is called with argv plus exactly
--    one options table, that the table is the shared builder, and that the
--    plugin never constructs a `-C` operand;
-- 2. the pure argv builder carries the allowlisted git args only, and the
--    options builder carries the host-resolved `cwd = "pane"` token; and
-- 3. the stub rejects a plugin-supplied path with the host's diagnostic and
--    refuses `cwd = "pane"` when the focused view has no session.

local MockHost = require("support.mock_host")

local PLUGIN_ID = "bitty-terminal.git-panel"

local COMMANDS = {
  PLUGIN_ID .. ":open",
  PLUGIN_ID .. ":status",
  PLUGIN_ID .. ":diff",
  PLUGIN_ID .. ":log",
  PLUGIN_ID .. ":branch",
}

local EVENTS = { "terminal.cwd-changed", "terminal.title-changed", "focus.changed" }

local GRANTS = {
  "panel.provider",
  "panel.create",
  "terminal.semantic-read",
  "process.spawn:git",
}

local function activate(overrides)
  local options = {
    grants = GRANTS,
    commands = COMMANDS,
    events = EVENTS,
    snapshot = { title = "spawn-argv", zones = { { metadata = { cwd = "/srv/git/repo" } } } },
  }
  for key, value in pairs(overrides or {}) do
    options[key] = value
  end
  local host = MockHost.new(options)
  _G.bitty = host.bitty
  for _, module in ipairs({
    "git-panel.init",
    "git-panel.allowlist",
    "git-panel.scope",
    "git-panel.listing",
    "git-panel.scene",
  }) do
    package.loaded[module] = nil
  end
  return require("git-panel.init"), host
end

-- Index just past the matching `)` for the call whose `(` is at `open_paren`.
local function call_arguments(source, open_paren)
  local depth = 0
  local index = open_paren
  while index <= #source do
    local char = string.sub(source, index, index)
    if char == "(" then
      depth = depth + 1
    elseif char == ")" then
      depth = depth - 1
      if depth == 0 then
        return string.sub(source, open_paren + 1, index - 1)
      end
    end
    index = index + 1
  end
  return nil
end

-- Count commas at bracket depth zero, so `{ "a", "b" }` inside one argument
-- does not look like a second argument.
local function top_level_commas(text)
  local depth = 0
  local commas = 0
  for index = 1, #text do
    local char = string.sub(text, index, index)
    if char == "(" or char == "{" or char == "[" then
      depth = depth + 1
    elseif char == ")" or char == "}" or char == "]" then
      depth = depth - 1
    elseif char == "," and depth == 0 then
      commas = commas + 1
    end
  end
  return commas
end

local function read_source(root)
  local path = root .. "/lua/git-panel/init.lua"
  local handle = assert(io.open(path, "r"))
  local source = handle:read("*a")
  handle:close()
  return source
end

local function run(context)
  local tap = context.tap
  local plugin = activate()
  local source = read_source(context.root)

  -- Static guard: exactly one spawn call site, argv plus one options table.
  -- The plugin never builds a `-C` operand and never passes a path.
  do
    local calls = 0
    local init = 1
    while true do
      local start = string.find(source, "process_ns.spawn(", init, true)
      if start == nil then
        break
      end
      calls = calls + 1
      local open_paren = start + #"process_ns.spawn"
      local arguments = call_arguments(source, open_paren)
      tap.ok(arguments ~= nil, "spawn call has a closed argument list")
      tap.equal(
        top_level_commas(arguments or ""),
        1,
        "spawn call takes argv plus one options table"
      )
      tap.ok(
        string.find(arguments or "", "spawn_options", 1, true) ~= nil,
        "spawn options come from the shared builder"
      )
      init = open_paren + #(arguments or "") + 2
    end
    tap.equal(calls, 1, "exactly one process_ns.spawn call site")
    tap.equal(string.find(source, '"-C"', 1, true), nil, "no -C operand is constructed")
    tap.ok(string.find(source, 'M.SPAWN_CWD = "pane"', 1, true) ~= nil, "the pane token is pinned")
  end

  -- Pure builder: the allowlisted git args travel unchanged.
  do
    local argv = plugin.spawn_argv({ "status", "--porcelain" })
    tap.equal(type(argv), "table", "valid builder returns argv")
    tap.equal(#argv, 2, "argv carries the git args only")
    tap.equal(argv[1], "status", "verb first")
    tap.equal(argv[2], "--porcelain", "flag second")
    tap.equal(plugin.spawn_argv({ "log", "--oneline", "-n", "10" })[4], "10", "values survive")
  end

  -- Options builder: one key, the host-resolved token.
  do
    local options = plugin.spawn_options()
    tap.equal(type(options), "table", "options builder returns a table")
    tap.equal(options.cwd, "pane", "cwd is the pane token")
    local keys = 0
    for key in pairs(options) do
      keys = keys + 1
      tap.equal(key, "cwd", "only cwd is set")
    end
    tap.equal(keys, 1, "exactly one option key")
  end

  -- The allowlist still governs the args: a denied verb or flag yields no
  -- argv, and a raw `-C` cannot smuggle a directory.
  do
    tap.equal(plugin.spawn_argv({ "push" }), nil, "write verb denied")
    tap.equal(plugin.spawn_argv({ "status", "--output=/tmp/x" }), nil, "output flag denied")
    tap.equal(plugin.spawn_argv({ "-C", "/tmp/x", "status" }), nil, "raw -C denied")
    tap.equal(plugin.spawn_argv({ "--git-dir=/tmp/x", "status" }), nil, "git-dir denied")
  end

  -- End to end through the stub: the recorded call is the git args plus the
  -- pane token, never a directory.
  do
    local _, host = activate({ spawn_outputs = { ["status\0--porcelain"] = "" } })
    host:run("status", {})
    tap.equal(#host.spawn_calls, 2, "root resolution plus status")
    tap.equal(host.spawn_calls[1][1], "rev-parse", "root resolves first")
    tap.equal(host.spawn_calls[2][1], "status", "the command spawns next")
    for _, cwd in ipairs(host.spawn_dirs) do
      tap.equal(cwd, "pane", "the host resolved the pane token")
    end
  end

  -- A focused view without a session is refused by the host.
  do
    local _, host = activate({ pane_cwd_available = false })
    local ok, err = pcall(function()
      return host:run("status", {})
    end)
    tap.ok(not ok, "a sessionless focused view fails the command")
    tap.equal(
      type(err) == "table" and err.code or nil,
      "E_SPAWN_CWD_UNAVAILABLE",
      "the host refusal surfaces unchanged"
    )
    tap.equal(#host.spawn_calls, 0, "no child is spawned")
  end

  -- The bridge rejects a plugin-supplied path, so a regression that
  -- reintroduces one fails here as it would on a real host.
  do
    local _, host = activate()
    local ok, err = pcall(function()
      return host.bitty.process.spawn({ "status" }, { cwd = "/srv/git/repo" })
    end)
    tap.ok(not ok, "a path-valued cwd is refused")
    tap.equal(type(err) == "table" and err.code or nil, "E_DEF_INVALID", "bridge diagnostic")
  end
end

return { run = run }
