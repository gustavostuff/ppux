local PaletteLinkController = require("controllers.palette.palette_link_controller")
local UiScale = require("user_interface.ui_scale")

local M = {}
local DOUBLE_CLICK_SECONDS = 0.35
local DOUBLE_CLICK_MOVE_TOLERANCE = 4

local lastHeaderTitleClick = nil
local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function isInHeaderTitleArea(win, x, y)
  if not (win and win.isInHeader and win:isInHeader(x, y)) then
    return false
  end

  local headerLeft, headerTop, headerWidth, headerHeight
  if win.getHeaderRect then
    headerLeft, headerTop, headerWidth, headerHeight = win:getHeaderRect()
  else
    headerLeft = win.x or 0
    headerTop = (win.y or 0) - (win.headerH or UiScale.windowHeaderHeight())
    headerWidth = ((win.cellW or 0) * (win.visibleCols or win.cols or 0) * (win.zoom or 1))
    headerHeight = win.headerH or UiScale.windowHeaderHeight()
  end

  local left = headerLeft + 4
  local right = headerLeft + headerWidth - 4
  if win.headerToolbar and type(win.headerToolbar.x) == "number" and type(win.headerToolbar.w) == "number" then
    right = math.min(right, win.headerToolbar.x - 2)
  end

  return x >= left and x <= right and y >= headerTop and y <= (headerTop + headerHeight)
end

function M._resetHeaderDoubleClickState()
  lastHeaderTitleClick = nil
  PaletteLinkController.resetDoubleClickState()
end

local function isPointInWindowInteractiveArea(win, x, y)
  if not win then
    return false
  end
  if win.contains and win:contains(x, y) then
    return true
  end
  if win.specializedToolbar and win.specializedToolbar.contains and win.specializedToolbar:contains(x, y) then
    return true
  end
  if win.headerToolbar and win.headerToolbar.contains and win.headerToolbar:contains(x, y) then
    return true
  end
  return false
end

function M.getTopInteractiveWindowAt(x, y, wm)
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local win = windows[i]
    if win and not win._closed and not win._minimized and win._groupHidden ~= true then
      if isPointInWindowInteractiveArea(win, x, y) then
        return win
      end
    end
  end
  return nil
end

function M.findToolbarWindowAt(x, y, wm)
  local win = M.getTopInteractiveWindowAt(x, y, wm)
  if not win then
    return nil
  end
  if not win._collapsed and win.specializedToolbar and win.specializedToolbar.contains and win.specializedToolbar:contains(x, y) then
    return win
  end
  if win.headerToolbar and win.headerToolbar.contains and win.headerToolbar:contains(x, y) then
    return win
  end
  return nil
end

local function isWindowDragMouseButton(button)
  return button == 2 or button == 3
end

function M.getPaletteLinkDropTarget(wm, sourceWin, x, y)
  return PaletteLinkController.getDropTarget(wm, sourceWin, x, y)
end

function M.canApplyPaletteLinkToTarget(targetWin, paletteWin)
  return PaletteLinkController.canApplyToTarget(targetWin, paletteWin)
end

function M.getPaletteLinkHoverTarget(wm, sourceWin, x, y)
  return PaletteLinkController.getHoverTarget(wm, sourceWin, x, y)
end

local function beginToolbarWindowDragIfNeeded(toolbar, button, x, y, win)
  if not (toolbar and toolbar.contains and isWindowDragMouseButton(button)) then
    return false
  end
  if not toolbar:contains(x, y) then
    return false
  end
  -- Right/middle drag moves the window even from control buttons (minimize, collapse, close).
  win.dragging = true
  win.dx = x - win.x
  win.dy = y - win.y
  return true
end

function M.handleToolbarClicks(button, x, y, win, wm)
  if not win or win._closed or win._minimized or win._groupHidden == true then return false end

  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app or nil
  local skipDockedSpec = app
    and app.separateToolbar == true
    and wm
    and wm.getFocus
    and win == wm:getFocus()

  if not win._collapsed and win.specializedToolbar then
    local toolbar = win.specializedToolbar
    if not skipDockedSpec then
      if wm and wm.setFocus then
        wm:setFocus(win)
      end
      if beginToolbarWindowDragIfNeeded(toolbar, button, x, y, win) then
        return true
      end
      if toolbar.mousepressed and toolbar:mousepressed(x, y, button) then
        return true
      end
    elseif isWindowDragMouseButton(button) and toolbar.contains and toolbar:contains(x, y) then
      if wm and wm.setFocus then
        wm:setFocus(win)
      end
      if beginToolbarWindowDragIfNeeded(toolbar, button, x, y, win) then
        return true
      end
    end
  end

  if win.headerToolbar then
    local toolbar = win.headerToolbar
    if wm and wm.setFocus then
      wm:setFocus(win)
    end
    if beginToolbarWindowDragIfNeeded(toolbar, button, x, y, win) then
      return true
    end
    if toolbar.mousepressed and toolbar:mousepressed(x, y, button) then
      return true
    end
  end

  return false
