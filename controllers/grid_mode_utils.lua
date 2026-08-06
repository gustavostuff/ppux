-- grid_mode_utils.lua
-- Helpers for normalizing and cycling window grid display modes.

local M = {}

local modesDefault = { "none", "chess", "lines" }
-- PPU frame and sketch canvas windows add attribute-region lines after tile lines.
local modesWithAttr = { "none", "chess", "lines", "attr" }

local validModes = {
  none = true,
  chess = true,
  lines = true,
  attr = true,
}

function M.normalize(value)
  if value == true then return "chess" end
  if value == false or value == nil then return "none" end
  local str = tostring(value)
  if validModes[str] then return str end
  return "none"
end

--- @param value any
--- @param opts table|nil { includeAttr = bool } — PPU frame / sketch canvas cycle through "attr"
function M.next(value, opts)
  local modes = (opts and opts.includeAttr) and modesWithAttr or modesDefault
  local cur = M.normalize(value)
  if cur == "attr" and not (opts and opts.includeAttr) then
    return modes[1]
  end
  local idx = 1
  for i, m in ipairs(modes) do
    if m == cur then
      idx = i
      break
    end
  end
  return modes[(idx % #modes) + 1]
end

return M
