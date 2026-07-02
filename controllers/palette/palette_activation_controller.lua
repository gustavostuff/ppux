local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local function iterGlobalPaletteWindows(wm)
  local out = {}
  if not (wm and wm.getWindows) then
    return out
  end
  for _, win in ipairs(wm:getWindows() or {}) do
    if WindowCaps.isGlobalPaletteWindow(win) and win._runtimeOnly ~= true and win._closed ~= true then
      out[#out + 1] = win
    end
  end
  return out
end

function M.findActiveGlobalPaletteWindow(wm)
  for _, win in ipairs(iterGlobalPaletteWindows(wm)) do
    if win.activePalette == true then
      return win
    end
  end
  return nil
end

function M.shouldActivateNewGlobalPalette(wm)
  return M.findActiveGlobalPaletteWindow(wm) == nil
end

function M.refreshPaletteToolbarActiveIcons(wm)
  if not (wm and wm.getWindows) then
    return
  end
  for _, win in ipairs(wm:getWindows() or {}) do
    if win.isPalette and win.specializedToolbar and win.specializedToolbar.updateActiveIcon then
      win.specializedToolbar:updateActiveIcon()
    end
  end
end

--- Make `target` the sole shader-active global palette. Does not change window focus.
function M.activateGlobalPalette(target, app)
  if not WindowCaps.isGlobalPaletteWindow(target) then
    return false
  end

  local wm = app and app.wm or nil
  if not (wm and wm.getWindows) then
    return false
  end

  if target.activePalette == true then
    return true
  end

  for _, win in ipairs(wm:getWindows() or {}) do
    if win.isPalette then
      win.activePalette = false
    end
  end
  target.activePalette = true

  if target.syncToGlobalPalette then
    target:syncToGlobalPalette()
  end
  if app.invalidateConsumersOfPaletteWindow then
    app:invalidateConsumersOfPaletteWindow(target)
  elseif app.invalidatePpuFrameLayersAffectedByPaletteWin then
    app:invalidatePpuFrameLayersAffectedByPaletteWin(target)
  end

  M.refreshPaletteToolbarActiveIcons(wm)
  return true
end

return M
