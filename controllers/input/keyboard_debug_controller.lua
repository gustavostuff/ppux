local DebugController = require("controllers.dev.debug_controller")
local StatusHelpers = require("utils.status_helpers")

local M = {}

local function handleUnifiedDebugHotkey(ctx)
  local mode = DebugController.cycleHudMode()
  if mode == "off" then
    StatusHelpers.setStatus(ctx, "Dev HUD disabled")
  else
    StatusHelpers.setStatus(ctx, string.format("Dev HUD mode: %s", DebugController.getHudModeLabel(mode)))
  end
  return true
end

function M.handleDebugKeys(ctx, utils, key)
  if key == "f8" or key == "f9" then
    return handleUnifiedDebugHotkey(ctx)
  end

  if key == "f7" then
    if DebugController.isEnabled() then
      DebugController.clear()
      StatusHelpers.setStatus(ctx, "Debug log cleared")
    end
    return true
  end

  if key == "9" then
    return true
  end

  return false
end

return M
