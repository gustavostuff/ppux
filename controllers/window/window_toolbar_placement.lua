-- Window-attached specialized toolbar placement (when "Detached Window Toolbar" is off).
-- Settings key: windowToolbarPlacement = "top" | "left" | "right" | "bottom" | "auto"
-- "auto" picks the first side (top → right → left → bottom) whose strip fits the usable
-- canvas region (below the app top bar, above the taskbar).

local M = {}

M.KEY_TOP = "top"
M.KEY_LEFT = "left"
M.KEY_RIGHT = "right"
M.KEY_BOTTOM = "bottom"
M.KEY_AUTO = "auto"

-- Must match user_interface/toolbars/toolbar_base.lua TOOLBAR_OUTSIDE_GAP.
local OUT_GAP = 4

local function btnVis(b)
  return b and b.hidden ~= true
end

--- Usable canvas rect in screen space: [clipL, clipR) × [clipT, clipB), excluding app top bar
--- and area below the taskbar (same idea as window drag bounds + app chrome offset).
--- @param app table|nil
--- @return number clipL, number clipT, number clipR, number clipB
local function getWorkspaceClipHalfOpen(app)
  local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
  local ResolutionController = require("controllers.app.resolution_controller")

  local canvasW = ResolutionController.canvasWidth or 0
  local canvasH = ResolutionController.canvasHeight or 0
  if love and love.graphics then
    if canvasW <= 0 then
      canvasW = love.graphics.getWidth() or canvasW
    end
    if canvasH <= 0 then
      canvasH = love.graphics.getHeight() or canvasH
    end
  end
  if app and app.canvas then
    local cw = app.canvas:getWidth()
    local ch = app.canvas:getHeight()
    if type(cw) == "number" and cw > 0 then
      canvasW = cw
    end
    if type(ch) == "number" and ch > 0 then
      canvasH = ch
    end
  end

  local clipL = 0
  local clipT = 0
  if app then
    clipT = AppTopToolbarController.getContentOffsetY(app)
  end
  if type(clipT) ~= "number" or clipT < 0 then
    clipT = 0
  end

  local clipB = canvasH
  local taskbar = app and app.taskbar
  if taskbar and taskbar.getTopY then
    local ty = taskbar:getTopY()
    if type(ty) == "number" then
      clipB = math.min(clipB, ty)
    end
  elseif taskbar and type(taskbar.y) == "number" then
    clipB = math.min(clipB, taskbar.y)
  end

  local clipR = canvasW
  return clipL, clipT, clipR, clipB
end

local function rectFitsClip(l, t, r, b, clipL, clipT, clipR, clipB)
  if clipR <= clipL or clipB <= clipT then
    return false
  end
  return l >= clipL and t >= clipT and r <= clipR and b <= clipB
end

--- Horizontal strip width/height (matches ToolbarBase:_layoutButtons row metrics).
--- @param toolbar table
--- @param hh number header row height
--- @return number totalWidth, number barHeight, number rowHeight
local function horizontalStripMetrics(toolbar, hh)
  local rowHeight = toolbar:_getRowHeight(hh)
  local totalLabelWidth = 0
  for _, label in ipairs(toolbar.labels or {}) do
    if not label.renderInContent then
      totalLabelWidth = totalLabelWidth + label.width
    end
  end

  local rowWidths = {}
  local rowCount = 1
  local visibleIndex = 0
  for _, button in ipairs(toolbar.buttons or {}) do
    if btnVis(button) then
      visibleIndex = visibleIndex + 1
      local rowIndex = toolbar:_resolveButtonRow(button, visibleIndex)
      rowWidths[rowIndex] = (rowWidths[rowIndex] or 0) + button.w
      if rowIndex > rowCount then
        rowCount = rowIndex
      end
    end
  end

  local totalWidth = totalLabelWidth + (rowWidths[1] or 0)
  for rowIndex = 2, rowCount do
    totalWidth = math.max(totalWidth, rowWidths[rowIndex] or 0)
  end

  local barHeight = rowHeight * rowCount
  if rowHeight <= 0 then
    barHeight = tonumber(hh) or 0
  end
  return totalWidth, barHeight, rowHeight
end

--- Vertical strip width/height (matches ToolbarBase:_layoutButtonsVertical).
--- @return number colW, number stackHeight, number rowHeight
local function verticalStripMetrics(toolbar, hh, bx, by, bw, bh)
  local rowHeight = toolbar:_getRowHeight(hh)
  local colW = rowHeight
  for _, button in ipairs(toolbar.buttons or {}) do
    if btnVis(button) then
      colW = math.max(colW, button.w)
    end
  end
  for _, label in ipairs(toolbar.labels or {}) do
    if not label.renderInContent then
      colW = math.max(colW, label.width)
    end
  end

  local labelStackH = 0
  for _, label in ipairs(toolbar.labels or {}) do
    if not label.renderInContent then
      labelStackH = labelStackH + rowHeight
    end
  end
  local btnStackH = 0
  for _, button in ipairs(toolbar.buttons or {}) do
    if btnVis(button) then
      btnStackH = btnStackH + button.h
    end
  end
  local stackHeight = labelStackH + btnStackH
  return colW, stackHeight, rowHeight
