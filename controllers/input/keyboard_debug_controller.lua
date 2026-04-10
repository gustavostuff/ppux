local DebugController = require("controllers.dev.debug_controller")

local M = {}

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

local function handleUnifiedDebugHotkey(ctx)
  local mode = DebugController.cycleHudMode()
  if mode == "off" then
    setStatus(ctx, "Dev HUD disabled")
  else
    setStatus(ctx, string.format("Dev HUD mode: %s", DebugController.getHudModeLabel(mode)))
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
      setStatus(ctx, "Debug log cleared")
    end
    return true
  end

  if key == "9" then
    return true
  end

  return false
end

return M
