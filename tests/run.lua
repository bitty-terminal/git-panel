-- Headless behavior test runner for the git-panel plugin.
--
-- Plain Lua 5.4, no external test framework. Run from the package root:
--
--   lua5.4 tests/run.lua
--
-- Exits non-zero when any assertion fails.

local script = (arg and arg[0]) or "tests/run.lua"
local root = string.match(script, "^(.*)[/\\]tests[/\\]run%.lua$")
if root == nil or root == "" then
  root = "."
end

package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/tests/?.lua",
  package.path,
}, ";")

local tap = require("support.tap")
local context = { root = root, tap = tap }

for _, suite in ipairs({
  "spec.allowlist_spec",
  "spec.scope_spec",
  "spec.listing_spec",
  "spec.scene_spec",
  "spec.init_spec",
}) do
  local ok, err = pcall(function()
    require(suite).run(context)
  end)
  if not ok then
    tap.crash(suite, err)
  end
end

tap.finish()
