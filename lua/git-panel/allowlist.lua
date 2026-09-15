-- Allowlisted `git` spawn policy for Bitty Git Panel
-- (bitty-terminal.git-panel).
--
-- Pure functions with no host dependency, so the spawn policy is unit
-- testable in plain Lua. The verbs and bounds mirror the former bundled Rust
-- realization (`bitty-runtime/src/git_panel.rs`, removed by `bitty` CTX-0400):
-- exactly the seven read-only verbs of the accepted Layer 2 `[tools.git]`
-- slice (CTX-0425), at most `32` args of at most `256` bytes each with at
-- most `8 KiB` total, no null/control characters, no shell metacharacters,
-- and default-deny for `-`-leading flags (only the read-only
-- `ALLOWED_FLAGS` table passes, with explicit risky-flag blocks kept for
-- clarity). Anything else fails closed.
--
-- Capability string is exactly `process.spawn:git`: the closed
-- `process.spawn` family plus the `:git` parameter. Spawn goes through the
-- host-provided surface only, never through `os.execute`, `io.popen`, or a
-- Lua-loaded native module (denied by the Lua Runtime restricted library).
-- Outputs are piped to panel UI, never raw PTY injection.

local M = {}

M.PROCESS_SPAWN_GIT = "process.spawn:git"

M.ALLOWED_SUBCOMMANDS = {
  "status",
  "diff",
  "log",
  "branch",
  "show",
  "rev-parse",
  "ls-files",
}

M.MAX_ARGS = 32
M.MAX_ARG_BYTES = 256
M.MAX_TOTAL_BYTES = 8192

-- Read-only flags the plugin actually uses: every `-`-leading string passed
-- to `spawn_git` (`status --porcelain`, `branch -a`, `log --oneline -n 10`,
-- `diff --stat`) plus the read-only shapes the spec covers for the remaining
-- verbs (`rev-parse --abbrev-ref`, `ls-files --others`). Everything else
-- starting with `-` fails closed, which blocks read-to-write escapes such as
-- `--output`, `--index-file`, `--work-tree`, `--git-dir`, `-o`,
-- `--ext-diff`, and `--textconv`.
M.ALLOWED_FLAGS = {
  "--porcelain",
  "--stat",
  "--oneline",
  "-n",
  "-a",
  "--others",
  "--abbrev-ref",
}

local ALLOWED_FLAG_SET = {}
for _, flag in ipairs(M.ALLOWED_FLAGS) do
  ALLOWED_FLAG_SET[flag] = true
end

local RISKY_FLAGS = {
  ["--upload-pack"] = true,
  ["--receive-pack"] = true,
  ["--exec"] = true,
}

local function is_allowed_subcommand(sub)
  for _, allowed in ipairs(M.ALLOWED_SUBCOMMANDS) do
    if sub == allowed then
      return true
    end
  end
  return false
end

M.is_allowed_subcommand = is_allowed_subcommand

local function has_denied_byte(arg)
  for index = 1, #arg do
    local byte = string.byte(arg, index)
    if byte == 0 or byte < 32 or byte == 127 then
      return true
    end
    local char = string.sub(arg, index, index)
    if
      char == ";"
      or char == "&"
      or char == "|"
      or char == "`"
      or char == "$"
      or char == "("
      or char == ")"
      or char == "<"
      or char == ">"
      or char == "\\"
      or char == '"'
      or char == "'"
    then
      return true
    end
  end
  return false
end

local function is_risky_flag(arg)
  if RISKY_FLAGS[arg] then
    return true
  end
  if string.sub(arg, 1, 14) == "--upload-pack=" then
    return true
  end
  if string.sub(arg, 1, 15) == "--receive-pack=" then
    return true
  end
  return false
end

-- Default-deny for `-`-leading flags: only the read-only `ALLOWED_FLAGS`
-- table passes. Non-flag operands (hashes, `HEAD`, counts such as the `10`
-- in `log --oneline -n 10`) never reach this branch.
local function is_unknown_flag(arg)
  return string.sub(arg, 1, 1) == "-" and not ALLOWED_FLAG_SET[arg]
end

-- Dense-sequence check: every key must be a positive integer contiguous
-- from `1` with no holes and every member a string; returns the element
-- count, or `nil` when `args` is sparse, non-sequence, or non-string.
-- `ipairs` (and `#`) stop at or straddle the first `nil`, so a sequence
-- such as `{ "status", nil, "--output" }` would otherwise skip the denied
-- trailing flag and pass. `pairs` plus `rawget` close that hole.
local function dense_string_count(args)
  local count = 0
  for key in pairs(args) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return nil
    end
    count = count + 1
  end
  for index = 1, count do
    if type(rawget(args, index)) ~= "string" then
      return nil
    end
  end
  return count
end

-- Whether `args` is an allowlisted `git` invocation under `[tools.git]`.
-- Fails closed: non-table, empty, sparse/non-string, over-count, over-long,
-- over-total, denied bytes, non-allowlisted first-arg subcommand, risky
-- flags, or any other `-`-leading flag all deny.
function M.is_allowed_args(args)
  if type(args) ~= "table" then
    return false
  end
  local count = dense_string_count(args)
  if count == nil or count == 0 or count > M.MAX_ARGS then
    return false
  end
  local total = 0
  for index = 1, count do
    local arg = args[index]
    if #arg == 0 then
      return false
    end
    if #arg > M.MAX_ARG_BYTES then
      return false
    end
    total = total + #arg
    if total > M.MAX_TOTAL_BYTES then
      return false
    end
    if has_denied_byte(arg) then
      return false
    end
  end
  if not is_allowed_subcommand(args[1]) then
    return false
  end
  for index = 1, count do
    local arg = args[index]
    if is_risky_flag(arg) then
      return false
    end
    if is_unknown_flag(arg) then
      return false
    end
  end
  return true
end

-- Whether `command_str` (space-separated `git` args) is allowlisted.
-- Splits on whitespace and delegates to `is_allowed_args`.
function M.is_allowed_command_str(command_str)
  if type(command_str) ~= "string" then
    return false
  end
  if #command_str == 0 or #command_str > M.MAX_TOTAL_BYTES then
    return false
  end
  local args = {}
  for token in string.gmatch(command_str, "%S+") do
    args[#args + 1] = token
  end
  return M.is_allowed_args(args)
end

-- Whether `capability` is exactly the allowlisted spawn capability.
function M.is_process_spawn_git_allowed(capability)
  return capability == M.PROCESS_SPAWN_GIT
end

return M
