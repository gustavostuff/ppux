local Button = require("user_interface.button")
local Dropdown = require("user_interface.dropdown")
local Panel = require("user_interface.panel")
local TextField = require("user_interface.text_field")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")
local NametableBreakpointMath = require("utils.nametable_breakpoint_math")
local LoveCompat = require("utils.love_compat")

local Dialog = {}
Dialog.__index = Dialog

local INTRO_LINE = "PPU write break from col/row - start of finding the pointer site."

local STEP_1 = "1. On emulator go: Debugger > Breakpoints > Add"
local STEP_2 = "2. Memory=PPU, Write on; use the address below"
local STEP_3 = "3. Condition A == #tile (prefer a unique tile)"

local NT_BASE_ITEMS = {
  { value = 0x2000, text = "$2000" },
  { value = 0x2400, text = "$2400" },
  { value = 0x2800, text = "$2800" },
  { value = 0x2C00, text = "$2C00" },
}

local rebuildPanel
local focusColField
local clearResults
local setCopyEnabled

local function ntBaseValue(self)
  return self.ntBaseDropdown and self.ntBaseDropdown:getValue()
    or NametableBreakpointMath.DEFAULT_NAMETABLE_BASE
end

local function closeNtBaseMenu(self)
  if self.ntBaseDropdown and self.ntBaseDropdown:isMenuVisible() then
    self.ntBaseDropdown:closeMenu()
    return true
  end
  return false
end

