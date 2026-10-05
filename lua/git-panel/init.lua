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
-- handlers refresh only the cached snapshot-derived state and never spawn.
-- The cache binds the focused terminal identity (`terminal_id`,
-- `runtime_id`, `generation` from the semantic snapshot): an identity change
-- or a successful snapshot with missing cwd/title clears the stale value
-- instead of retaining another pane's root, and a focus change to a
-- different terminal pre-invalidates before the refresh so an unavailable
-- snapshot yields unavailable results rather than stale roots.

local allowlist = require("git-panel.allowlist")
local scope = require("git-panel.scope")
local listing = require("git-panel.listing")

local M = {}

M.COMMANDS = { "open", "status", "diff", "log", "branch" }
M.EVENTS = { "terminal.cwd-changed", "terminal.title-changed", "focus.changed" }

local cache = {
  cwd = nil,
  title = nil,
  terminal_id = nil,
  runtime_id = nil,
  generation = nil,
  repo_root = nil,
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
-- handlers (an unavailable snapshot keeps the pre-invalidated unavailable
-- state, never a stale pane's root).
--
-- The cwd comes from semantic-zone metadata newest-first (Plugin API v1
-- Lua Surface RFC: the snapshot carries no top-level `cwd`; zones without
-- shell integration simply contribute none), mirroring the statusline
-- package. The title is the snapshot `title`.
--
-- PLUG-APP-004: the cache binds the focused terminal identity
-- (`terminal_id`, `runtime_id`, `generation`). A successful snapshot always
-- overwrites (missing cwd/title clears to nil); an identity change clears
-- the derived repo root so the next status resolves against the new pane.
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

local function snapshot_identity(snap)
  local terminal_id = snap.terminal_id
  local runtime_id = snap.runtime_id
  local generation = snap.generation
  if type(terminal_id) ~= "number" or type(runtime_id) ~= "number" or type(generation) ~= "number" then
    return nil, nil, nil
  end
  return terminal_id, runtime_id, generation
end

local function invalidate_cache()
  cache.cwd = nil
  cache.title = nil
  cache.terminal_id = nil
  cache.runtime_id = nil
  cache.generation = nil
  cache.repo_root = nil
end

local function refresh_cache()
  local snap = snapshot()
  local cwd = snapshot_cwd(snap)
  local terminal_id, runtime_id, generation = snapshot_identity(snap)
  local title = nil
  if type(snap.title) == "string" then
    title = snap.title
  end
  if terminal_id ~= cache.terminal_id or runtime_id ~= cache.runtime_id or generation ~= cache.generation then
    cache.repo_root = nil
  end
  if cwd ~= cache.cwd then
    cache.repo_root = nil
  end
  cache.cwd = cwd
  cache.title = title
  cache.terminal_id = terminal_id
  cache.runtime_id = runtime_id
  cache.generation = generation
  return cache.cwd
end

function M.cached_cwd()
  return cache.cwd
end

function M.cached_title()
  return cache.title
end

function M.cached_identity()
  return cache.terminal_id, cache.runtime_id, cache.generation
end

function M.cached_repo_root()
  return cache.repo_root
end

-- Pre-invalidate on observation events whose payload names a different
-- terminal/runtime than the cache, so a slow or denied re-snapshot cannot
-- serve the previous pane's root. Handlers still never spawn.
local function note_observation_event(event)
  if type(event) ~= "table" or type(event.payload) ~= "table" then
    return
  end
  local payload = event.payload
  local terminal_id = payload.terminal_id
  local runtime_id = payload.runtime_id
  if type(terminal_id) == "number" and terminal_id ~= cache.terminal_id then
    invalidate_cache()
    return
  end
  if type(runtime_id) == "number" and runtime_id ~= cache.runtime_id then
    invalidate_cache()
    return
  end
end

-- Spawn `args` through the host-provided Layer 2 surface only: the
-- allowlist is checked before the call, the call itself is capability-gated
-- by the host, and output is capped to the panel payload bound. Never
-- `os.execute`, `io.popen`, or a native module (denied by the Lua Runtime
-- restricted library).
--
-- R17: the raw output is truncated to `MAX_SPAWN_OUTPUT_BYTES` (8 KiB)
-- before any parsing, and the truncation is recorded in the module-level
-- truncation bit (`last_spawn_truncated`); callers keep their own
-- display-limit truncation (`listing.MAX_ENTRIES` / `MAX_COMMITS`). A cut
-- that lands mid-line drops the trailing partial line so a fragment is
-- never parsed as an entry; the bound and the bit semantics are unchanged.
M.MAX_SPAWN_OUTPUT_BYTES = 8192

local last_spawn_truncated = false

function M.last_spawn_truncated()
  return last_spawn_truncated
end

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
  -- H-GP-02: run git in the pane's repository, not the host root. A nil cwd
  -- (no snapshot observed yet) leaves the key absent-equivalent for the host.
  local result = process_ns.spawn(args, { cwd = cache.cwd })
  if type(result) ~= "table" or type(result.output) ~= "string" then
    fail("E_SPAWN_FAILED", "spawn returned no bounded output")
  end
  local output = result.output
  if #output > M.MAX_SPAWN_OUTPUT_BYTES then
    output = string.sub(output, 1, M.MAX_SPAWN_OUTPUT_BYTES)
    -- R17: the cut can land mid-line, so drop the trailing partial line
    -- before any caller parses it; a fragment must never appear as an
    -- entry. When the cut coincides with a newline the last line is whole
    -- and is kept, and when no complete line survives at all the payload
    -- is empty.
    local last_newline = string.find(output, "\n[^\n]*$")
    if last_newline == nil then
      output = ""
    else
      output = string.sub(output, 1, last_newline)
    end
    last_spawn_truncated = true
  else
    last_spawn_truncated = false
  end
  return output
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

-- Unwrap git C-style quote-wrapping (`"my file.txt"`, octal escapes such
-- as `"caf\303\251.txt"`) in a single left-to-right pass. Unquoted paths
-- pass through untouched; a malformed wrapping yields `nil` (fail-closed
-- downstream).
--
-- PLUG-APP-006: the previous two-pass decoder (`gsub` octal, then `gsub`
-- single-char) mis-decoded a literal backslash before octal digits
-- (`"a\\303b"` decoded the second backslash plus `303` as octal instead of
-- a literal backslash plus `303`). The single pass consumes `\\` as an
-- escaped backslash before testing for octal, preserving supported bytes.
local function unquote_git_path(path)
  if path == nil then
    return nil
  end
  local first = string.sub(path, 1, 1)
  local last = string.sub(path, -1)
  if first ~= '"' and last ~= '"' then
    return path
  end
  if #path < 2 or first ~= '"' or last ~= '"' then
    return nil
  end
  local inner = string.sub(path, 2, -2)
  local out = {}
  local index = 1
  while index <= #inner do
    local char = string.sub(inner, index, index)
    if char ~= "\\" then
      out[#out + 1] = char
      index = index + 1
    else
      if index == #inner then
        return nil
      end
      local o1 = string.sub(inner, index + 1, index + 1)
      local o2 = string.sub(inner, index + 2, index + 2)
      local o3 = string.sub(inner, index + 3, index + 3)
      local is_octal = o1 >= "0"
        and o1 <= "7"
        and o2 >= "0"
        and o2 <= "7"
        and o3 >= "0"
        and o3 <= "7"
      if is_octal then
        local byte = tonumber(o1 .. o2 .. o3, 8)
        if byte == nil or byte > 255 then
          return nil
        end
        out[#out + 1] = string.char(byte)
        index = index + 4
      else
        local escaped = string.sub(inner, index + 1, index + 1)
        if escaped == "a" then
          out[#out + 1] = "\a"
        elseif escaped == "b" then
          out[#out + 1] = "\b"
        elseif escaped == "f" then
          out[#out + 1] = "\f"
        elseif escaped == "n" then
          out[#out + 1] = "\n"
        elseif escaped == "r" then
          out[#out + 1] = "\r"
        elseif escaped == "t" then
          out[#out + 1] = "\t"
        elseif escaped == "v" then
          out[#out + 1] = "\v"
        else
          out[#out + 1] = escaped
        end
        index = index + 2
      end
    end
  end
  return table.concat(out)
end

-- Quote-aware rename separator: the last ` -> ` outside C-quote wrapping.
-- A ` -> ` inside quotes belongs to the filename and never splits. Escaped
-- quotes (`\"`) and escaped backslashes (`\\`) never toggle the quote state.
local function find_rename_separator(rest)
  local last_sep = nil
  local in_quote = false
  local index = 1
  while index <= #rest do
    local char = string.sub(rest, index, index)
    if in_quote then
      if char == "\\" then
        index = index + 2
      elseif char == '"' then
        in_quote = false
        index = index + 1
      else
        index = index + 1
      end
    else
      if char == '"' then
        in_quote = true
        index = index + 1
      elseif char == " " and string.sub(rest, index, index + 3) == " -> " then
        last_sep = index
        index = index + 4
      else
        index = index + 1
      end
    end
  end
  return last_sep
end

local function rename_post_image(rest)
  local sep = find_rename_separator(rest)
  if sep == nil then
    return nil
  end
  local new_part = string.sub(rest, sep + 4)
  if new_part == "" then
    return nil
  end
  return new_part
end

-- Sane XY two-column semantics for porcelain v1: either column may carry
-- the change (` M` worktree-modified, `A ` staged-added), while unmerged
-- combinations (`U` in either column, `AA`, `DD`) report conflicted.
local function porcelain_status(x, y)
  if x == "U" or y == "U" then
    return "conflicted"
  end
  if (x == "A" and y == "A") or (x == "D" and y == "D") then
    return "conflicted"
  end
  return PORCELAIN_STATUS[x] or PORCELAIN_STATUS[y]
end

local function parse_porcelain(output)
  local paths = {}
  for line in string.gmatch(output or "", "[^\n]+") do
    -- Porcelain v1 is `XY SP path`: either column may carry the change
    -- (` M` is a worktree modification, `A ` a staged addition). The path
    -- starts at byte 4 and is preserved verbatim (including trailing
    -- spaces); shorter lines or a missing separator space are invalid.
    if #line >= 4 and string.sub(line, 3, 3) == " " then
      local x = string.sub(line, 1, 1)
      local y = string.sub(line, 2, 2)
      local rest = string.sub(line, 4)
      local status = porcelain_status(x, y)
      if rest ~= "" and status ~= nil then
        local path = rest
        if status == "renamed" or status == "copied" then
          -- R18: renames/copies carry `old -> new`; the panel tracks the
          -- post-image. The split is quote-aware: only a ` -> ` outside
          -- C-quote wrapping separates, so a quoted ` -> ` inside a name
          -- never splits. Unquoted ambiguity keeps the greedy last-separator
          -- behavior.
          local new = rename_post_image(rest)
          if new ~= nil then
            path = new
          end
        end
        local decoded = unquote_git_path(path)
        if decoded ~= nil and decoded ~= "" then
          paths[#paths + 1] = { path = decoded, status = status }
        end
      end
    end
  end
  return paths
end

-- H-GP-01: resolve the parsed porcelain paths against the cached
-- repository root before scope checks. Relative means relative to the
-- repository root; `listing.list_status_entries` joins with `root` and
-- validates, so arbitrary roots work (not just the grant prefix) while
-- absolute out-of-scope paths and `..` escapes still drop fail-closed.
local function status_entries_from_output(output, root)
  local grouped = {}
  for _, item in ipairs(parse_porcelain(output)) do
    grouped[item.status] = grouped[item.status] or {}
    grouped[item.status][#grouped[item.status] + 1] = item.path
  end
  local entries = {}
  for status, paths in pairs(grouped) do
    for _, entry in ipairs(listing.list_status_entries(paths, status, { root = root })) do
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

-- PLUG-APP-005: the repository root is distinct from the pane cwd. The
-- pane cwd comes from the semantic snapshot and selects the spawn cwd; the
-- repository root comes from the accepted read-only `[tools.git]` contract
-- (`git rev-parse --show-toplevel`, allowlisted) and joins root-relative
-- porcelain records. A pane in a nested directory must not join against
-- the nested cwd. The bridge prerequisite is explicit: without
-- `bitty.process.spawn` both resolutions fail with `E_SPAWN_UNAVAILABLE`
-- (see README Known gaps); without a resolvable root, relatives drop
-- fail-closed while explicit-root headless use keeps working.
local function repo_root_from_output(output)
  if type(output) ~= "string" then
    return nil
  end
  local first = string.match(output, "^([^\r\n]*)")
  if first == nil or first == "" then
    return nil
  end
  if not scope.is_valid_path(first) then
    return nil
  end
  for segment in string.gmatch(first, "[^/]+") do
    if segment == ".." then
      return nil
    end
  end
  return first
end

local function resolve_repo_root()
  if cache.repo_root ~= nil then
    return cache.repo_root
  end
  if cache.cwd == nil then
    return nil
  end
  local output = spawn_git({ "rev-parse", "--show-toplevel" })
  local root = repo_root_from_output(output)
  if root ~= nil then
    cache.repo_root = root
  end
  return root
end

local function status_entries()
  refresh_cache()
  local root = resolve_repo_root()
  local output = spawn_git({ "status", "--porcelain" })
  return status_entries_from_output(output, root)
end

local function branch_list_from_output(output)
  local raw = {}
  for line in string.gmatch(output or "", "[^\n]+") do
    raw[#raw + 1] = line
  end
  return listing.list_branches(raw)
end

local function branch_list()
  refresh_cache()
  local output = spawn_git({ "branch", "-a" })
  return branch_list_from_output(output)
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
    -- M-GP-06: exactly one snapshot per open; the shared cache serves both
    -- the branch and the status derivations below (no per-listing refresh).
    -- The status derivation joins against the resolved repository root,
    -- not the pane cwd (PLUG-APP-005); the summary `cwd` still reports the
    -- pane cwd.
    refresh_cache()
    local root = resolve_repo_root()
    local branches = branch_list_from_output(spawn_git({ "branch", "-a" }))
    local entries = status_entries_from_output(spawn_git({ "status", "--porcelain" }), root)
    return {
      cwd = cache.cwd,
      repo_root = root,
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
-- never spawn: a slow or denied snapshot cannot stall event dispatch. A
-- payload naming a different terminal/runtime pre-invalidates so the
-- previous pane's root is never served as unavailable-turned-stale.
bitty.events.subscribe("terminal.cwd-changed", function(event)
  note_observation_event(event)
  pcall(refresh_cache)
end)

bitty.events.subscribe("terminal.title-changed", function(event)
  note_observation_event(event)
  pcall(refresh_cache)
end)

bitty.events.subscribe("focus.changed", function(event)
  note_observation_event(event)
  pcall(refresh_cache)
end)

M.status_entries = status_entries
M.branch_list = branch_list
M.commit_list = commit_list
M.diff_lines = diff_lines
M.parse_porcelain = parse_porcelain
M.resolve_repo_root = resolve_repo_root
M.repo_root_from_output = repo_root_from_output
M.invalidate_cache = invalidate_cache

return M
