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
  tap.ok(not scope.is_within_repo("~/projects/.."), "bare dotdot denied")
  tap.ok(not scope.is_within_repo(".."), "relative dotdot denied")
  -- R15: legit names containing two dots must stay admitted.
  tap.ok(scope.is_within_repo("~/projects/a..b"), "double dot inside name allowed")
  tap.ok(scope.is_within_repo("~/projects/backup..tar.gz"), "backup double-dot name allowed")
  tap.ok(scope.is_within_repo("~/projects/..."), "triple dot name allowed")
  tap.ok(not scope.is_within_repo(""), "empty denied")
  tap.ok(not scope.is_within_repo("~/projects/\0evil"), "null denied")

  tap.ok(scope.is_fs_allowed("~/projects/foo"), "fs allows child")
  tap.ok(not scope.is_fs_allowed("/etc/passwd"), "fs denies absolute")
  tap.ok(not scope.is_fs_allowed("~/projects/../secret"), "fs denies traversal")

  tap.ok(scope.validate_read("~/projects/foo") ~= nil, "validate_read admits child")
  tap.ok(scope.validate_read("/etc/passwd") == nil, "validate_read denies outside")
  tap.ok(scope.validate_read("~/projects/../evil") == nil, "validate_read denies traversal")

  -- H-GP-01 root helpers: repositories may live anywhere, not just under
  -- the granted prefix; validation is segment-wise against the given root.
  tap.ok(scope.is_absolute_path("/srv/git/repo"), "slash path absolute")
  tap.ok(scope.is_absolute_path("~/projects/foo"), "tilde path absolute")
  tap.ok(not scope.is_absolute_path("src/lib.rs"), "relative not absolute")
  tap.ok(not scope.is_absolute_path(""), "empty not absolute")

  tap.ok(scope.is_within_root("/srv/git/repo", "/srv/git/repo"), "root itself within")
  tap.ok(scope.is_within_root("/srv/git/repo", "/srv/git/repo/src/lib.rs"), "arbitrary root child within")
  tap.ok(scope.is_within_root("~/projects/foo", "~/projects/foo/src/lib.rs"), "grant-root child within")
  tap.ok(not scope.is_within_root("/srv/git/repo", "/srv/git/repo2/x"), "sibling prefix rejected")
  tap.ok(not scope.is_within_root("/srv/git/repo", "/srv/git/repo/../evil"), "dotdot escape rejected")
  tap.ok(not scope.is_within_root("/srv/git/repo", "/etc/passwd"), "outside rejected")

  tap.equal(scope.join_root("/srv/git/repo", "src/lib.rs"), "/srv/git/repo/src/lib.rs", "relative joins root")
  tap.equal(scope.join_root("~/projects/foo/", "README.md"), "~/projects/foo/README.md", "trailing slash root")
  tap.equal(scope.join_root("/srv/git/repo", "./src/lib.rs"), "/srv/git/repo/src/lib.rs", "dot segment normalizes")
  tap.equal(scope.join_root("/srv/git/repo", "a/../b.txt"), "/srv/git/repo/b.txt", "inner dotdot normalizes")
  tap.equal(scope.join_root("/srv/git/repo", "../evil"), nil, "escaping dotdot rejected")
  tap.equal(scope.join_root("/srv/git/repo", "../../evil"), nil, "deep escape rejected")
  tap.equal(scope.join_root("/srv/git/repo", "/etc/passwd"), nil, "absolute rel rejected")
  tap.equal(scope.join_root("/srv/git/repo", "~/projects/x"), nil, "tilde rel rejected")
  tap.equal(scope.join_root("/srv/git/repo", "."), nil, "bare dot rejected")
end

return M
