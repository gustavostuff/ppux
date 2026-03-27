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
    headerTop = (win.y or 0) - (win.headerH or 15)
    headerWidth = ((win.cellW or 0) * (win.visibleCols or win.cols or 0) * (win.zoom or 1))
    headerHeight = win.headerH or 15
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
end

local function isWindowDragMouseButton(button)
  return button == 2 or button == 3
end

local function beginToolbarWindowDragIfNeeded(toolbar, button, x, y, win)
  if not (toolbar and toolbar.contains and isWindowDragMouseButton(button)) then
    return false
  end
  if not toolbar:contains(x, y) then
    return false
  end
  win.dragging = true
  win.dx = x - win.x
  win.dy = y - win.y
  return true
end

function M.handleToolbarClicks(button, x, y, win, wm)
  if not win or win._closed or win._minimized then return false end

  wm:setFocus(win)

  if not win._collapsed and win.specializedToolbar then
    local toolbar = win.specializedToolbar
    if toolbar.updatePosition then
      toolbar:updatePosition()
    end
    if beginToolbarWindowDragIfNeeded(toolbar, button, x, y, win) then
      return true
    end
    if toolbar.mousepressed and toolbar:mousepressed(x, y, button) then
      return true
    end
  end

  if win.headerToolbar then
    local toolbar = win.headerToolbar
    if toolbar.updatePosition then
      toolbar:updatePosition()
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
  local focusedWin = wm:getFocus()
  if not focusedWin or focusedWin._closed or focusedWin._minimized then return false end

  if not focusedWin._collapsed and focusedWin.specializedToolbar then
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
  local windows = wm:getWindows()
  for _, w in ipairs(windows) do
    if not w._closed and not w._minimized then
      if not w._collapsed and w.specializedToolbar and w.specializedToolbar.mousemoved then
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
  if isWindowDragMouseButton(button) and win and isInHeaderTitleArea(win, x, y) then
    wm:setFocus(win)
    lastHeaderTitleClick = nil
    if type(opts.onWindowTitleContextMenu) == "function" then
      opts.onWindowTitleContextMenu(win, x, y, button)
    end
    return false
  end

  if button == 1 and win and win:isInHeader(x, y) then
    wm:setFocus(win)
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

  local windows = wm:getWindows()
  if not windows then return false end
  local focused = wm:getFocus()

  for i = #windows, 1, -1 do
    local w = windows[i]
    if w == focused and not w._closed and not w._minimized and w:hitResizeHandle(x, y) then
      w:mousepressed(x, y, button)
      return true
    end
  end
  return false
end

function M.handleResizeEnd(button, x, y, fwin)
  if fwin and not fwin._minimized and fwin.resizing and fwin.mousereleased then
    fwin:mousereleased(x, y, button)
    return true
  end
  return false
end

function M.handleWindowDragEnd(button, x, y, fwin)
  if fwin and not fwin._minimized and fwin.dragging and fwin.mousereleased then
    fwin:mousereleased(x, y, button)
    return true
  end
  return false
end

return M
