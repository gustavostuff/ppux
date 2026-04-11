-- palette_window.lua
-- Global palette window (default: 1 row x 4 cols).
-- Arrow keys move selection. Shift + arrows adjust selected color nibble.
local Window = require("user_interface.windows_system.window")
local Palettes = require("palettes")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local Text = require("utils.text_utils")
local colors = require("app_colors")
local UiScale = require("user_interface.ui_scale")
local images = require("images")
local katsudo = require("lib.katsudo")
local DebugController = require("controllers.dev.debug_controller")
local CanvasSpace = require("utils.canvas_space")

local NORMAL_CELL_W, NORMAL_CELL_H = 32, 24
local COMPACT_CELL_W, COMPACT_CELL_H = 20, 13

local function buildSelectionAnim()
  if images and images.palette_selection then
    return katsudo.new(images.palette_selection, 32, 24, 4, 0.1)
  end
  -- Fallback for test environment with no image assets.
  return { draw = function() end }
end

local function buildStripSelectionAnim()
  if images and images.strip_palette_selection then
    return katsudo.new(images.strip_palette_selection, 8, 6, 4, 0.1)
  end
  return { draw = function() end }
end

local PaletteWindow = {
  selection = buildSelectionAnim(),
  stripSelection = buildStripSelectionAnim(),
}
PaletteWindow.__index = PaletteWindow
setmetatable(PaletteWindow, { __index = Window })

local function clamp(n,a,b) if n<a then return a elseif n>b then return b else return n end end
local function hex2(n) return string.format("%02X", n) end

local function getLabelTextColor(rgb)
  rgb = rgb or colors.black
  local r, g, b = rgb[1] or 0, rgb[2] or 0, rgb[3] or 0
  local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
  local base = (luminance >= 0.5) and colors.black or colors.white
  if luminance >= 0.5 then
    return { base[1], base[2], base[3], 0.5 }
  end
  return { base[1], base[2], base[3], 0.5 }
end

local function nibbleAdjust(code, dx, dy)
  local v  = tonumber(code,16) or 0
  local hi = math.floor(v/16)
  local lo = v % 16
  hi = clamp(hi + (dy or 0), 0, 3)
  lo = clamp(lo + (dx or 0), 0, 15)
  return hex2(hi*16+lo)
end

local function markPaletteUnsaved()
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  if app and app.markUnsaved then
    app:markUnsaved("palette_color_change")
  end
end

local function recordPaletteColorUndo(win, actions, paletteStates)
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  if not (app and app.undoRedo and app.undoRedo.addPaletteColorEvent) then
    return false
  end
  return app.undoRedo:addPaletteColorEvent({
    type = "palette_color",
    actions = actions,
    paletteStates = paletteStates,
  })
end

local function invalidateLinkedPpuFrames(paletteWin)
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  if app and app.invalidatePpuFrameLayersAffectedByPaletteWin then
    app:invalidatePpuFrameLayersAffectedByPaletteWin(paletteWin)
  end
end

local function buildCodeFromNibbles(hi, lo)
  hi = clamp(tonumber(hi) or 0, 0, 3)
  lo = clamp(tonumber(lo) or 0, 0, 15)
  return hex2(hi * 16 + lo)
end

function PaletteWindow.new(x, y, zoom, paletteName, rows, cols, data)
  data = data or {}
  data.resizable = false -- palette windows can't be resized
  data.minWindowSize = 0
  rows, cols = rows or 1, cols or 4
  local cellW, cellH = NORMAL_CELL_W, NORMAL_CELL_H
  local self = Window.new(x, y, cellW, cellH, cols, rows, zoom or 1.0, data)
  setmetatable(self, PaletteWindow)
  self.isPalette   = true
  self.paletteName = paletteName or "smooth_fbx"
  self.palette     = Palettes[self.paletteName] or Palettes.smooth_fbx
  self.kind        = "palette"
  self.compactView = (data.compactView == true)
  self.normalCellW = NORMAL_CELL_W
  self.normalCellH = NORMAL_CELL_H
  self.compactCellW = COMPACT_CELL_W
  self.compactCellH = COMPACT_CELL_H
  -- activePalette: true if this is the active palette (only one should be active at a time)
  self.activePalette = (data.activePalette ~= nil) and data.activePalette or false

  -- Build codes grid (2D) and items[]; default to ShaderPaletteController codes if initCodes not given
  self.codes2D = {}
  local flat = data.initCodes or ShaderPaletteController.getCodes()
  local i = 1
  for r=0, rows-1 do
    self.codes2D[r] = {}
    for c=0, cols-1 do
      local code = flat[i] or "03"
      self.codes2D[r][c] = code
      self:set(c, r, code)
      i = i + 1
    end
  end
  
  -- Sync to global palette manager if this palette is active
  if self.activePalette then
    self:syncToGlobalPalette()
  end

  self:setCompactMode(self.compactView)

  return self
