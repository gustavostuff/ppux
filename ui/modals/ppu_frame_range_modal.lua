local Button = require("ui.button")
local Panel = require("ui.panel")
local TextField = require("ui.text_field")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local RomHexGrid = require("ui.rom_hex_grid")
local Shared = require("controllers.app.core_controller_shared")
local ResolutionController = require("controllers.app.resolution_controller")
local NametableStreamScanner = require("utils.nametable_stream_scanner")
local NametableShapePreview = require("ui.nametable_shape_preview")

-- Set nametable address range: ROM hex grid + Start/End + Scan/Set/Cancel.
-- On open: no stream markers. Scan marks complete streams (960 NT + 64 attr).
-- Grid uses two-click range pick (start, then end; same cell clears).
-- Shape preview shows when Start/End match a scanned hit.

local Dialog = {}
Dialog.__index = Dialog

local FOOTER_ROWS = 5 -- Start, End, buttons, Esc, status
local PANEL_COLS = 3

local function rowspanForHeight(height, cellH, spacingY)
  cellH = math.max(1, math.floor(tonumber(cellH) or 15))
  spacingY = math.max(0, math.floor(tonumber(spacingY) or 0))
  local step = cellH + spacingY
  return math.max(1, math.ceil((math.max(1, height) + spacingY) / step))
end

local function cellWForHexGrid(spacingX, cols, panelCols)
  local gridW = RomHexGrid.contentWidth(cols)
  spacingX = math.max(0, math.floor(tonumber(spacingX) or 0))
  panelCols = math.max(1, math.floor(tonumber(panelCols) or 2))
  local gaps = spacingX * math.max(0, panelCols - 1)
  return math.max(1, math.ceil((gridW - gaps) / panelCols))
end

local function syncModalGridMetrics(self)
  local spacingX = self.buttonGap or self.colGap or 0
  local cols = (self.hexGrid and self.hexGrid.getCols and self.hexGrid:getCols()) or 16
  self.cellW = cellWForHexGrid(spacingX, cols, PANEL_COLS)
end

local function rebuildPanel(self)
  syncModalGridMetrics(self)
  local cellH = self.cellH
  local spacingY = self.rowGap or 0
  local hexRows = rowspanForHeight(RomHexGrid.contentHeight(), cellH, spacingY)
  local totalRows = hexRows + FOOTER_ROWS

  self.panel = Panel.new({
    cols = PANEL_COLS,
    rows = totalRows,
    cellW = self.cellW,
    cellH = cellH,
    padding = self.padding,
    spacingX = self.buttonGap,
    spacingY = spacingY,
    cellPaddingX = self.cellPaddingX,
    cellPaddingY = self.cellPaddingY,
    visible = self.visible,
    title = self.title,
    titleH = self.titleH,
    bgColor = self.bgColor,
    titleBgColor = self.titleBgColor,
    _modalChromeOverBlue = self._modalChromeOverBlue == true,
  })

  local startRow = hexRows + 1
  local endRow = startRow + 1
  local buttonRow = endRow + 1
  local escRow = buttonRow + 1
  local statusRow = escRow + 1

  self.panel:setCell(1, 1, {
    component = self.hexGrid,
    colspan = PANEL_COLS,
    rowspan = hexRows,
  })
  self.panel:setCell(1, startRow, { text = "Start:" })
  self.panel:setCell(2, startRow, { component = self.startField })
  self.panel:setCell(1, endRow, { text = "End:" })
  self.panel:setCell(2, endRow, { component = self.endField })
  self.panel:setCell(3, startRow, {
    component = self.shapePreview,
    rowspan = 2,
  })
  self.panel:setCell(1, buttonRow, { component = self.scanButton })
  self.panel:setCell(2, buttonRow, { component = self.cancelButton })
  self.panel:setCell(3, buttonRow, { component = self.setButton })
  self.panel:setCell(1, escRow, { text = "Esc) Close", colspan = 2 })
  local statusText = self._statusText or ""
  if statusText ~= "" then
    self.panel:setCell(1, statusRow, { text = statusText, colspan = PANEL_COLS })
  end
end

local function hitsToMinimapMarkers(hits)
  local markers = {}
  for i, hit in ipairs(hits or {}) do
    local startAddr = math.floor(tonumber(hit.start) or -1)
    local endAddr = math.floor(tonumber(hit["end"]) or -1)
    if startAddr >= 0 and endAddr >= startAddr then
      markers[#markers + 1] = {
        offset = startAddr,
        color = RomHexGrid.highlightKeyForIndex(i),
        groupCount = 1,
        groupSize = endAddr - startAddr + 1,
      }
    end
  end
  return markers
end