end

--- @param wnd table|nil
--- @param app table|nil
--- @param toolbar table|nil  ToolbarBase instance (specialized toolbar)
--- @return string
function M.resolveAutoPlacement(wnd, app, toolbar)
  if not wnd or not toolbar or not wnd.getHeaderRect or not wnd.getBaseContentScreenRect then
    return M.KEY_TOP
  end

  local hx, hy, hw, hh = wnd:getHeaderRect()
  local bx, by, bw, bh = wnd:getBaseContentScreenRect()
  if type(hx) ~= "number" or type(hy) ~= "number" or type(hw) ~= "number" then
    return M.KEY_TOP
  end
  bx, by, bw, bh = bx or 0, by or 0, bw or 0, bh or 0

  local twTop, thTop = horizontalStripMetrics(toolbar, hh)
  local twBot, thBot = horizontalStripMetrics(toolbar, hh)
  local colW, stackH = verticalStripMetrics(toolbar, hh, bx, by, bw, bh)

  local clipL, clipT, clipR, clipB = getWorkspaceClipHalfOpen(app)

  local candidates = { M.KEY_TOP, M.KEY_RIGHT, M.KEY_LEFT, M.KEY_BOTTOM }
  for _, side in ipairs(candidates) do
    local l, t, r, b
    if side == M.KEY_TOP then
      local contentLeft = hx + math.floor((hw - twTop) / 2)
      l = contentLeft
      t = math.floor(hy - thTop - 1)
      r = l + twTop
      b = t + thTop
    elseif side == M.KEY_BOTTOM then
      local contentLeft = bx + math.floor((bw - twBot) / 2)
      l = contentLeft
      t = math.floor(by + bh + OUT_GAP)
      r = l + twBot
      b = t + thBot
    elseif side == M.KEY_LEFT then
      local xLeft = bx - OUT_GAP - colW
      local y0 = math.floor(by + math.max(0, (bh - stackH) * 0.5))
      l = xLeft
      t = y0
      r = l + colW
      b = t + stackH
    else
      local xLeft = bx + bw + OUT_GAP
      local y0 = math.floor(by + math.max(0, (bh - stackH) * 0.5))
      l = xLeft
      t = y0
      r = l + colW
      b = t + stackH
    end

    if rectFitsClip(l, t, r, b, clipL, clipT, clipR, clipB) then
      return side
    end
  end

  return M.KEY_TOP
end

--- @param key string|nil
--- @return string
function M.normalizeKey(key)
  if key == M.KEY_LEFT then return M.KEY_LEFT end
  if key == M.KEY_RIGHT then return M.KEY_RIGHT end
  if key == M.KEY_BOTTOM then return M.KEY_BOTTOM end
  if key == M.KEY_AUTO then return M.KEY_AUTO end
  if key == M.KEY_TOP then return M.KEY_TOP end
  return M.KEY_AUTO
end

--- Placement used for layout.
--- @param key string|nil
--- @param wnd table|nil  focused window (for auto placement)
--- @param app table|nil
--- @param toolbar table|nil  specialized toolbar instance (for auto placement)
--- @return string
function M.effectiveForLayout(key, wnd, app, toolbar)
  local k = M.normalizeKey(key)
  if k == M.KEY_AUTO then
    return M.resolveAutoPlacement(wnd, app, toolbar)
  end
  return k
end

-- Dropdown items use numeric `value` (see user_interface/dropdown.lua).
-- Order in UI: Auto, Top, Left, Right, Bottom.
local VAL_AUTO, VAL_TOP, VAL_LEFT, VAL_RIGHT, VAL_BOTTOM = 1, 2, 3, 4, 5

--- @param key string|nil
--- @return number
function M.dropdownValueForKey(key)
  local k = M.normalizeKey(key)
  if k == M.KEY_TOP then return VAL_TOP end
  if k == M.KEY_LEFT then return VAL_LEFT end
  if k == M.KEY_RIGHT then return VAL_RIGHT end
  if k == M.KEY_BOTTOM then return VAL_BOTTOM end
  return VAL_AUTO
end

--- @param value number|nil
--- @return string
function M.keyForDropdownValue(value)
  local v = tonumber(value)
  if v == VAL_TOP then return M.KEY_TOP end
  if v == VAL_LEFT then return M.KEY_LEFT end
  if v == VAL_RIGHT then return M.KEY_RIGHT end
  if v == VAL_BOTTOM then return M.KEY_BOTTOM end
  if v == VAL_AUTO then return M.KEY_AUTO end
  return M.KEY_AUTO
end

return M
