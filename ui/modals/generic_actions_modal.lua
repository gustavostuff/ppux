local Panel = require("ui.panel")
local Checkbox = require("ui.checkbox")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local colors = require("app_colors")

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
  local checkboxRows = self.checkbox and 1 or 0
  local rows = optionRows + checkboxRows + 1
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
    titleBgColor = self.titleBgColor,
    _modalChromeOverBlue = self._modalChromeOverBlue == true,
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
    local text
    if type(self.optionTextFormatter) == "function" then
      text = tostring(self.optionTextFormatter(i, option) or "")
    else
      text = string.format("%d) %s", i, option.text or "")
    end
    self.panel:setCell(col, row, {
      kind = "button",
      text = text,
      colspan = optionColspan,
      transparent = true,
      textAlign = "left",
      contentPaddingX = leftInset,
      action = function()
        self:hide()
        if option and option.callback then
          option.callback()
        end
      end,
    })
  end

  if self.checkbox then
    local checkboxRow = optionRows + 1
    local ink = nil
    if self._modalChromeOverBlue == true then
      ink = colors:chromeTextIconsColorNonFocused()
    end
    local checkbox = Checkbox.new({
      text = self.checkbox.text or "Don't ask again",
      checked = self.checkboxChecked == true,
      -- Align icon with option button outlines (not the indented button label text).
      contentPaddingX = 0,
      contentColor = ink,
      onChange = function(checked)
        self.checkboxChecked = checked == true
      end,
    })
    self._checkbox = checkbox
    self.panel:setCell(1, checkboxRow, {
      kind = "component",
      component = checkbox,
      colspan = cols,
    })
  else
    self._checkbox = nil
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
    optionTextFormatter = nil,
    checkbox = nil,
    checkboxChecked = false,
    _checkbox = nil,
  }, Dialog)

  ModalPanelUtils.applyPanelDefaults(self)
  rebuildPanel(self)
  return self
end

--- @param title string
--- @param options table|nil
--- @param opts table|nil optional `{ checkbox = { text = string, checked = boolean|nil } }`
function Dialog:show(title, options, opts)
  opts = opts or {}
  self.title = title or ""
  self.options = options or {}
  if type(opts.checkbox) == "table" then
    self.checkbox = {
      text = opts.checkbox.text or "Don't ask again",
    }
    self.checkboxChecked = opts.checkbox.checked == true
  else
    self.checkbox = nil
    self.checkboxChecked = false
  end
  self.visible = true
  rebuildPanel(self)
end

function Dialog:isCheckboxChecked()
  return self.checkboxChecked == true
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
      -- Hide first so a newly opened text field is not under this modal;
      -- Love2D still delivers textinput for this key after keypressed.
      self:hide()
      option.callback()
      return true
    end
  end

  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if not self:_containsBox(x, y) then
    self:hide()
    return true
  end
  if button ~= 1 then return true end
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
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas, self)
  self.panel:draw()
end

return Dialog
