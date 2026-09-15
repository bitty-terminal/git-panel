-- Behavior spec for the git-panel bounded listings.
--
-- Run from the package root: `lua5.4 tests/run.lua`.

local M = {}

function M.run(context)
  local tap = context.tap
  local listing = require("git-panel.listing")

  tap.ok(listing.is_valid_branch_name("main"), "main is valid")
  tap.ok(listing.is_valid_branch_name("feature/foo-bar"), "feature branch valid")
  tap.ok(listing.is_valid_branch_name("release-1.0"), "release branch valid")
  tap.ok(listing.is_valid_branch_name("user@host"), "embedded at without brace valid")
  tap.ok(not listing.is_valid_branch_name(""), "empty invalid")
  tap.ok(not listing.is_valid_branch_name("a/b/../c"), "dotdot invalid")
  tap.ok(not listing.is_valid_branch_name("bad~name"), "tilde invalid")
  tap.ok(not listing.is_valid_branch_name("bad^name"), "caret invalid")
  tap.ok(not listing.is_valid_branch_name("bad:name"), "colon invalid")
  tap.ok(not listing.is_valid_branch_name("bad?glob"), "question invalid")
  tap.ok(not listing.is_valid_branch_name("bad*glob"), "star invalid")
  tap.ok(not listing.is_valid_branch_name(".hidden"), "leading dot invalid")
  tap.ok(not listing.is_valid_branch_name("trailing/"), "trailing slash invalid")
  tap.ok(not listing.is_valid_branch_name("double//slash"), "double slash invalid")
  tap.ok(not listing.is_valid_branch_name("evil;rm -rf"), "semicolon invalid")
  tap.ok(not listing.is_valid_branch_name("bad\0evil"), "null invalid")
  -- R30 (simplified `git check-ref-format`): reflog `@{` sequences, a lone
  -- `@`, and a leading `-` are rejected.
  tap.ok(not listing.is_valid_branch_name("foo@{0}"), "at-brace reflog invalid")
  tap.ok(not listing.is_valid_branch_name("@{"), "bare at-brace invalid")
  tap.ok(not listing.is_valid_branch_name("@"), "lone at invalid")
  tap.ok(not listing.is_valid_branch_name("-main"), "leading dash invalid")
  tap.ok(not listing.is_valid_branch_name("-"), "lone dash invalid")

  tap.ok(listing.is_valid_commit_hash("abc1234"), "short hash valid")
  tap.ok(listing.is_valid_commit_hash("abcdef1234567890abcdef1234567890abcdef12"), "full hash valid")
  tap.ok(not listing.is_valid_commit_hash("abc"), "too short invalid")
  tap.ok(not listing.is_valid_commit_hash("zzzzzzz"), "non-hex invalid")
  tap.ok(not listing.is_valid_commit_hash(""), "empty invalid")

  local branches = listing.list_branches({ "main", "* main", "feature/foo", "main", "bad..branch", "" })
  tap.equal(#branches, 2, "branches deduped and invalid filtered")
  tap.equal(branches[1].name, "feature/foo", "branches sorted")
  tap.equal(branches[2].name, "main", "main second")
  tap.ok(branches[2].is_current, "current tracked")

  local many = {}
  for i = 1, 50 do
    many[#many + 1] = "branch" .. i
  end
  tap.equal(#listing.list_branches(many), listing.MAX_BRANCHES, "branches bounded at 32")

  local filtered = listing.filter_branches(branches, "feature")
  tap.equal(#filtered, 1, "branch filter matches")
  tap.equal(#listing.filter_branches(branches, "FEATURE"), 1, "branch filter case-insensitive")
  tap.equal(#listing.filter_branches(branches, ""), 2, "empty query returns all")

  local status = listing.list_status_entries(
    { "~/projects/foo.txt", "~/projects/bar.rs", "~/projects/foo.txt", "/etc/passwd" },
    "modified"
  )
  tap.equal(#status, 2, "status deduped and scoped")
  tap.equal(status[1].path, "~/projects/bar.rs", "status sorted")
  tap.equal(status[1].status, "modified", "status carried")

  local many_status = {}
  for i = 1, 200 do
    many_status[#many_status + 1] = "~/projects/file" .. i .. ".txt"
  end
  tap.equal(#listing.list_status_entries(many_status, "modified"), listing.MAX_ENTRIES, "status bounded at 128")
  tap.equal(#listing.filter_status_entries(status, "foo"), 1, "status filter matches")

  -- H-GP-01: repo-root-relative paths resolve against the given root,
  -- including roots outside the granted prefix; without a root they drop.
  local rooted = listing.list_status_entries({ "src/lib.rs", "README.md" }, "modified", {
    root = "~/projects/foo",
  })
  tap.equal(#rooted, 2, "relative paths resolve against root")
  tap.equal(rooted[1].path, "~/projects/foo/README.md", "resolved path sorted first")
  tap.equal(rooted[2].path, "~/projects/foo/src/lib.rs", "resolved path joined")
  local anywhere = listing.list_status_entries({ "src/lib.rs" }, "modified", { root = "/srv/git/repo" })
  tap.equal(#anywhere, 1, "arbitrary root supported")
  tap.equal(anywhere[1].path, "/srv/git/repo/src/lib.rs", "arbitrary root joined")
  tap.equal(#listing.list_status_entries({ "../evil", "/etc/passwd" }, "modified", { root = "/srv/git/repo" }), 0, "escape and outside dropped")
  tap.equal(#listing.list_status_entries({ "src/lib.rs" }, "modified"), 0, "relative without root dropped")
  tap.equal(#listing.list_status_entries({ "src/lib.rs" }, "modified", { root = "../evil" }), 0, "traversal root dropped")

  -- R19: `git log` reverse-chronological input order is preserved; no
  -- hash re-sort. The input here is deliberately not hash-sorted.
  local commits = listing.list_commits({
    { hash = "def5678", message = "add feature" },
    { hash = "abc1234", message = "fix bug" },
    { hash = "def5678", message = "add feature" },
    { hash = "zzzzzzz", message = "bad hash" },
  })
  tap.equal(#commits, 2, "commits deduped and invalid filtered")
  tap.equal(commits[1].hash, "def5678", "input order preserved, not hash-sorted")
  tap.equal(commits[2].hash, "abc1234", "second input second")
  tap.equal(commits[1].short_hash, "def5678", "short hash derived")
  local sorted_view = listing.sorted_commits_by_hash(commits)
  tap.equal(sorted_view[1].hash, "abc1234", "sorted view orders by hash")
  tap.equal(commits[1].hash, "def5678", "sorted view leaves input order alone")

  local many_commits = {}
  for i = 1, 100 do
    many_commits[#many_commits + 1] = { hash = string.format("%07x", 0xabc000 + i), message = "commit " .. i }
  end
  tap.equal(#listing.list_commits(many_commits), listing.MAX_COMMITS, "commits bounded at 64")
  tap.equal(#listing.filter_commits(commits, "fix"), 1, "commit filter matches message")
  tap.equal(#listing.filter_commits(commits, "abc"), 1, "commit filter matches hash")
  tap.equal(#listing.filter_commits(commits, "FIX"), 1, "commit filter case-insensitive")

  tap.equal(listing.MAX_ENTRIES, 128, "MAX_ENTRIES is 128")
  tap.equal(listing.MAX_COMMITS, 64, "MAX_COMMITS is 64")
  -- R30: one branch bound for ingestion and presentation.
  tap.equal(listing.MAX_BRANCHES, 32, "MAX_BRANCHES is 32")
  tap.equal(listing.MAX_SELECTION, nil, "MAX_SELECTION removed")
  tap.equal(listing.MAX_NAME_CHARS, 128, "MAX_NAME_CHARS is 128")
  tap.equal(listing.MAX_COMMIT_MESSAGE_CHARS, 256, "MAX_COMMIT_MESSAGE_CHARS is 256")
end

return M
