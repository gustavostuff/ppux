local Button = require("user_interface.button")
local Panel = require("user_interface.panel")
local TextField = require("user_interface.text_field")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function rebuildPanel(self)
  self.panel = Panel.new({
    cols = 2,
    rows = 6,
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
    textOffsetY = self.textOffsetY,
  })

  self.panel:setCell(1, 1, { text = "Start:" })
  self.panel:setCell(2, 1, { component = self.startField })
  self.panel:setCell(1, 2, { text = "End:" })
  self.panel:setCell(2, 2, { component = self.endField })
  self.panel:setCell(1, 3, { text = "Bank:" })
  self.panel:setCell(2, 3, { component = self.bankField })
  self.panel:setCell(1, 4, { text = "Page:" })
  self.panel:setCell(2, 4, { component = self.pageField })
  self.panel:setCell(1, 5, { component = self.setButton })
  self.panel:setCell(2, 5, { component = self.cancelButton })
  self.panel:setCell(1, 6, { text = "Esc) Close", colspan = 2 })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Set tile range",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = nil,
    cellH = nil,
    fieldH = ModalPanelUtils.MODAL_BUTTON_H,
    buttonW = 68,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    onConfirm = nil,
    onCancel = nil,
    targetWindow = nil,
    panel = nil,
  }, Dialog)

  self.startField = TextField.new({
    width = 104,
    height = self.fieldH,
    mask = "0x000000",
  })
  self.endField = TextField.new({
    width = 104,
    height = self.fieldH,
    mask = "0x000000",
  })
  self.bankField = TextField.new({
    width = 104,
    height = self.fieldH,
  })
  self.pageField = TextField.new({
    width = 104,
    height = self.fieldH,
  })
  self.setButton = Button.new({
    text = "Set",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    textOffsetY = ModalPanelUtils.MODAL_TEXT_OFFSET_Y,
    action = function()
      self:_confirm()
    end,
  })
  self.cancelButton = Button.new({
    text = "Cancel",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    textOffsetY = ModalPanelUtils.MODAL_TEXT_OFFSET_Y,
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

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Set tile range"
  self.targetWindow = opts.window
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true

  self.startField:setText(opts.initialStartAddress or "")
  self.endField:setText(opts.initialEndAddress or "")
  self.bankField:setText(opts.initialBank or "")
  self.pageField:setText(opts.initialPage or "")
  self.startField:setFocused(true)
  self.endField:setFocused(false)
  self.bankField:setFocused(false)
  self.pageField:setFocused(false)
  self.setButton.pressed = false
  self.cancelButton.pressed = false
  self.setButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.startField:setFocused(false)
  self.endField:setFocused(false)
  self.bankField:setFocused(false)
  self.pageField:setFocused(false)
  self.setButton.pressed = false
  self.cancelButton.pressed = false
  self.setButton.hovered = false
  self.cancelButton.hovered = false
  self.onConfirm = nil
  self.onCancel = nil
  self.targetWindow = nil
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
  local callback = self.onConfirm
  local targetWindow = self.targetWindow
  if callback then
    local ok = callback(
      self.startField:getText() or "",
      self.endField:getText() or "",
      self.bankField:getText() or "",
      self.pageField:getText() or "",
      targetWindow
    )
    if ok == false then
      return false
    end
  end
  self:hide()
  return true
end

function Dialog:_cancel()
  local callback = self.onCancel
  local targetWindow = self.targetWindow
  self:hide()
  if callback then
    callback(targetWindow)
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
    self:_confirm()
    return true
  end
  if key == "tab" then
    if self.startField.focused then
      self.startField:setFocused(false)
      self.endField:setFocused(true)
      self.bankField:setFocused(false)
      self.pageField:setFocused(false)
    elseif self.endField.focused then
      self.startField:setFocused(false)
      self.endField:setFocused(false)
      self.bankField:setFocused(true)
      self.pageField:setFocused(false)
    elseif self.bankField.focused then
      self.startField:setFocused(false)
      self.endField:setFocused(false)
      self.bankField:setFocused(false)
      self.pageField:setFocused(true)
    else
      self.startField:setFocused(true)
      self.endField:setFocused(false)
      self.bankField:setFocused(false)
      self.pageField:setFocused(false)
    end
    return true
  end
  if self.startField.focused and self.startField:onKeyPressed(key) then
    return true
  end
  if self.endField.focused and self.endField:onKeyPressed(key) then
    return true
  end
  if self.bankField.focused and self.bankField:onKeyPressed(key) then
    return true
  end
  if self.pageField.focused and self.pageField:onKeyPressed(key) then
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  if self.startField.focused then
    return self.startField:onTextInput(text)
  end
  if self.endField.focused then
    return self.endField:onTextInput(text)
  end
  if self.bankField.focused then
    return self.bankField:onTextInput(text)
  end
  if self.pageField.focused then
    return self.pageField:onTextInput(text)
  end
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
  self.panel:setVisible(true)
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
end

return Dialog
