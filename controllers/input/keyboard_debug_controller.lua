local DebugController = require("controllers.dev.debug_controller")

local M = {}

local function handleUnifiedDebugHotkey(ctx)
  local mode = DebugController.cycleHudMode()
  if mode == "off" then
    ctx.setStatus("Dev HUD disabled")
  else
    ctx.setStatus(string.format("Dev HUD mode: %s", DebugController.getHudModeLabel(mode)))
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
      ctx.setStatus("Debug log cleared")
    end
    return true
  end

  if key == "9" then
    return true
  end

  return false
end

return M
