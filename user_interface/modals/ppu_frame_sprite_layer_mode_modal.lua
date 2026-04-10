local Button = require("user_interface.button")
local Panel = require("user_interface.panel")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function normalizeSpriteMode(mode)
  return (mode == "8x16") and "8x16" or "8x8"
end

local function rebuildPanel(self)
  self.panel = Panel.new({
    cols = 2,
    rows = 3,
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
  })

  self.panel:setCell(1, 1, { text = "Sprite mode" })
  self.panel:setCell(2, 1, { component = self.modeButton })
  self.panel:setCell(1, 2, { component = self.createButton })
  self.panel:setCell(2, 2, { component = self.cancelButton })
  self.panel:setCell(1, 3, { text = "Esc) Close", colspan = 2 })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Create sprite layer",
    spriteMode = "8x8",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = nil,
    cellH = nil,
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

  self.modeButton = Button.new({
    text = "8x8",
    tooltip = "Sprite mode: 8x8",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    action = function()
      self:toggleSpriteMode()
    end,
  })

  self.createButton = Button.new({
    text = "Create",
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

function Dialog:getSpriteMode()
  return normalizeSpriteMode(self.spriteMode)
end

function Dialog:_updateModeButtonVisual()
  local spriteMode = self:getSpriteMode()
  self.modeButton.text = spriteMode
  self.modeButton.tooltip = "Sprite mode: " .. spriteMode
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
  self.title = opts.title or "Create sprite layer"
  self.targetWindow = opts.window
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true
  self.spriteMode = normalizeSpriteMode(opts.initialMode)
  self:_updateModeButtonVisual()

  self.modeButton.pressed = false
  self.modeButton.hovered = false
  self.createButton.pressed = false
  self.cancelButton.pressed = false
  self.createButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.modeButton.pressed = false
  self.modeButton.hovered = false
  self.createButton.pressed = false
  self.cancelButton.pressed = false
  self.createButton.hovered = false
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
    local ok = callback(self:getSpriteMode(), targetWindow)
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
  if key == "tab" or key == "left" or key == "right" or key == "space" then
    self:toggleSpriteMode()
    return true
  end
  return false
end

function Dialog:textinput(_text)
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
