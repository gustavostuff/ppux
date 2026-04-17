local Draw = require("utils.draw_utils")
local colors = require("app_colors")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local Text = require("utils.text_utils")

local M = {}

local MODE_BADGE_TEXT_PAD_X = 6
local MODE_BADGE_ICON_GAP = 0
local MODE_BADGE_TILE_BG = { 0.0, 0.56, 0.0 }
local MODE_BADGE_EDIT_BG = { 0.82, 0.64, 0.16 }

local function clampBrushColorIndex(app)
  return math.max(1, math.min(4, ((app and app.currentColor) or 0) + 1))
end

function M.install(Taskbar, Helpers)
  local function resolveBrushIndicatorColor(app)
    local colorIndex = clampBrushColorIndex(app)
    local fallback = ShaderPaletteController.colorOfIndex(colorIndex) or colors.white
    if not app then return fallback end

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

  local function getModeIndicatorData(self)
    local mode = (self.app and self.app.mode == "edit") and "edit" or "tile"
    local isEdit = (mode == "edit")
    return {
      mode = mode,
      label = isEdit and "Edit" or "Tile",
      bg = isEdit and MODE_BADGE_EDIT_BG or MODE_BADGE_TILE_BG,
      -- Fixed contrast on colored badges: ignore theme textPrimary.
      textColor = isEdit and colors.black or colors.white,
      icon = isEdit and self.modeEditIcon or self.modeTileIcon,
      useCursorShader = isEdit,
    }
  end

  local function getModeIndicatorLayout(self)
    local data = getModeIndicatorData(self)
    local font = love.graphics.getFont()
    local textW = (font and font:getWidth(data.label)) or 0
    local textH = (font and font:getHeight()) or 0
    local badgeW = math.max(24, textW + (MODE_BADGE_TEXT_PAD_X * 2))
    local badgeH = self.h
    local iconW = self.h
    local iconH = self.h
    local totalW = badgeW + MODE_BADGE_ICON_GAP + iconW

    local badgeX = math.floor((self.x + self.w) - Helpers.CONTROL_GAP - totalW)
    local badgeY = self.y
    local iconX = badgeX + badgeW + MODE_BADGE_ICON_GAP
    local iconY = self.y
    local icon = data.icon
    local iw = (icon and icon.getWidth and icon:getWidth()) or iconW
    local ih = (icon and icon.getHeight and icon:getHeight()) or iconH
    local drawX = iconX + math.floor((iconW - iw) * 0.5)
    if icon and self.app and self.app.canvas and self.app.canvas.getWidth and icon.getWidth then
      drawX = self.app.canvas:getWidth() - icon:getWidth()
    end
    local drawY = math.floor(iconY + (iconH - ih) * 0.5)

    return {
      data = data,
      badgeX = badgeX,
      badgeY = badgeY,
      badgeW = badgeW,
      badgeH = badgeH,
      textW = textW,
      textH = textH,
      iconDrawX = drawX,
      iconDrawY = drawY,
      iconDrawW = iw,
      iconDrawH = ih,
    }
  end

  function Taskbar:_modeIndicatorContains(x, y)
    local layout = getModeIndicatorLayout(self)
    if Helpers.pointInRect(x, y, layout.badgeX, layout.badgeY, layout.badgeW, layout.badgeH) then
      return true
    end
    if Helpers.pointInRect(x, y, layout.iconDrawX, layout.iconDrawY, layout.iconDrawW, layout.iconDrawH) then
      return true
    end
    return false
  end

  function Taskbar:_toggleMode()
    local app = self and self.app
    if not app then return end
    if app._buildCtx then
      local ctx = app:_buildCtx()
      if ctx and ctx.getMode and ctx.setMode then
        local nextMode = (ctx.getMode() == "edit") and "tile" or "edit"
        ctx.setMode(nextMode)
        return
      end
    end
    app.mode = (app.mode == "edit") and "tile" or "edit"
  end

  function Taskbar:_drawModeIndicator()
    local layout = getModeIndicatorLayout(self)
    local data = layout.data

    local bg = data.bg
    love.graphics.setColor(bg[1], bg[2], bg[3], 1)
    love.graphics.rectangle("fill", layout.badgeX, layout.badgeY, layout.badgeW, layout.badgeH)

    local tc = data.textColor
    local textX = math.floor(layout.badgeX + (layout.badgeW - layout.textW) * 0.5)
    local textY = math.floor(layout.badgeY + (layout.badgeH - layout.textH) * 0.5)
    Text.print(data.label, textX, textY, {
      color = { tc[1], tc[2], tc[3], 1 },
      -- text_utils remaps near-white to textPrimary unless literal; badge needs fixed colors.
      literalColor = true,
    })

    local icon = data.icon
    if icon then
      if data.useCursorShader then
        local shader = Draw.getCursorShader and Draw.getCursorShader() or nil
        if shader then
          local paint = resolveBrushIndicatorColor(self.app) or colors.white
          shader:send("u_paintColor", { paint[1] or 1, paint[2] or 1, paint[3] or 1 })
          local now = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
          shader:send("u_time", now)
          shader:send("u_applyPaint", true)
          love.graphics.setShader(shader)
        end
        love.graphics.setColor(colors.white)
        Draw.drawIcon(icon, layout.iconDrawX, layout.iconDrawY, { respectTheme = false })
        love.graphics.setShader()
      else
        love.graphics.setColor(colors.white)
        Draw.drawIcon(icon, layout.iconDrawX, layout.iconDrawY, { respectTheme = false })
      end
    end

    love.graphics.setColor(colors.white)
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
    local statusW = (font and font:getWidth(statusDisplay)) or 0
    local drawX = math.max(textX, textRight - statusW)

    if drawStatusText then
      Text.print(statusDisplay, drawX, self.y + 3, { color = colors.white })
    end
  end
end

return M
