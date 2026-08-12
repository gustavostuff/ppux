local Button = require("ui.button")
local Checkbox = require("ui.checkbox")
local Panel = require("ui.panel")
local TextField = require("ui.text_field")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local RomHexGrid = require("ui.rom_hex_grid")
local Shared = require("controllers.app.core_controller_shared")
local ResolutionController = require("controllers.app.resolution_controller")
local NametableStreamScanner = require("utils.nametable_stream_scanner")
local NametableShapePreview = require("ui.nametable_shape_preview")
local NametableUtils = require("utils.nametable_utils")
local colors = require("app_colors")

-- Set nametable address range: ROM hex grid + Start/End + Set/Cancel.
-- Selection mode OFF (default): two-click manual range (start, then end;
-- same cell clears). Any click starts a new pick — no inside-range lock.
-- Selection mode ON: one-shot Scan for this modal life; click any cell in a
-- complete stream to select that whole range (manual ranges are unavailable).
-- Shape preview shows for complete streams (1024 unique page writes) and is cached.

local Dialog = {}
Dialog.__index = Dialog

-- Mode checkbox, Start, End, buttons, Esc, status
local FOOTER_ROWS = 6
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

  local modeRow = hexRows + 1
  local startRow = modeRow + 1
  local endRow = startRow + 1
  local buttonRow = endRow + 1
  local escRow = buttonRow + 1
  local statusRow = escRow + 1

  self.panel:setCell(1, 1, {
    component = self.hexGrid,
    colspan = PANEL_COLS,
    rowspan = hexRows,
  })
  self.panel:setCell(1, modeRow, {
    component = self.selectionModeCheckbox,
    colspan = 2,
  })
  self.panel:setCell(3, modeRow, { text = "NT preview" })
  self.panel:setCell(1, startRow, { text = "Start:" })
  self.panel:setCell(2, startRow, { component = self.startField })
  self.panel:setCell(1, endRow, { text = "End:" })
  self.panel:setCell(2, endRow, { component = self.endField })
  self.panel:setCell(3, startRow, {
    component = self.shapePreview,
    rowspan = 2,
  })
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

local function sliceRomBytes(romRaw, startAddr, endAddr)
  local out = {}
  startAddr = math.floor(tonumber(startAddr) or 0)
  endAddr = math.floor(tonumber(endAddr) or startAddr)
  if type(romRaw) ~= "string" or startAddr < 0 or endAddr < startAddr then
    return out
  end
  local len = #romRaw
  for addr = startAddr, endAddr do
    if addr >= len then
      break
    end
    out[#out + 1] = string.byte(romRaw, addr + 1) or 0
  end
  return out
end

local function shapeCacheKey(startAddr, endAddr, codec)
  return string.format(
    "%d:%d:%s",
    math.floor(tonumber(startAddr) or -1),
    math.floor(tonumber(endAddr) or -1),
    tostring(codec or "konami"):lower()
  )
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
    -- Cached scan for this modal life (Selection mode ON).
    _scanComputed = false,
    -- Cached decoded nametables for shape preview: key -> nt bytes table.
    _shapeCache = {},
    -- Two-click manual range (Selection mode OFF).
    _rangeAnchor = nil,
    _rangeStart = nil,
    _rangeEnd = nil,
  }, Dialog)

  self.hexGrid = RomHexGrid.new({
    cols = 16,
    groupSize = 1,
    maxSelectedStarts = 1,
    replaceSelect = true,
    defaultCellStyle = "ninja",
    -- Manual pick: red. Scan mode: keep the stream's highlight cycle color.
    selectedColorForAddr = function(addr)
      if self:isSelectionMode() then
        return self.hexGrid:highlightColorForStart(addr)
      end
      local c = colors.red
      return { c[1], c[2] or 0, c[3] or 0, 1 }
    end,
    onSelect = function(addr, selectOpts)
      selectOpts = selectOpts or {}
      self:_onGridSelect(addr, {
        fromGrid = true,
        selectionCapHit = selectOpts.selectionCapHit == true,
      })
    end,
  })
  self.shapePreview = NametableShapePreview.new()
  self.selectionModeCheckbox = Checkbox.new({
    text = "Selection mode",
    checked = false,
    onChange = function(checked)
      self:_onSelectionModeChanged(checked == true)
    end,
  })
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

