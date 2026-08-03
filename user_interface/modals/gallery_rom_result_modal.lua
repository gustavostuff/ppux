-- gallery_rom_result_modal.lua
-- Success / failure result after gallery ROM generation.

local Button = require("user_interface.button")
local Panel = require("user_interface.panel")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function rebuildPanel(self)
  self.panel = Panel.new({
    cols = 1,
    rows = 2,
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
    text = self.message,
    colspan = 1,
  })
  self.panel:setCell(1, 2, {
    component = self.okButton,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Gallery ROM",
    message = "",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    buttonW = 56,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    cellW = nil,
    cellH = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    pressedButton = nil,
    onClose = nil,
    panel = nil,
  }, Dialog)

  self.okButton = Button.new({
    text = "OK",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_close()
    end,
  })

  ModalPanelUtils.applyPanelDefaults(self)
  if (self.cellW or 0) < 280 then
    self.cellW = 280
  end
  self.buttonGap = self.colGap
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible
end

--- opts.ok (bool), opts.message, opts.title, opts.onClose
function Dialog:show(opts)
  opts = opts or {}
  local ok = opts.ok == true
  self.title = opts.title or (ok and "Gallery ROM built" or "Gallery ROM failed")
  self.message = opts.message or (ok and "Done." or "Failed.")
  self.onClose = opts.onClose
  self.visible = true
  self.pressedButton = nil
  self.okButton.pressed = false
  self.okButton.hovered = false
  self.okButton.focused = true
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.pressedButton = nil
  self.okButton.pressed = false
  self.okButton.hovered = false
  self.okButton.focused = false
  self.onClose = nil
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

function Dialog:_close()
  local callback = self.onClose
  self:hide()
  if callback then
    callback()
  end
end

function Dialog:handleKey(key)
  if not self.visible then
    return false
  end
  if key == "escape" or key == "return" or key == "kpenter" or key == "space" then
    self:_close()
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
    self:_close()
    return true
  end
  self.pressedButton = nil
  if self.okButton:contains(x, y) then
    self.okButton.pressed = true
    self.pressedButton = self.okButton
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
  self.okButton.pressed = false
  if pressedButton and pressedButton:contains(x, y) and pressedButton.action then
    pressedButton.action()
  end
  return true
end

function Dialog:mousemoved(x, y)
  if not self.visible then
    return false
  end
  self.okButton.hovered = self.okButton:contains(x, y)
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
