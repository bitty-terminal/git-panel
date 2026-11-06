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
  -- R15: reject only exact `..` segments so legit names containing two
  -- dots (`a..b`, `backup..tar.gz`) stay admitted while `..`, `../x`,
  -- and `x/../y` traversal stays denied.
  for segment in string.gmatch(path, "[^/]+") do
    if segment == ".." then
      return false
    end
  end
  return true
end

-- Alias for the repo-scope check: `candidate` must satisfy `is_within_repo`.
function M.is_fs_allowed(candidate)
  return M.is_within_repo(candidate)
end

-- True for host-absolute paths (`/...`, `~/...`). Everything else is
-- repo-root-relative per the H-GP-01 definition: `git status --porcelain`
-- emits paths relative to the repository root.
function M.is_absolute_path(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local first = string.sub(path, 1, 1)
  return first == "/" or first == "~"
end

-- True when `candidate` equals `root` or nests strictly under it. The
-- boundary is segment-wise (`root .. "/"`), so a sibling such as
-- `<root>2/x` never prefix-matches, and any `..` segment fails closed.
-- Unlike `is_within_repo`, the root is a parameter, so repositories rooted
-- anywhere (not just the `~/projects/` grant prefix) are supported.
function M.is_within_root(root, candidate)
  if not M.is_valid_path(root) or not M.is_valid_path(candidate) then
    return false
  end
  local base = string.gsub(root, "/+$", "")
  if base == "" then
    base = "/"
  end
  for segment in string.gmatch(base, "[^/]+") do
    if segment == ".." then
      return false
    end
  end
  if candidate == base then
    return true
  end
  if string.sub(candidate, 1, #base) ~= base then
    return false
  end
  if string.sub(candidate, #base + 1, #base + 1) ~= "/" then
    return false
  end
  for segment in string.gmatch(candidate, "[^/]+") do
    if segment == ".." then
      return false
    end
  end
  return true
end

-- Join repo-root-relative `rel` onto `root` (H-GP-01: relative means
-- relative to the repository root). Returns the joined path, or `nil`
-- fail-closed when either side is invalid, `rel` is absolute, or `..`
-- would escape `root` (`.` segments normalize away). A `rel` resolving
-- to the root itself (`.`, empty segments) also yields `nil`: a status
-- entry must name a path under the root.
function M.join_root(root, rel)
  if not M.is_valid_path(root) or not M.is_valid_path(rel) then
    return nil
  end
  if M.is_absolute_path(rel) then
    return nil
  end
  local base = string.gsub(root, "/+$", "")
  if base == "" then
    base = "/"
  end
  for segment in string.gmatch(base, "[^/]+") do
    if segment == ".." then
      return nil
    end
  end
  local parts = {}
  for segment in string.gmatch(rel, "[^/]+") do
    if segment == "." then
      -- normalize away
    elseif segment == ".." then
      if #parts == 0 then
        return nil
      end
      parts[#parts] = nil
    else
      parts[#parts + 1] = segment
    end
  end
  if #parts == 0 then
    return nil
  end
  local joined = base .. "/" .. table.concat(parts, "/")
  if not M.is_valid_path(joined) then
    return nil
  end
  return joined
end

-- Validated read scope, or `nil` when outside the grant (fail-closed).
function M.validate_read(path)
  if M.is_within_repo(path) then
    return path
  end
  return nil
end

return M
