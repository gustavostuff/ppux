-- Recognizes modifier / edit-hold keys for keyboard routing only.
-- (Status-bar hints on Ctrl/Shift/Alt were removed.)

local M = {}

local MODIFIER_KEYS = {
  lshift = true,
  rshift = true,
  lctrl = true,
  rctrl = true,
  lalt = true,
  ralt = true,
  f = true,
  g = true,
}

function M.reset()
end

function M.isModifierKey(key)
  return MODIFIER_KEYS[key] == true
end

function M.updateStatus()
end

return M
