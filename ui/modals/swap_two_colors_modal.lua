-- Modal: swap two palette indices on selected tile/sprite item(s).
-- Layout: [before] → [ramp] → [after], then Swap/Cancel.

local Button = require("ui.button")
local Panel = require("ui.panel")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local SwapTwoColorsController = require("controllers.chr.swap_two_colors_controller")
local Tile = require("ui.windows_system.tile_item")
local images = require("images")
local colors = require("app_colors")
local Draw = require("utils.draw_utils")

local Dialog = {}
Dialog.__index = Dialog

local TILE = 8
local PREVIEW_SCALE = 4
local SWATCH_SIZE = 10
local SWATCH_GAP = 2
local SWATCH_PAD = 1
local SECTION_GAP = 6
local CONTENT_PAD_X = 8
local CONTENT_PAD_Y = 8
local SELECTION_RECT_ANIM = {
  stepPx = 1,
  intervalSeconds = 0.1,
}

local function rowspanForHeight(height, cellH, spacingY)
  cellH = math.max(1, math.floor(tonumber(cellH) or 15))
  spacingY = math.max(0, math.floor(tonumber(spacingY) or 0))
  local step = cellH + spacingY
  return math.max(1, math.ceil((math.max(1, height) + spacingY) / step))
end

local function cloneScratchTile(srcTile)
  local t = Tile.blank(0)
  if srcTile and srcTile.pixels then
    for i = 1, 64 do
      t.pixels[i] = srcTile.pixels[i] or 0
    end
  end
  return t
end

local function scrollRightIcon()
  return images and images.icons and images.icons.chrome and images.icons.chrome.icon_scroll_toolbar_right
end

local function iconSize(icon)
  if not icon then
    return 15, 15
  end
  if type(icon.getWidth) == "function" and type(icon.getHeight) == "function" then
    return icon:getWidth() or 15, icon:getHeight() or 15
  end
  return tonumber(icon.w) or 15, tonumber(icon.h) or 15
end

----------------------------------------------------------------
-- Preview strip (before or after)
----------------------------------------------------------------

local PreviewStrip = {}
PreviewStrip.__index = PreviewStrip

function PreviewStrip.new()
  return setmetatable({
    x = 0,
    y = 0,
    w = TILE * PREVIEW_SCALE + 4,
    h = TILE * PREVIEW_SCALE + 4,
    top = nil,
    bot = nil,
    mode = "8x8",
    layer = nil,
    item = nil,
    romRaw = nil,
    paletteNumber = 1,
  }, PreviewStrip)
end

function PreviewStrip:setPosition(x, y)
  self.x = math.floor(tonumber(x) or 0)
  self.y = math.floor(tonumber(y) or 0)
end

function PreviewStrip:setSize(w, h)
  if type(w) == "number" then self.w = math.floor(w) end
  if type(h) == "number" then self.h = math.floor(h) end
end

function PreviewStrip:contains(px, py)
  return px >= self.x and px < self.x + self.w
    and py >= self.y and py < self.y + self.h
end

function PreviewStrip:contentSize()
  local pw = TILE * PREVIEW_SCALE
  local ph = (self.mode == "8x16") and (TILE * 2 * PREVIEW_SCALE) or (TILE * PREVIEW_SCALE)
  return pw, ph
end

function PreviewStrip:setTiles(top, bot, mode)
  self.top = top
  self.bot = bot
  self.mode = (mode == "8x16") and "8x16" or "8x8"
  local cw, ch = self:contentSize()
  self.w = cw
  self.h = ch
end

function PreviewStrip:draw()
  local pw = TILE * PREVIEW_SCALE
  local ph = (self.mode == "8x16") and (TILE * 2 * PREVIEW_SCALE) or (TILE * PREVIEW_SCALE)
  local boxX = math.floor(self.x + math.floor((self.w - pw) * 0.5))
  local boxY = math.floor(self.y + math.floor((self.h - ph) * 0.5))

  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", boxX, boxY, pw, ph)

  if self.top then
    ShaderPaletteController.applyLayerItemPalette(
      self.layer,
      self.item,
      true,
      self.romRaw,
      self.paletteNumber,
      1.0,
      { transparentZero = false }
    )
    if self.top.draw then
      self.top:draw(boxX, boxY, PREVIEW_SCALE)
    end
    if self.mode == "8x16" and self.bot and self.bot.draw then
      self.bot:draw(boxX, boxY + TILE * PREVIEW_SCALE, PREVIEW_SCALE)
    end
    ShaderPaletteController.releaseShader()
  end

  if images and images.pattern_a then
    love.graphics.setColor(1, 1, 1, 1)
    Draw.drawRepeatingImageAnimated(
      images.pattern_a,
      boxX,
      boxY,
      pw,
      ph,
      SELECTION_RECT_ANIM
    )
  else
    love.graphics.setColor(colors.white)
    love.graphics.rectangle("line", boxX, boxY, pw, ph)
  end
  love.graphics.setColor(colors.white)
