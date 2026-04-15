local Button = require("user_interface.button")
local Panel = require("user_interface.panel")
local TextField = require("user_interface.text_field")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function rebuildPanel(self)
  self.panel = Panel.new({
    cols = 2,
    rows = 5,
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

  self.panel:setCell(1, 1, { text = "Bank:" })
  self.panel:setCell(2, 1, { component = self.bankField })
  self.panel:setCell(1, 2, { text = "Tile number:" })
  self.panel:setCell(2, 2, { component = self.tileField })
  self.panel:setCell(1, 3, { text = "OAM start:" })
  self.panel:setCell(2, 3, { component = self.oamStartField })
  self.panel:setCell(1, 4, { component = self.addButton })
  self.panel:setCell(2, 4, { component = self.cancelButton })
  self.panel:setCell(1, 5, { text = "Esc) Close", colspan = 2 })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Add sprite",
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
    _focusIndex = 1,
  }, Dialog)

  self.bankField = TextField.new({
    width = 104,
    height = self.fieldH,
  })
  self.tileField = TextField.new({
    width = 104,
    height = self.fieldH,
  })
  self.oamStartField = TextField.new({
    width = 104,
    height = self.fieldH,
    mask = "0x000000",
  })
  self.addButton = Button.new({
    text = "Add",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
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

function Dialog:_setFocus(index)
  self._focusIndex = math.max(1, math.min(3, tonumber(index) or 1))
  self.bankField:setFocused(self._focusIndex == 1)
  self.tileField:setFocused(self._focusIndex == 2)
  self.oamStartField:setFocused(self._focusIndex == 3)
end

function Dialog:_focusNext()
  self:_setFocus((self._focusIndex % 3) + 1)
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Add sprite"
  self.targetWindow = opts.window
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true

  self.bankField:setText(opts.initialBank or "")
  self.tileField:setText(opts.initialTile or "")
  self.oamStartField:setText(opts.initialOamStart or "")
  self:_setFocus(1)
  self.addButton.pressed = false
  self.cancelButton.pressed = false
  self.addButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self:_setFocus(1)
  self.addButton.pressed = false
  self.cancelButton.pressed = false
  self.addButton.hovered = false
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
      self.bankField:getText() or "",
      self.tileField:getText() or "",
      self.oamStartField:getText() or "",
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
    self:_focusNext()
    return true
  end
  if self.bankField.focused and self.bankField:onKeyPressed(key) then
    return true
  end
  if self.tileField.focused and self.tileField:onKeyPressed(key) then
    return true
  end
  if self.oamStartField.focused and self.oamStartField:onKeyPressed(key) then
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  if self.bankField.focused then
    return self.bankField:onTextInput(text)
  end
  if self.tileField.focused then
    return self.tileField:onTextInput(text)
  end
  if self.oamStartField.focused then
    return self.oamStartField:onTextInput(text)
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

  if self.bankField:contains(x, y) then
    self:_setFocus(1)
  elseif self.tileField:contains(x, y) then
    self:_setFocus(2)
  elseif self.oamStartField:contains(x, y) then
    self:_setFocus(3)
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