rebuildPanel = function(self)
  local focused = self.panel and self.panel.focusedComponent or nil
  self.panel = Panel.new({
    cols = 2,
    rows = 14,
    cellW = self.cellW,
    cellH = self.cellH,
    cellWidths = {
      [1] = 100,
      [2] = 200,
    },
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
    text = INTRO_LINE,
    colspan = 2,
  })
  self.panel:setCell(1, 2, {
    text = "Col (0-31):",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 2, {
    component = self.colField,
  })
  self.panel:setCell(1, 3, {
    text = "Row (0-29):",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 3, {
    component = self.rowField,
  })
  self.panel:setCell(1, 4, {
    text = "Tile index:",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 4, {
    component = self.tileField,
  })
  self.panel:setCell(1, 5, {
    text = "NT base:",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 5, {
    component = self.ntBaseDropdown,
  })
  self.panel:setCell(1, 6, {
    component = self.calculateButton,
  })
  self.panel:setCell(2, 6, {
    component = self.clearButton,
  })
  self.panel:setCell(1, 7, {
    text = self.addressLabel or "PPU address  --",
    colspan = 2,
  })
  self.panel:setCell(1, 8, {
    text = self.conditionLabel or "Condition     --",
    colspan = 2,
  })
  self.panel:setCell(1, 9, {
    component = self.copyAddressButton,
  })
  self.panel:setCell(2, 9, {
    component = self.copyConditionButton,
  })
  self.panel:setCell(1, 10, {
    text = STEP_1,
    colspan = 2,
  })
  self.panel:setCell(1, 11, {
    text = STEP_2,
    colspan = 2,
  })
  self.panel:setCell(1, 12, {
    text = STEP_3,
    colspan = 2,
  })
  self.panel:setCell(1, 13, {
    text = "Sky/blank tiles fire often. Attrs $23C0+ are not tiles.",
    colspan = 2,
  })

  if focused then
    self.panel:setFocusedComponent(focused)
  end
end

focusColField = function(self)
  self.colField:setFocused(true)
  self.rowField:setFocused(false)
  self.tileField:setFocused(false)
  if self.panel then
    self.panel:setFocusedComponent(self.colField)
  end
end

setCopyEnabled = function(self, enabled)
  self.copyAddressButton.enabled = enabled
  self.copyConditionButton.enabled = enabled
end

clearResults = function(self)
  self.resultAddress = nil
  self.resultCondition = nil
  self.addressLabel = "PPU address  --"
  self.conditionLabel = "Condition     --"
  setCopyEnabled(self, false)
end

local function copyText(text)
  if type(text) ~= "string" or text == "" then
    return false
  end
  return LoveCompat.setClipboardText(text) ~= false
end

local function makeNtBaseDropdown(self)
  return Dropdown.new({
    getBounds = function()
      return {
        w = self._canvasW or 800,
        h = self._canvasH or 600,
      }
    end,
    default = NametableBreakpointMath.DEFAULT_NAMETABLE_BASE,
    tooltip = "Nametable base (Name Table Viewer shows which is on screen)",
    items = (function()
      local out = {}
      for _, it in ipairs(NT_BASE_ITEMS) do
        out[#out + 1] = {
          value = it.value,
          text = it.text,
          onPick = function()
            clearResults(self)
            rebuildPanel(self)
          end,
        }
      end
      return out
    end)(),
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Nametable Breakpoint Calculator",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = nil,
    cellH = nil,
    fieldH = ModalPanelUtils.MODAL_BUTTON_H,
    buttonW = 100,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    panel = nil,
    resultAddress = nil,
    resultCondition = nil,
    addressLabel = "PPU address  --",
    conditionLabel = "Condition     --",
    statusCallback = nil,
    _canvasW = nil,
    _canvasH = nil,
  }, Dialog)

  self.colField = TextField.new({
    width = 360,
    height = self.fieldH,
  })
  self.rowField = TextField.new({
    width = 360,
    height = self.fieldH,
  })
  self.tileField = TextField.new({
    width = 360,
    height = self.fieldH,
    mask = "00",
  })
  self.ntBaseDropdown = makeNtBaseDropdown(self)

  self.calculateButton = Button.new({
    text = "Calculate",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:calculate()
    end,
  })
  self.clearButton = Button.new({
    text = "Clear",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:clear()
    end,
  })
  self.copyAddressButton = Button.new({
    text = "Copy address",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    enabled = false,
    action = function()
      self:copyAddress()
    end,
  })
  self.copyConditionButton = Button.new({
    text = "Copy condition",
    w = 120,
    h = self.buttonH,
    transparent = true,
    enabled = false,
    action = function()
      self:copyCondition()
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

function Dialog:_setStatus(message)
  if type(self.statusCallback) == "function" then
    self.statusCallback(message)
  end
end

function Dialog:_cycleFocus()
  local fields = { self.colField, self.rowField, self.tileField }
  local current = self.panel and self.panel.focusedComponent or nil
  local nextIndex = 1
  for i, field in ipairs(fields) do
    if current == field then
      nextIndex = (i % #fields) + 1
      break
    end
  end
  if self.panel then
    self.panel:setFocusedComponent(fields[nextIndex])
  end
  return true
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Nametable Breakpoint Calculator"
  self.statusCallback = opts.statusCallback
  self.visible = true
  closeNtBaseMenu(self)
  clearResults(self)
  self.colField:setText(opts.initialCol or "0")
  self.rowField:setText(opts.initialRow or "0")
  self.tileField:setText(opts.initialTile or "")
  rebuildPanel(self)
  focusColField(self)
end

function Dialog:hide()
  self.visible = false
  closeNtBaseMenu(self)
  self.colField:setFocused(false)
  self.rowField:setFocused(false)
  self.tileField:setFocused(false)
  for _, field in ipairs({ self.colField, self.rowField, self.tileField }) do
    if field._dragSelecting then
      field._dragSelecting = false
    end
  end
  self.statusCallback = nil
  if self.panel then
    self.panel:setVisible(false)
    self.panel:setFocusedComponent(nil)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:clear()
  closeNtBaseMenu(self)
  self.colField:setText("0")
  self.rowField:setText("0")
  self.tileField:setText("")
  clearResults(self)
  rebuildPanel(self)
  focusColField(self)
  self:_setStatus("Cleared.")
end

function Dialog:calculate()
  closeNtBaseMenu(self)

  local col, colErr = NametableBreakpointMath.parseCellIndex(
    self.colField:getText(),
    NametableBreakpointMath.NAMETABLE_COLS - 1
  )
  if not col then
    clearResults(self)
    rebuildPanel(self)
    self:_setStatus(colErr == "out_of_range" and "Col must be 0-31." or "Enter a valid col (0-31).")
    return false
  end

  local row, rowErr = NametableBreakpointMath.parseCellIndex(
    self.rowField:getText(),
    NametableBreakpointMath.NAMETABLE_ROWS - 1
  )
  if not row then
    clearResults(self)
    rebuildPanel(self)
    self:_setStatus(rowErr == "out_of_range" and "Row must be 0-29." or "Enter a valid row (0-29).")
    return false
  end

  local tile, tileErr = NametableBreakpointMath.parseTileIndex(self.tileField:getText())
  if not tile then
    clearResults(self)
    rebuildPanel(self)
    self:_setStatus(tileErr == "empty" and "Enter a tile index (hex)." or "Invalid tile index.")
    return false
  end

  local addr, _warn, err = NametableBreakpointMath.cellToPpuAddress(col, row, {
    nametableBase = ntBaseValue(self),
  })
  if not addr then
    clearResults(self)
    rebuildPanel(self)
    self:_setStatus("Could not compute PPU address.")
    return false
  end

  self.colField:setText(tostring(col))
  self.rowField:setText(tostring(row))
  self.tileField:setText(NametableBreakpointMath.formatTileByte(tile))

  self.resultAddress = NametableBreakpointMath.formatPpuAddress(addr)
  self.resultCondition = NametableBreakpointMath.formatConditionA(tile)
  self.addressLabel = "PPU address  " .. self.resultAddress
  self.conditionLabel = "Condition     " .. self.resultCondition
  setCopyEnabled(self, true)
  rebuildPanel(self)
  self:_setStatus(string.format("%s | %s", self.resultAddress, self.resultCondition))
  return true
end

function Dialog:copyAddress()
  if not self.resultAddress then
    return false
  end
  if copyText(self.resultAddress) then
    self:_setStatus("Copied address: " .. self.resultAddress)
    return true
  end
  self:_setStatus("Clipboard unavailable.")
  return false
end

function Dialog:copyCondition()
  if not self.resultCondition then
    return false
  end
  if copyText(self.resultCondition) then
    self:_setStatus("Copied condition: " .. self.resultCondition)
    return true
  end
  self:_setStatus("Clipboard unavailable.")
  return false
end

function Dialog:_containsBox(x, y)
  if self.panel and self._boxX then
    return self.panel:contains(x, y)
  end
  return true
end

function Dialog:_containsDropdownHit(x, y)
  return self.ntBaseDropdown and self.ntBaseDropdown:contains(x, y) == true
end

function Dialog:getTooltipAt(x, y)
  if not self.visible then
    return nil
  end
  local dd = self.ntBaseDropdown
  if dd and dd.trigger and dd.trigger.tooltip and dd.trigger:contains(x, y) then
    local tip = dd.trigger.tooltip
    if tip ~= "" then
      return tip
    end
  end
  if not self.panel or not self:_containsBox(x, y) then
    return nil
  end
  return self.panel:getTooltipAt(x, y)
end

function Dialog:handleKey(key)
  if not self.visible then
    return false
  end
  if key == "escape" then
    if closeNtBaseMenu(self) then
      return true
    end
    self:hide()
    return true
  end
  if key == "tab" then
    return self:_cycleFocus()
  end
  if key == "return" or key == "kpenter" then
    self:calculate()
    return true
  end
  if self.panel and self.panel:handleKey(key) then
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible or not self.panel then
    return false
  end
  return self.panel:textinput(text)
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then
    return false
  end
  if button ~= 1 then
    return true
  end

  local dd = self.ntBaseDropdown
  if dd and dd:isMenuVisible() then
    dd:handleMousePressed(x, y, button)
    return true
  end
  if dd and dd:handleMousePressed(x, y, button) then
    return true
  end

  if not self:_containsBox(x, y) and not self:_containsDropdownHit(x, y) then
    self:hide()
    return true
  end
  return self.panel and self.panel:mousepressed(x, y, button) == true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then
    return false
  end
  local dd = self.ntBaseDropdown
  if dd and dd:handleMouseReleased(x, y, button) then
    return true
  end
  if not self.panel then
    return false
  end
  return self.panel:mousereleased(x, y, button) == true
end

function Dialog:mousemoved(x, y)
  if not self.visible then
    return false
  end
  if self.ntBaseDropdown then
    self.ntBaseDropdown:mousemoved(x, y)
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
  if canvas then
    self._canvasW = canvas:getWidth()
    self._canvasH = canvas:getHeight()
  end
  if self.ntBaseDropdown and self.ntBaseDropdown.setGetBounds then
    self.ntBaseDropdown:setGetBounds(function()
      return {
        w = self._canvasW or 800,
        h = self._canvasH or 600,
      }
    end)
  end

  ModalPanelUtils.refreshTargetMetrics(self)
  self.buttonGap = self.colGap
  if not self.panel then
    rebuildPanel(self)
    focusColField(self)
  else
    self.panel.cellW = self.cellW
    self.panel.cellH = self.cellH
    self.panel.padding = self.padding
    self.panel.spacingX = self.buttonGap
    self.panel.spacingY = self.rowGap
    self.panel.cellPaddingX = self.cellPaddingX
    self.panel.cellPaddingY = self.cellPaddingY
    self.panel.title = self.title
    self.panel.titleH = self.titleH
    self.panel.bgColor = self.bgColor
    self.panel.titleBgColor = self.titleBgColor
    ModalPanelUtils.syncPanelChrome(self.panel, self)
    self.panel:setVisible(true)
  end
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
  if self.ntBaseDropdown and self.ntBaseDropdown.drawMenu then
    self.ntBaseDropdown:drawMenu()
  end
end

return Dialog