function Dialog:isSelectionMode()
  return self.selectionModeCheckbox and self.selectionModeCheckbox:isChecked()
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
  self.hexGrid.groupSize = 1
  self.hexGrid:setSelectedAddr(startAddr, {
    emit = false,
    allowOccupied = true,
    allowDisabled = true,
    resetColors = false,
    scrollToReveal = false,
  })
  self.hexGrid:setSelectedGroupSizes({ [startAddr] = span })
end

function Dialog:_syncManualMinimap()
  if self:isSelectionMode() then
    return
  end
  local rs, re = self._rangeStart, self._rangeEnd
  if type(rs) == "number" and type(re) == "number" and re >= rs then
    self.hexGrid:setMinimapMarkers({
      {
        offset = rs,
        color = "red",
        groupCount = 1,
        groupSize = re - rs + 1,
      },
    })
  else
    self.hexGrid:setMinimapMarkers({})
  end
end

function Dialog:_setUserSelectedCell(addr)
  if type(addr) ~= "number" then
    self.hexGrid:setUserSelectedStarts({})
    return
  end
  addr = math.floor(addr)
  self.hexGrid:setUserSelectedStarts({ addr }, {
    groupSizeByStart = { [addr] = 1 },
  })
end

function Dialog:_syncFieldsFromRange(startAddr, endAddr)
  self._syncingFromGrid = true
  self.startField:setText(self:_formatAddr(startAddr))
  self.endField:setText(self:_formatAddr(endAddr))
  self._syncingFromGrid = false
end

--- Decode range; return nametable when it is a complete page (1024 unique writes).
function Dialog:_tryCompleteNametable(startAddr, endAddr)
  startAddr = math.floor(tonumber(startAddr) or -1)
  endAddr = math.floor(tonumber(endAddr) or -1)
  if startAddr < 0 or endAddr < startAddr then
    return nil
  end
  local data = sliceRomBytes(self.romRaw, startAddr, endAddr)
  if #data < 2 then
    return nil
  end
  local nt, _, meta = NametableUtils.decode_compressed_nametable(
    data,
    false,
    self.codec or "konami"
  )
  if type(nt) ~= "table" or #nt < 960 then
    return nil
  end
  if type(meta) ~= "table" or meta.complete ~= true then
    return nil
  end
  local total = math.floor(tonumber(meta.totalPageWrites) or 0)
  if total > 1024 then
    return nil
  end
  return nt
end

function Dialog:_cacheShapeForRange(startAddr, endAddr)
  local key = shapeCacheKey(startAddr, endAddr, self.codec)
  local cached = self._shapeCache[key]
  if cached ~= nil then
    return cached
  end
  local nt = self:_tryCompleteNametable(startAddr, endAddr)
  if nt then
    self._shapeCache[key] = nt
  else
    self._shapeCache[key] = false
  end
  return self._shapeCache[key]
end

function Dialog:_refreshShapePreview(startAddr, endAddr)
  if not self.shapePreview then
    return
  end
  local nt = self:_cacheShapeForRange(startAddr, endAddr)
  if type(nt) == "table" then
    self.shapePreview:setFromNametable(nt)
  else
    self.shapePreview:clear()
  end
end

function Dialog:_clearRangeSelection()
  self._rangeAnchor = nil
  self._rangeStart = nil
  self._rangeEnd = nil
  self.hexGrid.groupSize = 1
  self.hexGrid:setSelectedGroupSizes({})
  self.hexGrid:setUserSelectedStarts({})
  self.hexGrid:_setStarts({}, 0, {
    emit = false,
    allowEmpty = true,
    resetColors = false,
    scrollToReveal = false,
  })
  if not self:isSelectionMode() then
    self.hexGrid.uniformSemiColor = nil
    self.hexGrid:setSemiSelectedStarts({}, { resetColors = true })
  end
  self:_syncManualMinimap()
  self._syncingFromGrid = true
  self.startField:setText("")
  self.endField:setText("")
  self._syncingFromGrid = false
  if self.shapePreview then
    self.shapePreview:clear()
  end
end

function Dialog:_manualRangeRed()
  local c = colors.red
  return { c[1], c[2] or 0, c[3] or 0, 1 }
end

--- Mid two-click: red semi outline from anchor→hover (or anchor alone).
function Dialog:_refreshManualRangePreview()
  if self:isSelectionMode() then
    return
  end
  local anchor = self._rangeAnchor
  if type(anchor) ~= "number" then
    return
  end
  if type(self._rangeStart) == "number" and type(self._rangeEnd) == "number" then
    return
  end
  local hover = nil
  local grid = self.hexGrid
  if grid and grid._hoverX ~= nil and grid._hoverY ~= nil then
    hover = grid:addrAtPixel(grid._hoverX, grid._hoverY)
  end
  local other = type(hover) == "number" and hover or anchor
  local lo = math.min(anchor, other)
  local hi = math.max(anchor, other)
  grid.uniformSemiColor = self:_manualRangeRed()
  grid:setSemiSelectedStarts({ lo }, {
    groupSizeByStart = { [lo] = hi - lo + 1 },
    resetColors = true,
  })
