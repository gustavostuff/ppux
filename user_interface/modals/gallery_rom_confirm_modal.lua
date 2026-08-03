-- gallery_rom_confirm_modal.lua
-- Confirm which packed sketch canvases will become gallery ROM slides.

local Button = require("user_interface.button")
local Panel = require("user_interface.panel")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

local MAX_VISIBLE_SLIDES = 16

local function windowLabel(win, index)
  local title = nil
  if type(win) == "table" then
    title = win.title or win.name
  end
  if type(title) ~= "string" or title == "" then
    title = string.format("Sketch canvas %d", index)
  end
  return title
end

local function rebuildPanel(self)
  local entries = self.entries or {}
  local noteRows = (self.note and self.note ~= "") and 1 or 0
  -- summary + optional note + list + buttons
  local rows = 1 + noteRows + math.max(1, #entries) + 1
  local listStartRow = 2 + noteRows

  self.panel = Panel.new({
    cols = 2,
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
    text = self.summaryText,
    colspan = 2,
  })

  if noteRows == 1 then
    self.panel:setCell(1, 2, {
      kind = "label",
      text = self.note,
      colspan = 2,
    })
  end

  if #entries == 0 then
    self.panel:setCell(1, listStartRow, {
      kind = "label",
      text = "(none)",
      colspan = 2,
    })
  else
    for i, entry in ipairs(entries) do
      self.panel:setCell(1, listStartRow + i - 1, {
        kind = "label",
        text = string.format("%d. %s", entry.index, entry.label),
        colspan = 2,
        align = "left",
      })
    end
  end

  local buttonRow = rows
  self.panel:setCell(1, buttonRow, {
    component = self.confirmButton,
  })
  self.panel:setCell(2, buttonRow, {
    component = self.cancelButton,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Generate gallery ROM",
    summaryText = "",
    note = nil,
    entries = {},
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    buttonW = 72,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    cellW = nil,
    cellH = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    pressedButton = nil,
    focusedButton = "confirm",
    onConfirm = nil,
    onCancel = nil,
    panel = nil,
    sketches = nil,
  }, Dialog)

  self.confirmButton = Button.new({
    text = "Confirm",
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
  -- Wider cells so window titles fit.
  if (self.cellW or 0) < 160 then
    self.cellW = 160
  end
  self.buttonGap = self.colGap
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible
end

--- opts.sketches: packed sketch windows in slide order
--- opts.onConfirm(sketchesForBuild), opts.onCancel()
function Dialog:show(opts)
  opts = opts or {}
  local sketches = opts.sketches or {}
  self.sketches = sketches
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.title = opts.title or "Generate gallery ROM"

  local total = #sketches
  local used = math.min(total, MAX_VISIBLE_SLIDES)
  self.summaryText = string.format(
    "%d packed sketch canvas%s will be inserted:",
    used,
    used == 1 and "" or "es"
  )
  if total > MAX_VISIBLE_SLIDES then
    self.note = string.format(
      "Only the first %d of %d will be included (gallery max).",
      MAX_VISIBLE_SLIDES,
      total
    )
  else
    self.note = nil
  end

  local entries = {}
  for i = 1, used do
    entries[#entries + 1] = {
      index = i,
      label = windowLabel(sketches[i], i),
    }
  end
  self.entries = entries

  self.visible = true
  self.pressedButton = nil
  self.focusedButton = "confirm"
  self.confirmButton.pressed = false
  self.cancelButton.pressed = false
  self.confirmButton.hovered = false
  self.cancelButton.hovered = false
  self.confirmButton.enabled = used > 0
  self:_setFocusedButton("confirm")
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.pressedButton = nil
  self.focusedButton = "confirm"
  self.confirmButton.pressed = false
  self.cancelButton.pressed = false
  self.confirmButton.hovered = false
  self.cancelButton.hovered = false
  self.confirmButton.focused = false
  self.cancelButton.focused = false
  self.onConfirm = nil
  self.onCancel = nil
  self.sketches = nil
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
  if which ~= "confirm" and which ~= "cancel" then
    return
  end
  self.focusedButton = which
  self.confirmButton.focused = (which == "confirm")
  self.cancelButton.focused = (which == "cancel")
end

function Dialog:_toggleFocusedButton()
  if self.focusedButton == "cancel" then
    self:_setFocusedButton("confirm")
  else
    self:_setFocusedButton("cancel")
  end
end

function Dialog:_confirm()
  local sketches = self.sketches or {}
  local used = {}
  local n = math.min(#sketches, MAX_VISIBLE_SLIDES)
  for i = 1, n do
    used[#used + 1] = sketches[i]
  end
  local callback = self.onConfirm
  self:hide()
  if callback then
    callback(used)
  end
end

function Dialog:_cancel()
  local callback = self.onCancel
  self:hide()
  if callback then
    callback()
  end
end

function Dialog:handleKey(key)
  if not self.visible then
    return false
  end
  if key == "escape" then
    self:_cancel()
    return true
  end
  if key == "left" or key == "right" or key == "tab" then
    self:_toggleFocusedButton()
    return true
  end
  if key == "return" or key == "kpenter" then
    if self.focusedButton == "cancel" then
      self:_cancel()
    else
      self:_confirm()
    end
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
    self:_cancel()
    return true
  end

  self.pressedButton = nil
  if self.confirmButton.enabled ~= false and self.confirmButton:contains(x, y) then
    self.confirmButton.pressed = true
    self:_setFocusedButton("confirm")
    self.pressedButton = self.confirmButton
  elseif self.cancelButton:contains(x, y) then
    self.cancelButton.pressed = true
    self:_setFocusedButton("cancel")
    self.pressedButton = self.cancelButton
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
  self.confirmButton.pressed = false
  self.cancelButton.pressed = false

  if pressedButton and pressedButton:contains(x, y) and pressedButton.action then
    pressedButton.action()
  end
  return true
end

function Dialog:mousemoved(x, y)
  if not self.visible then
    return false
  end
  self.confirmButton.hovered = self.confirmButton:contains(x, y)
  self.cancelButton.hovered = self.cancelButton:contains(x, y)
  return true
end

function Dialog:draw(canvas)
  if not self.visible then
    return
  end
  rebuildPanel(self)
  self.panel:setVisible(true)
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
end

return Dialog
