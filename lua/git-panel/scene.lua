-- Declarative scenes for Bitty Git Panel (bitty-terminal.git-panel).
--
-- Pure builders producing Plugin API v1 declarative components only
-- (`Text`, `Row`, `Column`, `List`, depth `16`). No host dependency, no I/O.
-- The host presents the returned component through the W-01 focusable overlay
-- session (`bitty.ui.overlay.update`); this module never touches PTY bytes,
-- the grid, or the render/input hot paths. Text truncates to the listing
-- name/message bounds (`128`/`256` code points).
--
-- The overlay host stacks a `Column`/`List` root's direct children as rows, so
-- `panel` returns one `Text` child per displayed line.

local listing = require("git-panel.listing")

local M = {}

M.PANEL_TITLE = "Git Panel"
M.PANEL_MAX_STATUS_ROWS = 12
M.PANEL_MAX_COMMIT_ROWS = 8
M.PANEL_CLOSE_HINT = "Esc closes"

local function text(value)
  return { kind = "Text", text = value }
end

-- Empty panel placeholder.
function M.empty()
  return { kind = "Column", children = { text("No git data.") } }
end

-- Bounded branch rows for command results and tests: `{ label, current }`
-- with labels truncated to the listing name bound plus a current marker.
-- R30: bounded by the single branch bound (`MAX_BRANCHES`); the listing
-- ingests at most that many branches, so a wider presentation window could
-- never fill.
function M.branch_rows(branches, max_rows)
  local rows = {}
  local limit = max_rows or listing.MAX_BRANCHES
  for _, branch in ipairs(branches or {}) do
    if #rows >= limit then
      break
    end
    local label = listing.truncate_text(branch.name or "")
    if branch.is_current then
      label = "* " .. label
    else
      label = "  " .. label
    end
    rows[#rows + 1] = { label = label, current = branch.is_current == true }
  end
  return rows
end

-- Branch presentation as a v1 `List` of `Text` rows.
function M.branches(branches)
  local children = {}
  for _, row in ipairs(M.branch_rows(branches, listing.MAX_BRANCHES)) do
    children[#children + 1] = text(row.label)
  end
  if #children == 0 then
    return M.empty()
  end
  return { kind = "List", children = children }
end

-- Display-only repository-relative spelling of a resolved status path. The
-- status command keeps the host-absolute form for scope checks; the panel
-- shows the path relative to the resolved repository root.
function M.display_path(path, root)
  if type(path) ~= "string" then
    return ""
  end
  if type(root) ~= "string" or root == "" then
    return path
  end
  local base = string.gsub(root, "/+$", "")
  if base == "" then
    return path
  end
  if path == base then
    return "."
  end
  if string.sub(path, 1, #base + 1) == base .. "/" then
    local rest = string.sub(path, #base + 2)
    if rest == "" then
      return "."
    end
    return rest
  end
  return path
end

-- Bounded status rows: `{ label, status }` with `status  path`.
function M.status_rows(entries, max_rows)
  local rows = {}
  local limit = max_rows or M.PANEL_MAX_STATUS_ROWS
  for _, entry in ipairs(entries or {}) do
    if #rows >= limit then
      break
    end
    local status = entry.status or "changed"
    local path = listing.truncate_text(entry.path or "")
    rows[#rows + 1] = { label = status .. "  " .. path, status = status }
  end
  return rows
end

-- Bounded commit rows: `{ label, short_hash }` with `short_hash  message`.
function M.commit_rows(commits, max_rows)
  local rows = {}
  local limit = max_rows or M.PANEL_MAX_COMMIT_ROWS
  for _, commit in ipairs(commits or {}) do
    if #rows >= limit then
      break
    end
    local hash = commit.short_hash or ""
    local message = listing.truncate_message(commit.message or "")
    rows[#rows + 1] = { label = hash .. "  " .. message, short_hash = hash }
  end
  return rows
end

-- Full panel scene: title, current branch, bounded status rows, bounded
-- recent-log rows, and the close hint. `state` carries already-derived data:
-- `branch`, `status` (display paths), `status_total`, `commits`,
-- `commit_total`, and optional row bounds.
function M.panel(state)
  state = state or {}
  local lines = {}
  local function add(value)
    lines[#lines + 1] = text(value)
  end

  local status = state.status or {}
  local status_total = state.status_total or #status
  local commits = state.commits or {}
  local commit_total = state.commit_total or #commits

  add(M.PANEL_TITLE)
  add("Branch: " .. (state.branch or "(detached HEAD)"))
  add(string.format("Status: %d change(s)", status_total))
  local status_rows = M.status_rows(status, state.max_status_rows)
  if #status_rows == 0 then
    add("  working tree clean")
  end
  for _, row in ipairs(status_rows) do
    add("  " .. row.label)
  end
  if status_total > #status_rows then
    add(string.format("  ... %d more", status_total - #status_rows))
  end

  add(string.format("Recent commits: %d", commit_total))
  local commit_rows = M.commit_rows(commits, state.max_commit_rows)
  if #commit_rows == 0 then
    add("  no commits")
  end
  for _, row in ipairs(commit_rows) do
    add("  " .. row.label)
  end
  if commit_total > #commit_rows then
    add(string.format("  ... %d more", commit_total - #commit_rows))
  end

  add(M.PANEL_CLOSE_HINT)
  return { kind = "Column", children = lines }
end

return M