end

function Dialog:_beginManualRangeAnchor(addr)
  addr = math.floor(tonumber(addr) or 0)
  self._rangeAnchor = addr
  self._rangeStart = nil
  self._rangeEnd = nil
  self.hexGrid:setUserSelectedStarts({})
  self.hexGrid:setSelectedGroupSizes({})
  self.hexGrid:_setStarts({}, 0, {
    emit = false,
    allowEmpty = true,
    resetColors = false,
    scrollToReveal = false,
  })
  self._syncingFromGrid = true
  self.startField:setText(self:_formatAddr(addr))
  self.endField:setText(self:_formatAddr(addr))
  self._syncingFromGrid = false
  self:_syncManualMinimap()
  if self.shapePreview then
    self.shapePreview:clear()
  end
  self:_refreshManualRangePreview()
end

function Dialog:_commitRange(startAddr, endAddr, opts)
  opts = opts or {}
  if endAddr < startAddr then
    startAddr, endAddr = endAddr, startAddr
  end
  self._rangeAnchor = nil
  self._rangeStart = startAddr
  self._rangeEnd = endAddr
  if not self:isSelectionMode() then
    self.hexGrid.uniformSemiColor = nil
    self.hexGrid:setSemiSelectedStarts({}, { resetColors = true })
  end
  self:_applyRangeSelection(startAddr, endAddr)
  self:_syncFieldsFromRange(startAddr, endAddr)
  if opts.userSelectedAddr ~= nil then
    self:_setUserSelectedCell(opts.userSelectedAddr)
  else
    self.hexGrid:setUserSelectedStarts({})
  end
  self:_syncManualMinimap()
  self:_refreshShapePreview(startAddr, endAddr)
end

function Dialog:_restoreCurrentSelectionVisual()
  local rs, re = self._rangeStart, self._rangeEnd
  if type(rs) == "number" and type(re) == "number" then
    self:_applyRangeSelection(rs, re)
    self:_syncFieldsFromRange(rs, re)
    return
  end
  self.hexGrid.groupSize = 1
  self.hexGrid:setSelectedGroupSizes({})
  self.hexGrid:setUserSelectedStarts({})
  self.hexGrid:_setStarts({}, 0, {
    emit = false,
    allowEmpty = true,
    resetColors = false,
    scrollToReveal = false,
  })
end

function Dialog:_onGridSelect(addr, _opts)
  addr = math.floor(tonumber(addr) or 0)

  -- Selection mode: only whole scanned streams; clicked cell → User-selected.
  if self:isSelectionMode() then
    local hit = NametableStreamScanner.hitAt(self.scanHits, addr)
    if not hit then
      self:_restoreCurrentSelectionVisual()
      return
    end
    local s = math.floor(tonumber(hit.start) or addr)
    local e = math.floor(tonumber(hit["end"]) or addr)
    self:_commitRange(s, e, { userSelectedAddr = addr })
    return
  end

  -- Manual two-click: first click anchors start; second sets end.
  -- Same cell as the anchor clears. Any other click starts a new pick.
  local anchor = self._rangeAnchor
  if type(anchor) == "number" then
    if addr == anchor then
      self:_clearRangeSelection()
      return
    end
    self:_commitRange(anchor, addr)
    return
  end

  self:_beginManualRangeAnchor(addr)
end

function Dialog:_alignShapePreviewToSet()
  local shape = self.shapePreview
  local btn = self.setButton
  if not shape or not btn then
    return
  end
  local sw = shape:getWidth()
  local bx = tonumber(btn.x) or 0
  local bw = tonumber(btn.w) or self.buttonW or 68
  local sy = tonumber(shape.y) or 0
  shape:setPosition(math.floor(bx + (bw - sw) * 0.5), sy + 1)
end

function Dialog:_syncFromAddressFields()
  if self._syncingFromGrid then
    return
  end
  -- Scan selection mode is click-only; typed fields stay display of the pick.
  if self:isSelectionMode() then
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