end

----------------------------------------------------------------
-- Color ramp picker (max 2 selections) — compact horizontal strip
----------------------------------------------------------------

local ColorRamp = {}
ColorRamp.__index = ColorRamp

function ColorRamp.new(onChanged)
  local n = 4
  local w = SWATCH_PAD * 2 + n * SWATCH_SIZE + (n - 1) * SWATCH_GAP
  local h = SWATCH_PAD * 2 + SWATCH_SIZE
  return setmetatable({
    x = 0,
    y = 0,
    w = w,
    h = h,
    colorsRgb = nil,
    selected = {}, -- ordered list of 0-based indices, max 2
    onChanged = onChanged,
  }, ColorRamp)
end

function ColorRamp:setPosition(x, y)
  self.x = math.floor(tonumber(x) or 0)
  self.y = math.floor(tonumber(y) or 0)
end

function ColorRamp:setSize(w, h)
  if type(w) == "number" then self.w = math.floor(w) end
  if type(h) == "number" then self.h = math.floor(h) end
end

function ColorRamp:contains(px, py)
  return px >= self.x and px < self.x + self.w
    and py >= self.y and py < self.y + self.h
end

function ColorRamp:contentSize()
  local n = 4
  local w = SWATCH_PAD * 2 + n * SWATCH_SIZE + (n - 1) * SWATCH_GAP
  local h = SWATCH_PAD * 2 + SWATCH_SIZE
  return w, h
end

function ColorRamp:setColors(rgbList)
  self.colorsRgb = rgbList
end

function ColorRamp:getSelectedPair()
  if #self.selected == 2 then
    return self.selected[1], self.selected[2]
  end
  return nil, nil
end

function ColorRamp:clearSelection()
  self.selected = {}
  if self.onChanged then
    self.onChanged(self)
  end
end

function ColorRamp:_swatchRect(i)
  local x = math.floor(self.x + SWATCH_PAD + (i - 1) * (SWATCH_SIZE + SWATCH_GAP))
  local y = math.floor(self.y + math.floor((self.h - SWATCH_SIZE) * 0.5))
  return x, y, SWATCH_SIZE, SWATCH_SIZE
end

function ColorRamp:_indexAt(px, py)
  for i = 1, 4 do
    local x, y, w, h = self:_swatchRect(i)
    if px >= x and px < x + w and py >= y and py < y + h then
      return i - 1
    end
  end
  return nil
end

function ColorRamp:isHoveringSwatchAt(px, py)
  return self:_indexAt(px, py) ~= nil
end

function ColorRamp:_isSelected(idx0)
  for _, s in ipairs(self.selected) do
    if s == idx0 then
      return true
    end
  end
  return false
end