local function hitsToSemiSelection(hits)
  local starts = {}
  local groupSizeByStart = {}
  for _, hit in ipairs(hits or {}) do
    local startAddr = math.floor(tonumber(hit.start) or -1)
    local endAddr = math.floor(tonumber(hit["end"]) or -1)
    if startAddr >= 0 and endAddr >= startAddr then
      starts[#starts + 1] = startAddr
      groupSizeByStart[startAddr] = endAddr - startAddr + 1
    end
  end
  return starts, groupSizeByStart
end

local function applyScanMarks(hexGrid, hits)
  if not hexGrid then
    return
  end
  local starts, groupSizeByStart = hitsToSemiSelection(hits)
  hexGrid:setMinimapMarkers(hitsToMinimapMarkers(hits))
  hexGrid:setSemiSelectedStarts(starts, {
    groupSizeByStart = groupSizeByStart,
    resetColors = true,
  })
end

local function clearScanMarks(hexGrid)
  if not hexGrid then
    return
  end
  hexGrid:setMinimapMarkers({})
  hexGrid:setSemiSelectedStarts({}, { resetColors = true })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Set tile range",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = nil,
    cellH = nil,
    fieldH = ModalPanelUtils.MODAL_BUTTON_H,
    buttonW = 68,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    onConfirm = nil,
    onCancel = nil,
    targetWindow = nil,
    romRaw = "",
    codec = "konami",
    scanHits = {},
    panel = nil,
    _syncingFromGrid = false,
    _statusText = nil,
    -- Two-click range: first click anchors start; second sets end (same cell clears).
    -- Committed range: click inside = no-op; click outside = clear.
    _rangeAnchor = nil,
    _rangeStart = nil,
    _rangeEnd = nil,
  }, Dialog)

  self.hexGrid = RomHexGrid.new({
    cols = 16,
    groupSize = 1,
    maxSelectedStarts = 1,
    replaceSelect = true,
    selectionAnts = true,
    selectionCrosshair = true,
    onSelect = function(addr, selectOpts)
      selectOpts = selectOpts or {}
      self:_onGridSelect(addr, {
        fromGrid = true,
        selectionCapHit = selectOpts.selectionCapHit == true,
      })
    end,
  })
  self.shapePreview = NametableShapePreview.new()
  self.startField = TextField.new({
    width = 104,
    height = self.fieldH,
    mask = "0x000000",
  })
  self.endField = TextField.new({
    width = 104,
    height = self.fieldH,
    mask = "0x000000",
  })
  self.scanButton = Button.new({
    text = "Scan",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_runScan()
    end,
  })
  self.setButton = Button.new({
    text = "Set",
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
  self._uses_modal_default_cellW = false
  syncModalGridMetrics(self)
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible
end

function Dialog:_formatAddr(addr)
  return string.format("0x%06X", math.floor(tonumber(addr) or 0))
end

function Dialog:_setStatus(text)
  self._statusText = text
  if self.panel then
    rebuildPanel(self)
  end
end

function Dialog:_applyRangeSelection(startAddr, endAddr, opts)
  opts = opts or {}
  startAddr = math.floor(tonumber(startAddr) or 0)
  endAddr = math.floor(tonumber(endAddr) or startAddr)
  if endAddr < startAddr then
    endAddr = startAddr
  end
  local span = endAddr - startAddr + 1
  -- Keep grid groupSize at 1 (byte). Variable stream length uses selectedGroupSizes
  -- so OAM-style fixed groups stay intact and spans do not bleed into each other.
  self.hexGrid.groupSize = 1
  self.hexGrid:setSelectedAddr(startAddr, {
    emit = false,
    allowOccupied = true,
    allowDisabled = true,
    resetColors = false,
    -- Never jump the viewport on nametable select (click or typed range).
    scrollToReveal = false,
  })
  self.hexGrid:setSelectedGroupSizes({ [startAddr] = span })
end

function Dialog:_syncFieldsFromRange(startAddr, endAddr)
  self._syncingFromGrid = true
  self.startField:setText(self:_formatAddr(startAddr))
  self.endField:setText(self:_formatAddr(endAddr))
  self._syncingFromGrid = false
end

function Dialog:_refreshShapePreview(startAddr, endAddr, hit)
  if not self.shapePreview then
    return
  end
  if not hit then
    self.shapePreview:clear()
    return
  end
  local s = math.floor(tonumber(hit.start) or startAddr or -1)
  local e = math.floor(tonumber(hit["end"]) or endAddr or -1)
  if s < 0 or e < s then
    self.shapePreview:clear()
    return
  end
  self.shapePreview:setFromStream(self.romRaw, s, e, self.codec or "konami")
end

function Dialog:_clearRangeSelection()
  self._rangeAnchor = nil
  self._rangeStart = nil
  self._rangeEnd = nil
  self.hexGrid.groupSize = 1
  self.hexGrid:setSelectedGroupSizes({})
  self.hexGrid:_setStarts({}, 0, {
    emit = false,
    allowEmpty = true,
    resetColors = false,
    scrollToReveal = false,
  })
  self._syncingFromGrid = true
  self.startField:setText("")
  self.endField:setText("")
  self._syncingFromGrid = false
  if self.shapePreview then
    self.shapePreview:clear()
  end
end

function Dialog:_commitRange(startAddr, endAddr)
  if endAddr < startAddr then
    startAddr, endAddr = endAddr, startAddr
  end
  self._rangeAnchor = nil
  self._rangeStart = startAddr
  self._rangeEnd = endAddr
  self:_applyRangeSelection(startAddr, endAddr)
  self:_syncFieldsFromRange(startAddr, endAddr)
  self:_refreshShapePreview(startAddr, endAddr, self:_hitMatchingRange(startAddr, endAddr))
end

function Dialog:_hitMatchingRange(startAddr, endAddr)
  local hit = NametableStreamScanner.hitAt(self.scanHits, startAddr)
  if not hit then
    return nil
  end
  if math.floor(tonumber(hit.start) or -1) == startAddr
    and math.floor(tonumber(hit["end"]) or -1) == endAddr
  then
    return hit
  end
  return nil
end

function Dialog:_onGridSelect(addr, _opts)
  addr = math.floor(tonumber(addr) or 0)
  local anchor = self._rangeAnchor

  -- Mid two-click: waiting for end.
  if type(anchor) == "number" then
    if addr == anchor then
      self:_clearRangeSelection()
      return
    end
    self:_commitRange(anchor, addr)
    return
  end

  -- Committed range: inside = no-op (re-apply so the grid click does not stick);
  -- outside = clear and re-anchor at the clicked cell in one step.
  local rs, re = self._rangeStart, self._rangeEnd
  if type(rs) == "number" and type(re) == "number" then
    if addr >= rs and addr <= re then
      self:_applyRangeSelection(rs, re)
      self:_syncFieldsFromRange(rs, re)
      return
    end
    self:_clearRangeSelection()
    -- Fall through to re-anchor.
  end

  -- No range yet (or just cleared): first click anchors start
  -- (works on/inside/overlapping scan semis).
  self._rangeAnchor = addr
  self._rangeStart = nil
  self._rangeEnd = nil
  self:_applyRangeSelection(addr, addr)
  self:_syncFieldsFromRange(addr, addr)
  self:_refreshShapePreview(addr, addr, self:_hitMatchingRange(addr, addr))
end

function Dialog:_syncFromAddressFields()
  if self._syncingFromGrid then
    return
  end
  local startAddr = select(1, Shared.parseHexAddress(self.startField:getText() or ""))
  local endAddr = select(1, Shared.parseHexAddress(self.endField:getText() or ""))
  if type(startAddr) ~= "number" then
    return
  end
  if type(endAddr) ~= "number" then
    endAddr = startAddr
  end
  if endAddr < startAddr then
    endAddr = startAddr
  end
  self:_commitRange(startAddr, endAddr)
end

function Dialog:_runScan()
  if type(self.romRaw) ~= "string" or self.romRaw == "" then
    self:_setStatus("No ROM loaded")
    return
  end

  local hits, timingMs = NametableStreamScanner.scan(self.romRaw, {
    codec = self.codec or "konami",
    returnTiming = true,
  })
  self.scanHits = hits or {}
  applyScanMarks(self.hexGrid, self.scanHits)

  local n = #self.scanHits
  local status
  if n == 0 then
    status = "No complete streams"
  elseif timingMs ~= nil then
    status = string.format("%d stream%s (%.0f ms)", n, n == 1 and "" or "s", timingMs)
  else
    status = string.format("%d stream%s", n, n == 1 and "" or "s")
  end
  self:_setStatus(status)
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Set tile range"
  self.targetWindow = opts.window
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true
  self.romRaw = type(opts.romRaw) == "string" and opts.romRaw or ""
  self.codec = tostring(opts.codec or "konami"):lower()
  self.scanHits = {}
  self._statusText = nil
  self._rangeAnchor = nil
  self._rangeStart = nil
  self._rangeEnd = nil
  if self.shapePreview then
    self.shapePreview:clear()
  end

  self.hexGrid:setRomRaw(self.romRaw)
  clearScanMarks(self.hexGrid)
  self.hexGrid.groupSize = 1
  self.hexGrid:setSelectedGroupSizes({})

  self.startField:setText(opts.initialStartAddress or "")
  self.endField:setText(opts.initialEndAddress or "")
  self.startField:setFocused(true)
  self.endField:setFocused(false)
  self.scanButton.pressed = false
  self.setButton.pressed = false
  self.cancelButton.pressed = false
  self.scanButton.hovered = false
  self.setButton.hovered = false
  self.cancelButton.hovered = false

  local startAddr = select(1, Shared.parseHexAddress(opts.initialStartAddress or ""))
  local endAddr = select(1, Shared.parseHexAddress(opts.initialEndAddress or ""))
  if type(startAddr) == "number" then
    if type(endAddr) ~= "number" or endAddr < startAddr then
      endAddr = startAddr
    end
    self:_commitRange(startAddr, endAddr)
    -- Open only: bring the current range into view once.
    self.hexGrid:scrollToReveal(startAddr)
  else
    self.hexGrid:_setStarts({}, 0, {
      emit = false,
      allowEmpty = true,
      resetColors = true,
    })
  end

  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.startField:setFocused(false)
  self.endField:setFocused(false)
  self.scanButton.pressed = false
  self.setButton.pressed = false
  self.cancelButton.pressed = false
  self.scanButton.hovered = false
  self.setButton.hovered = false
  self.cancelButton.hovered = false
  self.onConfirm = nil
  self.onCancel = nil
  self.targetWindow = nil
  self.romRaw = ""
  self.scanHits = {}
  self._statusText = nil
  self._rangeAnchor = nil
  self._rangeStart = nil
  self._rangeEnd = nil
  if self.shapePreview then
    self.shapePreview:clear()
  end
  if self.hexGrid then
    clearScanMarks(self.hexGrid)
    self.hexGrid:setSelectedGroupSizes({})
    self.hexGrid:setRomRaw("")
  end
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
    local ok = callback(
      self.startField:getText() or "",
      self.endField:getText() or "",
      targetWindow
    )
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
  if key == "tab" then
    if self.startField.focused then
      self.startField:setFocused(false)
      self.endField:setFocused(true)
    else
      self.startField:setFocused(true)
      self.endField:setFocused(false)
    end
    return true
  end
  if self.startField.focused and self.startField:onKeyPressed(key) then
    self:_syncFromAddressFields()
    return true
  end
  if self.endField.focused and self.endField:onKeyPressed(key) then
    self:_syncFromAddressFields()
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  if self.startField.focused then
    local ok = self.startField:onTextInput(text)
    if ok then
      self:_syncFromAddressFields()
    end
    return ok
  end
  if self.endField.focused then
    local ok = self.endField:onTextInput(text)
    if ok then
      self:_syncFromAddressFields()
    end
    return ok
  end
  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end
  if not self:_containsBox(x, y) then
    self:_cancel()
    return true
  end
  if self.startField:contains(x, y) then
    self.startField:setFocused(true)
    self.endField:setFocused(false)
  elseif self.endField:contains(x, y) then
    self.endField:setFocused(true)
    self.startField:setFocused(false)
  end
  return self.panel and self.panel:mousepressed(x, y, button) or true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  if self.hexGrid then
    self.hexGrid:mousereleased(x, y, button)
  end
  return self.panel and self.panel:mousereleased(x, y, button) or true
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end
  if self.hexGrid then
    self.hexGrid:mousemoved(x, y)
  end
  if self.panel and not (self.hexGrid and self.hexGrid:isScrollDragging()) then
    self.panel:mousemoved(x, y)
  end
  return true
end

function Dialog:wheelmoved(dx, dy)
  if not self.visible then return false end
  local mx, my = 0, 0
  if ResolutionController and ResolutionController.getScaledMouse then
    local mouse = ResolutionController:getScaledMouse(true)
    mx = mouse and mouse.x or 0
    my = mouse and mouse.y or 0
  elseif love and love.mouse and love.mouse.getPosition then
    mx, my = love.mouse.getPosition()
  end
  if not self.hexGrid then
    return true
  end
  return self.hexGrid:wheelmovedAt(dx, dy, mx, my)
end

function Dialog:draw(canvas)
  if not self.visible then return end
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
    self.panel.title = self.title
    self.panel.titleH = self.titleH
    self.panel.bgColor = self.bgColor
    self.panel.titleBgColor = self.titleBgColor
    ModalPanelUtils.syncPanelChrome(self.panel, self)
    self.panel:setVisible(true)
  end
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas, self)
  self.panel:draw()
end

-- Exported for unit tests.
Dialog._hitsToMinimapMarkers = hitsToMinimapMarkers
Dialog._hitsToSemiSelection = hitsToSemiSelection
Dialog._applyScanMarks = applyScanMarks

return Dialog
