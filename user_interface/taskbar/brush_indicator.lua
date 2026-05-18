local colors = require("app_colors")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local Text = require("utils.text_utils")

local M = {}

local function clampBrushColorIndex(app)
  return math.max(1, math.min(4, ((app and app.currentColor) or 0) + 1))
end

function M.install(Taskbar, Helpers)
  local function resolveBrushIndicatorColor(app)
    local colorIndex = clampBrushColorIndex(app)
    local fallback = ShaderPaletteController.colorOfIndex(colorIndex) or colors.white
    if not app then
      return fallback
    end

    local wm = app.wm
    if not (wm and wm.windowAt and wm.getFocus) then
      return fallback
    end

    local mouse = ResolutionController:getScaledMouse(true)
    local win = wm:windowAt(mouse.x, mouse.y)
    if not win or win.isPalette then
      win = wm:getFocus()
    end
    if not win or win.isPalette then
      return fallback
    end

    local li = win.getActiveLayerIndex and win:getActiveLayerIndex() or 1
    local layer = win.layers and win.layers[li]
    if not layer then
      return fallback
    end

    local paletteNum
    if layer.kind == "sprite" then
      local spriteIdx = layer.hoverSpriteIndex or layer.selectedSpriteIndex
      local item = spriteIdx and layer.items and layer.items[spriteIdx] or nil
      paletteNum = item and item.paletteNumber or nil
    else
      local col, row
      if win.toGridCoords then
        local ok, c, r = win:toGridCoords(mouse.x, mouse.y)
        if ok then
          col, row = c, r
        end
      end
      if (not col or not row) and win.getSelected then
        local sc, sr, sl = win:getSelected()
        if sc and sr and (not sl or sl == li) then
          col, row = sc, sr
        end
      end
      if col and row then
        local idx = row * (win.cols or 1) + col
        if layer.paletteNumbers then
          paletteNum = layer.paletteNumbers[idx]
        end
      end
    end

    if not paletteNum then
      return fallback
    end

    local romRaw = app.appEditState and app.appEditState.romRaw
    local paletteColors = ShaderPaletteController.getPaletteColors(layer, paletteNum, romRaw)
    if paletteColors and paletteColors[colorIndex] then
      return paletteColors[colorIndex]
    end

    return fallback
  end

  local function drawBrushIndicator(self, swatchX, swatchY, swatchSize)
    local brushColor = resolveBrushIndicatorColor(self.app)
    love.graphics.setColor(colors.black)
    love.graphics.rectangle("fill", swatchX - 1, swatchY - 1, swatchSize + 2, swatchSize + 2)
    love.graphics.setColor(brushColor[1] or 1, brushColor[2] or 1, brushColor[3] or 1, 1)
    love.graphics.rectangle("fill", swatchX, swatchY, swatchSize, swatchSize)
  end

  function Taskbar:drawBrushIndicatorTopRight()
    local swatchSize = math.max(6, self.h - 6)
    local swatchX = math.floor(self.x + self.w - Helpers.CONTROL_GAP - swatchSize)
    local swatchY = math.floor(Helpers.CONTROL_GAP)
    drawBrushIndicator(self, swatchX, swatchY, swatchSize)
    love.graphics.setColor(colors.white)
  end

  function Taskbar:_drawStatusWithBrushIndicator(eventText, opts)
    opts = opts or {}
    local drawStatusText = (opts.drawStatusText ~= false)
    local drawBrush = (opts.drawBrush ~= false)
    local status = Helpers.formatStatusText(eventText)
    local margin = Helpers.CONTROL_GAP

    local swatchSize = math.max(6, self.h - 6)
    local controlsEndX = self.x + self.paddingX
    if #self.buttons > 0 then
      local last = self.buttons[#self.buttons]
      controlsEndX = last.x + last.w
    end
    local swatchX = math.floor(controlsEndX + margin)
    local swatchY = math.floor(self.y + (self.h - swatchSize) * 0.5)
    if drawBrush then
      drawBrushIndicator(self, swatchX, swatchY, swatchSize)
    end

    local leftAfterControls = swatchX + swatchSize + margin
    local textX = leftAfterControls
    local textRight = self.x + self.w - margin
    local maxTextWidth = math.max(0, textRight - textX)
    local statusDisplay = Helpers.fitStatusText(status, maxTextWidth)
    local font = love.graphics.getFont()
    local statusW = Text.safeGetFontWidth(statusDisplay, font)
    local drawX = math.max(textX, textRight - statusW)

    if drawStatusText then
      Text.print(statusDisplay, drawX, self.y + 3, { color = colors.white })
    end
  end
end

return M
