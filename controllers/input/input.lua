-- ============================================================================
-- User Input Module - Main Entry Point
-- ============================================================================
-- Coordinates keyboard and mouse input handling

local KeyboardInput = require("controllers.input.keyboard_input")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
local KeyboardModifierHintController = require("controllers.input.keyboard_modifier_hint_controller")
local MouseInput = require("controllers.input.mouse_input")
local MouseWindowChromeController = require("controllers.input.mouse_window_chrome_controller")
local SpriteController = require("controllers.sprite.sprite_controller")

local M = {}

-- Shared state and context
local ctx

-- Shared drag state
local drag = {
  pending = false, startX = 0, startY = 0,
  active = false, srcWin = nil, srcCol = 0, srcRow = 0, srcLayer = 1, item = nil,
  copyMode = false,         -- tile drag copy mode (Ctrl+click drag)
  tileGroup = nil,          -- multi-tile drag payload for group copy operations
  srcTemporarilyCleared = false, -- source hidden while normal move drag is active
  ghostAlpha = 0.5,
  currentX = 0,            -- current mouse X position during drag
  currentY = 0,            -- current mouse Y position during drag
}

-- Tile paint mode state
local tilePaintState = {
  active = false,          -- whether we're currently tile painting (mouse down)
  lastCol = nil,          -- last column painted (to avoid repainting same cell)
  lastRow = nil,          -- last row painted (to avoid repainting same cell)
}

-- Shared constants
local DRAG_TOL = 4

-- Shared utility functions
local function ctrlDown()
  return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
end

local function shiftDown()
  return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end

local function altDown()
  return love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")
end

local function screenToContent(win, x, y)
  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  return (x - win.x) / z, (y - win.y) / z
end

-- Returns: hit, col, row, item
local function pickByVisual(win, x, y, layerIndex)
  if win and win.kind == "chr" and win.toGridCoords and win.get then
    local ok, col, row = win:toGridCoords(x, y)
    if ok then
      local item = (win.getVirtualTileHandle and win:getVirtualTileHandle(col, row, layerIndex))
        or win:get(col, row, layerIndex)
      if item then
        return true, col, row, item
      end
    end
    return false
  end

  -- Convert to window-local "content" coords (pre-scroll)
  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local cx = (x - win.x) / z
  local cy = (y - win.y) / z

  local cw, ch = win.cellW, win.cellH
  if not (cw and ch) then return false end

  -- Account for scroll: drawn content is translated by -scroll*cw/ch,
  -- so we add that here to compare against absolute grid positions.
  local scol = (win.scrollCol or 0)
  local srow = (win.scrollRow or 0)
  local cxAbs = cx + scol * cw
  local cyAbs = cy + srow * ch

  for row = 0, (win.rows or 0) - 1 do
    for col = 0, (win.cols or 0) - 1 do
      local item = win.get and win:get(col, row, layerIndex)
      if item then
        local x0 = col * cw
        local y0 = row * ch
        if cxAbs >= x0 and cxAbs < x0 + cw and cyAbs >= y0 and cyAbs < y0 + ch then
          return true, col, row, item
        end
      end
    end
  end
  return false
end

-- Helper function to change brush size (used by keyboard and wheel)
local function changeBrushSize(app, newSize)
  if not app then return end
  newSize = math.max(1, math.min(4, newSize))  -- Clamp between 1 and 4
  app.brushSize = newSize
  local sizeNames = {[1] = "1x1", [2] = "3x3", [3] = "5x5", [4] = "7x7"}
  ctx.setStatus("Brush size: " .. (sizeNames[newSize] or tostring(newSize)))
end

