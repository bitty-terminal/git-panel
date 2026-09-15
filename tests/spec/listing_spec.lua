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

  local commits = listing.list_commits({
    { hash = "abc1234", message = "fix bug" },
    { hash = "def5678", message = "add feature" },
    { hash = "abc1234", message = "fix bug" },
    { hash = "zzzzzzz", message = "bad hash" },
  })
  tap.equal(#commits, 2, "commits deduped and invalid filtered")
  tap.equal(commits[1].hash, "abc1234", "commits sorted by hash")
  tap.equal(commits[1].short_hash, "abc1234", "short hash derived")

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
  tap.equal(listing.MAX_BRANCHES, 32, "MAX_BRANCHES is 32")
  tap.equal(listing.MAX_NAME_CHARS, 128, "MAX_NAME_CHARS is 128")
  tap.equal(listing.MAX_COMMIT_MESSAGE_CHARS, 256, "MAX_COMMIT_MESSAGE_CHARS is 256")
  tap.equal(listing.MAX_SELECTION, 64, "MAX_SELECTION is 64")
end

return M
