-- Entry point for Bitty Git Panel (bitty-terminal.git-panel).
--
-- The host evaluates this file once per plugin activation and owns every
-- resource created here for the lifetime of that generation. Registration
-- calls (`bitty.commands.register`, `bitty.events.subscribe`) are valid only
-- while this file executes.
--
-- Accepted surface: Plugin API v1 Lua Surface RFC (ADR 0009) plus the
-- accepted Layer 2 `[tools.git]` slice (CTX-0425): capabilities requested in
-- `bitty-plugin.toml` are `panel.provider` (tiled panel factory),
-- `panel.create` (panel instantiation), `terminal.semantic-read` (read-only
-- cwd/title observation), `process.spawn:git` (the seven allowlisted
-- read-only verbs with bounded output), and `fs.read:~/projects/**`
-- (working-tree read). The identifiers are unchanged from the former bundled
-- Rust realization (`bitty` CTX-0400); the split changes no identity.
--
-- Fail-closed discipline: a denied `terminal.semantic-read` propagates
-- instead of serving empty data, a denied or non-allowlisted spawn never
-- executes, out-of-scope paths are dropped, and a missing host spawn surface
-- reports `E_SPAWN_UNAVAILABLE` (the real bridge does not expose
-- `bitty.process` yet; see the README "Known gaps"). Observation event
-- handlers refresh only the cached snapshot-derived state and never spawn,
-- keeping the last-known-good value when the snapshot is unavailable.

local allowlist = require("git-panel.allowlist")
local scope = require("git-panel.scope")
local listing = require("git-panel.listing")

local M = {}

M.COMMANDS = { "open", "status", "diff", "log", "branch" }
M.EVENTS = { "terminal.cwd-changed", "terminal.title-changed", "focus.changed" }

local cache = {
  cwd = nil,
  title = nil,
}

local function fail(code, message)
  error({ class = "runtime", code = code, message = message }, 0)
end

-- Read-only semantic snapshot. Errors propagate: a denied
-- `terminal.semantic-read` must fail closed rather than serve empty data.
local function snapshot()
  if bitty.terminal == nil or type(bitty.terminal.snapshot) ~= "function" then
    fail("E_SNAPSHOT_UNAVAILABLE", "host has no terminal.snapshot surface")
  end
  local value = bitty.terminal.snapshot({ scope = "semantic" })
  if type(value) ~= "table" then
    fail("E_SNAPSHOT_UNAVAILABLE", "semantic snapshot is not a table")
  end
  return value
end

-- Refresh the cached snapshot-derived state. Called directly by commands
-- (a denied snapshot propagates fail-closed) and behind `pcall` by event
-- handlers (last-known-good survives a denied or slow snapshot).
--
-- The cwd comes from semantic-zone metadata newest-first (Plugin API v1
-- Lua Surface RFC: the snapshot carries no top-level `cwd`; zones without
-- shell integration simply contribute none), mirroring the statusline
-- package. The title is the snapshot `title`.
local function snapshot_cwd(snap)
  local zones = snap.zones
  if type(zones) ~= "table" then
    return nil
  end
  for index = #zones, 1, -1 do
    local zone = zones[index]
    if type(zone) == "table" and type(zone.metadata) == "table" then
      local cwd = zone.metadata.cwd
      if type(cwd) == "string" and cwd ~= "" then
        return cwd
      end
    end
  end
  return nil
end

local function refresh_cache()
  local snap = snapshot()
  local cwd = snapshot_cwd(snap)
  if cwd ~= nil then
    cache.cwd = cwd
  end
  if type(snap.title) == "string" then
    cache.title = snap.title
  end
  return cache.cwd
end

function M.cached_cwd()
  return cache.cwd
end

-- Spawn `args` through the host-provided Layer 2 surface only: the
-- allowlist is checked before the call, the call itself is capability-gated
-- by the host, and output is capped to the panel payload bound. Never
-- `os.execute`, `io.popen`, or a native module (denied by the Lua Runtime
-- restricted library).
local function spawn_git(args)
  if not allowlist.is_allowed_args(args) then
    fail("E_SPAWN_DENIED", "git invocation is outside the [tools.git] allowlist")
  end
  -- Layer 2 spawn surface (accepted `[tools.git]` slice, CTX-0425). It is
  -- beyond the vendored Plugin API v1 defs, so the field access carries a
  -- localized suppression; the negative LuaLS fixture still rejects every
  -- other unknown surface.
  ---@diagnostic disable-next-line: undefined-field
  local process_ns = bitty.process
  if type(process_ns) ~= "table" or type(process_ns.spawn) ~= "function" then
    fail("E_SPAWN_UNAVAILABLE", "host has no process.spawn surface yet")
  end
  local result = process_ns.spawn(args)
  if type(result) ~= "table" or type(result.output) ~= "string" then
    fail("E_SPAWN_FAILED", "spawn returned no bounded output")
  end
  return result.output