-- Helper function to get selected tile from CHR window
-- Returns: tile reference, or nil if not available
local function getSelectedTileFromCHR()
  if not ctx or not ctx.wm then return nil end
  
  local wm = ctx.wm()
  local windows = wm:getWindows()
  if not windows then return nil end
  
  -- Find the focused CHR window, or any CHR window if none is focused
  local chrWin = nil
  local focused = wm:getFocus()
  if focused and focused.kind == "chr" then
    chrWin = focused
  else
    -- Search for any CHR window
    for _, win in ipairs(windows) do
      if win.kind == "chr" then
        chrWin = win
        break
      end
    end
  end
  
  if not chrWin then return nil end
  
  -- Get selected coordinates from CHR window
  local col, row, layerIdx = chrWin:getSelected()
  if not (col and row) then return nil end
  
  -- Get the tile reference directly from the CHR window
  return chrWin:get(col, row, layerIdx)
end

-- Setup function
function M.setup(context)
  ctx = context
  ctx.setMode("tile")
  
  -- Initialize keyboard and mouse modules with shared state
  KeyboardInput.setup(ctx, {
    ctrlDown = ctrlDown,
    shiftDown = shiftDown,
    altDown = altDown,
    changeBrushSize = changeBrushSize,
  })
  
  MouseInput.setup(ctx, drag, tilePaintState, {
    ctrlDown = ctrlDown,
    shiftDown = shiftDown,
    altDown = altDown,
    screenToContent = screenToContent,
    pickByVisual = pickByVisual,
    changeBrushSize = changeBrushSize,
    DRAG_TOL = DRAG_TOL,
    getSelectedTileFromCHR = getSelectedTileFromCHR,
  })
end

function M.resetRuntimeState()
  drag.pending = false
  drag.startX = 0
  drag.startY = 0
  drag.active = false
  drag.srcWin = nil
  drag.srcCol = 0
  drag.srcRow = 0
  drag.srcLayer = 1
  drag.item = nil
  drag.copyMode = false
  drag.tileGroup = nil
  drag.srcTemporarilyCleared = false
  drag.currentX = 0
  drag.currentY = 0
  tilePaintState.active = false
  tilePaintState.lastCol = nil
  tilePaintState.lastRow = nil
  if MouseInput.resetTransientState then
    MouseInput.resetTransientState()
  end
  if KeyboardClipboardController and KeyboardClipboardController.reset then
    KeyboardClipboardController.reset()
  end
  if KeyboardModifierHintController and KeyboardModifierHintController.reset then
    KeyboardModifierHintController.reset()
  end
  if MouseWindowChromeController and MouseWindowChromeController._resetHeaderDoubleClickState then
    MouseWindowChromeController._resetHeaderDoubleClickState()
  end
  if SpriteController and SpriteController.endDrag then
    SpriteController.endDrag()
  end
end

-- Keyboard event handler
function M.keypressed(key, AppCoreControllerRef)
  return KeyboardInput.keypressed(key, AppCoreControllerRef)
end

function M.keyreleased(key, AppCoreControllerRef)
  return KeyboardInput.keyreleased(key, AppCoreControllerRef)
end

-- Mouse event handlers
function M.mousepressed(x, y, button)
  return MouseInput.mousepressed(x, y, button)
end

function M.mousemoved(x, y, dx, dy)
  return MouseInput.mousemoved(x, y, dx, dy)
end

function M.mousereleased(x, y, button)
  return MouseInput.mousereleased(x, y, button)
end

function M.wheelmoved(dx, dy)
  return MouseInput.wheelmoved(dx, dy)
end

-- Utility functions
function M.isDraggingTile()
  return drag and (drag.pending or drag.active)
end

function M.drawOverlay()
  return MouseInput.drawOverlay()
end

function M.getTooltipCandidate(x, y)
  return MouseInput.getTooltipCandidate and MouseInput.getTooltipCandidate(x, y)
end

function M.getDragState()
  return drag
end

function M.getTilePaintState()
  return tilePaintState
end

function M.getTileMarquee()
  return MouseInput.getTileMarquee and MouseInput.getTileMarquee()
end

return M
