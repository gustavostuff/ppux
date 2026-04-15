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
    text = self.message,
    colspan = 2,
  })
  self.panel:setCell(1, 2, {
    component = self.yesButton,
  })
  self.panel:setCell(2, 2, {
    component = self.noButton,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Save changes before quitting?",
    message = "Unsaved work may be lost.",
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
    focusedButton = "yes",
    onYes = nil,
    onNo = nil,
    panel = nil,
  }, Dialog)

  self.yesButton = Button.new({
    text = "Yes",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_confirmYes()
    end,
  })
  self.noButton = Button.new({
    text = "No",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_confirmNo()
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
  self.title = opts.title or "Save changes before quitting?"
  self.message = opts.message or "Unsaved work may be lost."
  self.onYes = opts.onYes
  self.onNo = opts.onNo
  self.visible = true
  self.pressedButton = nil
  self.focusedButton = "yes"
  self.yesButton.pressed = false
  self.noButton.pressed = false
  self.yesButton.hovered = false
  self.noButton.hovered = false
  self:_setFocusedButton("yes")
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.pressedButton = nil
  self.focusedButton = "yes"
  self.yesButton.pressed = false
  self.noButton.pressed = false
  self.yesButton.hovered = false
  self.noButton.hovered = false
  self.yesButton.focused = false
  self.noButton.focused = false
  self.onYes = nil
  self.onNo = nil
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

function Dialog:_setFocusedButton(which)
  if which ~= "yes" and which ~= "no" then return end
  self.focusedButton = which
  self.yesButton.focused = (which == "yes")
  self.noButton.focused = (which == "no")
end

function Dialog:_toggleFocusedButton()
  if self.focusedButton == "no" then
    self:_setFocusedButton("yes")
  else
    self:_setFocusedButton("no")
  end
end

function Dialog:_confirmYes()
  local callback = self.onYes
  self:hide()
  if callback then callback() end
end

function Dialog:_confirmNo()
  local callback = self.onNo
  self:hide()
  if callback then callback() end
end

function Dialog:handleKey(key)
  if not self.visible then return false end
  if key == "escape" then
    self:hide()
    return true
  end
  if key == "left" or key == "right" then
    self:_toggleFocusedButton()
    return true
  end
  if key == "return" or key == "kpenter" then
    if self.focusedButton == "no" then
      self:_confirmNo()
    else
      self:_confirmYes()
    end
    return true
  end
  if key == "y" or key == "Y" then
    self:_confirmYes()
    return true
  end
  if key == "n" or key == "N" then
    self:_confirmNo()
    return true
  end
  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end
  if not self:_containsBox(x, y) then
    self:hide()
    return true
  end

  self.pressedButton = nil
  if self.yesButton:contains(x, y) then
    self.yesButton.pressed = true
    self:_setFocusedButton("yes")
    self.pressedButton = self.yesButton
  elseif self.noButton:contains(x, y) then
    self.noButton.pressed = true
    self:_setFocusedButton("no")
    self.pressedButton = self.noButton
  end
  return true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end

  local pressedButton = self.pressedButton
  self.pressedButton = nil
  self.yesButton.pressed = false
  self.noButton.pressed = false

  if pressedButton and pressedButton:contains(x, y) and pressedButton.action then
    pressedButton.action()
  end
  return true
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end
  self.yesButton.hovered = self.yesButton:contains(x, y)
  self.noButton.hovered = self.noButton:contains(x, y)
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
