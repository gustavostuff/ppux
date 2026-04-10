local Button = require("user_interface.button")
local Panel = require("user_interface.panel")
local TextField = require("user_interface.text_field")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function rebuildPanel(self)
  self.panel = Panel.new({
    cols = 2,
    rows = 4,
    cellW = self.cellW,
    cellH = self.cellH,
    cellWidths = {
      [1] = 88,
      [2] = 232,
    },
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

  self.panel:setCell(1, 1, {
    text = "Plain",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 1, {
    component = self.plainField,
  })

  self.panel:setCell(1, 2, {
    text = "Long plain",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 2, {
    component = self.longField,
  })

  self.panel:setCell(1, 3, {
    text = "Masked",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 3, {
    component = self.maskedField,
  })

  self.panel:setCell(1, 4, {
    component = self.resetButton,
  })
  self.panel:setCell(2, 4, {
    component = self.closeButton,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Text Field Demo",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = nil,
    cellH = nil,
    fieldH = ModalPanelUtils.MODAL_BUTTON_H,
    buttonW = 88,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    panel = nil,
    _boxX = nil,
    _boxY = nil,
    _boxW = nil,
    _boxH = nil,
  }, Dialog)

  self.plainField = TextField.new({
    width = 232,
    height = self.fieldH,
  })
  self.longField = TextField.new({
    width = 232,
    height = self.fieldH,
  })
  self.maskedField = TextField.new({
    width = 232,
    height = self.fieldH,
    mask = "0x000000",
  })

  self.resetButton = Button.new({
    text = "Reset",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    textOffsetY = ModalPanelUtils.MODAL_TEXT_OFFSET_Y,
    action = function()
      self:resetFields()
    end,
  })
  self.closeButton = Button.new({
    text = "Close",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    textOffsetY = ModalPanelUtils.MODAL_TEXT_OFFSET_Y,
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

function Dialog:resetFields()
  self.plainField:setText("Hello")
  self.longField:setText("Alpha Bravo Charlie Delta Echo Foxtrot")
  self.maskedField:setText("3F10")
  self.panel:setFocusedComponent(self.plainField)
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Text Field Demo"
  self.visible = true
  rebuildPanel(self)
  self:resetFields()
end

function Dialog:hide()
  self.visible = false
  if self.panel then
    self.panel:setVisible(false)
  end
  self.plainField:setFocused(false)
  self.longField:setFocused(false)
  self.maskedField:setFocused(false)
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

function Dialog:_cycleFocus()
  local fields = {
    self.plainField,
    self.longField,
    self.maskedField,
  }
  local current = self.panel and self.panel.focusedComponent or nil
  local nextIndex = 1
  for i, field in ipairs(fields) do
    if current == field then
      nextIndex = (i % #fields) + 1
      break
    end
  end
  if self.panel then
    self.panel:setFocusedComponent(fields[nextIndex])
  end
  return true
end

function Dialog:handleKey(key)
  if not self.visible then return false end
  if key == "escape" then
    self:hide()
    return true
  end
  if key == "tab" then
    return self:_cycleFocus()
  end
  if self.panel and self.panel:handleKey(key) then
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible or not self.panel then return false end
  return self.panel:textinput(text)
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end
  if not self:_containsBox(x, y) then
    self:hide()
    return true
  end
  return self.panel and self.panel:mousepressed(x, y, button) == true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible or not self.panel then return false end
  return self.panel:mousereleased(x, y, button) == true
end

function Dialog:mousemoved(x, y)
  if not self.visible or not self.panel then return false end
  self.panel:mousemoved(x, y)
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
