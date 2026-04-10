local Panel = require("user_interface.panel")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function buttonLabel(option)
  if option and option.buttonText and option.buttonText ~= "" then
    return option.buttonText
  end
  return tostring(option and option.text or "")
end

local function rebuildPanel(self)
  local optionCount = #(self.options or {})
  local rows = math.max(1, math.ceil(optionCount / 2)) + 1
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
    titleBgColor = self.titleBgColor,
  })

  for i, option in ipairs(self.options or {}) do
    local row = math.floor((i - 1) / 2) + 1
    local col = ((i - 1) % 2 == 0) and 1 or 3
    self.panel:setCell(col, row, {
      kind = "button",
      icon = option and option.icon or nil,
      text = buttonLabel(option),
      colspan = 2,
      transparent = true,
      textAlign = "left",
      contentPaddingX = leftInset,
      action = function()
        local callback = option and option.callback or nil
        self:hide()
        if callback then
          callback()
        end
      end,
    })
  end

  self.panel:setCell(1, rows, {
    text = "Esc) Close",
    colspan = 4,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "New Window",
    options = {},
    padding = nil,
    colGap = nil,
    rowGap = nil,
    titleH = nil,
    cellW = nil,
    cellH = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    panel = nil,
  }, Dialog)

  ModalPanelUtils.applyPanelDefaults(self)
  rebuildPanel(self)
  return self
end

function Dialog:show(title, options)
  self.title = title or "New Window"
  self.options = options or {}
  self.visible = true
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.options = {}
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:isVisible()
  return self.visible
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
  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return false end
  if not self:_containsBox(x, y) then
    self:hide()
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
  ModalPanelUtils.drawBackdrop(canvas)
  self.panel:setVisible(true)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
end

return Dialog
