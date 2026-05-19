local Shared = require("controllers.app.core_controller_shared")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")
local BankViewController = require("controllers.chr.bank_view_controller")
local BrushController = require("controllers.input_support.brush_controller")
local RevertTilePixelsController = require("controllers.chr.revert_tile_pixels_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local PatternTableMapping = require("utils.pattern_table_mapping")
local WindowCaps = require("controllers.window.window_capabilities")
local ChrBankUiHelpers = require("controllers.chr.chr_bank_ui_helpers")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")

return function(AppCoreController)

local function wantsPatternTableJumpInsteadOfChr(context)
  local win = context and context.win
  if not win then return false end
  if WindowCaps.isPatternTable(win) then return false end
  return WindowCaps.isPpuFrame(win) or WindowCaps.isOamAnimation(win)
end

local function findWindowByStableId(wm, id)
  if type(id) ~= "string" or id == "" or not wm or not wm.getWindows then
    return nil
  end
  for _, w in ipairs(wm:getWindows()) do
    if w._id == id and not w._closed then
      return w
    end
  end
  return nil
end

--- Layer that owns linkedPatternTableWindowId / patternTable (not the transient PPU ref overlay).
local function consumerLayerForPatternLink(context)
  local layer = context and context.layer
  if layer and layer._runtimePatternTableRefLayer == true then
    return layer._runtimePatternTableRefTargetLayer
  end
  return layer
end

function AppCoreController:_patternLogicalSlotForJump(context)
  if not context then return nil end
  if type(context.byteVal) == "number" then
    return Shared.clampByte(context.byteVal)
  end
  if type(context.logicalIndex) == "number" then
    return Shared.clampByte(context.logicalIndex)
  end
  if context.layer and context.layer.kind == "sprite" and context.item then
    if type(context.item.tile) == "number" then
      return Shared.clampByte(context.item.tile)
    end
  end
  if context.layer and context.layer.kind == "tile" and context.win and WindowCaps.isPpuFrame(context.win) and context.item then
    if PatternTableMapping.validate(context.layer.patternTable) then
      local li = PatternTableMapping.logicalIndexForTileRef(context.layer, context.item)
      if type(li) == "number" then
        return Shared.clampByte(li)
      end
    end
  end
  return nil
end

function AppCoreController:_resolveLinkedPatternTableWindow(context)
  local consumer = consumerLayerForPatternLink(context)
  local linkedId = consumer and consumer.linkedPatternTableWindowId
  local ptWin = findWindowByStableId(self.wm, linkedId)
  if not (ptWin and WindowCaps.isPatternTable(ptWin)) then
    return nil
  end
  return ptWin
end

function AppCoreController:_patternTableJumpNavigateEnabled(context)
  if self.wm then
    PatternTableDisplayController.resolveLinkedPatternTableLayers(self.wm)
  end
  if not wantsPatternTableJumpInsteadOfChr(context) then
    return false
  end
  local layer = consumerLayerForPatternLink(context)
  if not (layer and PatternTableMapping.validate(layer.patternTable)) then
    return false
  end
  local logical = self:_patternLogicalSlotForJump(context)
  local ptWin = self:_resolveLinkedPatternTableWindow(context)
  return logical ~= nil and ptWin ~= nil
end

function AppCoreController:_nametablePatternTableNavigateEnabled(context)
  if self.wm then
    PatternTableDisplayController.resolveLinkedPatternTableLayers(self.wm)
  end
  if not (context and context.win and WindowCaps.isPpuFrame(context.win)) then
    return false
  end
  local layer = context.layer
  if not (layer and layer.kind == "tile") then return false end
  if not PatternTableMapping.validate(layer.patternTable) then return false end
  if self:_patternLogicalSlotForJump(context) == nil then return false end
  if not self:_resolveLinkedPatternTableWindow(context) then return false end
  return context.tileIndex ~= nil
end

function AppCoreController:_gridCellForPatternLogicalIndex(ptWin, ptLayerIndex, logicalIndex)
  if not (
    ptWin
    and type(logicalIndex) == "number"
    and ptLayerIndex
    and WindowCaps.isPatternTable(ptWin)
  ) then
    return nil, nil
  end
  local ptLayer = ptWin.getLayer and ptWin:getLayer(ptLayerIndex) or (ptWin.layers and ptWin.layers[ptLayerIndex])
  local cols = math.max(1, math.floor(tonumber(ptWin.cols) or 16))
  local rows = math.max(1, math.floor(tonumber(ptWin.rows) or 16))
  local layoutMode = (ptLayer and ptLayer.mode) or "8x8"
  local maxPos = math.min(255, rows * cols - 1)
  for pos = 0, maxPos do
    if BankViewController.chrOrderingIndexForGridPos(layoutMode, pos) == logicalIndex then
      local col = pos % cols
      local row = math.floor(pos / cols)
      return col, row
    end
  end
  return nil, nil
end

--- Focus pattern_table window cell matching the consuming layer's linked pattern slot (PPU nametable / OAM / ref overlay).
function AppCoreController:_selectInLinkedPatternTableWindow(context)
  if not self:_patternTableJumpNavigateEnabled(context) then
    self:setStatus("Link this layer to an open pattern table window to jump to it")
    return false
  end
  local ptWin = self:_resolveLinkedPatternTableWindow(context)
  local logical = self:_patternLogicalSlotForJump(context)
  if not ptWin or logical == nil then
    self:setStatus("Link this layer to an open pattern table window to jump to it")
    return false
  end
  local ptLayerIndex = (ptWin.getActiveLayerIndex and ptWin:getActiveLayerIndex()) or ptWin.activeLayer or 1

  PatternTableDisplayController.resolveLinkedPatternTableLayers(self.wm)
  PatternTableDisplayController.populateTileLayerItemsFromPatternTable(ptWin, ptLayerIndex, {
    tilesPool = self.appEditState and self.appEditState.tilesPool,
    appEditState = self.appEditState,
    ensureTiles = function(bankIdx)
      local st = self.appEditState
      if st and st.chrBanksBytes and st.chrBanksBytes[bankIdx] then
        BankViewController.ensureBankTiles(st, bankIdx)
      end
    end,
  })

  local col, row = self:_gridCellForPatternLogicalIndex(ptWin, ptLayerIndex, logical)
  if col == nil or row == nil then
    self:setStatus(string.format("Pattern logical slot %d is outside the linked pattern grid", logical))
    return false
  end

  if ptWin.setActiveLayerIndex then
    ptWin:setActiveLayerIndex(ptLayerIndex)
  else
    ptWin.activeLayer = ptLayerIndex
  end

  Shared.scrollChrWindowToCell(ptWin, col, row)
  local ptLayerResolved = ptWin.getLayer and ptWin:getLayer(ptLayerIndex)
    or (ptWin.layers and ptWin.layers[ptLayerIndex])
  local lm = ptLayerResolved and ptLayerResolved.mode or "8x8"
  local selOpts = (lm == "8x16" or lm == "oddEven") and { exactChrTile = true } or nil
  ptWin:setSelected(col, row, ptLayerIndex, selOpts)
  if self.wm and self.wm.setFocus then
    self.wm:setFocus(ptWin)
  end
  self:setStatus(string.format("Pattern table logical slot %d", logical))
  return true
end

function AppCoreController:_buildPpuTileContext(win, layerIndex, col, row)
  if not (win and win.kind == "ppu_frame" and type(col) == "number" and type(row) == "number") then
    return nil
  end

  local layer = win.getLayer and win:getLayer(layerIndex) or (win.layers and win.layers[layerIndex])
  if not (layer and layer.kind == "tile") then
    return nil
  end

  local idx = Shared.ppuTileLinearIndex(win, col, row)
  local byteVal = win.nametableBytes and win.nametableBytes[idx] or nil
  local item = win.get and win:get(col, row, layerIndex) or nil

  local sourceBank = tonumber(item._bankIndex)
  if not sourceBank and type(byteVal) == "number" and type(layer.patternTable) == "table" then
    local map = PatternTableMapping.buildMap(layer.patternTable)
    local entry = map and map[Shared.clampByte(byteVal)] or nil
    sourceBank = entry and tonumber(entry.bank) or nil
  end
  sourceBank = sourceBank or 1

  return {
    win = win,
    layerIndex = layerIndex,
    layer = layer,
    col = col,
    row = row,
    item = item,
    byteVal = (type(byteVal) == "number") and Shared.clampByte(byteVal) or nil,
    tileIndex = Shared.normalizeTileIndex(item),
    sourceBank = sourceBank,
  }
end

function AppCoreController:_ensurePpuPatternTableReferenceLayer(context, opts)
  opts = opts or {}
  if not (context and context.win and context.layer) then
    return false
  end
  local win = context.win
  if win.patternLayerSoloMode ~= true and opts.allowReferenceLayer ~= true then
    if win.removePatternReferenceLayers then
      win:removePatternReferenceLayers(context.layerIndex)
    end
    return true
  end
  local layer = context.layer
  if type(layer.patternTable) ~= "table" then
    self:setStatus("This layer has no patternTable")
    return false
  end
  local map, mapErr = PpuRange.buildPatternTableMapAllowPartial(layer.patternTable)
  if not map then
    self:setStatus(tostring(mapErr or "Invalid patternTable mapping"))
    return false
  end

  local refLayer = nil
  local refLayerIndex = nil
  for i, L in ipairs(context.win.layers or {}) do
    if L
      and L._runtimePatternTableRefLayer == true
      and tonumber(L._runtimePatternTableRefTargetLayerIndex) == tonumber(context.layerIndex)
    then
      refLayer = L
      refLayerIndex = i
      break
    end
  end

  if not refLayer then
    if not (context.win and context.win.addLayer) then
      self:setStatus("Could not create pattern table reference layer")
      return false
    end
    refLayerIndex = context.win:addLayer({
      name = string.format("Pattern Table L%d", tonumber(context.layerIndex) or 1),
      kind = "tile",
      opacity = 1.0,
      items = {},
    })
    refLayer = context.win.layers and context.win.layers[refLayerIndex] or nil
    if not refLayer then
      self:setStatus("Could not create pattern table reference layer")
      return false
    end
  end

  refLayer._runtimeOnly = true
  refLayer._runtimePatternTableRefLayer = true
  refLayer._runtimePatternTableRefTargetLayerIndex = tonumber(context.layerIndex) or 1
  refLayer._runtimePatternTableRefTargetLayer = context.layer
  refLayer._runtimePatternTableRefTargetWin = context.win
  refLayer.items = {}
  refLayer._runtimePatternTableLogicalByCell = {}

  local tilesPool = self.appEditState and self.appEditState.tilesPool or nil
  if not tilesPool then
    self:setStatus("No tilesPool available for pattern table reference")
    return false
  end
  if self.appEditState and self.appEditState.chrBanksBytes and type(layer.patternTable.ranges) == "table" then
    for _, r in ipairs(layer.patternTable.ranges) do
      PpuRange.foreachBankInPatternRange(r, function(bank)
        bank = tonumber(bank)
        if bank and self.appEditState.chrBanksBytes[bank] then
          BankViewController.ensureBankTiles(self.appEditState, bank)
        end
      end)
    end
    tilesPool = self.appEditState.tilesPool or tilesPool
  end
  for logicalIndex = 0, 255 do
    local entry = map[logicalIndex]
    if entry then
      local bankTiles = tilesPool[entry.bank]
      local tileRef = bankTiles and bankTiles[entry.tileIndex] or nil
      local col = logicalIndex % 16
      local row = math.floor(logicalIndex / 16)
      local idx = (row * (context.win.cols or 32)) + col + 1
      refLayer.items[idx] = tileRef
      refLayer._runtimePatternTableLogicalByCell[idx] = logicalIndex
    end
  end

  if opts.keepActiveLayer ~= true then
    if context.win.setActiveLayerIndex then
      context.win:setActiveLayerIndex(refLayerIndex)
    else
      context.win.activeLayer = refLayerIndex
    end
  end
  if context.win.invalidateNametableLayerCanvas then
    context.win:invalidateNametableLayerCanvas(refLayerIndex)
  end
  local size = PpuRange.patternTableLogicalSize(layer.patternTable)
  self:setStatus(string.format("Prepared pattern table reference layer (%d/256 tiles)", tonumber(size) or 0))
  return true
end

function AppCoreController:_buildSelectInChrContext(win, layerIndex, col, row, itemIndex)
  if not (win and type(layerIndex) == "number") then
    return nil
  end

  local layer = win.getLayer and win:getLayer(layerIndex) or (win.layers and win.layers[layerIndex])
  if not layer then
    return nil
  end

  if layer.kind == "tile" then
    if not (type(col) == "number" and type(row) == "number") then
      return nil
    end

    local item = nil
    if win.getVirtualTileHandle then
      item = win:getVirtualTileHandle(col, row, layerIndex)
    end
    if not item and win.get then
      item = win:get(col, row, layerIndex)
    end
    if not item then
      return nil
    end

    local sourceBank = tonumber(item._bankIndex)
    if not sourceBank and win.kind == "ppu_frame" and win.nametableBytes then
      local idx = Shared.ppuTileLinearIndex(win, col, row)
      local byteVal = win.nametableBytes[idx]
      if type(byteVal) == "number" and type(layer.patternTable) == "table" then
        local map = PatternTableMapping.buildMap(layer.patternTable)
        local entry = map and map[Shared.clampByte(byteVal)] or nil
        sourceBank = entry and tonumber(entry.bank) or nil
      end
    end
    sourceBank = sourceBank or 1

    return {
      win = win,
      layerIndex = layerIndex,
      layer = layer,
      col = col,
      row = row,
      item = item,
      tileIndex = Shared.normalizeTileIndex(item),
      sourceBank = sourceBank,
      logicalIndex = (layer._runtimePatternTableRefLayer == true
        and layer._runtimePatternTableLogicalByCell
        and layer._runtimePatternTableLogicalByCell[((row * (win.cols or 32)) + col + 1)])
        or (WindowCaps.isPatternTable(win)
          and BankViewController.chrOrderingIndexForGridPos(layer.mode or "8x8", (row * (win.cols or 16)) + col))
        or ((row * (win.cols or 16)) + col),
    }
  end

  if layer.kind == "sprite" then
    if type(itemIndex) ~= "number" then
      return nil
    end
    local item = layer.items and layer.items[itemIndex] or nil
    if not item or item.removed == true then
      return nil
    end

    return {
      win = win,
      layerIndex = layerIndex,
      layer = layer,
      itemIndex = itemIndex,
      item = item,
      tileIndex = Shared.normalizeTileIndex(item),
      sourceBank = tonumber(item.bank)
        or tonumber(layer.bank)
        or tonumber(item.topRef and item.topRef._bankIndex)
        or 1,
    }
  end

  return nil
end

function AppCoreController:_selectPpuTileInChrWindow(context)
  if not context then
    return false
  end

  if type(context.tileIndex) ~= "number" then
    self:setStatus("This item has no CHR source selection to jump to")
    return false
  end

  local winBank = self.winBank
  if not (winBank and winBank.kind == "chr") then
    self:setStatus("No CHR/ROM bank window is available")
    return false
  end

  local sourceBank = tonumber(context.sourceBank) or 1
  if self.appEditState then
    self.appEditState.currentBank = sourceBank
  end

  if not (winBank.layers and winBank.layers[sourceBank]) and self.rebuildBankWindowItems then
    self:rebuildBankWindowItems()
  end

  if winBank.setCurrentBank then
    winBank:setCurrentBank(sourceBank)
  end

  local col, row = Shared.findChrWindowCellForTile(winBank, sourceBank, context.tileIndex)
  if (col == nil or row == nil) and self.rebuildBankWindowItems then
    self:rebuildBankWindowItems()
    if winBank.setCurrentBank then
      winBank:setCurrentBank(sourceBank)
    end
    col, row = Shared.findChrWindowCellForTile(winBank, sourceBank, context.tileIndex)
  end

  if col == nil or row == nil then
    self:setStatus(string.format("Tile %d was not found in CHR bank %d", context.tileIndex, sourceBank))
    return false
  end

  Shared.scrollChrWindowToCell(winBank, col, row)
  winBank:setSelected(col, row, sourceBank, { exactChrTile = true })
  if self.wm and self.wm.setFocus then
    self.wm:setFocus(winBank)
  end

  self:setStatus(string.format("Selected CHR tile %d in bank %d", context.tileIndex, sourceBank))
  return true
end

function AppCoreController:_selectAllReferencesFromContext(context)
  if not context then
    return false
  end
  self:hideAppContextMenus()
  local MultiSelectController = require("controllers.input_support.multi_select_controller")
  local ok, count = MultiSelectController.selectAllChrReferences(
    context.win,
    context.layerIndex,
    tonumber(context.sourceBank) or 1,
    context.tileIndex
  )
  if not ok then
    self:setStatus("Could not select references")
    return false
  end
  if count == 0 then
    self:setStatus("No matching references")
  elseif count == 1 then
    self:setStatus("Selected 1 reference")
  else
    self:setStatus(string.format("Selected %d references", count))
  end
  return true
end

function AppCoreController:_buildPpuTileContextMenuItems(context)
  local items = {
    {
      text = "Undo pixel edits",
      menuGroup = "ppt_edit_history",
      enabled = RevertTilePixelsController.canRevertContext(self, context),
      callback = function()
        local ok, err = RevertTilePixelsController.revertForContext(self, context)
        if ok then
          self:setStatus("Reverted tile pixels to original CHR")
        else
          self:setStatus(tostring(err or "Could not revert tile pixels"))
        end
      end,
    },
  }
  if context and context.tileIndex ~= nil then
    items[#items + 1] = {
      text = "Select in pattern table window",
      menuGroup = "ppt_selection",
      enabled = self:_nametablePatternTableNavigateEnabled(context),
      callback = function()
        self:_selectInLinkedPatternTableWindow(context)
      end,
    }
    items[#items + 1] = {
      text = "Select all references",
      menuGroup = "ppt_selection",
      enabled = true,
      callback = function()
        self:_selectAllReferencesFromContext(context)
      end,
    }
  end
  if context and context.win and context.layerIndex then
    self:_appendJumpToLinkedPaletteMenuItem(items, context.win, context.layerIndex)
    self:_appendRemoveRomPaletteLinkMenuItem(items, context.win, context.layerIndex)
  end
  self:_appendPasteContextMenuItem(items, context)
  return items
end

--- Remove one pattern-table tile range containing the given row-major logical index (0–255).
--- Works for PPU nametable layers and standalone pattern_table windows.
function AppCoreController:_removeTileRangeFromPatternTableLayer(targetWin, targetLayer, targetLayerIndex, logicalIndex)
  if not (targetWin and targetLayer and type(targetLayerIndex) == "number" and type(logicalIndex) == "number") then
    return false
  end
  local patternTable = type(targetLayer.patternTable) == "table" and targetLayer.patternTable or nil
  local ranges = patternTable and patternTable.ranges
  if type(ranges) ~= "table" or #ranges == 0 then
    self:setStatus("No tile ranges to remove")
    return false
  end

  local recordUndo = WindowCaps.isPpuFrame(targetWin)
  local beforeState = recordUndo and PpuRange.snapshotPpuFrameRangeState(targetWin, targetLayerIndex) or nil

  local idx = math.max(0, math.floor(logicalIndex))
  local cursor = 0
  local removeIndex = nil
  for i, range in ipairs(ranges) do
    local len, cerr = PpuRange.patternRangeLogicalLength(range)
    if cerr == nil and type(len) == "number" then
      if idx >= cursor and idx < (cursor + len) then
        removeIndex = i
        break
      end
      cursor = cursor + len
    end
  end
  if not removeIndex then
    self:setStatus("Could not resolve a range at that logical tile")
    return false
  end

  table.remove(ranges, removeIndex)
  targetLayer.patternTable = patternTable

  local tilesPool = self.appEditState and self.appEditState.tilesPool or nil

  if WindowCaps.isPpuFrame(targetWin) then
    if targetWin.refreshNametableVisuals then
      targetWin:refreshNametableVisuals(tilesPool, targetLayerIndex)
    elseif targetWin.invalidateNametableLayerCanvas then
      targetWin:invalidateNametableLayerCanvas(targetLayerIndex)
    end
    if targetWin.patternLayerSoloMode == true then
      self:_ensurePpuPatternTableReferenceLayer({
        win = targetWin,
        layerIndex = targetLayerIndex,
        layer = targetLayer,
      }, { keepActiveLayer = true, allowReferenceLayer = true })
    elseif targetWin.removePatternReferenceLayers then
      targetWin:removePatternReferenceLayers(targetLayerIndex)
    end
  elseif WindowCaps.isPatternTable(targetWin) then
    PatternTableDisplayController.populateTileLayerItemsFromPatternTable(targetWin, targetLayerIndex, {
      tilesPool = tilesPool,
      ensureTiles = function(bankIdx)
        local st = self.appEditState
        if st and st.chrBanksBytes and st.chrBanksBytes[bankIdx] then
          BankViewController.ensureBankTiles(st, bankIdx)
        end
      end,
      appEditState = self.appEditState,
    })
    PatternTableDisplayController.invalidateConsumersUsingPatternTable(self, patternTable)
    if targetWin.invalidateTileLayerCanvas then
      targetWin:invalidateTileLayerCanvas(targetLayerIndex)
    end
  end

  if targetWin.specializedToolbar and targetWin.specializedToolbar.updateIcons then
    targetWin.specializedToolbar:updateIcons()
  end

  local total = PpuRange.patternTableLogicalSize(patternTable)
  if recordUndo and beforeState then
    local afterState = PpuRange.snapshotPpuFrameRangeState(targetWin, targetLayerIndex)
    if self.undoRedo and self.undoRedo.addPpuFrameRangeEvent
      and PpuRange.didPpuFrameRangeSettingsChange(beforeState, afterState)
    then
      self.undoRedo:addPpuFrameRangeEvent({
        type = "ppu_frame_range",
        win = targetWin,
        layerIndex = targetLayerIndex,
        beforeState = beforeState,
        afterState = afterState,
      })
    end
  end

  self:setStatus(string.format("Removed tile range #%d (%d/256 tiles)", removeIndex, tonumber(total) or 0))
  return true
end

function AppCoreController:_removePpuPatternRangeFromRuntimeReference(context)
  if not (context and context.layer and context.layer._runtimePatternTableRefLayer == true and type(context.logicalIndex) == "number") then
    return false
  end
  local targetWin = context.layer._runtimePatternTableRefTargetWin
  local targetLayerIndex = context.layer._runtimePatternTableRefTargetLayerIndex
  local targetLayer = context.layer._runtimePatternTableRefTargetLayer
  if not (targetWin and targetLayerIndex and targetLayer) then
    self:setStatus("Missing target PPU layer for runtime pattern table reference")
    return false
  end
  if targetWin.getLayer then
    targetLayer = targetWin:getLayer(targetLayerIndex) or targetLayer
  end
  if not targetLayer then
    self:setStatus("Target PPU tile layer is no longer available")
    return false
  end

  return self:_removeTileRangeFromPatternTableLayer(targetWin, targetLayer, targetLayerIndex, context.logicalIndex)
end

function AppCoreController:_buildSelectInChrContextMenuItems(context)
  local canSelectAllRefs = false
  if context and context.win and context.layer then
    local win = context.win
    local layer = context.layer
    canSelectAllRefs = (layer.kind == "tile" or layer.kind == "sprite")
      and not WindowCaps.isPpuFrame(win)
      and not WindowCaps.isChrLike(win)
      and type(context.tileIndex) == "number"
  end

  local items = {
    {
      text = "Undo pixel edits",
      menuGroup = "sel_chr_undo",
      enabled = RevertTilePixelsController.canRevertContext(self, context),
      callback = function()
        local ok, err = RevertTilePixelsController.revertForContext(self, context)
        if ok then
          self:setStatus("Reverted tile pixels to original CHR")
        else
          self:setStatus(tostring(err or "Could not revert tile pixels"))
        end
      end,
    },
    (wantsPatternTableJumpInsteadOfChr(context) and {
      text = "Select in pattern table window",
      menuGroup = "sel_chr_navigate",
      enabled = self:_patternTableJumpNavigateEnabled(context),
      callback = function()
        self:_selectInLinkedPatternTableWindow(context)
      end,
    } or {
      text = "Select in CHR/ROM window",
      menuGroup = "sel_chr_navigate",
      enabled = context and context.tileIndex ~= nil,
      callback = function()
        self:_selectPpuTileInChrWindow(context)
      end,
    }),
    {
      text = "Select all references",
      menuGroup = "sel_chr_navigate",
      enabled = canSelectAllRefs,
      callback = function()
        self:_selectAllReferencesFromContext(context)
      end,
    },
  }
  if context and context.layer and context.layer.kind == "sprite"
      and context.win
      and (context.win.kind == "oam_animation" or context.win.kind == "ppu_frame")
      and type(context.itemIndex) == "number" then
    table.insert(items, 1, {
      text = "Edit sprite",
      menuGroup = "sel_chr_sprite_edit",
      enabled = true,
      callback = function()
        return self:showPpuFrameAddSpriteModal(context.win, {
          editSprite = {
            layerIndex = context.layerIndex,
            itemIndex = context.itemIndex,
          },
        })
      end,
    })
    table.insert(items, 2, {
      text = "Reset position",
      menuGroup = "sel_chr_sprite_reset",
      enabled = self:_oamSpriteSelectionNeedsPositionReset(context.win, context.layerIndex),
      callback = function()
        local n = self:_resetOamLinkedSpritePositions(context.win, context.layerIndex)
        if n <= 0 then
          self:setStatus("Sprites already at ROM positions")
        else
          self:setStatus((n == 1) and "Reset sprite position" or string.format("Reset %d sprite positions", n))
        end
      end,
    })
  end
  if context and context.layer and context.layer._runtimePatternTableRefLayer == true then
    items[#items + 1] = {
      text = "Remove tile range at this tile",
      menuGroup = "sel_chr_pattern_ref",
      enabled = type(context.logicalIndex) == "number",
      callback = function()
        self:_removePpuPatternRangeFromRuntimeReference(context)
      end,
    }
  elseif context and context.layer and context.layer.kind == "tile"
      and context.win and WindowCaps.isPatternTable(context.win)
      and type(context.logicalIndex) == "number"
      and type(context.layer.patternTable) == "table"
      and type(context.layer.patternTable.ranges) == "table"
      and #context.layer.patternTable.ranges > 0
  then
    items[#items + 1] = {
      text = "Remove tile range at this tile",
      menuGroup = "sel_chr_pattern_table",
      enabled = true,
      callback = function()
        local win = context.win
        local li = tonumber(context.layerIndex) or 1
        local layer = win.getLayer and win:getLayer(li) or (win.layers and win.layers[li])
        self:_removeTileRangeFromPatternTableLayer(win, layer, li, context.logicalIndex)
      end,
    }
  end
  if context and context.win and context.layerIndex then
    self:_appendJumpToLinkedPaletteMenuItem(items, context.win, context.layerIndex)
    self:_appendRemoveRomPaletteLinkMenuItem(items, context.win, context.layerIndex)
  end
  if context and context.layer and context.layer.kind == "sprite"
      and context.win
      and (context.win.kind == "oam_animation" or context.win.kind == "ppu_frame")
      and type(context.itemIndex) == "number" then
    items[#items + 1] = {
      text = "Remove sprite",
      menuGroup = "sel_chr_sprite_remove",
      enabled = true,
      callback = function()
        local MultiSelectController = require("controllers.input_support.multi_select_controller")
        local result = MultiSelectController.deleteSpriteSelection(
          context.win,
          context.layerIndex,
          self.undoRedo,
          { indices = { context.itemIndex } }
        )
        if result and result.status then
          self:setStatus(result.status)
        elseif not result then
          self:setStatus("Could not remove sprite")
        end
      end,
    }
  end
  self:_appendPasteContextMenuItem(items, context)
  return items
end

function AppCoreController:_buildChrBankTileContext(win, col, row)
  if not (win and type(col) == "number" and type(row) == "number") then
    return nil
  end

  local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  local layer = win.getLayer and win:getLayer(li) or (win.layers and win.layers[li])
  if not (layer and layer.kind == "tile") then
    return nil
  end

  local item = win.get and win:get(col, row, li) or nil
  if not item then
    return nil
  end

  local bankIdx = tonumber(item._bankIndex) or tonumber(layer.bank) or tonumber(win.currentBank) or tonumber(li) or 1
  local logicalIndex = (row * (win.cols or 16)) + col

  return {
    win = win,
    layerIndex = li,
    layer = layer,
    col = col,
    row = row,
    item = item,
    sourceBank = bankIdx,
    tileIndex = Shared.normalizeTileIndex(item),
    logicalIndex = logicalIndex,
  }
end

function AppCoreController:_buildChrBankTileContextMenuItems(context)
  local bankIdx = tonumber(context and context.sourceBank) or 1
  local ti = context and context.tileIndex
  local copyHexEnabled =
    type(ti) == "number"
    and self.appEditState
    and self.appEditState.chrBanksBytes
    and self.appEditState.chrBanksBytes[bankIdx]
  local items = {
    {
      text = "Undo pixel edits",
      menuGroup = "chr_bank_undo",
      enabled = RevertTilePixelsController.canRevertContext(self, context),
      callback = function()
        local ok, err = RevertTilePixelsController.revertForContext(self, context)
        if ok then
          self:setStatus("Reverted tile pixels to original CHR")
        else
          self:setStatus(tostring(err or "Could not revert tile pixels"))
        end
      end,
    },
    {
      text = "Copy tile bytes (hex)",
      menuGroup = "chr_bank_copy",
      enabled = not not copyHexEnabled,
      callback = function()
        local ok, msg = ChrBankUiHelpers.copyChrTileHexToClipboard(self, bankIdx, ti)
        if msg then
          self:setStatus(msg)
        end
        if not ok and not msg then
          self:setStatus("Could not copy tile hex")
        end
      end,
    },
  }
  if context and context.win and context.layerIndex then
    self:_appendJumpToLinkedPaletteMenuItem(items, context.win, context.layerIndex)
    self:_appendRemoveRomPaletteLinkMenuItem(items, context.win, context.layerIndex)
  end
  self:_appendPasteContextMenuItem(items, context)
  return items
end

function AppCoreController:showPpuTileContextMenu(win, layerIndex, col, row, x, y)
  if not (self.ppuTileContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = self:_buildPpuTileContext(win, layerIndex, col, row)
  if not context then
    return false
  end

  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, self:_buildPpuTileContextMenuItems(context))
  return self.ppuTileContextMenu:isVisible()
end

function AppCoreController:showSelectInChrContextMenu(win, layerIndex, col, row, itemIndex, x, y)
  if not (self.ppuTileContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = self:_buildSelectInChrContext(win, layerIndex, col, row, itemIndex)
  if not context then
    return false
  end

  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, self:_buildSelectInChrContextMenuItems(context))
  return self.ppuTileContextMenu:isVisible()
end

function AppCoreController:showChrBankTileContextMenu(win, col, row, x, y)
  if not (self.ppuTileContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = self:_buildChrBankTileContext(win, col, row)
  if not context then
    return false
  end

  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, self:_buildChrBankTileContextMenuItems(context))
  return self.ppuTileContextMenu:isVisible()
end

function AppCoreController:_buildRomPaletteCellContextMenuItems(context)
  local win = context and context.win
  local col = context and context.col
  local row = context and context.row
  local selfRef = self
  if not (win and type(col) == "number" and type(row) == "number") then
    return {}
  end

  local editable = win.isCellEditable and win:isCellEditable(col, row)

  return {
    {
      text = "Clear value",
      menuGroup = "rom_palette_cell_edit",
      enabled = editable == true,
      callback = function()
        selfRef:hideAppContextMenus()
        if not editable then
          return
        end
        local beforeState = Shared.captureRomPaletteAddressUndoState(win)
        if not (win.clearRomCellBinding and win:clearRomCellBinding(col, row)) then
          selfRef:setStatus("ROM palette cell cannot be cleared")
          return
        end
        if selfRef.invalidatePpuFrameLayersAffectedByPaletteWin then
          selfRef:invalidatePpuFrameLayersAffectedByPaletteWin(win)
        end
        if selfRef.undoRedo and selfRef.undoRedo.addRomPaletteAddressEvent then
          selfRef.undoRedo:addRomPaletteAddressEvent({
            type = "rom_palette_address",
            win = win,
            beforeState = beforeState,
            afterState = Shared.captureRomPaletteAddressUndoState(win),
          })
        end
        selfRef:setStatus(string.format("Cleared ROM palette cell (%d,%d)", col, row))
      end,
    },
    {
      text = "Change ROM address",
      menuGroup = "rom_palette_cell_metadata",
      enabled = true,
      callback = function()
        selfRef:hideAppContextMenus()
        if selfRef.showRomPaletteAddressModal then
          selfRef:showRomPaletteAddressModal(win, col, row)
        end
      end,
    },
  }
end

function AppCoreController:showRomPaletteCellContextMenu(win, col, row, x, y)
  if not (self.ppuTileContextMenu and win and type(col) == "number" and type(row) == "number" and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = { win = win, col = col, row = row }
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, self:_buildRomPaletteCellContextMenuItems(context))
  return self.ppuTileContextMenu:isVisible()
end

end
