local NumericSpinner = require("user_interface.numeric_spinner")
local Button = require("user_interface.button")
local TextField = require("user_interface.text_field")
local Panel = require("user_interface.panel")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local DEFAULT_WINDOW_NAME = "New Window"

local function normalizeSpriteMode(mode)
  return (mode == "8x16") and "8x16" or "8x8"
end

local function modeLabel(mode)
  return normalizeSpriteMode(mode)
end

local function trim(text)
  text = tostring(text or "")
  return text:match("^%s*(.-)%s*$")
end

local function rebuildPanel(self)
  local leftInset = math.floor((self.cellH or 0) / 2)
  self.modeButton.contentPaddingX = leftInset
  self.createButton.contentPaddingX = leftInset
  self.cancelButton.contentPaddingX = leftInset

  local rowCursor = 1
  local nameRow = rowCursor
  rowCursor = rowCursor + 1
  local spriteModeRow = nil
  if self.showSpriteMode == true then
    spriteModeRow = rowCursor
    rowCursor = rowCursor + 1
  end
  local colsRow = rowCursor
  rowCursor = rowCursor + 1
  local rowsRow = rowCursor
  rowCursor = rowCursor + 1
  local buttonsRow = rowCursor
  rowCursor = rowCursor + 1
  local footerRow = rowCursor

  self.panel = Panel.new({
    cols = 4,
    rows = footerRow,
    cellW = self.cellW,
    cellH = self.cellH,
    padding = self.padding,
    spacingX = self.colGap,
    spacingY = self.rowGap,
    cellPaddingX = self.cellPaddingX,
    cellPaddingY = self.cellPaddingY,
    visible = self.visible,
    title = self.title,
    titleH = self.titleH,
    bgColor = self.bgColor,
    titleBgColor = self.titleBgColor,
  })

  self.panel:setCell(1, nameRow, { text = "Name:" })
  self.panel:setCell(2, nameRow, { component = self.nameField, colspan = 3 })

  if spriteModeRow then
    self.panel:setCell(1, spriteModeRow, {
      text = "Sprite mode:",
      preserveTrailingColon = true,
    })
    self.panel:setCell(2, spriteModeRow, {
      component = self.modeButton,
    })
  end

  self.panel:setCell(1, colsRow, { text = "Cols:" })
  self.panel:setCell(2, colsRow, { component = self.colsSpinner, colspan = 2 })

  self.panel:setCell(1, rowsRow, { text = "Rows:" })
  self.panel:setCell(2, rowsRow, { component = self.rowsSpinner, colspan = 2 })

  self.panel:setCell(1, buttonsRow, {
    component = self.createButton,
    colspan = 2,
  })
  self.panel:setCell(3, buttonsRow, {
    component = self.cancelButton,
    colspan = 2,
  })
  self.panel:setCell(1, footerRow, {
    text = "Esc) Close",
    colspan = 4,
  })
end

function Dialog.new()
  local spinnerDefaults = {
    value = 8,
    min = 4,
    max = 32,
    step = 1,
    valueWidth = 32,
  }

  local self = setmetatable({
    visible = false,
    title = "Window Settings",
    colsSpinner = NumericSpinner.new(spinnerDefaults),
    rowsSpinner = NumericSpinner.new(spinnerDefaults),
    nameField = TextField.new({
      width = 172,
      height = ModalPanelUtils.MODAL_BUTTON_H,
    }),
    spriteMode = "8x8",
    selectedOption = nil,
    showSpriteMode = true,
    onConfirm = nil,
    onCancel = nil,
    padding = nil,
    colGap = nil,
    rowGap = nil,
    cellW = nil,
    cellH = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    panel = nil,
  }, Dialog)

  self.modeButton = Button.new({
    text = "8x8",
    tooltip = "Sprite mode: 8x8",
    h = ModalPanelUtils.MODAL_BUTTON_H,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    action = function()
      self:toggleSpriteMode()
    end,
  })
  self.createButton = Button.new({
    text = "Create",
    h = ModalPanelUtils.MODAL_BUTTON_H,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    action = function()
      self:_confirm()
    end,
  })
  self.cancelButton = Button.new({
    text = "Cancel",
    h = ModalPanelUtils.MODAL_BUTTON_H,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    action = function()
      self:_cancel()
    end,
  })

  ModalPanelUtils.applyPanelDefaults(self)
  rebuildPanel(self)
  return self
end

function Dialog:getSpriteMode()
  return normalizeSpriteMode(self.spriteMode)
end

function Dialog:_updateModeButtonVisual()
  self.modeButton.text = modeLabel(self:getSpriteMode())
  self.modeButton.tooltip = "Sprite mode: " .. self:getSpriteMode()
end

function Dialog:toggleSpriteMode()
  if self:getSpriteMode() == "8x16" then
    self.spriteMode = "8x8"
  else
    self.spriteMode = "8x16"
  end
  self:_updateModeButtonVisual()
  return self.spriteMode
end

function Dialog:isVisible()
  return self.visible
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Window Settings"
  self.selectedOption = opts.option or nil
  self.showSpriteMode = self.selectedOption and self.selectedOption.requiresSpriteMode == true or false
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.spriteMode = "8x8"
  self.rowsSpinner:setValue(tonumber(opts.initialRows) or 8)
  self.colsSpinner:setValue(tonumber(opts.initialCols) or 8)
  self.modeButton.pressed = false
  self.modeButton.hovered = false
  self.createButton.pressed = false
  self.cancelButton.pressed = false
  self.createButton.hovered = false
  self.cancelButton.hovered = false
  self.nameField:setText(opts.initialName or DEFAULT_WINDOW_NAME)
  self.nameField:setFocused(true)
  self:_updateModeButtonVisual()
  self.visible = true
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.title = "Window Settings"
  self.selectedOption = nil
  self.onConfirm = nil
  self.onCancel = nil
  self.modeButton.pressed = false
  self.modeButton.hovered = false
  self.createButton.pressed = false
  self.cancelButton.pressed = false
  self.createButton.hovered = false
  self.cancelButton.hovered = false
  self.nameField:setFocused(false)
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:getWindowName()
  local name = trim(self.nameField:getText())
  if name == "" then
    return nil
  end
  return name
end

function Dialog:_confirm()
  local callback = self.onConfirm
  local option = self.selectedOption
  if callback then
    local ok = callback(
      self.colsSpinner.value,
      self.rowsSpinner.value,
      self:getSpriteMode(),
      self:getWindowName(),
      option
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
  local option = self.selectedOption
  self:hide()
  if callback then
    callback(option)
  end
  return true
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
  if self.nameField:onKeyPressed(key) then
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  return self.nameField:onTextInput(text)
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return false end
  if not self:_containsBox(x, y) then
    self:_cancel()
    return true
  end

  return self.panel and self.panel:mousepressed(x, y, button) or false
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
