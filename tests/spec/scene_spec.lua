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

  tap.ok(only_v1(scene.empty()), "empty uses v1 nodes only")

  local branches = {
    { name = "feature/foo", is_current = false },
    { name = "main", is_current = true },
  }
  local branch_scene = scene.branches(branches)
  tap.ok(only_v1(branch_scene), "branch scene uses v1 nodes only")

  local status = {
    { path = "~/projects/bar.rs", status = "modified" },
    { path = "~/projects/foo.txt", status = "added" },
  }
  tap.ok(only_v1(scene.status(status)), "status scene uses v1 nodes only")

  local commits = {
    { hash = "abc1234", short_hash = "abc1234", message = "fix bug" },
    { hash = "def5678", short_hash = "def5678", message = "add feature" },
  }
  tap.ok(only_v1(scene.log(commits)), "log scene uses v1 nodes only")
  tap.ok(only_v1(scene.diff({ "-old", "+new" })), "diff scene uses v1 nodes only")

  local rows = scene.branch_rows(branches, 64)
  tap.equal(#rows, 2, "two branch rows")
  tap.ok(rows[2].current, "current flagged on main")

  local long = string.rep("b", 200)
  local truncated = scene.branch_rows({ { name = long, is_current = false } }, 64)
  tap.ok(#truncated[1].label <= 128 + 8, "long branch label truncated near bound")
end

return M
