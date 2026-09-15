-- Bounded git listings for Bitty Git Panel (bitty-terminal.git-panel).
--
-- Pure functions with no host dependency. Mirrors the former bundled Rust
-- realization (`bitty-runtime/src/git_panel.rs`, removed by `bitty`
-- CTX-0400): branch names follow the simplified `git check-ref-format`
-- shape plus spawn-safety rejection of shell metacharacters, commit hashes
-- are `7..40` hex characters, and every listing is deduplicated and
-- truncated to its bound (`128` status entries, `64`
-- commits, `32` branches, `128`-char names, `256`-char messages). Branches
-- and status entries sort deterministically; commits preserve the
-- reverse-chronological `git log` input order (R19). Filters
-- are case-insensitive substring matches bounded to the listing cap.

local scope = require("git-panel.scope")

local M = {}

M.MAX_ENTRIES = 128
M.MAX_COMMITS = 64
M.MAX_BRANCHES = 32
M.MAX_NAME_CHARS = 128
M.MAX_COMMIT_MESSAGE_CHARS = 256
M.MAX_SELECTION = 64

M.FILE_STATUSES = {
  modified = true,
  added = true,
  deleted = true,
  renamed = true,
  copied = true,
  untracked = true,
  conflicted = true,
  ignored = true,
  clean = true,
}

local function char_count(text)
  if utf8 ~= nil and utf8.len ~= nil then
    local count = utf8.len(text)
    if type(count) == "number" then
      return count
    end
  end
  local count = 0
  local index = 1
  while index <= #text do
    local byte = string.byte(text, index)
    if byte < 0x80 or byte >= 0xC0 then
      count = count + 1
    end
    index = index + 1
  end
  return count
end

local function char_slice(text, max)
  if max <= 0 then
    return ""
  end
  if char_count(text) <= max then
    return text
  end
  if utf8 ~= nil and utf8.offset ~= nil then
    local offset = utf8.offset(text, max + 1)
    if offset ~= nil then
      return string.sub(text, 1, offset - 1)
    end
  end
  local count = 0
  local index = 1
  while index <= #text do
    local byte = string.byte(text, index)
    if byte < 0x80 or byte >= 0xC0 then
      count = count + 1
      if count > max then
        return string.sub(text, 1, index - 1)
      end
    end
    index = index + 1
  end
  return text
end

local function contains_plain(haystack, needle)
  return string.find(haystack, needle, 1, true) ~= nil
end

function M.is_valid_branch_name(branch)
  if type(branch) ~= "string" then
    return false
  end
  if #branch == 0 or #branch > M.MAX_NAME_CHARS then
    return false
  end
  for _, denied in ipairs({ "..", "~", "^", ":", "?", "*", "[", "//", ".lock" }) do
    if contains_plain(branch, denied) then
      return false
    end
  end
  if string.sub(branch, 1, 1) == "/" or string.sub(branch, 1, 1) == "." then
    return false
  end
  if string.sub(branch, -1) == "/" or string.sub(branch, -1) == "." then
    return false
  end
  for index = 1, #branch do
    local byte = string.byte(branch, index)
    if byte == 0 or byte < 32 or byte == 127 then
      return false
    end
    local char = string.sub(branch, index, index)
    if char == " " or char == "\t" then
      return false
    end
    if
      char == ";"
      or char == "&"
      or char == "|"
      or char == "`"
      or char == "$"
      or char == "("
      or char == ")"
      or char == "<"
      or char == ">"
      or char == "\\"
      or char == '"'
      or char == "'"
    then
      return false
    end
  end
  return true
end

function M.is_valid_commit_hash(hash)
  if type(hash) ~= "string" then
    return false
  end
  if #hash < 7 or #hash > 40 then
    return false
  end
  return string.match(hash, "^[0-9a-fA-F]+$") ~= nil
end

local function sort_branches(branches)
  table.sort(branches, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    if a.is_current ~= b.is_current then
      return a.is_current
    end
    return false
  end)
end