end

function PaletteWindow:supportsCompactMode()
  return true
end

function PaletteWindow:setCompactMode(enabled)
  self.compactView = (enabled == true)
  if self.compactView then
    self.cellW = self.compactCellW
    self.cellH = self.compactCellH
  else
    self.cellW = self.normalCellW
    self.cellH = self.normalCellH
  end
  return self.compactView
end

-- Items cannot be removed
function PaletteWindow:clear(col,row) end

-- Override setSelected to add debug logging for color selection
function PaletteWindow:setSelected(col, row, layerIndex)
  Window.setSelected(self, col, row, layerIndex)
  if col ~= nil and row ~= nil then
    local code = self.codes2D and self.codes2D[row] and self.codes2D[row][col]
    if code then
      DebugController.log("info", "PAL", "Palette '%s' color selected: (%d,%d) = %s", self.title or "untitled", col, row, code)
    end
  end
end

-- Arrow keys move selection inside palette bounds.
function PaletteWindow:moveSelectedByArrows(dx,dy)
  if (dx or 0) == 0 and (dy or 0) == 0 then return false end
  local sc, sr, li = self:getSelected()
  if sc == nil or sr == nil then return false end

  local nc = clamp(sc + (dx or 0), 0, (self.cols or 1) - 1)
  local nr = clamp(sr + (dy or 0), 0, (self.rows or 1) - 1)
  if nc == sc and nr == sr then return false end

  self:setSelected(nc, nr, li)
  return true
end

-- Arrow keys tweak the selected cell's code
function PaletteWindow:adjustSelectedByArrows(dx,dy)
  local sc, sr = self:getSelected()
  if not sc or not sr then return end
  local old = self.codes2D[sr][sc]
  local new = nibbleAdjust(old, dx, dy)
  if new == old then return end
  self.codes2D[sr][sc] = new
  self:set(sc, sr, new)
  
  DebugController.log("info", "PAL", "Palette '%s' color adjusted at (%d,%d): %s -> %s", self.title or "untitled", sc, sr, old, new)
  
  -- Sync to global palette manager if this palette is active
  if self.activePalette then
    if self.rows==1 and self.cols==4 then
      ShaderPaletteController.setCodeAt(sc+1, new)
    else
      -- For multi-row palettes, sync all codes to global
      local flat = {}
      for r=0, self.rows-1 do
        for c=0, self.cols-1 do
          local idx = r * self.cols + c + 1
          flat[idx] = self.codes2D[r][c]
        end
      end
      ShaderPaletteController.setCodes(flat)
    end
    invalidateLinkedPpuFrames(self)
  end

  recordPaletteColorUndo(self, {
    {
      win = self,
      row = sr,
      col = sc,
      beforeCode = old,
      afterCode = new,
    }
  })

  markPaletteUnsaved()
end

-- Sync this palette's codes to the global palette manager
function PaletteWindow:syncToGlobalPalette()
  if not self.activePalette then return end
  
  local flat = {}
  for r=0, self.rows-1 do
    for c=0, self.cols-1 do
      local idx = r * self.cols + c + 1
      flat[idx] = self.codes2D[r][c]
    end
  end
  -- Only sync first 4 codes if standard 1x4 palette
  if self.rows==1 and self.cols==4 then
    ShaderPaletteController.setCodes(flat)
  else
    ShaderPaletteController.setCodes(flat)
  end
end

function PaletteWindow:getFirstColor()
  return self.palette[self.codes2D[0][0]]
end

