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

  -- bitty#2966: the panel scene carries the branch, bounded status rows, and
  -- bounded recent-log rows, all as v1 nodes.
  local panel = scene.panel({
    branch = "main",
    status = {
      { path = "src/lib.rs", status = "modified" },
      { path = "README.md", status = "added" },
    },
    status_total = 2,
    commits = {
      { short_hash = "abc1234", message = "fix bug" },
      { short_hash = "def5678", message = "add feature" },
    },
    commit_total = 2,
  })
  tap.ok(only_v1(panel), "panel uses v1 nodes only")
  tap.equal(panel.kind, "Column", "panel is a row stack")
  local labels = {}
  for _, child in ipairs(panel.children) do
    labels[#labels + 1] = child.text
  end
  tap.equal(labels[1], "Git Panel", "panel title first")
  tap.equal(labels[2], "Branch: main", "panel names the current branch")
  tap.equal(labels[3], "Status: 2 change(s)", "panel counts status entries")
  tap.equal(labels[4], "  modified  src/lib.rs", "panel status row")
  tap.equal(labels[5], "  added  README.md", "panel second status row")
  tap.equal(labels[6], "Recent commits: 2", "panel counts commits")
  tap.equal(labels[7], "  abc1234  fix bug", "panel log row")
  tap.equal(labels[8], "  def5678  add feature", "panel second log row")
  tap.equal(labels[9], scene.PANEL_CLOSE_HINT, "panel documents the close path")

  local detached = scene.panel({ branch = nil, status = {}, commits = {} })
  local detached_labels = {}
  for _, child in ipairs(detached.children) do
    detached_labels[#detached_labels + 1] = child.text
  end
  tap.equal(detached_labels[2], "Branch: (detached HEAD)", "detached HEAD placeholder")
  tap.ok(
    table.concat(detached_labels, "\n"):find("working tree clean", 1, true) ~= nil,
    "clean status placeholder"
  )
  tap.ok(
    table.concat(detached_labels, "\n"):find("no commits", 1, true) ~= nil,
    "empty log placeholder"
  )

  -- Bounds: the panel shows at most the declared row counts.
  local many_status = {}
  for i = 1, 50 do
    many_status[#many_status + 1] = { path = "file" .. i .. ".txt", status = "modified" }
  end
  local many_commits = {}
  for i = 1, 50 do
    many_commits[#many_commits + 1] = {
      short_hash = string.format("%07x", 0xabc000 + i),
      message = "commit " .. i,
    }
  end
  tap.equal(
    #scene.status_rows(many_status),
    scene.PANEL_MAX_STATUS_ROWS,
    "status rows bounded"
  )
  tap.equal(
    #scene.commit_rows(many_commits),
    scene.PANEL_MAX_COMMIT_ROWS,
    "commit rows bounded"
  )
  local bounded = scene.panel({
    branch = "main",
    status = many_status,
    status_total = #many_status,
    commits = many_commits,
    commit_total = #many_commits,
  })
  local bounded_text = {}
  for _, child in ipairs(bounded.children) do
    bounded_text[#bounded_text + 1] = child.text
  end
  tap.ok(
    table.concat(bounded_text, "\n"):find("... 38 more", 1, true) ~= nil,
    "status overflow is summarized"
  )
  tap.ok(
    table.concat(bounded_text, "\n"):find("... 42 more", 1, true) ~= nil,
    "commit overflow is summarized"
  )

  -- Display-only path spelling: strip the resolved root, keep foreign paths.
  tap.equal(
    scene.display_path("/srv/git/repo/src/lib.rs", "/srv/git/repo"),
    "src/lib.rs",
    "display path is repo-relative"
  )
  tap.equal(
    scene.display_path("/srv/git/repo/", "/srv/git/repo"),
    ".",
    "display path handles the root itself"
  )
  tap.equal(
    scene.display_path("/etc/passwd", "/srv/git/repo"),
    "/etc/passwd",
    "display path keeps foreign paths"
  )

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
