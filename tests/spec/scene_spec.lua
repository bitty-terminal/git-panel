-- Behavior spec for the git-panel declarative scenes.
--
-- Run from the package root: `lua5.4 tests/run.lua`.

local M = {}

local function kinds(node, out)
  out = out or {}
  if type(node) ~= "table" then
    return out
  end
  if type(node.kind) == "string" then
    out[#out + 1] = node.kind
  end
  if type(node.children) == "table" then
    for _, child in ipairs(node.children) do
      kinds(child, out)
    end
  end
  return out
end

local function only_v1(node)
  for _, kind in ipairs(kinds(node)) do
    if kind ~= "Text" and kind ~= "Row" and kind ~= "Column" and kind ~= "List" then
      return false
    end
  end
  return true
end

function M.run(context)
  local tap = context.tap
  local scene = require("git-panel.scene")
  local listing = require("git-panel.listing")

  tap.ok(only_v1(scene.empty()), "empty uses v1 nodes only")

  local branches = {
    { name = "feature/foo", is_current = false },
    { name = "main", is_current = true },
  }
  local branch_scene = scene.branches(branches)
  tap.ok(only_v1(branch_scene), "branch scene uses v1 nodes only")

  local rows = scene.branch_rows(branches)
  tap.equal(#rows, 2, "two branch rows")
  tap.ok(rows[2].current, "current flagged on main")

  local long = string.rep("b", 200)
  local truncated = scene.branch_rows({ { name = long, is_current = false } })
  tap.ok(#truncated[1].label <= 128 + 8, "long branch label truncated near bound")

  -- M-GP-05: only the branch presentation path lives in scene.lua; the
  -- status, log, and diff presenters were removed as dead code.
  tap.equal(scene.status, nil, "status presenter removed")
  tap.equal(scene.log, nil, "log presenter removed")
  tap.equal(scene.diff, nil, "diff presenter removed")

  -- R30: the single branch bound pins both entries at 32.
  tap.equal(listing.MAX_BRANCHES, 32, "single branch bound is 32")
  local many = {}
  for i = 1, 50 do
    many[#many + 1] = { name = "branch" .. i, is_current = false }
  end
  tap.equal(#scene.branch_rows(many), 32, "branch rows default bounded at 32")
  tap.equal(#scene.branches(many).children, 32, "branch scene bounded at 32")
end

return M
