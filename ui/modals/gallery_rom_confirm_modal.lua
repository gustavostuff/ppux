-- gallery_rom_confirm_modal.lua
-- Confirm gallery ROM build options for packed sketch canvases.

local Button = require("ui.button")
local Panel = require("ui.panel")
local Checkbox = require("ui.checkbox")
local NumericSpinner = require("ui.numeric_spinner")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local colors = require("app_colors")

local Dialog = {}
Dialog.__index = Dialog

local MAX_VISIBLE_SLIDES = 16
local DEFAULT_FADE_HOLD = 6
local MIN_FADE_HOLD = 1
local MAX_FADE_HOLD = 30

local function chromeInk(self)
  if self._modalChromeOverBlue == true then
    return colors:chromeTextIconsColorNonFocused()
  end
  return nil
end

local function rebuildPanel(self)
  local noteRows = (self.note and self.note ~= "") and 1 or 0
  -- summary+useTransitions, optional note, hold frames, showFirstOnce, buttons
  local rows = 4 + noteRows

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
  })
  self.panel:setCell(2, 1, {
    kind = "component",
    component = self.useTransitionsCheckbox,
  })

  local row = 2
  if noteRows == 1 then
    self.panel:setCell(1, row, {
      kind = "label",
      text = self.note,
      colspan = 2,
    })
    row = row + 1
  end

  self.panel:setCell(1, row, {
    kind = "label",
    text = "Transition frames:",
  })
  self.panel:setCell(2, row, {
    kind = "component",
    component = self.holdSpinner,
  })
  row = row + 1

  self.panel:setCell(1, row, {
    kind = "component",
    component = self.showFirstOnceCheckbox,
    colspan = 2,
  })
  row = row + 1

  self.panel:setCell(1, row, {
    component = self.confirmButton,
  })
  self.panel:setCell(2, row, {
    component = self.cancelButton,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Generate gallery ROM",
    summaryText = "",
    note = nil,
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

  self.useTransitionsCheckbox = Checkbox.new({
    text = "Use transitions",
    checked = true,
    onChange = function(checked)
      self:_syncHoldSpinnerEnabled(checked == true)
    end,
  })
  self.showFirstOnceCheckbox = Checkbox.new({
    text = "Show first slide once",
    checked = false,
  })
  self.holdSpinner = NumericSpinner.new({
    value = DEFAULT_FADE_HOLD,
    min = MIN_FADE_HOLD,
    max = MAX_FADE_HOLD,
    minValueWidth = 20,
  })

  ModalPanelUtils.applyPanelDefaults(self)
  if (self.cellW or 0) < 160 then
    self.cellW = 160
  end
  self.buttonGap = self.colGap
  rebuildPanel(self)
  return self
end

function Dialog:_syncHoldSpinnerEnabled(enabled)
  -- Spinner has no enabled flag; keep value and let build ignore it when off.
  self._transitionsEnabled = enabled == true
end

function Dialog:isVisible()
  return self.visible
end

--- opts.sketches: packed sketch windows in slide order
--- opts.onConfirm(sketchesForBuild, buildOpts), opts.onCancel()
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
    "%d packed sketch canvas%s will be inserted",
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

  local ink = chromeInk(self)
  self.useTransitionsCheckbox:setChecked(true, { silent = true })
  self.useTransitionsCheckbox.contentColor = ink
  self.showFirstOnceCheckbox:setChecked(false, { silent = true })
  self.showFirstOnceCheckbox.contentColor = ink
  self.holdSpinner:setValue(DEFAULT_FADE_HOLD)
  self:_syncHoldSpinnerEnabled(true)

  self.visible = true
  self.focusedButton = "confirm"
  self.confirmButton.pressed = false
  self.cancelButton.pressed = false
  self.confirmButton.hovered = false
  self.cancelButton.hovered = false
  self.confirmButton.enabled = used > 0
  self:_setFocusedButton("confirm")
  self.panel = nil
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
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

function Dialog:_buildOpts()
  return {
    fadeHold = math.floor(tonumber(self.holdSpinner and self.holdSpinner.value) or DEFAULT_FADE_HOLD),
    useTransitions = self.useTransitionsCheckbox:isChecked(),
    showFirstOnce = self.showFirstOnceCheckbox:isChecked(),
  }
end

function Dialog:_confirm()
  local sketches = self.sketches or {}
  local used = {}
  local n = math.min(#sketches, MAX_VISIBLE_SLIDES)
  for i = 1, n do
    used[#used + 1] = sketches[i]
  end
  local buildOpts = self:_buildOpts()
  local callback = self.onConfirm
  self:hide()
  if callback then
    callback(used, buildOpts)
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
  if key == "up" then
    if self.useTransitionsCheckbox:isChecked() then
      self.holdSpinner:adjust(1)
    end
    return true
  end
  if key == "down" then
    if self.useTransitionsCheckbox:isChecked() then
      self.holdSpinner:adjust(-1)
    end
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
  return self.panel and self.panel:mousepressed(x, y, button) or true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then
    return false
  end
  return self.panel and self.panel:mousereleased(x, y, button) or true
end

function Dialog:mousemoved(x, y)
  if not self.visible then
    return false
  end
  if self.panel then
    self.panel:mousemoved(x, y)
  end
  return true
end

function Dialog:draw(canvas)
  if not self.visible then
    return
  end
  ModalPanelUtils.refreshTargetMetrics(self)
  if not self.panel then
    rebuildPanel(self)
  else
    self.panel.cellW = self.cellW
    self.panel.cellH = self.cellH
    self.panel.padding = self.padding
    self.panel.spacingX = self.buttonGap
    self.panel.spacingY = self.rowGap
    self.panel.cellPaddingX = self.cellPaddingX
    self.panel.cellPaddingY = self.cellPaddingY
  end
  self.panel:setVisible(true)
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
end

return Dialog