function ColorRamp:toggleIndex(idx0)
  if type(idx0) ~= "number" or idx0 < 0 or idx0 > 3 then
    return
  end
  for i, s in ipairs(self.selected) do
    if s == idx0 then
      table.remove(self.selected, i)
      if self.onChanged then
        self.onChanged(self)
      end
      return
    end
  end
  if #self.selected >= 2 then
    table.remove(self.selected, 1)
  end
  self.selected[#self.selected + 1] = idx0
  if self.onChanged then
    self.onChanged(self)
  end
end

function ColorRamp:mousepressed(px, py, button)
  if button ~= 1 then
    return false
  end
  local idx = self:_indexAt(px, py)
  if idx == nil then
    return false
  end
  self:toggleIndex(idx)
  return true
end

function ColorRamp:draw()
  local rgb = self.colorsRgb
  for i = 1, 4 do
    local x, y, w, h = self:_swatchRect(i)
    local c = rgb and rgb[i] or colors.gray or { 0.4, 0.4, 0.4 }
    love.graphics.setColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
    love.graphics.rectangle("fill", x, y, w, h)
    if self:_isSelected(i - 1) and images and images.pattern_a then
      love.graphics.setColor(1, 1, 1, 1)
      Draw.drawRepeatingImageAnimated(
        images.pattern_a,
        x,
        y,
        w,
        h,
        SELECTION_RECT_ANIM
      )
    end
  end
  love.graphics.setColor(colors.white)
end

----------------------------------------------------------------
-- Horizontal content row: preview → arrow → ramp → arrow → preview
----------------------------------------------------------------

local ContentRow = {}
ContentRow.__index = ContentRow

function ContentRow.new(beforePreview, colorRamp, afterPreview)
  return setmetatable({
    x = 0,
    y = 0,
    w = 100,
    h = 40,
    beforePreview = beforePreview,
    colorRamp = colorRamp,
    afterPreview = afterPreview,
  }, ContentRow)
end

function ContentRow:setPosition(x, y)
  self.x = math.floor(tonumber(x) or 0)
  self.y = math.floor(tonumber(y) or 0)
  self:_layoutChildren()
end

function ContentRow:setSize(w, h)
  if type(w) == "number" then self.w = math.floor(w) end
  if type(h) == "number" then self.h = math.floor(h) end
  self:_layoutChildren()
end

function ContentRow:contains(px, py)
  return px >= self.x and px < self.x + self.w
    and py >= self.y and py < self.y + self.h
end

function ContentRow:_arrowSize()
  return iconSize(scrollRightIcon())
end

function ContentRow:preferredSize()
  local bw, bh = self.beforePreview:contentSize()
  local rw, rh = self.colorRamp:contentSize()
  local aw, ah = self:_arrowSize()
  local aw2, ah2 = self.afterPreview:contentSize()
  local inner = bw + SECTION_GAP + aw + SECTION_GAP + rw + SECTION_GAP + aw + SECTION_GAP + aw2
  local w = inner + CONTENT_PAD_X * 2
  local h = math.max(bh, rh, ah, ah2) + CONTENT_PAD_Y * 2
  return w, h
end

function ContentRow:_layoutChildren()
  local bw, bh = self.beforePreview:contentSize()
  local rw, rh = self.colorRamp:contentSize()
  local aw, ah = self:_arrowSize()
  local aw2, ah2 = self.afterPreview:contentSize()
  local contentH = math.max(bh, rh, ah, ah2)
  local rowH = math.max(contentH + CONTENT_PAD_Y * 2, self.h)
  local contentTop = self.y + CONTENT_PAD_Y

  local x = self.x + CONTENT_PAD_X
  local function place(comp, cw, ch)
    local cy = contentTop + math.floor((contentH - ch) * 0.5)
    comp:setPosition(x, cy)
    comp:setSize(cw, ch)
    x = x + cw + SECTION_GAP
  end

  place(self.beforePreview, bw, bh)
  self._arrow1X = x
  self._arrow1Y = contentTop + math.floor((contentH - ah) * 0.5)
  self._arrowW = aw
  self._arrowH = ah
  x = x + aw + SECTION_GAP
  place(self.colorRamp, rw, rh)
  self._arrow2X = x
  self._arrow2Y = contentTop + math.floor((contentH - ah) * 0.5)
  x = x + aw + SECTION_GAP
  place(self.afterPreview, aw2, ah2)

  self.w = math.max(self.w, (x - self.x) + CONTENT_PAD_X)
  self.h = rowH
end

function ContentRow:_drawArrow(ax, ay)
  local icon = scrollRightIcon()
  if icon then
    love.graphics.setColor(colors.white)
    Draw.drawIcon(icon, ax, ay)
  else
    love.graphics.setColor(colors.white)
    love.graphics.print(">", ax, ay)
  end
end

function ContentRow:draw()
  self:_layoutChildren()
  if self.beforePreview.draw then
    self.beforePreview:draw()
  end
  self:_drawArrow(self._arrow1X or self.x, self._arrow1Y or self.y)
  if self.colorRamp.draw then
    self.colorRamp:draw()
  end
  self:_drawArrow(self._arrow2X or self.x, self._arrow2Y or self.y)
  if self.afterPreview.draw then
    self.afterPreview:draw()
  end
end

function ContentRow:mousepressed(px, py, button)
  if self.colorRamp and self.colorRamp:contains(px, py) then
    return self.colorRamp:mousepressed(px, py, button)
  end
  return false
end

----------------------------------------------------------------
-- Dialog
----------------------------------------------------------------

local function syncContentMetrics(self)
  local cw, ch = self.contentRow:preferredSize()
  self.contentRow.w = cw
  self.contentRow.h = ch
  local spacingX = self.buttonGap or self.colGap or 0
  -- Two equal columns so Swap/Cancel sit under the row; widen to fit content.
  self.cellW = math.max(self.buttonW or 68, math.ceil((cw - spacingX) / 2))
end

local function rebuildPanel(self)
  syncContentMetrics(self)
  local cellH = self.cellH
  local spacingY = self.rowGap or 0
  local _, contentH = self.contentRow:preferredSize()
  local contentRows = rowspanForHeight(contentH, cellH, spacingY)
  local totalRows = contentRows + 2 -- buttons + Esc

  self.panel = Panel.new({
    cols = 2,
    rows = totalRows,
    cellW = self.cellW,
    cellH = cellH,
    padding = self.padding,
    spacingX = self.buttonGap,
    spacingY = spacingY,
    cellPaddingX = self.cellPaddingX,
    cellPaddingY = self.cellPaddingY,
    visible = self.visible,
    title = self.title,
    titleH = self.titleH,
    bgColor = self.bgColor,
    titleBgColor = self.titleBgColor,
    _modalChromeOverBlue = self._modalChromeOverBlue == true,
  })

  local buttonRow = contentRows + 1
  local escRow = buttonRow + 1

  self.panel:setCell(1, 1, {
    component = self.contentRow,
    colspan = 2,
    rowspan = contentRows,
  })
  self.panel:setCell(1, buttonRow, { component = self.applyButton })
  self.panel:setCell(2, buttonRow, { component = self.cancelButton })
  self.panel:setCell(1, escRow, { text = "Esc) Close", colspan = 2 })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Swap 2 colors",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = 68,
    cellH = nil,
    buttonW = 68,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    onConfirm = nil,
    onCancel = nil,
    context = nil,
    app = nil,
    panel = nil,
    _sourceTop = nil,
    _sourceBot = nil,
    _previewMode = "8x8",
    _afterTop = nil,
    _afterBot = nil,
  }, Dialog)

  self.beforePreview = PreviewStrip.new()
  self.afterPreview = PreviewStrip.new()
  self.colorRamp = ColorRamp.new(function()
    self:_refreshAfterPreview()
    self:_updateApplyEnabled()
  end)
  self.contentRow = ContentRow.new(self.beforePreview, self.colorRamp, self.afterPreview)

  self.applyButton = Button.new({
    text = "Swap",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    enabled = false,
    action = function()
      self:_confirm()
    end,
  })

  self.cancelButton = Button.new({
    text = "Cancel",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_cancel()
    end,
  })

  ModalPanelUtils.applyPanelDefaults(self)
  self.buttonGap = self.colGap
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible
end

