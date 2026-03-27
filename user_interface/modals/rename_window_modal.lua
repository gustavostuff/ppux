local Button = require("user_interface.button")
local Panel = require("user_interface.panel")
local TextField = require("user_interface.text_field")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function trim(text)
  text = tostring(text or "")
  return text:match("^%s*(.-)%s*$")
end

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
    textOffsetY = self.textOffsetY,
  })

  self.panel:setCell(1, 1, {
    component = self.textField,
    colspan = 2,
  })
  self.panel:setCell(1, 2, {
    component = self.renameButton,
  })
  self.panel:setCell(2, 2, {
    component = self.cancelButton,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Rename Window",
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
    pressedButton = nil,
    onConfirm = nil,
    onCancel = nil,
    targetWindow = nil,
    panel = nil,
  }, Dialog)

  self.textField = TextField.new({
    width = 220,
    height = self.fieldH,
  })
  self.renameButton = Button.new({
    text = "Rename",
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
  self.title = opts.title or "Rename Window"
  self.targetWindow = opts.window
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true

  local initialTitle = opts.initialTitle
  if initialTitle == nil and self.targetWindow then
    initialTitle = self.targetWindow.title
  end
  self.textField:setText(initialTitle or "")
  self.textField:setFocused(true)
  self.pressedButton = nil
  self.renameButton.pressed = false
  self.cancelButton.pressed = false
  self.renameButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.textField:setFocused(false)
  self.pressedButton = nil
  self.renameButton.pressed = false
  self.cancelButton.pressed = false
  self.renameButton.hovered = false
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
  local raw = self.textField:getText() or ""
  local title = trim(raw)
  if title == "" then
    return false
  end

  local callback = self.onConfirm
  local target = self.targetWindow
  self:hide()
  if callback then
    callback(title, target)
  end
  return true
end

function Dialog:_cancel()
  local callback = self.onCancel
  local target = self.targetWindow
  self:hide()
  if callback then
    callback(target)
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
    self.textField:setFocused(not self.textField.focused)
    return true
  end
  if self.textField:onKeyPressed(key) then
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  return self.textField:onTextInput(text)
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end
  if not self:_containsBox(x, y) then
    self:_cancel()
    return true
  end

  self.pressedButton = nil
  self.renameButton.pressed = false
  self.cancelButton.pressed = false

  local fieldFocused = self.textField:contains(x, y)
  self.textField:setFocused(fieldFocused)

  if self.renameButton:contains(x, y) then
    self.renameButton.pressed = true
    self.pressedButton = self.renameButton
  elseif self.cancelButton:contains(x, y) then
    self.cancelButton.pressed = true
    self.pressedButton = self.cancelButton
  end

  return true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end

  local pressed = self.pressedButton
  self.pressedButton = nil
  self.renameButton.pressed = false
  self.cancelButton.pressed = false

  if pressed and pressed:contains(x, y) and pressed.action then
    pressed.action()
  end
  return true
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end
  self.renameButton.hovered = self.renameButton:contains(x, y)
  self.cancelButton.hovered = self.cancelButton:contains(x, y)
  return true
end

function Dialog:draw(canvas)
  if not self.visible then return end
  rebuildPanel(self)
  self.panel:setVisible(true)
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
end

return Dialog
