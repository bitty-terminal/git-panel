-- Spawn-argv contract tests for `git-panel.init`.
--
-- Two guards for the P1 defect where every command passed an unsupported
-- `process.spawn` `cwd` option and failed on a real host while the mock
-- accepted it:
--
-- 1. a static scan proves `process_ns.spawn` is called with argv only (one
--    argument, no `cwd` key), so the unsupported option cannot reappear; and
-- 2. the pure argv builder is exercised: the pane directory is a distinct
--    `git -C <dir>` element and an invalid directory fails closed.

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

local function activate()
  local host = MockHost.new({
    grants = GRANTS,
    commands = COMMANDS,
    events = EVENTS,
    snapshot = { title = "spawn-argv", zones = { { metadata = { cwd = "/srv/git/repo" } } } },
    git_dir_policy = "confined",
  })
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
  return require("git-panel.init")
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

  -- Static guard: every `process_ns.spawn` call takes one argv argument and
  -- never names `cwd`. The plugin has exactly one spawn call site.
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
      tap.equal(top_level_commas(arguments or ""), 0, "spawn call takes argv only")
      tap.equal(
        string.find(arguments or "", "cwd", 1, true),
        nil,
        "spawn call never passes a cwd option"
      )
      init = open_paren + #(arguments or "") + 2
    end
    tap.equal(calls, 1, "exactly one process_ns.spawn call site")
    tap.ok(string.find(source, '"-C"', 1, true) ~= nil, "pane directory travels as -C")
  end

  -- Pure builder: the directory is a distinct argv element in front of the
  -- allowlisted git args.
  do
    local argv = plugin.spawn_argv({ "status", "--porcelain" }, "/srv/git/repo")
    tap.equal(type(argv), "table", "valid builder returns argv")
    tap.equal(#argv, 4, "argv has directory pair plus git args")
    tap.equal(argv[1], "-C", "first element selects the directory")
    tap.equal(argv[2], "/srv/git/repo", "second element is the directory")
    tap.equal(argv[3], "status", "git verb follows the directory")
    tap.equal(argv[4], "--porcelain", "git flags follow the verb")
    tap.equal(argv[2] .. argv[3], "/srv/git/repostatus", "directory is not concatenated into args")
  end

  -- Invalid directories fail closed (relative, home-relative, traversal,
  -- control byte, missing) and never yield an argv.
  do
    local bad = {
      { name = "relative", dir = "srv/git/repo" },
      { name = "home-relative", dir = "~/projects/foo" },
      { name = "traversal", dir = "/srv/git/../etc" },
      { name = "control byte", dir = "/srv/git/repo\0" },
      { name = "empty", dir = "" },
      { name = "nil", dir = nil },
      { name = "option-shaped", dir = "-C" },
    }
    for _, case in ipairs(bad) do
      tap.equal(plugin.pane_dir(case.dir), nil, "pane_dir rejects " .. case.name)
      tap.equal(plugin.spawn_argv({ "status" }, case.dir), nil, "builder rejects " .. case.name)
    end
    tap.equal(plugin.pane_dir("/srv/git/repo"), "/srv/git/repo", "absolute directory admitted")
    tap.equal(plugin.pane_dir("/"), "/", "root directory admitted")
    tap.equal(plugin.pane_dir("/srv/git/repo/"), "/srv/git/repo/", "trailing slash preserved")
  end

  -- The git allowlist still governs the args after the directory: a denied
  -- verb or flag yields no argv even with a valid directory.
  do
    tap.equal(plugin.spawn_argv({ "push" }, "/srv/git/repo"), nil, "write verb denied")
    tap.equal(plugin.spawn_argv({ "status", "--output=/tmp/x" }, "/srv/git/repo"), nil, "output flag denied")
    tap.equal(plugin.spawn_argv({ "-C", "/tmp/x", "status" }, "/srv/git/repo"), nil, "raw -C denied")
  end
end

return { run = run }
