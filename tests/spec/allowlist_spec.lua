-- Behavior spec for the git-panel spawn allowlist.
--
-- TDD red step: this spec fails until `lua/git-panel/allowlist.lua` exists.
-- Run from the package root: `lua5.4 tests/run.lua`.

local M = {}

function M.run(context)
  local tap = context.tap
  local allowlist = require("git-panel.allowlist")

  tap.equal(#allowlist.ALLOWED_SUBCOMMANDS, 7, "exactly seven read-only verbs")
  for _, verb in ipairs({ "status", "diff", "log", "branch", "show", "rev-parse", "ls-files" }) do
    tap.ok(allowlist.is_allowed_subcommand(verb), "admits " .. verb)
  end
  for _, verb in ipairs({ "commit", "push", "reset", "checkout", "fetch", "clone", "add", "remote" }) do
    tap.ok(not allowlist.is_allowed_subcommand(verb), "denies write verb " .. verb)
  end

  tap.ok(allowlist.is_allowed_args({ "status", "--porcelain" }), "status --porcelain")
  tap.ok(allowlist.is_allowed_args({ "diff", "--stat" }), "diff --stat")
  tap.ok(allowlist.is_allowed_args({ "log", "--oneline", "-n", "10" }), "log --oneline -n 10")
  tap.ok(allowlist.is_allowed_args({ "branch", "-a" }), "branch -a")
  tap.ok(allowlist.is_allowed_args({ "show", "abc1234" }), "show hash")
  tap.ok(allowlist.is_allowed_args({ "rev-parse", "--abbrev-ref", "HEAD" }), "rev-parse HEAD")
  tap.ok(allowlist.is_allowed_args({ "ls-files", "--others" }), "ls-files --others")

  tap.ok(not allowlist.is_allowed_args({ "push" }), "denies push")
  tap.ok(not allowlist.is_allowed_args({ "commit" }), "denies commit")
  tap.ok(not allowlist.is_allowed_args({ "checkout" }), "denies checkout")
  tap.ok(not allowlist.is_allowed_args({ "fetch" }), "denies fetch")
  tap.ok(not allowlist.is_allowed_args({}), "denies empty args")

  local many = { "status" }
  for i = 1, allowlist.MAX_ARGS + 1 do
    many[#many + 1] = "arg" .. i
  end
  tap.ok(not allowlist.is_allowed_args(many), "denies more than MAX_ARGS")

  tap.ok(not allowlist.is_allowed_args({ "status", "; rm -rf /" }), "denies semicolon")
  tap.ok(not allowlist.is_allowed_args({ "log", "$(evil)" }), "denies dollar-paren")
  tap.ok(not allowlist.is_allowed_args({ "diff", "`evil`" }), "denies backtick")
  tap.ok(not allowlist.is_allowed_args({ "status", "a&b" }), "denies ampersand")
  tap.ok(not allowlist.is_allowed_args({ "status", "a|b" }), "denies pipe")
  tap.ok(not allowlist.is_allowed_args({ "status", "a\7b" }), "denies control char")
  tap.ok(not allowlist.is_allowed_args({ "status", "--upload-pack=evil" }), "denies upload-pack=")
  tap.ok(not allowlist.is_allowed_args({ "status", "--upload-pack" }), "denies upload-pack")
  tap.ok(not allowlist.is_allowed_args({ "log", "--receive-pack", "x" }), "denies receive-pack")
  tap.ok(not allowlist.is_allowed_args({ "log", "--exec", "x" }), "denies exec flag")
  tap.ok(not allowlist.is_allowed_args({ "status", "--output=/tmp/out" }), "denies output path")
  tap.ok(not allowlist.is_allowed_args({ "diff", "--output=evil" }), "denies diff output")
  tap.ok(not allowlist.is_allowed_args({ "status", "--index-file=/tmp/index" }), "denies index-file")
  tap.ok(not allowlist.is_allowed_args({ "log", "--work-tree=/tmp/wt" }), "denies work-tree")
  tap.ok(not allowlist.is_allowed_args({ "show", "--git-dir=/tmp/gd" }), "denies git-dir")
  tap.ok(not allowlist.is_allowed_args({ "diff", "--ext-diff" }), "denies ext-diff")
  tap.ok(not allowlist.is_allowed_args({ "diff", "--textconv" }), "denies textconv")
  tap.ok(not allowlist.is_allowed_args({ "log", "-o", "evil" }), "denies short output flag")

  local long_arg = string.rep("a", allowlist.MAX_ARG_BYTES + 1)
  tap.ok(not allowlist.is_allowed_args({ "status", long_arg }), "denies overlong arg")

  tap.ok(allowlist.is_allowed_command_str("status --porcelain"), "command string admitted")
  tap.ok(allowlist.is_allowed_command_str("log --oneline -n 10"), "log command string admitted")
  tap.ok(not allowlist.is_allowed_command_str("push origin main"), "push string denied")
  tap.ok(not allowlist.is_allowed_command_str(""), "empty string denied")
  tap.ok(not allowlist.is_allowed_command_str("status; rm -rf /"), "metachar string denied")

  tap.ok(allowlist.is_process_spawn_git_allowed("process.spawn:git"), "exact capability admitted")
  tap.ok(not allowlist.is_process_spawn_git_allowed("process.spawn:rg"), "other tool denied")
  tap.ok(not allowlist.is_process_spawn_git_allowed("process.spawn"), "bare family denied")
  tap.ok(not allowlist.is_process_spawn_git_allowed("fs.read:~/projects/**"), "fs scope denied")

  tap.equal(allowlist.MAX_ARGS, 32, "MAX_ARGS is 32")
  tap.equal(allowlist.MAX_ARG_BYTES, 256, "MAX_ARG_BYTES is 256")
  tap.equal(allowlist.MAX_TOTAL_BYTES, 8192, "MAX_TOTAL_BYTES is 8 KiB")
end

return M
