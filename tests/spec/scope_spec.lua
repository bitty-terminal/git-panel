-- Behavior spec for the git-panel working-tree read scope.
--
-- Run from the package root: `lua5.4 tests/run.lua`.

local M = {}

function M.run(context)
  local tap = context.tap
  local scope = require("git-panel.scope")

  tap.equal(scope.FS_READ_PATTERN, "~/projects/**", "read pattern pins ~/projects/**")
  tap.ok(scope.is_valid_path("~/projects/foo"), "valid path")
  tap.ok(not scope.is_valid_path(""), "empty path invalid")
  tap.ok(not scope.is_valid_path("~/projects/\0evil"), "null byte invalid")
  tap.ok(not scope.is_valid_path("~/projects/foo\7"), "control char invalid")
  local long = "~/projects/" .. string.rep("a", 5000)
  tap.ok(not scope.is_valid_path(long), "overlong path invalid")

  tap.ok(scope.is_within_repo("~/projects"), "repo root itself")
  tap.ok(scope.is_within_repo("~/projects/"), "repo root with slash")
  tap.ok(scope.is_within_repo("~/projects/foo"), "child path")
  tap.ok(scope.is_within_repo("~/projects/foo/bar"), "nested path")
  tap.ok(not scope.is_within_repo("~/Documents/foo"), "outside root denied")
  tap.ok(not scope.is_within_repo("/home/user/projects/foo"), "absolute denied")
  tap.ok(not scope.is_within_repo("~/projects/../etc/passwd"), "traversal denied")
  tap.ok(not scope.is_within_repo("~/projects/foo/../bar"), "inner traversal denied")
  tap.ok(not scope.is_within_repo(""), "empty denied")
  tap.ok(not scope.is_within_repo("~/projects/\0evil"), "null denied")

  tap.ok(scope.is_fs_allowed("~/projects/foo"), "fs allows child")
  tap.ok(not scope.is_fs_allowed("/etc/passwd"), "fs denies absolute")
  tap.ok(not scope.is_fs_allowed("~/projects/../secret"), "fs denies traversal")

  tap.ok(scope.validate_read("~/projects/foo") ~= nil, "validate_read admits child")
  tap.ok(scope.validate_read("/etc/passwd") == nil, "validate_read denies outside")
  tap.ok(scope.validate_read("~/projects/../evil") == nil, "validate_read denies traversal")
end

return M
