local Button = require("ui.button")
local Dropdown = require("ui.dropdown")
local Panel = require("ui.panel")
local TextField = require("ui.text_field")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local RelocationPointerMath = require("utils.relocation_pointer_math")
local LoveCompat = require("utils.love_compat")
local colors = require("app_colors")

local Dialog = {}
Dialog.__index = Dialog

local INTRO_LINE = "Converts relocateTo offset to lo/hi for romPatches."
local FOOTER_LINE_2 = "Patch order: lo, then hi. Same PRG bank required."
local FOOTER_LINE_3 = "(You must find the pointer bytes in ROM, manually)"

local HEADER_ITEMS = {
  { value = 0x10, text = "0x10" },
  { value = 0x00, text = "0x00" },
}

local BANK_ITEMS = {
  { value = 0x2000, text = "0x2000" },
  { value = 0x4000, text = "0x4000" },
  { value = 0x8000, text = "0x8000" },
}

local CPU_BASE_ITEMS = {
  { value = 0x8000, text = "$8000" },
  { value = 0xA000, text = "$A000" },
  { value = 0xC000, text = "$C000" },
}

local rebuildPanel
local focusOffsetField
local clearResults
local setCopyEnabled
local onMappingChanged

local function mappingOpts(self)
  return {
    headerSize = self.headerDropdown and self.headerDropdown:getValue() or RelocationPointerMath.DEFAULT_HEADER_SIZE,
    bankSize = self.bankDropdown and self.bankDropdown:getValue() or RelocationPointerMath.DEFAULT_BANK_SIZE,
    cpuMapBase = self.cpuBaseDropdown and self.cpuBaseDropdown:getValue() or RelocationPointerMath.DEFAULT_CPU_MAP_BASE,
  }
end

local function formulaText(self)
  return RelocationPointerMath.formatFormula(mappingOpts(self))
end

local function configDropdowns(self)
  return {
    self.headerDropdown,
    self.bankDropdown,
    self.cpuBaseDropdown,
  }
end

local function closeAllDropdownMenus(self)
  local closed = false
  for _, dd in ipairs(configDropdowns(self)) do
    if dd and dd:isMenuVisible() then
      dd:closeMenu()
      closed = true
    end
  end
  return closed
end

onMappingChanged = function(self)
  clearResults(self)
  rebuildPanel(self)
  if self.panel and self.panel.focusedComponent == nil then
    focusOffsetField(self)
  end
end

local function makeMappingDropdown(self, items, defaultValue, tooltip)
  return Dropdown.new({
    getBounds = function()
      return {
        w = self._canvasW or 800,
        h = self._canvasH or 600,
      }
    end,
    default = defaultValue,
    tooltip = tooltip,
    menuOpenAbove = false,
    onBeforeOpenMenu = function(opened)
      for _, dd in ipairs(configDropdowns(self)) do
        if dd and dd ~= opened then
          dd:closeMenu()
        end
      end
    end,
    items = (function()
      local out = {}
      for _, it in ipairs(items) do
        out[#out + 1] = {
          value = it.value,
          text = it.text,
          onPick = function()
            onMappingChanged(self)
          end,
        }
      end
      return out
    end)(),
  })
end

