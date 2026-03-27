-- grid_mode_utils.lua
-- Helpers for normalizing and cycling window grid display modes.

local M = {}

local modes = { "none", "chess", "lines" }
local modeIndex = {}
for i, m in ipairs(modes) do
  modeIndex[m] = i
end

function M.normalize(value)
  if value == true then return "chess" end
  if value == false or value == nil then return "none" end
  local str = tostring(value)
  if modeIndex[str] then return str end
  return "none"
end

function M.next(value)
  local cur = M.normalize(value)
  local idx = modeIndex[cur] or 1
  local nextIdx = (idx % #modes) + 1
  return modes[nextIdx]
end

return M
