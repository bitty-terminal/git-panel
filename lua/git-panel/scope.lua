-- Working-tree read scope for Bitty Git Panel (bitty-terminal.git-panel).
--
-- Pure functions with no host dependency. Mirrors the former bundled Rust
-- realization (`bitty-runtime/src/git_panel.rs`, removed by `bitty`
-- CTX-0400): paths are bounded to `4096` bytes with no null or control
-- characters, and the granted read scope is exactly `~/projects/**`
-- (real-path resolved, symlinks/devices rejected per host policy). Any path
-- outside the scope fails closed via `nil`.

local M = {}

M.FS_READ_PATTERN = "~/projects/**"
M.MAX_PATH_BYTES = 4096

function M.is_valid_path(path)
  if type(path) ~= "string" then
    return false
  end
  if #path == 0 or #path > M.MAX_PATH_BYTES then
    return false
  end
  for index = 1, #path do
    local byte = string.byte(path, index)
    if byte == 0 or byte < 32 or byte == 127 then
      return false
    end
  end
  return true
end

function M.is_within_repo(path)
  if not M.is_valid_path(path) then
    return false
  end
  if path == "~/projects" or path == "~/projects/" then
    return true
  end
  if string.sub(path, 1, 11) ~= "~/projects/" then
    return false
  end
  if string.find(path, "..", 1, true) ~= nil then
    return false
  end
  return true
end

-- Alias for the repo-scope check: `candidate` must satisfy `is_within_repo`.
function M.is_fs_allowed(candidate)
  return M.is_within_repo(candidate)
end

-- Validated read scope, or `nil` when outside the grant (fail-closed).
function M.validate_read(path)
  if M.is_within_repo(path) then
    return path
  end
  return nil
end

return M
