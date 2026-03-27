local NumericSpinner = require("user_interface.numeric_spinner")
local Button = require("user_interface.button")
local TextField = require("user_interface.text_field")
local Panel = require("user_interface.panel")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")
local images = require("images")

local Dialog = {}
Dialog.__index = Dialog

local DEFAULT_WINDOW_NAME = "New Window"

local function normalizeSpriteMode(mode)
  return (mode == "8x16") and "8x16" or "8x8"
end

local function modeIcon(mode)
  if mode == "8x16" then
    return images and images.icons and images.icons.icon_8x16
  end
  return images and images.icons and images.icons.icon_8x8
end

local function trim(text)
  text = tostring(text or "")
  return text:match("^%s*(.-)%s*$")
end

local function compactOptionLabel(option, index)
  if option and option.buttonText and option.buttonText ~= "" then
    return option.buttonText
  end

  local text = tostring(option and option.text or "")
  if text:find("Static Art") and text:find("%(tiles%)") then
    return "Static Tiles window"
  end
  if text:find("Static Art") and text:find("%(sprites%)") then
    return "Static Sprites window"
  end
  if text:find("Animation") and text:find("%(tiles%)") then
    return "Animation Tiles window"
  end
  if text:find("Animation") and text:find("%(sprites%)") then
    return "Animation Sprites window"
  end

  return tostring(index or "")
end

local function activateOption(self, option)
  if not (option and option.callback) then
    return false
  end

  option.callback(
    self.colsSpinner.value,
    self.rowsSpinner.value,
    self:getSpriteMode(),
    self:getWindowName()
  )
  self:hide()
  return true
end

local function rebuildPanel(self)
  local optionCount = #(self.options or {})
  local buttonRows = math.max(1, optionCount)
  local rows = 4 + buttonRows + 1
  local leftInset = math.floor((self.cellH or 0) / 2)
  self.panel = Panel.new({
    cols = 4,
    rows = rows,
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
    textOffsetY = self.textOffsetY,
  })

  self.panel:setCell(4, 1, {
    component = self.modeButton,
  })

  self.panel:setCell(1, 1, { text = "Cols:" })
  self.panel:setCell(2, 1, { component = self.colsSpinner, colspan = 2 })

  self.panel:setCell(1, 2, { text = "Rows:" })
  self.panel:setCell(2, 2, { component = self.rowsSpinner, colspan = 2 })

  self.panel:setCell(1, 3, { text = "Name:" })
  self.panel:setCell(2, 3, { component = self.nameField, colspan = 3 })

  self.panel:setCell(1, 4, {
    text = "Create:",
    colspan = 4,
    preserveTrailingColon = true,
  })

  for i, option in ipairs(self.options or {}) do
    local row = 4 + i
    self.panel:setCell(1, row, {
      kind = "button",
      text = compactOptionLabel(option, i),
      colspan = 4,
      transparent = true,
      textAlign = "left",
      contentPaddingX = leftInset,
      action = function()
        activateOption(self, option)
      end,
    })
  end

  self.panel:setCell(1, rows, {
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
    labelWidth = 24,
  }

  local self = setmetatable({
    visible = false,
    title = "New Window",
    options = {},
    colsSpinner = NumericSpinner.new(spinnerDefaults),
    rowsSpinner = NumericSpinner.new(spinnerDefaults),
    nameField = TextField.new({
      width = 172,
      height = ModalPanelUtils.MODAL_BUTTON_H,
    }),
    spriteMode = "8x8",
    pressedModeButton = false,
    modeButtonSize = ModalPanelUtils.MODAL_ICON_BUTTON_SIZE,
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
    icon = modeIcon("8x8"),
    tooltip = "Sprite mode: 8x8",
    w = self.modeButtonSize,
    h = self.modeButtonSize,
    action = function()
      self:toggleSpriteMode()
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
  self.modeButton.icon = modeIcon(self:getSpriteMode())
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

function Dialog:show(title, options)
  self.title = title or "New Window"
  self.options = options or {}
  self.spriteMode = "8x8"
  self.pressedModeButton = false
  self.modeButton.pressed = false
  self.modeButton.hovered = false
  self.nameField:setText(DEFAULT_WINDOW_NAME)
  self.nameField:setFocused(true)
  self:_updateModeButtonVisual()
  self.visible = true
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.title = ""
  self.options = {}
  self.pressedModeButton = false
  self.modeButton.pressed = false
  self.modeButton.hovered = false
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
    self:hide()
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
    self:hide()
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
