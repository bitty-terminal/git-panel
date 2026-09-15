-- Declarative scenes for Bitty Git Panel (bitty-terminal.git-panel).
--
-- Pure builders producing Plugin API v1 declarative components only
-- (`Text`, `Row`, `Column`, `List`, depth `16`) for branch, status, diff,
-- and log presentation. No host dependency, no I/O. The host mounts the
-- returned component in the panel surface owned by the `panel.provider`
-- registration; this module never touches PTY bytes, the grid, or the
-- render/input hot paths. Text truncates to the overlay text bound (`128`)
-- and commit messages to the tooltip bound (`256`).

local listing = require("git-panel.listing")

local M = {}

local function text(value)
  return { kind = "Text", text = value }
end

-- Empty panel placeholder.
function M.empty()
  return { kind = "Column", children = { text("No git data.") } }
end

-- Bounded branch rows for command results and tests: `{ label, current }`
-- with labels truncated to the overlay text bound plus a current marker.
function M.branch_rows(branches, max_rows)
  local rows = {}
  local limit = max_rows or listing.MAX_SELECTION
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

-- Status presentation as a v1 `List` of `path (status)` rows, bounded to
-- the entry cap.
function M.status(entries)
  local children = {}
  for index, entry in ipairs(entries or {}) do
    if index > listing.MAX_ENTRIES then
      break
    end
    children[#children + 1] = text(
      listing.truncate_text(entry.path or "") .. " (" .. tostring(entry.status or "?") .. ")"
    )
  end
  if #children == 0 then
    return M.empty()
  end
  return { kind = "List", children = children }
end

-- Log presentation as a v1 `List` of `short-hash message` rows, bounded to
-- the commit cap with messages at the tooltip bound.
function M.log(commits)
  local children = {}
  for index, commit in ipairs(commits or {}) do
    if index > listing.MAX_COMMITS then
      break
    end
    local message = listing.truncate_message(commit.message or "")
    children[#children + 1] = text(tostring(commit.short_hash or commit.hash or "?") .. " " .. message)
  end
  if #children == 0 then
    return M.empty()
  end
  return { kind = "List", children = children }
end

-- Diff presentation as a v1 `List` of bounded text lines.
function M.diff(lines)
  local children = {}
  for index, line in ipairs(lines or {}) do
    if index > listing.MAX_ENTRIES then
      break
    end
    children[#children + 1] = text(listing.truncate_text(tostring(line)))
  end
  if #children == 0 then
    return M.empty()
  end
  return { kind = "List", children = children }
end

return M