rebuildPanel = function(self)
  local focused = self.panel and self.panel.focusedComponent or nil
  self.panel = Panel.new({
    cols = 3,
    rows = 12,
    cellW = self.cellW,
    cellH = self.cellH,
    cellWidths = {
      [1] = 112,
      [2] = 88,
      [3] = 88,
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
    colspan = 3,
  })
  self.panel:setCell(1, 2, {
    text = "ROM file offset (relocateTo)",
    colspan = 3,
  })
  self.panel:setCell(1, 3, {
    component = self.offsetField,
    colspan = 3,
  })
  self.panel:setCell(1, 4, {
    text = "Header size:",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 4, {
    component = self.headerDropdown,
    colspan = 2,
  })
  self.panel:setCell(1, 5, {
    text = "Bank size:",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 5, {
    component = self.bankDropdown,
    colspan = 2,
  })
  self.panel:setCell(1, 6, {
    text = "CPU map base:",
    preserveTrailingColon = true,
  })
  self.panel:setCell(2, 6, {
    component = self.cpuBaseDropdown,
    colspan = 2,
  })
  self.panel:setCell(1, 7, {
    component = self.calculateButton,
  })
  self.panel:setCell(2, 7, {
    component = self.clearButton,
  })
  self.panel:setCell(1, 8, {
    text = "Pointer bytes",
  })
  self.panel:setCell(2, 8, {
    text = self.resultBytesLabel or "--",
    colspan = 2,
    textColor = (self.resultLo ~= nil) and colors.green or nil,
  })
  self.panel:setCell(1, 9, {
    component = self.copyLoButton,
  })
  self.panel:setCell(2, 9, {
    component = self.copyHiButton,
  })
  self.panel:setCell(3, 9, {
    component = self.copyBothButton,
  })
  self.panel:setCell(1, 10, {
    text = formulaText(self),
    colspan = 3,
  })
  self.panel:setCell(1, 11, {
    text = FOOTER_LINE_2,
    colspan = 3,
  })
  self.panel:setCell(1, 12, {
    text = FOOTER_LINE_3,
    colspan = 3,
  })

  if focused then
    self.panel:setFocusedComponent(focused)
  end
end

focusOffsetField = function(self)
  self.offsetField:setFocused(true)
  if self.panel then
    self.panel:setFocusedComponent(self.offsetField)
  end
end

setCopyEnabled = function(self, enabled)
  self.copyLoButton.enabled = enabled
  self.copyHiButton.enabled = enabled
  self.copyBothButton.enabled = enabled
end

clearResults = function(self)
  self.resultLo = nil
  self.resultHi = nil
  self.resultBytesLabel = "--"
  setCopyEnabled(self, false)
end

local function copyText(text)
  if type(text) ~= "string" or text == "" then
    return false
  end
  return LoveCompat.setClipboardText(text) ~= false
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Relocation Pointer Calculator",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = nil,
    cellH = nil,
    fieldH = ModalPanelUtils.MODAL_BUTTON_H,
    buttonW = 88,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    panel = nil,
    resultLo = nil,
    resultHi = nil,
    resultBytesLabel = "--",
    statusCallback = nil,
    _canvasW = nil,
    _canvasH = nil,
  }, Dialog)

  self.offsetField = TextField.new({
    width = 288,
    height = self.fieldH,
    mask = "0x000000",
  })

  self.headerDropdown = makeMappingDropdown(
    self,
    HEADER_ITEMS,
    RelocationPointerMath.DEFAULT_HEADER_SIZE,
    "iNES header size subtracted before bank math"
  )
  self.bankDropdown = makeMappingDropdown(
    self,
    BANK_ITEMS,
    RelocationPointerMath.DEFAULT_BANK_SIZE,
    "PRG bank window size"
  )
  self.cpuBaseDropdown = makeMappingDropdown(
    self,
    CPU_BASE_ITEMS,
    RelocationPointerMath.DEFAULT_CPU_MAP_BASE,
    "CPU address where the bank window is mapped"
  )

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
  self.copyLoButton = Button.new({
    text = "Copy lo",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    enabled = false,
    action = function()
      self:copyLo()
    end,
  })
  self.copyHiButton = Button.new({
    text = "Copy hi",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    enabled = false,
    action = function()
      self:copyHi()
    end,
  })
  self.copyBothButton = Button.new({
    text = "Copy both",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    enabled = false,
    action = function()
      self:copyBoth()
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

function Dialog:getMappingOpts()
  return mappingOpts(self)
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Relocation Pointer Calculator"
  self.statusCallback = opts.statusCallback
  self.visible = true
  closeAllDropdownMenus(self)
  clearResults(self)
  self.offsetField:setText(opts.initialOffset or "")
  rebuildPanel(self)
  focusOffsetField(self)
end

function Dialog:hide()
  self.visible = false
  closeAllDropdownMenus(self)
  self.offsetField:setFocused(false)
  if self.offsetField._dragSelecting then
    self.offsetField._dragSelecting = false
  end
  self.statusCallback = nil
  if self.panel then
    self.panel:setVisible(false)
    self.panel:setFocusedComponent(nil)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:clear()
  closeAllDropdownMenus(self)
  self.offsetField:setText("")
  clearResults(self)
  rebuildPanel(self)
  focusOffsetField(self)
  self:_setStatus("Cleared.")
end

function Dialog:calculate()
  closeAllDropdownMenus(self)
  local offset, parseErr = RelocationPointerMath.parseFileOffset(self.offsetField:getText())
  if not offset then
    clearResults(self)
    rebuildPanel(self)
    self:_setStatus(parseErr == "empty" and "Enter a ROM file offset." or "Invalid hex offset.")
    return false
  end

  self.offsetField:setText(RelocationPointerMath.formatFileOffset(offset))

  local _cpu, lo, hi, err = RelocationPointerMath.fileOffsetToPointer(offset, mappingOpts(self))
  if not lo then
    clearResults(self)
    rebuildPanel(self)
    self:_setStatus(err == "before_header" and "Offset is inside the header." or "Could not compute pointer.")
    return false
  end

  self.resultLo = lo
  self.resultHi = hi
  local loHex = RelocationPointerMath.formatByte(lo)
  local hiHex = RelocationPointerMath.formatByte(hi)
  self.resultBytesLabel = string.format("%s  %s  (lo, hi)", loHex, hiHex)
  setCopyEnabled(self, true)
  rebuildPanel(self)
  self:_setStatus(string.format("Pointer %s %s", loHex, hiHex))
  return true
end

function Dialog:copyLo()
  if self.resultLo == nil then
    return false
  end
  local text = RelocationPointerMath.formatByte(self.resultLo)
  if copyText(text) then
    self:_setStatus("Copied lo: " .. text)
    return true
  end
  self:_setStatus("Clipboard unavailable.")
  return false
end

function Dialog:copyHi()
  if self.resultHi == nil then
    return false
  end
  local text = RelocationPointerMath.formatByte(self.resultHi)
  if copyText(text) then
    self:_setStatus("Copied hi: " .. text)
    return true
  end
  self:_setStatus("Clipboard unavailable.")
  return false
end

function Dialog:copyBoth()
  if self.resultLo == nil or self.resultHi == nil then
    return false
  end
  local text = string.format(
    "%s %s",
    RelocationPointerMath.formatByte(self.resultLo),
    RelocationPointerMath.formatByte(self.resultHi)
  )
  if copyText(text) then
    self:_setStatus("Copied: " .. text)
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
  for _, dd in ipairs(configDropdowns(self)) do
    if dd and dd:contains(x, y) then
      return true
    end
  end
  return false
end

function Dialog:getTooltipAt(x, y)
  if not self.visible then
    return nil
  end
  for _, dd in ipairs(configDropdowns(self)) do
    if dd and dd.trigger and dd.trigger.tooltip and dd.trigger:contains(x, y) then
      local tip = dd.trigger.tooltip
      if tip ~= "" then
        return tip
      end
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
    if closeAllDropdownMenus(self) then
      return true
    end
    self:hide()
    return true
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

  for _, dd in ipairs(configDropdowns(self)) do
    if dd and dd:isMenuVisible() then
      dd:handleMousePressed(x, y, button)
      return true
    end
  end

  for _, dd in ipairs(configDropdowns(self)) do
    if dd and dd:handleMousePressed(x, y, button) then
      return true
    end
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
  for _, dd in ipairs(configDropdowns(self)) do
    if dd and dd:handleMouseReleased(x, y, button) then
      return true
    end
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
  -- Open list paints above other dropdown triggers; only it should receive hover.
  for _, dd in ipairs(configDropdowns(self)) do
    if dd and dd:isMenuVisible() and dd.menu and dd.menu:contains(x, y) then
      for _, other in ipairs(configDropdowns(self)) do
        if other and other.trigger then
          other.trigger.hovered = false
        end
      end
      dd:mousemoved(x, y)
      return true
    end
  end
  for _, dd in ipairs(configDropdowns(self)) do
    if dd then
      dd:mousemoved(x, y)
    end
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
  for _, dd in ipairs(configDropdowns(self)) do
    if dd and dd.setGetBounds then
      dd:setGetBounds(function()
        return {
          w = self._canvasW or 800,
          h = self._canvasH or 600,
        }
      end)
    end
  end

  ModalPanelUtils.refreshTargetMetrics(self)
  self.buttonGap = self.colGap
  -- Avoid rebuilding Panel each frame so press/release and text focus stay on one instance.
  if not self.panel then
    rebuildPanel(self)
    focusOffsetField(self)
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
  for _, dd in ipairs(configDropdowns(self)) do
    if dd and dd.drawMenu then
      dd:drawMenu()
    end
  end
end

return Dialog
