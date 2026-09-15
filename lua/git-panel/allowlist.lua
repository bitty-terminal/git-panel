-- Allowlisted `git` spawn policy for Bitty Git Panel
-- (bitty-terminal.git-panel).
--
-- Pure functions with no host dependency, so the spawn policy is unit
-- testable in plain Lua. The verbs and bounds mirror the former bundled Rust
-- realization (`bitty-runtime/src/git_panel.rs`, removed by `bitty` CTX-0400):
-- exactly the seven read-only verbs of the accepted Layer 2 `[tools.git]`
-- slice (CTX-0425), at most `32` args of at most `256` bytes each with at
-- most `8 KiB` total, no null/control characters, no shell metacharacters,
-- and no risky flags. Anything else fails closed.
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

-- Whether `args` is an allowlisted `git` invocation under `[tools.git]`.
-- Fails closed: empty, over-count, over-long, over-total, denied bytes,
-- non-allowlisted first-arg subcommand, or risky flags all deny.
function M.is_allowed_args(args)
  if type(args) ~= "table" or #args == 0 then
    return false
  end
  if #args > M.MAX_ARGS then
    return false
  end
  local total = 0
  for _, arg in ipairs(args) do
    if type(arg) ~= "string" or #arg == 0 then
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
  for _, arg in ipairs(args) do
    if is_risky_flag(arg) then
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