--- Hand cursor only over the four ramp swatches (not previews / arrows / buttons).
function Dialog:isHoveringColorRampSwatchAt(px, py)
  if not self.visible or not self.colorRamp then
    return false
  end
  if self.contentRow and type(self.contentRow._layoutChildren) == "function" then
    self.contentRow:_layoutChildren()
  end
  return self.colorRamp:isHoveringSwatchAt(px, py) == true
end

function Dialog:_updateApplyEnabled()
  local a, b = self.colorRamp:getSelectedPair()
  local enabled = a ~= nil and b ~= nil and a ~= b
  self.applyButton.enabled = enabled
end

function Dialog:_refreshAfterPreview()
  local a, b = self.colorRamp:getSelectedPair()
  if not (self._sourceTop and a ~= nil and b ~= nil) then
    self._afterTop = self._sourceTop and cloneScratchTile(self._sourceTop) or nil
    self._afterBot = self._sourceBot and cloneScratchTile(self._sourceBot) or nil
  else
    local remappedTop = SwapTwoColorsController.remapPixelsCopy(self._sourceTop.pixels, a, b)
    self._afterTop = Tile.blank(0)
    if remappedTop then
      self._afterTop.pixels = remappedTop
    end
    if self._sourceBot then
      local remappedBot = SwapTwoColorsController.remapPixelsCopy(self._sourceBot.pixels, a, b)
      self._afterBot = Tile.blank(0)
      if remappedBot then
        self._afterBot.pixels = remappedBot
      end
    else
      self._afterBot = nil
    end
  end

  self.afterPreview:setTiles(self._afterTop, self._afterBot, self._previewMode)
  self.afterPreview.layer = self.beforePreview.layer
  self.afterPreview.item = self.beforePreview.item
  self.afterPreview.romRaw = self.beforePreview.romRaw
  self.afterPreview.paletteNumber = self.beforePreview.paletteNumber