end

local PORCELAIN_STATUS = {
  M = "modified",
  A = "added",
  D = "deleted",
  R = "renamed",
  C = "copied",
  ["?"] = "untracked",
  U = "conflicted",
  ["!"] = "ignored",
}

local function parse_porcelain(output)
  local paths = {}
  for line in string.gmatch(output or "", "[^\n]+") do
    -- Porcelain v1 is `XY SP path`: either column may carry the change
    -- (` M` is a worktree modification, `A ` a staged addition).
    local x = string.sub(line, 1, 1)
    local y = string.sub(line, 2, 2)
    local path = string.match(line, "^..%s+(.-)%s*$")
    local status = PORCELAIN_STATUS[x] or PORCELAIN_STATUS[y]
    if path ~= nil and status ~= nil then
      paths[#paths + 1] = { path = path, status = status }
    end
  end
  return paths
end

local function status_entries()
  refresh_cache()
  local output = spawn_git({ "status", "--porcelain" })
  local grouped = {}
  for _, item in ipairs(parse_porcelain(output)) do
    grouped[item.status] = grouped[item.status] or {}
    grouped[item.status][#grouped[item.status] + 1] = item.path
  end
  local entries = {}
  for status, paths in pairs(grouped) do
    for _, entry in ipairs(listing.list_status_entries(paths, status)) do
      entries[#entries + 1] = entry
    end
  end
  table.sort(entries, function(a, b)
    return a.path < b.path
  end)
  while #entries > listing.MAX_ENTRIES do
    entries[#entries] = nil
  end
  return entries
end

local function branch_list()
  refresh_cache()
  local output = spawn_git({ "branch", "-a" })
  local raw = {}
  for line in string.gmatch(output or "", "[^\n]+") do
    raw[#raw + 1] = line
  end
  return listing.list_branches(raw)
end

local function commit_list()
  refresh_cache()
  local output = spawn_git({ "log", "--oneline", "-n", "10" })
  local raw = {}
  for line in string.gmatch(output or "", "[^\n]+") do
    local hash, message = string.match(line, "^(%S+)%s+(.-)%s*$")
    if hash ~= nil then
      raw[#raw + 1] = { hash = hash, message = message or "" }
    end
  end
  return listing.list_commits(raw)
end

local function diff_lines()
  refresh_cache()
  local output = spawn_git({ "diff", "--stat" })
  local lines = {}
  for line in string.gmatch(output or "", "[^\n]+") do
    lines[#lines + 1] = line
    if #lines >= listing.MAX_ENTRIES then
      break
    end
  end
  return lines
end

bitty.commands.register({
  id = "open",
  title = "Git Panel: open",
  description = "Open the git panel with the cached working-tree summary.",
  run = function(_args)
    local branches = branch_list()
    local entries = status_entries()
    return {
      cwd = cache.cwd,
      branches = #branches,
      entries = #entries,
    }
  end,
})

bitty.commands.register({
  id = "status",
  title = "Git Panel: status",
  description = "Show bounded working-tree status entries via the allowlisted git status.",
  run = function(_args)
    return status_entries()
  end,
})

bitty.commands.register({
  id = "diff",
  title = "Git Panel: diff",
  description = "Show bounded diff stat lines via the allowlisted git diff.",
  run = function(_args)
    return diff_lines()
  end,
})

bitty.commands.register({
  id = "log",
  title = "Git Panel: log",
  description = "Show bounded commits via the allowlisted git log.",
  run = function(_args)
    return commit_list()
  end,
})

bitty.commands.register({
  id = "branch",
  title = "Git Panel: branch",
  description = "Show bounded branches via the allowlisted git branch.",
  run = function(_args)
    return branch_list()
  end,
})

-- Observation handlers refresh only the cached snapshot-derived state and
-- never spawn: a slow or denied snapshot cannot stall event dispatch, and
-- the last-known-good value survives.
bitty.events.subscribe("terminal.cwd-changed", function(_event)
  pcall(refresh_cache)
end)

bitty.events.subscribe("terminal.title-changed", function(_event)
  pcall(refresh_cache)
end)

bitty.events.subscribe("focus.changed", function(_event)
  pcall(refresh_cache)
end)

M.status_entries = status_entries
M.branch_list = branch_list
M.commit_list = commit_list
M.diff_lines = diff_lines
M.parse_porcelain = parse_porcelain

return M
