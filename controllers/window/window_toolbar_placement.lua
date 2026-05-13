-- Window-attached specialized toolbar placement (when "Detached Window Toolbar" is off).
-- Settings key: windowToolbarPlacement = "top" | "left" | "right" | "bottom" | "auto"
-- "auto" is reserved for future auto-positioning; layout currently matches "top".

local M = {}

M.KEY_TOP = "top"
M.KEY_LEFT = "left"
M.KEY_RIGHT = "right"
M.KEY_BOTTOM = "bottom"
M.KEY_AUTO = "auto"

--- @param key string|nil
--- @return string
function M.normalizeKey(key)
  if key == M.KEY_LEFT then return M.KEY_LEFT end
  if key == M.KEY_RIGHT then return M.KEY_RIGHT end
  if key == M.KEY_BOTTOM then return M.KEY_BOTTOM end
  if key == M.KEY_AUTO then return M.KEY_AUTO end
  return M.KEY_TOP
end

--- Placement used for layout (auto → top until smart placement exists).
--- @param key string|nil
--- @return string
function M.effectiveForLayout(key)
  local k = M.normalizeKey(key)
  if k == M.KEY_AUTO then
    return M.KEY_TOP
  end
  return k
end

-- Dropdown items use numeric `value` (see user_interface/dropdown.lua).
local VAL_TOP, VAL_LEFT, VAL_RIGHT, VAL_BOTTOM, VAL_AUTO = 1, 2, 3, 4, 5

--- @param key string|nil
--- @return number
function M.dropdownValueForKey(key)
  local k = M.normalizeKey(key)
  if k == M.KEY_LEFT then return VAL_LEFT end
  if k == M.KEY_RIGHT then return VAL_RIGHT end
  if k == M.KEY_BOTTOM then return VAL_BOTTOM end
  if k == M.KEY_AUTO then return VAL_AUTO end
  return VAL_TOP
end

--- @param value number|nil
--- @return string
function M.keyForDropdownValue(value)
  local v = tonumber(value)
  if v == VAL_LEFT then return M.KEY_LEFT end
  if v == VAL_RIGHT then return M.KEY_RIGHT end
  if v == VAL_BOTTOM then return M.KEY_BOTTOM end
  if v == VAL_AUTO then return M.KEY_AUTO end
  return M.KEY_TOP
end

return M