function Dialog:_ensureScanComputed()
  if self._scanComputed then
    applyScanMarks(self.hexGrid, self.scanHits)
    return
  end
  if type(self.romRaw) ~= "string" or self.romRaw == "" then
    self.scanHits = {}
    self._scanComputed = true
    clearScanMarks(self.hexGrid)
    self:_setStatus("No ROM loaded")
    return
  end

  local hits, timingMs = NametableStreamScanner.scan(self.romRaw, {
    codec = self.codec or "konami",
    returnTiming = true,
  })
  self.scanHits = hits or {}
  self._scanComputed = true
  applyScanMarks(self.hexGrid, self.scanHits)

  -- Warm shape cache for every complete stream found.
  for _, hit in ipairs(self.scanHits) do
    local s = math.floor(tonumber(hit.start) or -1)
    local e = math.floor(tonumber(hit["end"]) or -1)
    if s >= 0 and e >= s then
      self:_cacheShapeForRange(s, e)
    end
  end

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

function Dialog:_onSelectionModeChanged(enabled)
  self:_clearRangeSelection()
  if enabled then
    self.hexGrid.uniformSemiColor = nil
    self.startField:setFocused(false)
    self.endField:setFocused(false)
    self:_ensureScanComputed()
  else
    clearScanMarks(self.hexGrid)
    self.hexGrid:setUserSelectedStarts({})
    self:_syncManualMinimap()
    self:_setStatus(nil)
  end
end

function Dialog:cursorNameAt(mx, my)
  if not self.visible then
    return nil
  end
  if self.panel and type(self.panel.getButtonAt) == "function" and self.panel:getButtonAt(mx, my) then
    return "hand"
  end
  if self.selectionModeCheckbox and self.selectionModeCheckbox.contains
      and self.selectionModeCheckbox:contains(mx, my) then
    return "hand"
  end
  if not self:isSelectionMode() then
    if self.startField and self.startField.contains and self.startField:contains(mx, my) then
      return "hand"
    end
    if self.endField and self.endField.contains and self.endField:contains(mx, my) then
      return "hand"
    end
  end
  local grid = self.hexGrid
  if grid and type(grid.cursorNameAt) == "function" then
    local name = grid:cursorNameAt(mx, my)
    if type(name) == "string" then
      return name
    end
  end
  return "arrow"
end

--- Test / legacy hook: force a scan and enable marks (Selection mode ON).
function Dialog:_runScan()
  self._scanComputed = false
  self.selectionModeCheckbox:setChecked(true, { silent = true })
  self:_ensureScanComputed()
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
  self._scanComputed = false
  self._shapeCache = {}
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

  self.selectionModeCheckbox:setChecked(false, { silent = true })
  self.startField:setText(opts.initialStartAddress or "")
  self.endField:setText(opts.initialEndAddress or "")
  self.startField:setFocused(true)
  self.endField:setFocused(false)
  self.setButton.pressed = false
  self.cancelButton.pressed = false
  self.setButton.hovered = false
  self.cancelButton.hovered = false

  local startAddr = select(1, Shared.parseHexAddress(opts.initialStartAddress or ""))
  local endAddr = select(1, Shared.parseHexAddress(opts.initialEndAddress or ""))
  if type(startAddr) == "number" then
    if type(endAddr) ~= "number" or endAddr < startAddr then
      endAddr = startAddr
    end
    self:_commitRange(startAddr, endAddr)
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
  self.setButton.pressed = false
  self.cancelButton.pressed = false
  self.setButton.hovered = false
  self.cancelButton.hovered = false
  self.selectionModeCheckbox:setChecked(false, { silent = true })
  self.onConfirm = nil
  self.onCancel = nil
  self.targetWindow = nil
  self.romRaw = ""
  self.scanHits = {}
  self._scanComputed = false
  self._shapeCache = {}
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
  if self:isSelectionMode() then
    -- Fields are display-only in selection mode.
    return false
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
  if self:isSelectionMode() then
    return false
  end
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
  if not self:isSelectionMode() then
    if self.startField:contains(x, y) then
      self.startField:setFocused(true)
      self.endField:setFocused(false)
    elseif self.endField:contains(x, y) then
      self.endField:setFocused(true)
      self.startField:setFocused(false)
    end
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
  self:_refreshManualRangePreview()
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
  syncModalGridMetrics(self)
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
  self:_alignShapePreviewToSet()
  self:_refreshManualRangePreview()
  self.panel:draw()
end

Dialog._hitsToMinimapMarkers = hitsToMinimapMarkers
Dialog._hitsToSemiSelection = hitsToSemiSelection
Dialog._applyScanMarks = applyScanMarks

return Dialog
