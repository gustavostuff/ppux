local WindowCaps = require("controllers.window.window_capabilities")
local ResolutionController = require("controllers.app.resolution_controller")

local M = {}

local function stepSign(v)
  if v > 0 then return 1 elseif v < 0 then return -1 else return 0 end
end

local function handlePaletteColorSelection(env, win, mouse, wm)
  if not WindowCaps.isAnyPaletteWindow(win) then return nil end

  local utils = env.utils or {}
  local hit, vcol, vrow, vitem = utils.pickByVisual(win, mouse.x, mouse.y)
  if hit and vitem then
    if WindowCaps.isRomPaletteWindow(win) and win.isCellEditable and not win:isCellEditable(vcol, vrow) then
      return false
    end
    win:setSelected(vcol, vrow)
  end
  return true
end

local function handleZoom(env, win, mouse, wm, dy)
  local utils = env.utils or {}
  if not (utils.ctrlDown and utils.ctrlDown()) or not win then return false end
  if WindowCaps.isAnyPaletteWindow(win) then return false end

  wm:setFocus(win)
  local zstep = stepSign(dy)
  if zstep ~= 0 and win.addZoomLevel then
    win:addZoomLevel(zstep, mouse.x, mouse.y)
  end
  return true
end

local function handleHorizontalScroll(env, win, dx, dy)
  local utils = env.utils or {}
  if not (utils.shiftDown and utils.shiftDown()) then return false end

  if WindowCaps.isAnyPaletteWindow(win) then
    if WindowCaps.isRomPaletteWindow(win) or win.activePalette then
      win:adjustSelectedByArrows(-dy, 0)
    end
    return true
  end

  local raw = (dy ~= 0) and dy or dx
  local s = stepSign(raw)
  if s ~= 0 and win.scrollBy then
    win:scrollBy(-s, 0)
  end
  return true
end

local function handleVerticalScroll(env, win, dy)
  local utils = env.utils or {}
  if (utils.shiftDown and utils.shiftDown()) or (utils.ctrlDown and utils.ctrlDown()) then
    return false
  end

  if WindowCaps.isAnyPaletteWindow(win) then
    if WindowCaps.isRomPaletteWindow(win) or win.activePalette then
      win:adjustSelectedByArrows(0, -dy)
    end
    return true
  end

  local s = stepSign(dy)
  if s ~= 0 and win and win.scrollBy then
    win:scrollBy(0, -s)
  end
  return true
end

function M.handleWheel(env, dx, dy)
  local ctx = env.ctx
  local utils = env.utils or {}
  local wm = ctx.wm()
  local mouse = ResolutionController:getScaledMouse(true)
  local winBelowMouse = wm:windowAt(mouse.x, mouse.y)
  local focusedWindow = wm:getFocus()
  local app = ctx.app

  if (utils.ctrlDown and utils.ctrlDown())
    and (utils.altDown and utils.altDown())
    and ctx.getMode() == "edit"
  then
    if app and utils.changeBrushSize then
      local currentSize = app.brushSize or 1
      if dy > 0 then
        utils.changeBrushSize(app, currentSize + 1)
      elseif dy < 0 then
        utils.changeBrushSize(app, currentSize - 1)
      end
      return true
    end
  end

  if app and app.taskbar and app.taskbar.wheelmoved then
    if app.taskbar:wheelmoved(dx, dy) then
      return true
    end
  end

  local targetWin = winBelowMouse or focusedWindow
  if not targetWin then return false end

  if winBelowMouse and focusedWindow ~= winBelowMouse then
    wm:setFocus(winBelowMouse)
    focusedWindow = winBelowMouse
    targetWin = winBelowMouse
  end

  if WindowCaps.isAnyPaletteWindow(targetWin) then
    local paletteCellInteractive = handlePaletteColorSelection(env, targetWin, mouse, wm)
    if paletteCellInteractive == false then
      return true
    end
  end

  if handleZoom(env, targetWin, mouse, wm, dy) then return true end
  if handleHorizontalScroll(env, targetWin, dx, dy) then return true end
  if handleVerticalScroll(env, targetWin, dy) then return true end
  return false
end

return M