function PaletteWindow:getSelectedStripCodes()
  local selected = self.selected
  local row = selected and selected.row or nil
  local col = selected and selected.col or nil
  local code = row ~= nil and col ~= nil and self.codes2D and self.codes2D[row] and self.codes2D[row][col] or nil
  if type(code) ~= "string" then
    return nil
  end

  local value = tonumber(code, 16)
  if not value then
    return nil
  end

  local highNibble = math.floor(value / 16)
  local lowNibble = value % 16
  local rowCodes = {}
  local colCodes = {}

  for i = 0, 15 do
    rowCodes[#rowCodes + 1] = buildCodeFromNibbles(highNibble, i)
  end

  for i = 0, 3 do
    colCodes[#colCodes + 1] = buildCodeFromNibbles(i, lowNibble)
  end

  return {
    code = code,
    rowIndex = highNibble,
    colIndex = lowNibble,
    rowCodes = rowCodes,
    colCodes = colCodes,
  }
end

function PaletteWindow:getStripMetrics()
  if self.compactView then
    return nil
  end

  local selectedRow = self.selected and self.selected.row or 0
  local gridW = (self.cols or 0) * (self.cellW or 0)
  local gridH = (self.rows or 0) * (self.cellH or 0)
  local gap = 1
  local horizontalCellW = math.max(4, math.floor((self.cellW or 0) / 4 + 0.5))
  local horizontalCellH = math.max(4, math.floor((self.cellH or 0) / 4 + 0.5))
  local verticalCellW = horizontalCellW
  local verticalCellH = horizontalCellH

  return {
    gap = gap,
    horizontalX = 0,
    horizontalY = gridH + gap,
    horizontalCellW = horizontalCellW,
    horizontalCellH = horizontalCellH,
    verticalX = gridW + gap,
    verticalY = (selectedRow or 0) * (self.cellH or 0),
    verticalCellW = verticalCellW,
    verticalCellH = verticalCellH,
    extraWidth = gap + verticalCellW,
    extraHeight = gap + horizontalCellH,
  }
end

function PaletteWindow:drawSelectionStrips()
  local gctx = rawget(_G, "ctx")
  local wm = gctx and gctx.wm and gctx.wm() or nil
  if wm and wm.getFocus and wm:getFocus() ~= self then
    return nil
  end

  local strips = self:getSelectedStripCodes()
  if not strips then
    return nil
  end

  local metrics = self:getStripMetrics()
  if not metrics then
    return nil
  end

  for i, code in ipairs(strips.rowCodes) do
    local rgb = self.palette[code] or colors.black
    local x = metrics.horizontalX + ((i - 1) * metrics.horizontalCellW)
    local y = metrics.horizontalY
    love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
    love.graphics.rectangle("fill", x, y, metrics.horizontalCellW, metrics.horizontalCellH)
  end

  for i, code in ipairs(strips.colCodes) do
    local rgb = self.palette[code] or colors.black
    local x = metrics.verticalX
    local y = metrics.verticalY + ((i - 1) * metrics.verticalCellH)
    love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
    love.graphics.rectangle("fill", x, y, metrics.verticalCellW, metrics.verticalCellH)
  end

  love.graphics.setColor(colors.white)
  local horizontalMarkerX = metrics.horizontalX + (strips.colIndex * metrics.horizontalCellW)
  local horizontalMarkerY = metrics.horizontalY
  local verticalMarkerX = metrics.verticalX
  local verticalMarkerY = metrics.verticalY + (strips.rowIndex * metrics.verticalCellH)
  self.stripSelection:draw(horizontalMarkerX, horizontalMarkerY)
  self.stripSelection:draw(verticalMarkerX, verticalMarkerY)

  local horizontalStripW = #strips.rowCodes * metrics.horizontalCellW
  local horizontalStripH = metrics.horizontalCellH
  local verticalStripW = metrics.verticalCellW
  local verticalStripH = #strips.colCodes * metrics.verticalCellH

  love.graphics.setColor(colors.blue)
  love.graphics.rectangle("line",
    metrics.horizontalX,
    metrics.horizontalY,
    horizontalStripW + 1,
    horizontalStripH + 1
  )
  love.graphics.rectangle("line",
    metrics.verticalX,
    metrics.verticalY,
    verticalStripW + 1,
    verticalStripH + 1
  )

  return metrics
end

-- override parent
function PaletteWindow:highlightSelected(cw, ch)
  if self.selected and not self.compactView then
    local scx, scy = self.selected.col * cw, self.selected.row * ch
    love.graphics.setColor(colors.white)
    self.selection:draw(scx, scy)
  end
end

-- override parent
function PaletteWindow:drawGrid()
  local sx, sy, sw, sh = self:getScreenRect()
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  local z = (self.getZoomLevel and self:getZoomLevel()) or self.zoom or 1
  love.graphics.scale(z, z)

  local cw, ch = self.cellW, self.cellH
  for r=0, self.rows-1 do
    for c=0, self.cols-1 do
      local x, y = c*cw, r*ch
      local code = self.codes2D[r][c]
      local rgb  = (self.palette[code] or colors.black)
      love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
      love.graphics.rectangle("fill", x, y, cw, ch)

      if self.activePalette then
        Text.print(code, x + 3, y + 3, {
          color = getLabelTextColor(rgb),
          shadowColor = colors.transparent,
        })
      end

      love.graphics.setColor(colors.white)
    end
  end

  love.graphics.setScissor()
  self:drawSelectionStrips()
  if self.activePalette then
    self:highlightSelected(cw, ch)
  end
  love.graphics.pop()
  love.graphics.setColor(colors.white)
end

return PaletteWindow
