local Shared = require("controllers.app.core_controller_shared")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")
local BankViewController = require("controllers.chr.bank_view_controller")
local BrushController = require("controllers.input_support.brush_controller")
local RevertTilePixelsController = require("controllers.chr.revert_tile_pixels_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local PatternTableMapping = require("utils.pattern_table_mapping")
local WindowCaps = require("controllers.window.window_capabilities")
local TableUtils = require("utils.table_utils")

return function(AppCoreController)

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
      local bank = type(r) == "table" and tonumber(r.bank) or nil
      if bank and self.appEditState.chrBanksBytes[bank] then
        BankViewController.ensureBankTiles(self.appEditState, bank)
      end
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
        or (row * (win.cols or 16)) + col,
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
  winBank:setSelected(col, row, sourceBank)
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
      text = "Build/refresh pattern table reference layer",
      enabled = context and context.layer and type(context.layer.patternTable) == "table",
      callback = function()
        self:_ensurePpuPatternTableReferenceLayer(context, { keepActiveLayer = false })
      end,
    },
    {
      text = "Undo pixel edits",
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
      text = "Select in CHR/ROM window",
      callback = function()
        self:_selectPpuTileInChrWindow(context)
      end,
    }
    items[#items + 1] = {
      text = "Select all references",
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
  local patternTable = type(targetLayer.patternTable) == "table" and targetLayer.patternTable or nil
  local ranges = patternTable and patternTable.ranges
  if type(ranges) ~= "table" or #ranges == 0 then
    self:setStatus("No tile ranges to remove")
    return false
  end

  local beforeState = PpuRange.snapshotPpuFrameRangeState(targetWin, targetLayerIndex)
  local logicalIndex = math.max(0, math.floor(tonumber(context.logicalIndex) or 0))
  local cursor = 0
  local removeIndex = nil
  for i, range in ipairs(ranges) do
    local from, to = PpuRange.parsePatternRangeBounds(range)
    if from ~= nil and to ~= nil then
      local len = to - from + 1
      if logicalIndex >= cursor and logicalIndex < (cursor + len) then
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
  if targetWin.refreshNametableVisuals then
    targetWin:refreshNametableVisuals(tilesPool, targetLayerIndex)
  elseif targetWin.invalidateNametableLayerCanvas then
    targetWin:invalidateNametableLayerCanvas(targetLayerIndex)
  end
  self:_ensurePpuPatternTableReferenceLayer({
    win = targetWin,
    layerIndex = targetLayerIndex,
    layer = targetLayer,
  }, { keepActiveLayer = true })
  if targetWin.specializedToolbar and targetWin.specializedToolbar.updateIcons then
    targetWin.specializedToolbar:updateIcons()
  end

  local total = PpuRange.patternTableLogicalSize(patternTable)
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

  self:setStatus(string.format("Removed tile range #%d (%d/256 tiles)", removeIndex, tonumber(total) or 0))
  return true
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
      text = "Select in CHR/ROM window",
      enabled = context and context.tileIndex ~= nil,
      callback = function()
        self:_selectPpuTileInChrWindow(context)
      end,
    },
    {
      text = "Select all references",
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
  end
  if context and context.layer and context.layer._runtimePatternTableRefLayer == true then
    items[#items + 1] = {
      text = "Remove tile range at this tile",
      enabled = type(context.logicalIndex) == "number",
      callback = function()
        self:_removePpuPatternRangeFromRuntimeReference(context)
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
  local items = {
    {
      text = "Undo pixel edits",
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