end

function Dialog:_syncPreviewMeta(context, app)
  local layer = context and context.layer
  local item = context and context.item
  local romRaw = app and app.appEditState and app.appEditState.romRaw
  local palNum = SwapTwoColorsController.resolveContextPaletteNumber(context)
  local rgb = ShaderPaletteController.getPaletteColors(layer, palNum, romRaw)

  self.colorRamp:setColors(rgb)
  self.beforePreview.layer = layer
  self.beforePreview.item = item
  self.beforePreview.romRaw = romRaw
  self.beforePreview.paletteNumber = palNum
  self.afterPreview.layer = layer
  self.afterPreview.item = item
  self.afterPreview.romRaw = romRaw
  self.afterPreview.paletteNumber = palNum
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Swap 2 colors"
  self.context = opts.context
  self.app = opts.app
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true

  self:_syncPreviewMeta(self.context, self.app)

  local preview = SwapTwoColorsController.resolvePreviewTiles(self.app, self.context)
  self._previewMode = (preview and preview.mode) or "8x8"
  self._sourceTop = preview and preview.top or nil
  self._sourceBot = preview and preview.bot or nil

  if self._sourceTop then
    self._sourceTop = cloneScratchTile(self._sourceTop)
  end
  if self._sourceBot then
    self._sourceBot = cloneScratchTile(self._sourceBot)
  end

  self.beforePreview:setTiles(self._sourceTop, self._sourceBot, self._previewMode)
  self.colorRamp.selected = {}
  self:_refreshAfterPreview()
  self:_updateApplyEnabled()

  self.applyButton.pressed = false
  self.cancelButton.pressed = false
  self.applyButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.onConfirm = nil
  self.onCancel = nil
  self.context = nil
  self.app = nil
  self._sourceTop = nil
  self._sourceBot = nil
  self._afterTop = nil
  self._afterBot = nil
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:_containsBox(x, y)
  if self.panel and self._boxX then
    return self.panel:contains(x, y)
  end
  return true
end

function Dialog:getTooltipAt(x, y)
  if not self.visible or not self.panel or not self:_containsBox(x, y) then
    return nil
  end
  return self.panel:getTooltipAt(x, y)
end

function Dialog:_confirm()
  local a, b = self.colorRamp:getSelectedPair()
  if a == nil or b == nil then
    return false
  end
  local callback = self.onConfirm
  local context = self.context
  if callback then
    local ok = callback(a, b, context)
    if ok == false then
      return false
    end
  end
  self:hide()
  return true
end

function Dialog:_cancel()
  local callback = self.onCancel
  self:hide()
  if callback then
    callback()
  end
  return true
end

function Dialog:handleKey(key)
  if not self.visible then return false end
  if key == "escape" then
    self:_cancel()
    return true
  end
  if key == "return" or key == "kpenter" then
    if self.applyButton.enabled ~= false then
      self:_confirm()
    end
    return true
  end
  if key == "1" or key == "2" or key == "3" or key == "4" then
    self.colorRamp:toggleIndex(tonumber(key) - 1)
    return true
  end
  return false
end

function Dialog:textinput(_text)
  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end
  if not self:_containsBox(x, y) then
    self:_cancel()
    return true
  end
  return self.panel and self.panel:mousepressed(x, y, button) or true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  return self.panel and self.panel:mousereleased(x, y, button) or true
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end
  if self.panel then
    self.panel:mousemoved(x, y)
  end
  return true
end

function Dialog:draw(canvas)
  if not self.visible then return end
  ModalPanelUtils.refreshTargetMetrics(self)
  if not self.panel then
    rebuildPanel(self)
  else
    syncContentMetrics(self)
    self.panel.cellW = self.cellW
    self.panel.cellH = self.cellH
    self.panel.padding = self.padding
    self.panel.spacingX = self.buttonGap
    self.panel.spacingY = self.rowGap
    self.panel.cellPaddingX = self.cellPaddingX
    self.panel.cellPaddingY = self.cellPaddingY
    self.panel.title = self.title
    self.panel.titleH = self.titleH
    self.panel.bgColor = self.bgColor
    self.panel.titleBgColor = self.titleBgColor
    ModalPanelUtils.syncPanelChrome(self.panel, self)
    self.panel:setVisible(true)
  end
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
end

Dialog._ColorRamp = ColorRamp
Dialog._PreviewStrip = PreviewStrip
Dialog._ContentRow = ContentRow

return Dialog
