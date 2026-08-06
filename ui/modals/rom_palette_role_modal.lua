-- rom_palette_role_modal.lua
-- After creating a ROM Palette window: choose ROM-backed vs sketch free colors.

local Button = require("ui.button")
local Panel = require("ui.panel")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function rebuildPanel(self)
  local rows = 5 -- intro + 2 option blocks (label+button each condensed) + cancel
  -- Layout: intro, rom btn, rom hint, sketch btn, sketch hint, cancel
  rows = 6
  self.panel = Panel.new({
    cols = 1,
    rows = rows,
    cellW = self.cellW,
    cellH = self.cellH,
    padding = self.padding,
    spacingX = self.buttonGap,
    spacingY = self.rowGap,
    cellPaddingX = self.cellPaddingX,
    cellPaddingY = self.cellPaddingY,
    visible = self.visible,
    title = self.title,
    titleH = self.titleH,
    bgColor = self.bgColor,
    titleBgColor = self.titleBgColor,
    _modalChromeOverBlue = self._modalChromeOverBlue == true,
  })

  self.panel:setCell(1, 1, {
    kind = "label",
    text = self.introText,
    colspan = 1,
  })
  self.panel:setCell(1, 2, {
    component = self.romButton,
  })
  self.panel:setCell(1, 3, {
    kind = "label",
    text = self.romHint,
    colspan = 1,
  })
  self.panel:setCell(1, 4, {
    component = self.sketchButton,
  })
  self.panel:setCell(1, 5, {
    kind = "label",
    text = self.sketchHint,
    colspan = 1,
  })
  self.panel:setCell(1, 6, {
    component = self.cancelButton,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "ROM Palette type",
    introText = "How will this palette be used?",
    romHint = "Cells map to ROM addresses; link to PPU / OAM / static art.",
    sketchHint = "Free 4x4 colors for Sketch canvas art and gallery ROM export.",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    buttonW = 200,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    cellW = nil,
    cellH = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    pressedButton = nil,
    onChoose = nil,
    onCancel = nil,
    allowRomRole = true,
    panel = nil,
  }, Dialog)

  self.romButton = Button.new({
    text = "Existing ROM graphics",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_choose("rom")
    end,
  })
  self.sketchButton = Button.new({
    text = "Sketch canvas",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_choose("sketch")
    end,
  })
  self.cancelButton = Button.new({
    text = "Cancel",
    w = 72,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_cancel()
    end,
  })

  ModalPanelUtils.applyPanelDefaults(self)
  if (self.cellW or 0) < 320 then
    self.cellW = 320
  end
  self.buttonGap = self.colGap
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible
end

--- opts.allowRomRole (default true), opts.onChoose(role), opts.onCancel()
function Dialog:show(opts)
  opts = opts or {}
  self.allowRomRole = opts.allowRomRole ~= false
  self.onChoose = opts.onChoose
  self.onCancel = opts.onCancel
  self.title = opts.title or "ROM Palette type"
  self.visible = true
  self.pressedButton = nil
  self.romButton.enabled = self.allowRomRole
  self.romButton.pressed = false
  self.sketchButton.pressed = false
  self.cancelButton.pressed = false
  self.romButton.hovered = false
  self.sketchButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.pressedButton = nil
  self.onChoose = nil
  self.onCancel = nil
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

function Dialog:_choose(role)
  local callback = self.onChoose
  self:hide()
  if callback then
    callback(role)
  end
end

function Dialog:_cancel()
  local callback = self.onCancel
  self:hide()
  if callback then
    callback()
  end
end

function Dialog:handleKey(key)
  if not self.visible then
    return false
  end
  if key == "escape" then
    self:_cancel()
    return true
  end
  if key == "1" and self.allowRomRole then
    self:_choose("rom")
    return true
  end
  if key == "2" or (key == "1" and not self.allowRomRole) then
    self:_choose("sketch")
    return true
  end
  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then
    return false
  end
  if button ~= 1 then
    return true
  end
  if not self:_containsBox(x, y) then
    self:_cancel()
    return true
  end
  self.pressedButton = nil
  for _, b in ipairs({ self.romButton, self.sketchButton, self.cancelButton }) do
    if b.enabled ~= false and b:contains(x, y) then
      b.pressed = true
      self.pressedButton = b
      break
    end
  end
  return true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then
    return false
  end
  if button ~= 1 then
    return true
  end
  local pressedButton = self.pressedButton
  self.pressedButton = nil
  self.romButton.pressed = false
  self.sketchButton.pressed = false
  self.cancelButton.pressed = false
  if pressedButton and pressedButton:contains(x, y) and pressedButton.action then
    pressedButton.action()
  end
  return true
end

function Dialog:mousemoved(x, y)
  if not self.visible then
    return false
  end
  self.romButton.hovered = self.romButton:contains(x, y)
  self.sketchButton.hovered = self.sketchButton:contains(x, y)
  self.cancelButton.hovered = self.cancelButton:contains(x, y)
  return true
end

function Dialog:draw(canvas)
  if not self.visible then
    return
  end
  rebuildPanel(self)
  self.panel:setVisible(true)
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
end

return Dialog
