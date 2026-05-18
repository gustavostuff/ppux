local Button = require("user_interface.button")
local Panel = require("user_interface.panel")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function rebuildPanel(self)
  self.panel = Panel.new({
    cols = 2,
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
    align = "center",
    colspan = 2,
  })
  self.panel:setCell(1, 2, {
    component = self.cancelButton,
    colspan = 2,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Exit app",
    message = "Press Esc again to exit.",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = nil,
    cellH = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    cancelButton = nil,
    panel = nil,
  }, Dialog)

  self.cancelButton = Button.new({
    text = "Cancel",
    w = 56,
    h = ModalPanelUtils.MODAL_BUTTON_H,
    transparent = true,
    action = function()
      self:hide()
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

function Dialog:show()
  self.visible = true
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  if self.cancelButton then
    self.cancelButton.pressed = false
    self.cancelButton.hovered = false
    self.cancelButton.focused = false
  end
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:_containsBox(x, y)
  if not self.panel then
    return true
  end
  return self.panel:contains(x, y)
end

function Dialog:getTooltipAt(x, y)
  if not self.visible or not self.panel or not self:_containsBox(x, y) then
    return nil
  end
  return self.panel:getTooltipAt(x, y)
end

function Dialog:handleKey(key)
  if not self.visible then
    return false
  end
  if key == "escape" then
    self:hide()
    love.event.quit()
    return true
  end
  if key == "return" or key == "kpenter" then
    self:hide()
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
    self:hide()
    return true
  end
  return self.panel and self.panel:mousepressed(x, y, button) or true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then
    return false
  end
  return self.panel and self.panel:mousereleased(x, y, button) or true
end

function Dialog:mousemoved(x, y)
  if not self.visible then
    return false
  end
  if self.panel then
    self.panel:mousemoved(x, y)
  end
  return true
end

function Dialog:draw(canvas)
  if not self.visible then
    return
  end
  -- Do not rebuild the panel here: a full rebuild replaces the Panel object and clears
  -- pressedButton, so Cancel would not receive mousereleased after mousepressed (see
  -- generic_actions_modal draw). rebuildPanel runs from new() and show() only.
  self.panel:setVisible(true)
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
end

return Dialog