-- Filter and bound a raw branch listing to `MAX_BRANCHES` valid branches,
-- sorted deterministically with `* `-prefixed current tracking. Pure.
function M.list_branches(raw)
  local branches = {}
  local by_name = {}
  for _, line in ipairs(raw or {}) do
    if type(line) == "string" then
      local trimmed = string.match(line, "^%s*(.-)%s*$")
      local is_current = string.sub(trimmed, 1, 1) == "*"
      local name = trimmed
      if is_current then
        name = string.match(string.sub(trimmed, 2), "^%s*(.-)%s*$")
      end
      if M.is_valid_branch_name(name) then
        local known = by_name[name]
        if known == nil then
          local entry = { name = name, is_current = is_current, truncated = false }
          by_name[name] = entry
          branches[#branches + 1] = entry
        elseif is_current and not known.is_current then
          known.is_current = true
        end
      end
    end
  end
  sort_branches(branches)
  while #branches > M.MAX_BRANCHES do
    branches[#branches] = nil
  end
  return branches
end

-- Case-insensitive substring filter over branch names, bounded to
-- `MAX_BRANCHES`. The query is truncated to `MAX_NAME_CHARS`.
function M.filter_branches(branches, query)
  local bounded_query = char_slice(string.lower(query or ""), M.MAX_NAME_CHARS)
  local out = {}
  for _, branch in ipairs(branches or {}) do
    if #out >= M.MAX_BRANCHES then
      break
    end
    if bounded_query == "" or contains_plain(string.lower(branch.name), bounded_query) then
      out[#out + 1] = branch
    end
  end
  return out
end

-- Filter and bound a raw path listing to `MAX_ENTRIES` status entries with
-- `status`, sorted deterministically and deduplicated by path. Paths outside
-- the granted read scope are dropped (fail-closed). Pure.
--
-- H-GP-01: `git status --porcelain` emits repo-root-relative paths, which
-- never satisfy the host-absolute grant check. Pass `{ root = <repo root> }`
-- (the pane's cached cwd) so relative paths resolve against the repository
-- root before validation: joined, then admitted only when within the root.
-- Relative paths without a root, and absolute paths outside the grant scope,
-- are still dropped fail-closed. Entry paths for resolved relatives are the
-- joined host-absolute form.
function M.list_status_entries(raw, status, opts)
  if M.FILE_STATUSES[status] ~= true then
    return {}
  end
  local root = nil
  if type(opts) == "table" and type(opts.root) == "string" and opts.root ~= "" then
    root = opts.root
  end
  local entries = {}
  local seen = {}
  for _, path in ipairs(raw or {}) do
    local candidate = nil
    if type(path) == "string" and not scope.is_absolute_path(path) and root ~= nil then
      local joined = scope.join_root(root, path)
      if joined ~= nil and scope.is_within_root(root, joined) then
        candidate = joined
      end
    elseif scope.is_within_repo(path) then
      candidate = path
    end
    if candidate ~= nil and not seen[candidate] then
      seen[candidate] = true
      entries[#entries + 1] = { path = candidate, status = status }
    end
  end
  table.sort(entries, function(a, b)
    return a.path < b.path
  end)
  while #entries > M.MAX_ENTRIES do
    entries[#entries] = nil
  end
  return entries
end

-- Case-insensitive substring filter over status paths, bounded to
-- `MAX_ENTRIES`.
function M.filter_status_entries(entries, query)
  local bounded_query = char_slice(string.lower(query or ""), M.MAX_NAME_CHARS)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    if #out >= M.MAX_ENTRIES then
      break
    end
    if bounded_query == "" or contains_plain(string.lower(entry.path), bounded_query) then
      out[#out + 1] = entry
    end
  end
  return out
end

-- Filter and bound raw `{ hash, message }` commits to `MAX_COMMITS` valid
-- commits, deduplicated by hash with the input order preserved. R19: the
-- input arrives reverse-chronological from `git log` and must stay that way;
-- no hash re-sort happens here. A hash-sorted presentation is a display-only
-- concern for callers (see `sorted_commits_by_hash`). Messages truncate to
-- `MAX_COMMIT_MESSAGE_CHARS` at a code-point boundary. Pure.
function M.list_commits(raw)
  local commits = {}
  local seen = {}
  for _, item in ipairs(raw or {}) do
    if type(item) == "table" and M.is_valid_commit_hash(item.hash) and not seen[item.hash] then
      seen[item.hash] = true
      local message = char_slice(item.message or "", M.MAX_COMMIT_MESSAGE_CHARS)
      commits[#commits + 1] = {
        hash = item.hash,
        short_hash = string.sub(item.hash, 1, 7),
        message = message,
        truncated = char_count(item.message or "") > M.MAX_COMMIT_MESSAGE_CHARS,
      }
    end
  end
  while #commits > M.MAX_COMMITS do
    commits[#commits] = nil
  end
  return commits
end

-- Display-only hash-sorted view over an already-bounded commit list. Pure;
-- never used by the ingestion path, which preserves `git log` order (R19).
function M.sorted_commits_by_hash(commits)
  local view = {}
  for _, commit in ipairs(commits or {}) do
    view[#view + 1] = commit
  end
  table.sort(view, function(a, b)
    return a.hash < b.hash
  end)
  return view
end

-- Case-insensitive substring filter over commit hashes and messages,
-- bounded to `MAX_COMMITS`.
function M.filter_commits(commits, query)
  local bounded_query = char_slice(string.lower(query or ""), M.MAX_NAME_CHARS)
  local out = {}
  for _, commit in ipairs(commits or {}) do
    if #out >= M.MAX_COMMITS then
      break
    end
    if
      bounded_query == ""
      or contains_plain(string.lower(commit.hash), bounded_query)
      or contains_plain(string.lower(commit.message), bounded_query)
    then
      out[#out + 1] = commit
    end
  end
  return out
end

M.char_count = char_count
M.truncate_text = function(text)
  return char_slice(text or "", M.MAX_NAME_CHARS)
end
M.truncate_message = function(message)
  return char_slice(message or "", M.MAX_COMMIT_MESSAGE_CHARS)
end

return M