end

function M.handleToolbarRelease(button, x, y, wm)
  if PaletteLinkController.finishDrag(wm, x, y) then
    return true
  end

  local focusedWin = (wm and wm.getFocus and wm:getFocus()) or nil
  if not focusedWin or focusedWin._closed or focusedWin._minimized or focusedWin._groupHidden == true then return false end

  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app or nil
  local skipDockedSpec = app and app.separateToolbar == true

  if not focusedWin._collapsed and focusedWin.specializedToolbar and not skipDockedSpec then
    local toolbar = focusedWin.specializedToolbar
    if toolbar.updatePosition then
      toolbar:updatePosition()
    end
    if toolbar.mousereleased and toolbar:mousereleased(x, y, button) then
      return true
    end
  end

  if focusedWin.headerToolbar then
    local toolbar = focusedWin.headerToolbar
    if toolbar.updatePosition then
      toolbar:updatePosition()
    end
    if toolbar.mousereleased and toolbar:mousereleased(x, y, button) then
      return true
    end
  end

  return false
end

function M.updateToolbarHover(x, y, wm)
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app or nil
  local windows = wm:getWindows()
  for _, w in ipairs(windows) do
    if not w._closed and not w._minimized and w._groupHidden ~= true then
      local skipDockedSpec = app
        and app.separateToolbar == true
        and w == wm:getFocus()
      if not w._collapsed and w.specializedToolbar and w.specializedToolbar.mousemoved and not skipDockedSpec then
        w.specializedToolbar:mousemoved(x, y)
      end
      if w.headerToolbar and w.headerToolbar.mousemoved then
        w.headerToolbar:mousemoved(x, y)
      end
    end
  end
end

function M.handleHeaderClick(button, x, y, win, wm, opts)
  opts = opts or {}
  if win and (win._closed or win._minimized or win._groupHidden == true) then
    return false
  end
  if isWindowDragMouseButton(button) and win and isInHeaderTitleArea(win, x, y) then
    if wm and wm.setFocus then
      wm:setFocus(win)
    end
    lastHeaderTitleClick = nil
    if type(opts.onWindowTitleContextMenu) == "function" then
      opts.onWindowTitleContextMenu(win, x, y, button)
    end
    return false
  end

  if button == 1 and win and win:isInHeader(x, y) then
    if wm and wm.setFocus then
      wm:setFocus(win)
    end
    if M.handleToolbarClicks(button, x, y, win, wm) then
      return true
    end

    local titleAreaClick = isInHeaderTitleArea(win, x, y)
    if titleAreaClick then
      local t = tonumber(opts.nowSeconds) or nowSeconds()
      local prev = lastHeaderTitleClick
      local dt = prev and (t - (prev.time or 0)) or math.huge
      local dx = prev and math.abs((prev.x or 0) - x) or math.huge
      local dy = prev and math.abs((prev.y or 0) - y) or math.huge
      local sameWindow = prev and prev.win == win

      local isDoubleClick = sameWindow
        and dt >= 0
        and dt <= DOUBLE_CLICK_SECONDS
        and dx <= DOUBLE_CLICK_MOVE_TOLERANCE
        and dy <= DOUBLE_CLICK_MOVE_TOLERANCE

      lastHeaderTitleClick = {
        win = win,
        x = x,
        y = y,
        time = t,
      }

      if isDoubleClick and type(opts.onWindowTitleDoubleClick) == "function" then
        opts.onWindowTitleDoubleClick(win)
        return true
      end
    else
      lastHeaderTitleClick = nil
    end

    win:mousepressed(x, y, button)
    return true
  end
  return false
end

function M.handleResizeHandle(button, x, y, wm)
  if button ~= 1 then return false end

  local windows = wm and wm.getWindows and wm:getWindows()
  if not windows then return false end
  local focused = (wm and wm.getFocus and wm:getFocus()) or nil

  for i = #windows, 1, -1 do
    local w = windows[i]
    if w == focused and not w._closed and not w._minimized and w._groupHidden ~= true and w:hitResizeHandle(x, y) then
      w:mousepressed(x, y, button)
      return true
    end
  end
  return false
end

function M.handleResizeEnd(button, x, y, fwin)
  if fwin and not fwin._minimized and fwin._groupHidden ~= true and fwin.resizing and fwin.mousereleased then
    fwin:mousereleased(x, y, button)
    return true
  end
  return false
end

function M.handleWindowDragEnd(button, x, y, fwin)
  if fwin and not fwin._minimized and fwin._groupHidden ~= true and fwin.dragging and fwin.mousereleased then
    fwin:mousereleased(x, y, button)
    return true
  end
  return false
end

return M
