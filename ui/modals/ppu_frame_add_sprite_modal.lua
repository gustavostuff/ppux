local Button = require("ui.button")
local Checkbox = require("ui.checkbox")
local Panel = require("ui.panel")
local TextField = require("ui.text_field")
local Text = require("utils.text_utils")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local RomHexGrid = require("ui.rom_hex_grid")
local OamSpritePreview = require("ui.oam_sprite_preview")
local Shared = require("controllers.app.core_controller_shared")
local ResolutionController = require("controllers.app.resolution_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local OamScanner = require("scanners.oam_heuristic_scanner")
local colors = require("app_colors")

-- Shared Add/Edit sprite modal for PPU Frame and OAM Animation windows.
-- Hex grid + 2x preview sync with the OAM start field (first of 4 OAM bytes).
-- CHR bank/tile come from ROM + the window's linked pattern table on hydrate.
-- Add mode also mirrors the selection onto the target sprite layer as draft
-- `_addModalPreview` items (removed on Cancel / before Confirm).
-- Scan OFF (default): click to toggle 4-byte OAM groups.
-- Scan ON: one-shot heuristic scan for this modal life; click a marked pair /
-- metasprite run to toggle every 4-byte item in that hit (at least two).
-- Clicks outside hits are ignored. Add-mode multi-select still stacks hits.

local Dialog = {}
Dialog.__index = Dialog

local FOOTER_ROWS = 3 -- OAM field, buttons, Esc
local PANEL_COLS = 3
Dialog.NES_SPRITE_LIMIT = 64
Dialog.MSG_MAX_PER_ADD = "8 items allowed per Add event"
Dialog.MSG_NES_LIMIT = "64 sprites allowed (NES limit)"
Dialog.MSG_ALREADY_IN_LAYER = "Sprite already in layer"

local function isModalPreviewItem(item)
  return type(item) == "table" and item._addModalPreview == true
end

local function countActiveSprites(layer)
  local n = 0
  for _, item in ipairs((layer and layer.items) or {}) do
    if item.removed ~= true and not isModalPreviewItem(item) then
      n = n + 1
    end
  end
  return n
end

--- Exact OAM Y-byte starts already present in the layer (sorted ascending).
local function collectOccupiedOamStarts(layer, opts)
  opts = opts or {}
  local exclude = opts.excludeStartAddr
  local list = {}
  local seen = {}
  for _, item in ipairs((layer and layer.items) or {}) do
    if item and item.removed ~= true and not isModalPreviewItem(item) and type(item.startAddr) == "number" then
      local addr = math.floor(item.startAddr)
      if addr >= 0 and not seen[addr] and addr ~= exclude then
        seen[addr] = true
        list[#list + 1] = addr
      end
    end
  end
  table.sort(list)
  return list
end

--- Add mode default: first free group after the last disabled start, or 0 when none.
local function defaultAddOamStart(occupiedStarts, groupSize)
  groupSize = math.max(1, math.floor(tonumber(groupSize) or 4))
  local occupied = occupiedStarts or {}
  if #occupied == 0 then
    return 0
  end
  return math.floor(occupied[#occupied]) + groupSize
end

--- Gray scrollbar markers: one OAM group (4 bytes) per in-layer start.
local function occupiedMinimapMarkers(starts, groupSize)
  groupSize = math.max(1, math.floor(tonumber(groupSize) or 4))
  local markers = {}
  for _, addr in ipairs(starts or {}) do
    markers[#markers + 1] = {
      offset = math.floor(addr),
      color = "gray",
      groupCount = 1,
      groupSize = groupSize,
    }
  end
  return markers
end

-- Exported for unit tests.
Dialog._collectOccupiedOamStarts = collectOccupiedOamStarts
Dialog._defaultAddOamStart = defaultAddOamStart
Dialog._occupiedMinimapMarkers = occupiedMinimapMarkers
Dialog._isModalPreviewItem = isModalPreviewItem

local function startOverlapsOccupiedList(addr, occupiedStarts)
  addr = math.floor(tonumber(addr) or -1)
  if addr < 0 then
    return true
  end
  for _, occ in ipairs(occupiedStarts or {}) do
    if addr < occ + 4 and occ < addr + 4 then
      return true
    end
  end
  return false
end

function Dialog:_clearLayerPreviews()
  local layer = self.spriteLayer
  if not (layer and layer.items) then
    return false
  end
  local removed = false
  for i = #layer.items, 1, -1 do
    if isModalPreviewItem(layer.items[i]) then
      table.remove(layer.items, i)
      removed = true
    end
  end
  return removed
end

--- Mirror the current Add-mode hex selection onto the sprite layer for live preview.
function Dialog:_syncLayerPreview()
  if self.isEdit == true or not self.visible then
    return
  end
  local layer = self.spriteLayer
  if not layer then
    return
  end

  local starts = self.hexGrid and self.hexGrid:getSelectedStarts() or {}
  local occupied = collectOccupiedOamStarts(layer)
  local desired = {}
  local desiredSet = {}
  for _, addr in ipairs(starts) do
    addr = math.floor(tonumber(addr) or -1)
    if addr >= 0 and not desiredSet[addr] and not startOverlapsOccupiedList(addr, occupied) then
      desiredSet[addr] = true
      desired[#desired + 1] = addr
    end
  end

  layer.items = layer.items or {}
  local existingPreviewByAddr = {}
  local changed = false
  for i = #layer.items, 1, -1 do
    local item = layer.items[i]
    if isModalPreviewItem(item) then
      local addr = type(item.startAddr) == "number" and math.floor(item.startAddr) or nil
      if addr == nil or not desiredSet[addr] or existingPreviewByAddr[addr] then
        table.remove(layer.items, i)
        changed = true
      else
        existingPreviewByAddr[addr] = item
      end
    end
  end

  for _, addr in ipairs(desired) do
    if not existingPreviewByAddr[addr] then
      local item = {
        startAddr = addr,
        _addModalPreview = true,
      }
      layer.items[#layer.items + 1] = item
      existingPreviewByAddr[addr] = item
      changed = true
    end
  end

  if changed or #desired > 0 then
    local romRaw = self.romRaw
    if type(romRaw) == "string" and romRaw ~= "" then
      SpriteController.hydrateSpriteLayer(layer, {
        romRaw = romRaw,
        tilesPool = self.tilesPool,
        appEditState = self.appEditState,
        keepWorld = true,
      })
    end
  end
end

--- How many panel rows are needed so spanned cell height >= `height`.
local function rowspanForHeight(height, cellH, spacingY)
  cellH = math.max(1, math.floor(tonumber(cellH) or 15))
  spacingY = math.max(0, math.floor(tonumber(spacingY) or 0))
  local step = cellH + spacingY
  return math.max(1, math.ceil((math.max(1, height) + spacingY) / step))
end

--- Prefer one fewer row when ceil overshoots by nearly a full cell (grid→preview gap).
local function rowspanForHeightTight(height, cellH, spacingY)
  local rows = rowspanForHeight(height, cellH, spacingY)
  cellH = math.max(1, math.floor(tonumber(cellH) or 15))
  spacingY = math.max(0, math.floor(tonumber(spacingY) or 0))
  local step = cellH + spacingY
  local used = rows * step - spacingY
  if rows > 1 and (used - height) >= math.max(1, cellH - 2) then
    rows = rows - 1
  end
  return math.max(1, rows)
end

--- Panel cell width so PANEL_COLS (+ spacing) match the hex grid content width.
local function cellWForHexGrid(spacingX)
  local gridW = RomHexGrid.contentWidth()
  spacingX = math.max(0, math.floor(tonumber(spacingX) or 0))
  local gaps = spacingX * math.max(0, PANEL_COLS - 1)
  return math.max(1, math.ceil((gridW - gaps) / PANEL_COLS))
end

local function syncModalGridMetrics(self)
  local spacingX = self.buttonGap or self.colGap or 0
  self.cellW = cellWForHexGrid(spacingX)
end

local function rebuildPanel(self)
  syncModalGridMetrics(self)
  local cellH = self.cellH
  local spacingY = self.rowGap or 0
  local hexRows = rowspanForHeightTight(RomHexGrid.contentHeight(), cellH, spacingY)
  local previewRows = rowspanForHeight(self.preview:preferredHeight(), cellH, spacingY)
  local totalRows = hexRows + previewRows + FOOTER_ROWS

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

  local previewRow = hexRows + 1
  local oamRow = previewRow + previewRows
  local buttonRow = oamRow + 1
  local escRow = buttonRow + 1

  self.panel:setCell(1, 1, {
    component = self.hexGrid,
    colspan = PANEL_COLS,
    rowspan = hexRows,
  })
  self.panel:setCell(1, previewRow, {
    component = self.preview,
    colspan = PANEL_COLS,
    rowspan = previewRows,
  })
  -- OAM field + Scan; Cancel/Add one column left of the previous layout.
  self.panel:setCell(1, oamRow, { text = "OAM start:" })
  self.panel:setCell(2, oamRow, { component = self.oamStartField })
  self.panel:setCell(3, oamRow, { component = self.scannedModeCheckbox })
  self.panel:setCell(1, buttonRow, { component = self.cancelButton })
  self.panel:setCell(2, buttonRow, { component = self.addButton })
  self.panel:setCell(1, escRow, { text = "Esc) Close" })
  -- One Esc-row label: limit warning or scan status. Update `.text` in place.
  self.panel:setCell(2, escRow, {
    component = self.footerLabel,
    colspan = 2,
  })
end

local function newFooterLabel()
  return {
    text = "",
    isWarning = false,
    x = 0,
    y = 0,
    w = 0,
    h = 0,
    setPosition = function(self, x, y)
      self.x = x or self.x
      self.y = y or self.y
    end,
    setSize = function(self, w, h)
      self.w = w or self.w
      self.h = h or self.h
    end,
    draw = function(self)
      local msg = self.text
      if type(msg) ~= "string" or msg == "" then
        return
      end
      local font = nil
      if love and love.graphics and love.graphics.getFont then
        local ok, f = pcall(love.graphics.getFont)
        if ok then
          font = f
        end
      end
      local tw = Text.getFontWidth(msg, font)
      local th = font and font.getHeight and font:getHeight() or 10
      local marginX = math.floor((self.h or 0) / 2)
      local x = math.floor((self.x + (self.w or 0)) - marginX - tw)
      local y = self.y + math.floor(((self.h or th) - th) * 0.5)
      local color = self.isWarning and colors:modalWarningColor()
        or colors:chromeTextIconsColorNonFocused()
      Text.print(msg, x, y, {
        color = color,
        font = font,
        literalColor = true,
      })
    end,
  }
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Add sprite",
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
    spriteLayer = nil,
    romRaw = "",
    scanHits = {},
    panel = nil,
    _syncingFromGrid = false,
    _statusText = nil,
    _scanComputed = false,
    _committedStarts = {},
    _occupiedStarts = {},
    _minimapOccupiedStarts = {},
  }, Dialog)

  self.hexGrid = RomHexGrid.new({
    groupSize = 4,
    maxSelectedStarts = RomHexGrid.MAX_SELECTED_STARTS,
    defaultCellStyle = "ninja",
    selectionAnts = true,
    selectionAntsOnHover = true,
    scrollOnSelect = false,
    -- Scan mode: keep the hit's highlight cycle color on Selected groups.
    selectedColorForAddr = function(addr)
      if not self:isScannedMode() then
        return nil
      end
      local hit = OamScanner.hitAt(self.scanHits, addr)
      local colorAddr = (hit and hit.start) or addr
      return self.hexGrid:highlightColorForStart(colorAddr)
    end,
    canSelectAddr = function(addr)
      if not self:isScannedMode() then
        return true
      end
      return OamScanner.hitAt(self.scanHits, addr) ~= nil
    end,
    onSelect = function(addr, selectOpts)
      selectOpts = selectOpts or {}
      self:_onGridSelect(addr, {
        fromGrid = true,
        selectionCapHit = selectOpts.selectionCapHit == true,
      })
    end,
  })
  self.preview = OamSpritePreview.new()
  self.scannedModeCheckbox = Checkbox.new({
    text = "Scan",
    checked = false,
    onChange = function(checked)
      self:_onScannedModeChanged(checked == true)
    end,
  })
  self.oamStartField = TextField.new({
    width = 104,
    height = self.fieldH,
    mask = "0x000000",
  })
  self.addButton = Button.new({
    text = "Add",
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
  self.footerLabel = newFooterLabel()

  ModalPanelUtils.applyPanelDefaults(self)
  self.buttonGap = self.colGap
  -- Prefer grid-driven width over the modal default cellW.
  self._uses_modal_default_cellW = false
  syncModalGridMetrics(self)
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible
end

function Dialog:isScannedMode()
  return self.scannedModeCheckbox and self.scannedModeCheckbox:isChecked()
end

function Dialog:cursorNameAt(mx, my)
  if not self.visible then
    return nil
  end
  if self.panel and type(self.panel.getButtonAt) == "function" and self.panel:getButtonAt(mx, my) then
    return "hand"
  end
  if self.scannedModeCheckbox and self.scannedModeCheckbox.contains
      and self.scannedModeCheckbox:contains(mx, my) then
    return "hand"
  end
  if not self:isScannedMode() then
    if self.oamStartField and self.oamStartField.contains and self.oamStartField:contains(mx, my) then
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

function Dialog:_focusOamField()
  self.oamStartField:setFocused(true)
end

function Dialog:_formatOam(addr)
  return string.format("0x%06X", math.floor(tonumber(addr) or 0))
end

function Dialog:_setStatus(text)
  self._statusText = text
  self:_refreshFooterLabel()
end

function Dialog:_refreshFooterLabel()
  local label = self.footerLabel
  if not label then
    return
  end
  local warning = self._limitWarning
  if type(warning) == "string" and warning ~= "" then
    label.text = warning
    label.isWarning = true
    return
  end
  if self:isScannedMode() and type(self._statusText) == "string" and self._statusText ~= "" then
    label.text = self._statusText
    label.isWarning = false
    return
  end
  label.text = ""
  label.isWarning = false
end

local function hitsToUnderlinedSelection(hits)
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

local function hitsToScanMinimapMarkers(hits)
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

local function applyScanUnderlines(hexGrid, hits)
  if not hexGrid then
    return
  end
  local starts, groupSizeByStart = hitsToUnderlinedSelection(hits)
  hexGrid:setUnderlinedStarts(starts, {
    groupSizeByStart = groupSizeByStart,
    resetColors = true,
  })
end

local function clearScanUnderlines(hexGrid)
  if hexGrid then
    hexGrid:setUnderlinedStarts({}, { resetColors = true })
  end
end

function Dialog:_refreshMinimap()
  if not self.hexGrid then
    return
  end
  local markers = occupiedMinimapMarkers(self._minimapOccupiedStarts, self.hexGrid:getGroupSize())
  if self:isScannedMode() then
    local scanMarkers = hitsToScanMinimapMarkers(self.scanHits)
    for i = 1, #scanMarkers do
      markers[#markers + 1] = scanMarkers[i]
    end
  end
  self.hexGrid:setMinimapMarkers(markers)
end

function Dialog:_applySelectedStarts(starts, opts)
  opts = opts or {}
  starts = starts or {}
  local primary = opts.primary
  if type(primary) ~= "number" and #starts > 0 then
    primary = starts[#starts]
  end
  self.hexGrid:_setStarts(starts, primary or 0, {
    emit = false,
    allowEmpty = true,
    allowOccupied = self.isEdit == true,
    resetColors = opts.resetColors == true,
    scrollToReveal = false,
  })
  if type(opts.userSelectedAddr) == "number" then
    local addr = math.floor(opts.userSelectedAddr)
    self.hexGrid:setUserSelectedStarts({ addr }, {
      groupSizeByStart = { [addr] = 1 },
    })
  else
    self.hexGrid:setUserSelectedStarts({})
  end
  self._syncingFromGrid = true
  if #starts > 0 then
    self.oamStartField:setText(self:_formatOam(primary or starts[#starts]))
  end
  self._syncingFromGrid = false
  self:_syncPreviewFromGrid()
  self:_refreshLimitWarning()
end

function Dialog:_restoreCommittedSelection()
  self:_applySelectedStarts(self._committedStarts or {}, {
    resetColors = false,
  })
end

local function startsSet(list)
  local set = {}
  for _, addr in ipairs(list or {}) do
    set[math.floor(addr)] = true
  end
  return set
end

local function filterFreeHitStarts(self, hitStarts)
  local free = {}
  for _, addr in ipairs(hitStarts or {}) do
    addr = math.floor(tonumber(addr) or -1)
    if addr >= 0 and not startOverlapsOccupiedList(addr, self._occupiedStarts) then
      free[#free + 1] = addr
    end
  end
  return free
end

local function pickSpriteStartFromHit(hitStarts, addr)
  addr = math.floor(tonumber(addr) or 0)
  for _, startAddr in ipairs(hitStarts or {}) do
    if addr >= startAddr and addr < startAddr + OamScanner.SPRITE_SPAN then
      return startAddr
    end
  end
  return hitStarts and hitStarts[1] or nil
end

function Dialog:_onScanGridSelect(addr)
  addr = math.floor(tonumber(addr) or 0)
  local hit = OamScanner.hitAt(self.scanHits, addr)
  if not hit then
    self:_restoreCommittedSelection()
    return
  end

  local hitStarts = filterFreeHitStarts(self, OamScanner.startsForHit(hit))
  if self.isEdit == true then
    local picked = pickSpriteStartFromHit(hitStarts, addr)
    hitStarts = picked and { picked } or {}
  end
  if #hitStarts == 0 then
    self:_restoreCommittedSelection()
    return
  end

  local committed = self._committedStarts or {}
  local committedSet = startsSet(committed)
  -- Cap clamp can keep only part of the last hit. Treat any overlap as
  -- "this group is selected" so a second click deselects it.
  local anySelected = false
  for _, startAddr in ipairs(hitStarts) do
    if committedSet[startAddr] then
      anySelected = true
      break
    end
  end

  local nextStarts = {}
  local nextSet = {}
  if anySelected then
    local remove = startsSet(hitStarts)
    for _, startAddr in ipairs(committed) do
      if not remove[startAddr] and not nextSet[startAddr] then
        nextSet[startAddr] = true
        nextStarts[#nextStarts + 1] = startAddr
      end
    end
  else
    for _, startAddr in ipairs(committed) do
      if not nextSet[startAddr] then
        nextSet[startAddr] = true
        nextStarts[#nextStarts + 1] = startAddr
      end
    end
    for _, startAddr in ipairs(hitStarts) do
      if not nextSet[startAddr] then
        nextSet[startAddr] = true
        nextStarts[#nextStarts + 1] = startAddr
      end
    end
  end

  self._hitMax8 = #nextStarts > RomHexGrid.MAX_SELECTED_STARTS
  self:_applySelectedStarts(nextStarts, {
    userSelectedAddr = #nextStarts > 0 and addr or nil,
    resetColors = false,
  })
  self._committedStarts = self.hexGrid:getSelectedStarts()
end

function Dialog:_ensureScanComputed()
  if self._scanComputed then
    applyScanUnderlines(self.hexGrid, self.scanHits)
    self:_refreshMinimap()
    return
  end
  if type(self.romRaw) ~= "string" or self.romRaw == "" then
    self.scanHits = {}
    self._scanComputed = true
    clearScanUnderlines(self.hexGrid)
    self:_refreshMinimap()
    self:_setStatus("No ROM loaded")
    return
  end

  local hits, timingMs = OamScanner.scan(self.romRaw, { returnTiming = true })
  self.scanHits = hits or {}
  self._scanComputed = true
  applyScanUnderlines(self.hexGrid, self.scanHits)
  self:_refreshMinimap()

  local n = #self.scanHits
  local status
  if n == 0 then
    status = "No OAM pairs"
  elseif timingMs ~= nil then
    status = string.format("%d hit%s (%.0f ms)", n, n == 1 and "" or "s", timingMs)
  else
    status = string.format("%d hit%s", n, n == 1 and "" or "s")
  end
  self:_setStatus(status)
end

function Dialog:_clearScanSelection()
  self._committedStarts = {}
  self.hexGrid:setUserSelectedStarts({})
  self.hexGrid:_setStarts({}, 0, {
    emit = false,
    allowEmpty = true,
    resetColors = false,
    scrollToReveal = false,
  })
  self:_syncPreviewFromGrid()
  self:_refreshLimitWarning()
end

function Dialog:_onScannedModeChanged(enabled)
  enabled = enabled == true
  self.hexGrid.replaceSelect = enabled
  if enabled then
    self.oamStartField:setFocused(false)
    self:_clearScanSelection()
    self:_ensureScanComputed()
  else
    clearScanUnderlines(self.hexGrid)
    self.hexGrid:setUserSelectedStarts({})
    self:_refreshMinimap()
    local committed = self._committedStarts or {}
    if #committed == 0 then
      local initialAddr = defaultAddOamStart(self._occupiedStarts, self.hexGrid:getGroupSize())
      if self.isEdit == true then
        initialAddr = select(1, Shared.parseHexAddress(self.oamStartField:getText() or ""))
        if type(initialAddr) ~= "number" then
          initialAddr = 0
        end
      end
      self:_applySelectedStarts({ initialAddr }, { resetColors = true })
      self._committedStarts = self.hexGrid:getSelectedStarts()
    else
      self:_applySelectedStarts(committed, { resetColors = true })
    end
  end
  if self.panel then
    rebuildPanel(self)
  end
end

--- Test / legacy hook: force a scan and enable marks (Scan ON).
function Dialog:_runScan()
  self._scanComputed = false
  self.scannedModeCheckbox:setChecked(true, { silent = true })
  self.hexGrid.replaceSelect = true
  self:_ensureScanComputed()
end

function Dialog:_syncPreviewFromGrid()
  local starts = self.hexGrid:getSelectedStarts()
  local groupColors = {}
  for i = 1, #starts do
    local addr = starts[i]
    local c = nil
    if type(self.hexGrid.selectedColorForAddr) == "function" then
      c = self.hexGrid.selectedColorForAddr(addr)
    end
    if type(c) ~= "table" then
      c = self.hexGrid:highlightColorForStartIndex(i)
    end
    groupColors[i] = c
  end
  local prevH = self._previewPrefH
  self.preview:setSelectedStarts(starts, groupColors)
  local newH = self.preview:preferredHeight()
  self._previewPrefH = newH
  if self.visible and prevH ~= nil and newH ~= prevH and self.panel then
    rebuildPanel(self)
  end
  self:_refreshAddEnabled()
  self:_syncLayerPreview()
end

function Dialog:_refreshAddEnabled()
  local starts = self.hexGrid and self.hexGrid:getSelectedStarts() or {}
  self.addButton.enabled = #starts > 0
end

function Dialog:_refreshLimitWarning()
  local starts = self.hexGrid and self.hexGrid:getSelectedStarts() or {}
  local adding = #starts
  local existing = countActiveSprites(self.spriteLayer)
  local msg = nil
  -- NES 64 overflow takes priority over the per-Add 8-item cap message.
  if self.isEdit ~= true and (existing + adding > Dialog.NES_SPRITE_LIMIT) then
    msg = Dialog.MSG_NES_LIMIT
  elseif self._hitMax8 == true and self.isEdit ~= true then
    msg = Dialog.MSG_MAX_PER_ADD
  end
  self._limitWarning = msg
  self:_refreshFooterLabel()
end

function Dialog:_onGridSelect(addr, opts)
  opts = opts or {}
  addr = math.floor(tonumber(addr) or 0)
  if self:isScannedMode() then
    self:_onScanGridSelect(addr)
    return
  end
  -- Grid already owns multi-select state; only replace it for programmatic/tests.
  if opts.fromGrid ~= true then
    self.hexGrid:setSelectedAddr(addr, { emit = false })
  end
  if opts.selectionCapHit == true then
    self._hitMax8 = true
  elseif #(self.hexGrid:getSelectedStarts()) < RomHexGrid.MAX_SELECTED_STARTS then
    self._hitMax8 = false
  end
  self._committedStarts = self.hexGrid:getSelectedStarts()
  self._syncingFromGrid = true
  if #(self.hexGrid:getSelectedStarts()) > 0 then
    self.oamStartField:setText(self:_formatOam(addr))
  end
  self._syncingFromGrid = false
  self:_syncPreviewFromGrid()
  self:_refreshLimitWarning()
end

function Dialog:_syncFromOamField()
  if self._syncingFromGrid then
    return
  end
  if self:isScannedMode() then
    return
  end
  local addr = select(1, Shared.parseHexAddress(self.oamStartField:getText() or ""))
  if type(addr) ~= "number" then
    return
  end
  -- Do not emit onSelect: that setTexts the field and resets the caret (breaks left/right).
  self.hexGrid:setSelectedAddr(addr, { emit = false })
  self._hitMax8 = false
  self._committedStarts = self.hexGrid:getSelectedStarts()
  self:_syncPreviewFromGrid()
  self:_refreshLimitWarning()
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Add sprite"
  self.targetWindow = opts.window
  self.spriteLayer = opts.spriteLayer
  self.isEdit = opts.isEdit == true
    or (type(opts.primaryButtonText) == "string" and opts.primaryButtonText == "Save")
    or (type(opts.title) == "string" and opts.title:find("Edit", 1, true) ~= nil)
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true
  self._hitMax8 = false
  self._limitWarning = nil
  self.romRaw = type(opts.romRaw) == "string" and opts.romRaw or ""
  self.tilesPool = opts.tilesPool
  self.appEditState = opts.appEditState
  self.scanHits = {}
  self._scanComputed = false
  self._statusText = nil
  self._committedStarts = {}
  self:_refreshFooterLabel()
  if self.scannedModeCheckbox then
    self.scannedModeCheckbox:setChecked(false, { silent = true })
  end
  if self.hexGrid then
    self.hexGrid.replaceSelect = false
    self.hexGrid:setUserSelectedStarts({})
    clearScanUnderlines(self.hexGrid)
  end

  self.addButton.text = opts.primaryButtonText or "Add"

  -- Add: multi-select up to MAX; Edit: single selection (toggle off allowed).
  self.hexGrid.maxSelectedStarts = self.isEdit and 1 or RomHexGrid.MAX_SELECTED_STARTS

  local romRaw = type(opts.romRaw) == "string" and opts.romRaw or ""
  self.hexGrid:setRomRaw(romRaw)

  local excludeOccupied = nil
  if self.isEdit and opts.appearanceSprite and type(opts.appearanceSprite.startAddr) == "number" then
    excludeOccupied = math.floor(opts.appearanceSprite.startAddr)
  end
  -- Disabled = starts already in *this* layer only (other OAM-anim layers stay selectable).
  local occupied = collectOccupiedOamStarts(opts.spriteLayer, { excludeStartAddr = excludeOccupied })
  self._occupiedStarts = occupied
  self.hexGrid:setOccupiedStarts(occupied)
  -- Minimap: all in-layer starts (including the sprite being edited) so users can find them after scrolling.
  local minimapStarts = collectOccupiedOamStarts(opts.spriteLayer)
  self._minimapOccupiedStarts = minimapStarts
  self:_refreshMinimap()

  self.preview:setContext({
    romRaw = romRaw,
    spriteLayer = opts.spriteLayer,
    tilesPool = opts.tilesPool,
    appEditState = opts.appEditState,
    -- Edit mode: keep layer flip/palette (and live tile refs when address matches).
    appearanceSprite = opts.appearanceSprite,
  })

  local groupSize = self.hexGrid:getGroupSize()
  local initialAddr
  local selectOpts = { emit = false }
  if self.isEdit then
    local initialText = opts.initialOamStart or ""
    self.oamStartField:setText(initialText)
    initialAddr = select(1, Shared.parseHexAddress(initialText))
    if type(initialAddr) ~= "number" then
      initialAddr = 0
    end
    -- Allow keeping the sprite's current OAM start selected while editing.
    selectOpts.allowOccupied = true
  else
    -- After last disabled group in this layer; 0x00 when the layer has none.
    initialAddr = defaultAddOamStart(occupied, groupSize)
    self.oamStartField:setText(self:_formatOam(initialAddr))
  end
  self.hexGrid:setSelectedAddr(initialAddr, selectOpts)
  if self.isEdit ~= true then
    self.hexGrid:scrollToReveal(initialAddr)
  end
  self._committedStarts = self.hexGrid:getSelectedStarts()
  self:_syncPreviewFromGrid()
  self._previewPrefH = self.preview:preferredHeight()
  self:_refreshLimitWarning()

  self:_focusOamField()
  self.addButton.pressed = false
  self.cancelButton.pressed = false
  self.addButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self:_clearLayerPreviews()
  self.visible = false
  self.oamStartField:setFocused(false)
  self.addButton.pressed = false
  self.cancelButton.pressed = false
  self.addButton.hovered = false
  self.cancelButton.hovered = false
  if self.scannedModeCheckbox then
    self.scannedModeCheckbox:setChecked(false, { silent = true })
  end
  self.onConfirm = nil
  self.onCancel = nil
  self.targetWindow = nil
  self.spriteLayer = nil
  self.romRaw = nil
  self.tilesPool = nil
  self.appEditState = nil
  self.isEdit = false
  self._hitMax8 = false
  self._limitWarning = nil
  self.scanHits = {}
  self._scanComputed = false
  self._statusText = nil
  self._committedStarts = {}
  self._occupiedStarts = {}
  self._minimapOccupiedStarts = {}
  self:_refreshFooterLabel()
  if self.hexGrid then
    self.hexGrid.replaceSelect = false
    self.hexGrid:setUserSelectedStarts({})
    clearScanUnderlines(self.hexGrid)
  end
  if self.hexGrid and self.hexGrid.setOccupiedStarts then
    self.hexGrid:setOccupiedStarts({})
  end
  if self.hexGrid and self.hexGrid.setMinimapMarkers then
    self.hexGrid:setMinimapMarkers({})
  end
  if self.preview then
    self.preview.appearanceSprite = nil
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
  local starts = self.hexGrid and self.hexGrid:getSelectedStarts() or {}
  if #starts == 0 then
    return false
  end
  self:_refreshLimitWarning()
  -- Block Add when the selection would push the sprite layer past the NES OAM cap.
  if self.isEdit ~= true and self._limitWarning == Dialog.MSG_NES_LIMIT then
    return false
  end
  local callback = self.onConfirm
  local targetWindow = self.targetWindow
  if callback then
    -- Drop starts whose 4-byte span overlaps an in-layer sprite.
    if self.isEdit ~= true and self.hexGrid and self.hexGrid.startOverlapsOccupied then
      local filtered = {}
      for _, addr in ipairs(starts) do
        if not self.hexGrid:startOverlapsOccupied(addr) then
          filtered[#filtered + 1] = addr
        end
      end
      starts = filtered
      if #starts == 0 then
        self._limitWarning = Dialog.MSG_ALREADY_IN_LAYER
        self:_refreshFooterLabel()
        return false
      end
    end
    -- Drop draft layer previews before the confirm path inserts real items.
    self:_clearLayerPreviews()
    local ok = callback(
      self.oamStartField:getText() or "",
      targetWindow,
      { starts = starts }
    )
    if ok == false then
      -- Restore live previews if Add/Save was rejected.
      self:_syncLayerPreview()
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
  if self:isScannedMode() then
    return false
  end
  if key == "tab" then
    self:_focusOamField()
    return true
  end
  if self.oamStartField.focused and self.oamStartField:onKeyPressed(key) then
    -- Only re-sync grid/preview when the key can change the address text.
    if key ~= "left" and key ~= "right" and key ~= "home" and key ~= "end" then
      self:_syncFromOamField()
    end
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  if self:isScannedMode() then
    return false
  end
  if self.oamStartField.focused then
    local ok = self.oamStartField:onTextInput(text)
    if ok then
      self:_syncFromOamField()
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

  if not self:isScannedMode() and self.oamStartField:contains(x, y) then
    self:_focusOamField()
  end

  return self.panel and self.panel:mousepressed(x, y, button) or true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  return self.panel and self.panel:mousereleased(x, y, button) or true
end

function Dialog:_syncPreviewHoverFromGrid()
  if not (self.preview and self.hexGrid) then
    return
  end
  self.preview:setHoveredStart(self.hexGrid:getHoveredSelectedStart())
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end
  if self.panel then
    self.panel:mousemoved(x, y)
  end
  self:_syncPreviewHoverFromGrid()
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
  return self.hexGrid:wheelmovedAt(dx, dy, mx, my)
end

function Dialog:draw(canvas)
  if not self.visible then return end
  ModalPanelUtils.refreshTargetMetrics(self)
  syncModalGridMetrics(self)
  -- Do not rebuild the Panel each frame: each rebuild creates a new Panel and drops `pressedButton`
  -- captured on mouse pressed, so mousereleased never fires Save/Cancel.
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
  self:_syncPreviewHoverFromGrid()
  self.panel:draw()
end

Dialog._hitsToUnderlinedSelection = hitsToUnderlinedSelection
Dialog._hitsToScanMinimapMarkers = hitsToScanMinimapMarkers
Dialog._applyScanUnderlines = applyScanUnderlines

return Dialog
