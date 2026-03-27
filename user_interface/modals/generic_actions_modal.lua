local Panel = require("user_interface.panel")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local function rebuildPanel(self)
  local cols = math.max(1, self.cols or 1)
  local leftInset = math.floor((self.rowH or self.cellH or 0) / 2)
  local optionColspan = math.max(1, math.min(self.optionColspan or 1, cols))
  local useFullRowOptions = optionColspan >= cols
  local optionRows
  if useFullRowOptions then
    optionRows = math.max(1, #(self.options or {}))
  else
    optionRows = math.max(1, math.ceil(#(self.options or {}) / cols))
  end
  local rows = optionRows + 1
  self.panel = Panel.new({
    cols = cols,
    rows = rows,
    cellW = self.cellW,
    cellH = self.rowH,
    padding = self.padding,
    spacingY = self.rowGap,
    cellPaddingX = self.cellPaddingX,
    cellPaddingY = self.cellPaddingY,
    visible = self.visible,
    title = self.title,
    titleH = self.titleH,
    bgColor = self.bgColor,
    textOffsetY = self.textOffsetY,
  })

  for i, option in ipairs(self.options or {}) do
    local row
    local col
    if useFullRowOptions then
      row = i
      col = 1
    else
      row = math.floor((i - 1) / cols) + 1
      col = ((i - 1) % cols) + 1
    end
    local text = string.format("%d) %s", i, option.text or "")
    self.panel:setCell(col, row, {
      kind = "button",
      text = text,
      colspan = optionColspan,
      transparent = true,
      textAlign = "left",
      contentPaddingX = leftInset,
      action = function()
        if option and option.callback then
          option.callback()
        end
        self:hide()
      end,
    })
  end

  self.panel:setCell(1, rows, {
    text = self.footerText,
    colspan = cols,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "",
    options = {},
    cols = 2,
    optionColspan = 2,
    footerText = "Esc) Close",
    rowH = nil,
    rowGap = nil,
    padding = nil,
    titleH = nil,
    cellW = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    panel = nil,
    _boxX = nil,
    _boxY = nil,
    _boxW = nil,
    _boxH = nil,
  }, Dialog)

  ModalPanelUtils.applyPanelDefaults(self)
  rebuildPanel(self)
  return self
end

function Dialog:show(title, options)
  self.title = title or ""
  self.options = options or {}
  self.visible = true
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:isVisible()
  return self.visible
end

function Dialog:_containsBox(x, y)
  if not self.panel then return true end
  return self.panel:contains(x, y)
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

  local idx = tonumber(key)
  if idx and idx >= 1 and idx <= #self.options then
    local option = self.options[idx]
    if option and option.callback then
      option.callback()
      self:hide()
      return true
    end
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
