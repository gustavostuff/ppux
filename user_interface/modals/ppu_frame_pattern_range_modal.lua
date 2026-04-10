local NumericSpinner = require("user_interface.numeric_spinner")
local Button = require("user_interface.button")
local Panel = require("user_interface.panel")
local TextField = require("user_interface.text_field")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function isDecimalInput(text)
  return type(text) == "string" and text:match("^%d+$") ~= nil
end

local function rebuildPanel(self)
  self.panel = Panel.new({
    cols = 2,
    rows = 7,
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
    textOffsetY = self.textOffsetY,
  })

  self.panel:setCell(1, 1, { text = "Page:" })
  self.panel:setCell(2, 1, { component = self.pageSpinner })
  self.panel:setCell(1, 2, { text = "Bank:" })
  self.panel:setCell(2, 2, { component = self.bankField })
  self.panel:setCell(1, 3, { text = "From:" })
  self.panel:setCell(2, 3, { component = self.fromField })
  self.panel:setCell(1, 4, { text = "To:" })
  self.panel:setCell(2, 4, { component = self.toField })
  self.panel:setCell(1, 5, { text = "Values are decimal ^", colspan = 2 })
  self.panel:setCell(1, 6, { component = self.addButton })
  self.panel:setCell(2, 6, { component = self.cancelButton })
  self.panel:setCell(1, 7, { text = "Esc) Close", colspan = 2 })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Add tile range",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = nil,
    cellH = nil,
    fieldH = ModalPanelUtils.MODAL_BUTTON_H,
    buttonW = 72,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    onConfirm = nil,
    onCancel = nil,
    targetWindow = nil,
    panel = nil,
  }, Dialog)

  self.bankField = TextField.new({
    width = 104,
    height = self.fieldH,
  })
  self.fromField = TextField.new({
    width = 104,
    height = self.fieldH,
  })
  self.toField = TextField.new({
    width = 104,
    height = self.fieldH,
  })
  self.pageSpinner = NumericSpinner.new({
    value = 1,
    min = 1,
    max = 2,
    step = 1,
    valueWidth = 22,
  })
  self.addButton = Button.new({
    text = "Add",
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
  self.title = opts.title or "Add tile range"
  self.targetWindow = opts.window
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true

  self.bankField:setText(tostring(opts.initialBank or "1"))
  self.fromField:setText(tostring(opts.initialFrom or "0"))
  self.toField:setText(tostring(opts.initialTo or "255"))
  self.pageSpinner:setValue(tonumber(opts.initialPage) or 1)
  self.bankField:setFocused(true)
  self.fromField:setFocused(false)
  self.toField:setFocused(false)
  self.addButton.pressed = false
  self.cancelButton.pressed = false
  self.addButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.bankField:setFocused(false)
  self.fromField:setFocused(false)
  self.toField:setFocused(false)
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
      self.pageSpinner.value or 1,
      self.fromField:getText() or "",
      self.toField:getText() or "",
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
    if self.bankField.focused then
      self.bankField:setFocused(false)
      self.fromField:setFocused(true)
      self.toField:setFocused(false)
    elseif self.fromField.focused then
      self.bankField:setFocused(false)
      self.fromField:setFocused(false)
      self.toField:setFocused(true)
    else
      self.bankField:setFocused(true)
      self.fromField:setFocused(false)
      self.toField:setFocused(false)
    end
    return true
  end
  if (key == "up" or key == "right") and not (self.bankField.focused or self.fromField.focused or self.toField.focused) then
    self.pageSpinner:adjust(1)
    return true
  end
  if (key == "down" or key == "left") and not (self.bankField.focused or self.fromField.focused or self.toField.focused) then
    self.pageSpinner:adjust(-1)
    return true
  end
  if self.bankField.focused and self.bankField:onKeyPressed(key) then
    return true
  end
  if self.fromField.focused and self.fromField:onKeyPressed(key) then
    return true
  end
  if self.toField.focused and self.toField:onKeyPressed(key) then
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  if not isDecimalInput(text) then
    return false
  end
  if self.bankField.focused then
    return self.bankField:onTextInput(text)
  end
  if self.fromField.focused then
    return self.fromField:onTextInput(text)
  end
  if self.toField.focused then
    return self.toField:onTextInput(text)
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
