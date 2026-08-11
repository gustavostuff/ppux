-- gallery_rom_result_modal.lua
-- Success / failure result after gallery ROM generation.
-- Long paths use utils.text_utils.drawScrollingText (same marquee as open-file path).

local Button = require("ui.button")
local Panel = require("ui.panel")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local Text = require("utils.text_utils")
local colors = require("app_colors")

local Dialog = {}
Dialog.__index = Dialog

local function rebuildPanel(self)
  local hasDetail = type(self.detail) == "string" and self.detail ~= ""
  local rows = hasDetail and 3 or 2

  self.panel = Panel.new({
    cols = 3,
    rows = rows,
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
    kind = "label",
    text = self.message,
    colspan = 3,
  })

  local buttonRow = 2
  if hasDetail then
    self.panel:setCell(1, 2, {
      component = self.detailLabelComponent,
      colspan = 3,
    })
    buttonRow = 3
  end

  -- OK sits in the rightmost column only.
  self.panel:setCell(3, buttonRow, {
    component = self.okButton,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Gallery ROM",
    message = "",
    detail = nil,
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
    onClose = nil,
    panel = nil,
  }, Dialog)

  self.okButton = Button.new({
    text = "OK",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_close()
    end,
  })

  self.detailLabelComponent = {
    draw = function(component)
      local detail = self.detail
      if type(detail) ~= "string" or detail == "" then
        return
      end
      local font = love.graphics.getFont()
      local fh = font and font:getHeight() or 0
      local padX = math.floor(component.h / 2)
      local textY = component.y + math.floor((component.h - fh) / 2)
      local chromeWhite = self.panel and self.panel._modalChromeOverBlue == true
      local c = chromeWhite and colors:chromeTextIconsColorNonFocused() or (colors.textPrimary or colors.white)
      love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
      Text.drawScrollingText(
        detail,
        math.floor(component.x + padX),
        math.floor(textY),
        math.max(0, component.w - padX * 2),
        { key = self }
      )
    end,
  }

  ModalPanelUtils.applyPanelDefaults(self)
  -- Three columns: modest per-cell width so the dialog is wide without being huge.
  if (self.cellW or 0) < 120 then
    self.cellW = 120
  end
  self.buttonGap = self.colGap
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible
end

--- opts.ok, opts.message, opts.detail (optional long path), opts.title, opts.onClose
function Dialog:show(opts)
  opts = opts or {}
  local ok = opts.ok == true
  self.title = opts.title or (ok and "Gallery ROM built" or "Gallery ROM failed")

  local message = opts.message
  local detail = opts.detail
  -- Allow legacy "summary\\npath" messages.
  if detail == nil and type(message) == "string" then
    local summary, rest = message:match("^([^\n]*)\n(.*)$")
    if summary then
      message = summary
      detail = rest
    end
  end

  self.message = tostring(message or (ok and "Done." or "Failed."))
  if type(detail) == "string" and detail ~= "" then
    self.detail = detail
  else
    self.detail = nil
  end

  self.onClose = opts.onClose
  self.visible = true
  self.pressedButton = nil
  self.okButton.pressed = false
  self.okButton.hovered = false
  self.okButton.focused = true
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.pressedButton = nil
  self.okButton.pressed = false
  self.okButton.hovered = false
  self.okButton.focused = false
  self.onClose = nil
  self.detail = nil
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

function Dialog:_close()
  local callback = self.onClose
  self:hide()
  if callback then
    callback()
  end
end

function Dialog:handleKey(key)
  if not self.visible then
    return false
  end
  if key == "escape" or key == "return" or key == "kpenter" or key == "space" then
    self:_close()
    return true
  end
  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then
    return false
  end
  if button ~= 1 then
    return true
  end
  if not self:_containsBox(x, y) then
    self:_close()
    return true
  end
  self.pressedButton = nil
  if self.okButton:contains(x, y) then
    self.okButton.pressed = true
    self.pressedButton = self.okButton
  end
  return true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then
    return false
  end
  if button ~= 1 then
    return true
  end
  local pressedButton = self.pressedButton
  self.pressedButton = nil
  self.okButton.pressed = false
  if pressedButton and pressedButton:contains(x, y) and pressedButton.action then
    pressedButton.action()
  end
  return true
end

function Dialog:mousemoved(x, y)
  if not self.visible then
    return false
  end
  self.okButton.hovered = self.okButton:contains(x, y)
  return true
end

function Dialog:draw(canvas)
  if not self.visible then
    return
  end
  rebuildPanel(self)
  self.panel:setVisible(true)
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas, self)
  self.panel:draw()
end

return Dialog
