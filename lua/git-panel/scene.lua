-- Declarative scenes for Bitty Git Panel (bitty-terminal.git-panel).
--
-- Pure builders producing Plugin API v1 declarative components only
-- (`Text`, `Row`, `Column`, `List`, depth `16`) for branch presentation.
-- No host dependency, no I/O. The host mounts the returned component in
-- the panel surface owned by the `panel.provider` registration; this
-- module never touches PTY bytes, the grid, or the render/input hot
-- paths. Text truncates to the overlay text bound (`128`).
--
-- M-GP-05: only the branch path lives here. The status, log, and diff
-- presenters were dead code (never imported by init.lua) and were removed;
-- their presentation wiring lands in a follow-up once the panel mount
-- surface exists.

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

-- M-GP-05: status presenter removed as dead code; status presentation wiring lands in a follow-up once the panel mount surface exists.

-- M-GP-05: log presenter removed as dead code; log presentation wiring lands in a follow-up once the panel mount surface exists.

-- M-GP-05: diff presenter removed as dead code; diff presentation wiring lands in a follow-up once the panel mount surface exists.

return M
