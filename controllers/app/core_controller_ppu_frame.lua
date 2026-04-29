local Shared = require("controllers.app.core_controller_shared")
local BankViewController = require("controllers.chr.bank_view_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local SpriteStateSnapshot = require("controllers.sprite.sprite_state_snapshot")
local TableUtils = require("utils.table_utils")
local WindowCaps = require("controllers.window.window_capabilities")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")

return function(AppCoreController)

local function isNametableLayerRenderReady(layer)
  if type(layer) ~= "table" then
    return false, "Missing nametable layer"
  end
  if type(layer.nametableStartAddr) ~= "number" then
    return false, "nametableStartAddr is not set"
  end
  if type(layer.nametableEndAddr) ~= "number" then
    return false, "nametableEndAddr is not set"
  end
  local total, err = PpuRange.patternTableLogicalSize(layer.patternTable)
  if err then
    return false, err
  end
  if total ~= 256 then
    return false, string.format("patternTable ranges must add up to 256 tiles (got %d)", total)
  end
  return true, nil
end

local function hydrateNametableLayerIfReady(app, win, layer, layerIndex)
  local ready, reason = isNametableLayerRenderReady(layer)
  if not ready then
    if layer then
      layer.items = {}
    end
    if win and win.invalidateNametableLayerCanvas then
      win:invalidateNametableLayerCanvas(layerIndex)
    end
    return false, reason
  end

  local state = app and app.appEditState or {}
  local romRaw = state.romRaw
  if type(romRaw) ~= "string" or romRaw == "" then
    return false, "Open a ROM before loading a PPU frame range"
  end

  if type(layer.userDefinedAttrs) ~= "string"
    and type(win.nametableAttrBytes) == "table"
    and #win.nametableAttrBytes >= 64
  then
    local hexParts = {}
    for i = 1, 64 do
      local byteVal = tonumber(win.nametableAttrBytes[i]) or 0x00
      if byteVal < 0 then byteVal = 0x00 elseif byteVal > 255 then byteVal = 255 end
      hexParts[i] = string.format("%02x", byteVal)
    end
    layer.userDefinedAttrs = table.concat(hexParts, "")
  end

  local tilesPool = state.tilesPool
  local ok, err = NametableTilesController.hydrateWindowNametable(win, layer, {
    romRaw = romRaw,
    tilesPool = tilesPool,
    ensureTiles = function(bank)
      if not (state.chrBanksBytes and state.chrBanksBytes[bank]) then
        return false
      end
      BankViewController.ensureBankTiles(state, bank)
      return true
    end,
    nametableStartAddr = layer.nametableStartAddr,
    nametableEndAddr = layer.nametableEndAddr,
    patternTable = layer.patternTable,
    tileSwaps = layer.tileSwaps,
    userDefinedAttrs = layer.userDefinedAttrs,
    codec = layer.codec,
    reportErrors = false,
  })
  if not ok then
    return false, err or "Failed to load PPU frame range"
  end
  return true, nil
end

local getPpuPatternTableTargetLayer = function(win)
  if not (win and win.kind == "ppu_frame" and win.layers) then
    return nil, nil
  end
  local fallbackLayer, fallbackIndex = nil, nil
  for i, layer in ipairs(win.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      if not fallbackLayer then
        fallbackLayer, fallbackIndex = layer, i
      end
      if type(layer.nametableStartAddr) == "number" and type(layer.nametableEndAddr) == "number" then
        return layer, i
      end
    end
  end
  return fallbackLayer, fallbackIndex
end

-- Exposed for unit tests (implementation in ppu_frame_range_helpers.lua).
AppCoreController.didPpuFrameRangeSettingsChange = PpuRange.didPpuFrameRangeSettingsChange

local function copyNumberArray(values)
  local out = {}
  if type(values) ~= "table" then
    return out
  end
  for i = 1, #values do
    out[i] = values[i]
  end
  return out
end

local function numberArrayDiffers(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a ~= b
  end
  if #a ~= #b then
    return true
  end
  for i = 1, #a do
    if (a[i] or 0) ~= (b[i] or 0) then
      return true
    end
  end
  return false
end

local function didPpuFrameNametableSnapshotDiffer(beforeState, afterState)
  if not beforeState or not afterState then
    return false
  end
  return numberArrayDiffers(beforeState.nametableBytes, afterState.nametableBytes)
    or numberArrayDiffers(beforeState.nametableAttrBytes, afterState.nametableAttrBytes)
end

function AppCoreController:snapshotPpuFrameUndoState(win, layerIndex)
  return PpuRange.snapshotPpuFrameRangeState(win, layerIndex)
end

function AppCoreController:pushPpuFrameNametableUndoIfChanged(win, layerIndex, beforeState, afterState)
  if not (self.undoRedo and self.undoRedo.addPpuFrameRangeEvent) then
    return
  end
  if not (win and win.kind == "ppu_frame" and beforeState and afterState) then
    return
  end
  if not didPpuFrameNametableSnapshotDiffer(beforeState, afterState) then
    return
  end
  self.undoRedo:addPpuFrameRangeEvent({
    type = "ppu_frame_range",
    win = win,
    layerIndex = layerIndex,
    beforeState = beforeState,
    afterState = afterState,
  })
end

local function getFirstPpuSpriteLayer(win)
  if not (win and win.getSpriteLayers) then return nil, nil end
  local spriteLayers = win:getSpriteLayers() or {}
  local first = spriteLayers[1]
  if not first then
    return nil, nil
  end
  return first.layer, first.index
end

local function getTargetSpriteLayerForAddSprite(win)
  if not win then
    return nil, nil
  end

  if win.kind == "ppu_frame" then
    return getFirstPpuSpriteLayer(win)
  end

  if win.kind == "oam_animation" then
    local activeIndex = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
    local activeLayer = win.layers and win.layers[activeIndex] or nil
    if activeLayer and activeLayer.kind == "sprite" then
      return activeLayer, activeIndex
    end

    if win.layers then
      for i, layer in ipairs(win.layers) do
        if layer and layer.kind == "sprite" then
          return layer, i
        end
      end
    end
  end

  return nil, nil
end

local function getInitialPpuSpriteModalValues(app)
  local state = app and app.appEditState or {}
  local bankWindow = app and app.winBank or nil
  local bankNumber = (bankWindow and bankWindow.currentBank) or state.currentBank or 1
  local tileNumber = 0

  if bankWindow and bankWindow.getSelected and bankWindow.get then
    local col, row, layerIndex = bankWindow:getSelected()
    if type(col) == "number" and type(row) == "number" then
      local selectedTile = bankWindow:get(col, row, layerIndex)
      if selectedTile and type(selectedTile.index) == "number" then
        tileNumber = math.max(0, math.floor(selectedTile.index))
      end
    end
  end

  return tostring(bankNumber), tostring(tileNumber), ""
end

-- After changing `item.tile` (or bank), drop explicit bottom index so 8x16 hydration
-- recomputes the NES pair (even top + top+1) instead of keeping a stale tileBelow.
local function reset8x16SpriteTilePairAfterChrEdit(layer, item)
  if layer and layer.kind == "sprite" and layer.mode == "8x16" and item then
    item.tileBelow = nil
  end
end

local function hydrateUniqueSpriteLayers(layersSet, romRaw, tilesPool, appEditState)
  for layer in pairs(layersSet) do
    if layer and layer.kind == "sprite" then
      SpriteController.hydrateSpriteLayer(layer, {
        romRaw = romRaw,
        tilesPool = tilesPool,
        appEditState = appEditState,
        keepWorld = true,
      })
    end
  end
end

local function collectSpritesSharingOamStartAddr(app, oldStartAddr)
  local entries = {}
  if type(oldStartAddr) ~= "number" then
    return entries
  end
  local wm = app and app.wm
  if not (wm and wm.getWindows) then
    return entries
  end
  for _, w in ipairs(wm:getWindows() or {}) do
    if WindowCaps.isStartAddrSpriteSyncWindow(w) and not w._closed then
      for li, layer in ipairs(w.layers or {}) do
        if layer and layer.kind == "sprite" then
          for _, it in ipairs(layer.items or {}) do
            if it and it.removed ~= true
                and type(it.startAddr) == "number"
                and it.startAddr == oldStartAddr then
              entries[#entries + 1] = {
                win = w,
                layerIndex = li,
                layer = layer,
                sprite = it,
              }
            end
          end
        end
      end
    end
  end
  return entries
end

-- Updates every non-removed sprite item sharing oldStartAddr (PPU frame + OAM windows).
local function patchSharedOamSpriteBinding(app, oldStartAddr, bankNumber, tileNumber, oamStart)
  local layersToHydrate = {}
  for _, e in ipairs(collectSpritesSharingOamStartAddr(app, oldStartAddr)) do
    e.sprite.bank = bankNumber
    e.sprite.tile = tileNumber
    e.sprite.startAddr = oamStart
    reset8x16SpriteTilePairAfterChrEdit(e.layer, e.sprite)
    layersToHydrate[e.layer] = true
  end
  return layersToHydrate
end

function AppCoreController:showPpuFrameSpriteLayerModeModal(win, opts)
  if not (self.ppuFrameSpriteLayerModeModal and win and win.kind == "ppu_frame") then
    return false
  end

  opts = opts or {}
  self.ppuFrameSpriteLayerModeModal:show({
    title = opts.title or "Create sprite layer",
    window = win,
    initialMode = opts.initialMode or "8x8",
    onConfirm = opts.onConfirm,
    onCancel = opts.onCancel,
  })
  return true
end

function AppCoreController:showPpuFrameAddSpriteModal(win, modalOpts)
  if not (self.ppuFrameAddSpriteModal and win and (win.kind == "ppu_frame" or win.kind == "oam_animation")) then
    return false
  end

  modalOpts = modalOpts or {}
  local editSprite = modalOpts.editSprite
  local editLayerIndex, editItemIndex = nil, nil
  local isEdit = false
  if (win.kind == "oam_animation" or win.kind == "ppu_frame")
      and editSprite
      and type(editSprite.layerIndex) == "number"
      and type(editSprite.itemIndex) == "number" then
    editLayerIndex = editSprite.layerIndex
    editItemIndex = editSprite.itemIndex
    isEdit = true
  end

  local initialBank, initialTile, initialOamStart
  if isEdit then
    local editLayer = win.layers and win.layers[editLayerIndex] or nil
    local editItem = editLayer and editLayer.items and editLayer.items[editItemIndex] or nil
    if not (editLayer and editLayer.kind == "sprite" and editItem and editItem.removed ~= true) then
      return false
    end
    initialBank = tostring(tonumber(editItem.bank) or 1)
    initialTile = tostring(tonumber(editItem.tile) or 0)
    initialOamStart = (type(editItem.startAddr) == "number")
        and string.format("0x%06X", editItem.startAddr) or ""
  else
    initialBank, initialTile, initialOamStart = getInitialPpuSpriteModalValues(self)
  end

  local modalTitle = modalOpts.title or (isEdit and "Edit sprite" or "Add sprite")
  local primaryButtonText = modalOpts.primaryButtonText or (isEdit and "Save" or "Add")

  self.ppuFrameAddSpriteModal:show({
    title = modalTitle,
    primaryButtonText = primaryButtonText,
    window = win,
    initialBank = initialBank,
    initialTile = initialTile,
    initialOamStart = initialOamStart,
    onConfirm = function(bankText, tileText, oamStartText, targetWindow)
      local spriteLayer, spriteLayerIndex = getTargetSpriteLayerForAddSprite(targetWindow)
      if not spriteLayer then
        local message = "PPU frame window is missing a sprite layer"
        if targetWindow and targetWindow.kind == "oam_animation" then
          message = "OAM animation window is missing a sprite layer"
        end
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local bankNumber, bankErr = Shared.parseNonNegativeInteger(bankText, "Bank number")
      if not bankNumber then
        self:setStatus(bankErr)
        self:showToast("error", bankErr)
        return false
      end
      if bankNumber < 1 then
        local message = "Bank number must be 1 or greater"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local tileNumber, tileErr = Shared.parseNonNegativeInteger(tileText, "Tile number")
      if not tileNumber then
        self:setStatus(tileErr)
        self:showToast("error", tileErr)
        return false
      end

      local trimmedOam = tostring(oamStartText or ""):match("^%s*(.-)%s*$")
      local oamStart, oamErr
      if isEdit and trimmedOam == "" then
        oamStart = nil
      else
        oamStart, oamErr = Shared.parseHexAddress(oamStartText)
        if not oamStart then
          self:setStatus(oamErr)
          self:showToast("error", oamErr)
          return false
        end
      end

      local state = self.appEditState or {}
      local romRaw = state.romRaw
      local tilesPool = state.tilesPool
      if type(romRaw) ~= "string" or romRaw == "" then
        local message = "Open a ROM before adding an OAM-backed sprite"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      if not (tilesPool and tilesPool[bankNumber]) then
        local message = string.format("CHR bank %d is not available", bankNumber)
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      if not tilesPool[bankNumber][tileNumber] then
        local message = string.format("Tile %d is not available in CHR bank %d", tileNumber, bankNumber)
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      if isEdit then
        local layer = targetWindow.layers and targetWindow.layers[editLayerIndex] or nil
        local sprite = layer and layer.items and layer.items[editItemIndex] or nil
        if not (layer and layer.kind == "sprite" and sprite and sprite.removed ~= true) then
          self:setStatus("Could not find sprite to update")
          return false
        end

        local oldStartAddr = sprite.startAddr
        local entries
        if type(oldStartAddr) == "number" then
          entries = collectSpritesSharingOamStartAddr(self, oldStartAddr)
        else
          entries = {
            {
              win = targetWindow,
              layerIndex = editLayerIndex,
              layer = layer,
              sprite = sprite,
            },
          }
        end

        local beforeBySprite = {}
        for _, e in ipairs(entries) do
          beforeBySprite[e.sprite] = SpriteStateSnapshot.captureSpriteBindingState(e.sprite)
        end

        local layersToHydrate = {}
        if type(oldStartAddr) == "number" then
          layersToHydrate = patchSharedOamSpriteBinding(
            self,
            oldStartAddr,
            bankNumber,
            tileNumber,
            oamStart
          )
        else
          sprite.bank = bankNumber
          sprite.tile = tileNumber
          sprite.startAddr = oamStart
          reset8x16SpriteTilePairAfterChrEdit(layer, sprite)
          layersToHydrate[layer] = true
        end

        hydrateUniqueSpriteLayers(layersToHydrate, romRaw, tilesPool, state)

        local bindingActions = {}
        for _, e in ipairs(entries) do
          local spr = e.sprite
          local before = beforeBySprite[spr]
          local after = SpriteStateSnapshot.captureSpriteBindingState(spr)
          if before and after and not SpriteStateSnapshot.bindingStatesEqual(before, after) then
            bindingActions[#bindingActions + 1] = {
              win = e.win,
              layerIndex = e.layerIndex,
              sprite = spr,
              before = before,
              after = after,
            }
          end
        end
        if #bindingActions > 0 and self.undoRedo and self.undoRedo.addDragEvent then
          self.undoRedo:addDragEvent({
            type = "sprite_drag",
            mode = "sprite_binding",
            actions = bindingActions,
          })
        end

        layer.selectedSpriteIndex = editItemIndex
        layer.multiSpriteSelection = nil
        layer.multiSpriteSelectionOrder = nil
        layer.hoverSpriteIndex = editItemIndex

        if targetWindow.setActiveLayerIndex then
          targetWindow:setActiveLayerIndex(editLayerIndex)
        else
          targetWindow.activeLayer = editLayerIndex
        end

        self:markUnsaved("sprite_move")
        if type(oamStart) == "number" then
          self:setStatus(string.format(
            "Updated sprite at OAM 0x%06X (bank %d, tile %d)",
            oamStart,
            bankNumber,
            tileNumber
          ))
        else
          self:setStatus(string.format(
            "Updated sprite (bank %d, tile %d)",
            bankNumber,
            tileNumber
          ))
        end
        return true
      end

      spriteLayer.items = spriteLayer.items or {}
      table.insert(spriteLayer.items, {
        bank = bankNumber,
        startAddr = oamStart,
        tile = tileNumber,
      })

      SpriteController.hydrateSpriteLayer(spriteLayer, {
        romRaw = romRaw,
        tilesPool = tilesPool,
        appEditState = state,
        keepWorld = false,
      })

      local itemIndex = #spriteLayer.items
      spriteLayer.selectedSpriteIndex = itemIndex
      spriteLayer.multiSpriteSelection = nil
      spriteLayer.multiSpriteSelectionOrder = nil
      spriteLayer.hoverSpriteIndex = nil

      if targetWindow.setActiveLayerIndex then
        targetWindow:setActiveLayerIndex(spriteLayerIndex)
      else
        targetWindow.activeLayer = spriteLayerIndex
      end

      local sprite = spriteLayer.items[itemIndex]
      if self.undoRedo and self.undoRedo.addDragEvent and sprite then
        local afterState = SpriteStateSnapshot.captureSpriteState(sprite)
        if afterState then
          local beforeState = {
            worldX = afterState.worldX,
            worldY = afterState.worldY,
            x = afterState.x,
            y = afterState.y,
            dx = afterState.dx,
            dy = afterState.dy,
            hasMoved = afterState.hasMoved,
            removed = true,
          }
          if not SpriteStateSnapshot.statesEqual(beforeState, afterState) then
            self.undoRedo:addDragEvent({
              type = "sprite_drag",
              mode = "copy",
              actions = {
                {
                  win = targetWindow,
                  layerIndex = spriteLayerIndex,
                  sprite = sprite,
                  created = true,
                  before = beforeState,
                  after = afterState,
                },
              },
            })
          end
        end
      end

      self:markUnsaved("sprite_move")
      self:setStatus(string.format(
        "Added sprite from OAM 0x%06X on bank %d tile %d",
        oamStart,
        bankNumber,
        tileNumber
      ))
      return true
    end,
  })

  return true
end

function AppCoreController:_buildOamSpriteEmptySpaceContext(win, layerIndex)
  if not (win and type(layerIndex) == "number") then
    return nil
  end

  local layer = win.getLayer and win:getLayer(layerIndex) or (win.layers and win.layers[layerIndex])
  if not (layer and layer.kind == "sprite") then
    return nil
  end

  return {
    win = win,
    layerIndex = layerIndex,
    layer = layer,
    isOam = (win.kind == "oam_animation"),
  }
end

function AppCoreController:_buildOamSpriteEmptySpaceContextMenuItems(context)
  local items = {}
  if context and context.isOam then
    items[#items + 1] = {
      text = "Add new sprite",
      enabled = true,
      callback = function()
        return self:showPpuFrameAddSpriteModal(context.win)
      end,
    }

    local layer = context.layer
    if layer and layer.kind == "sprite" then
      local SpriteController = require("controllers.sprite.sprite_controller")
      local selected = SpriteController and SpriteController.getSelectedSpriteIndices(layer) or {}
      if #selected == 0 and layer.selectedSpriteIndex then
        selected = { layer.selectedSpriteIndex }
      end
      local hasRemovable = false
      for _, idx in ipairs(selected) do
        local s = layer.items and layer.items[idx]
        if s and s.removed ~= true then
          hasRemovable = true
          break
        end
      end
      if hasRemovable then
        items[#items + 1] = {
          text = "Remove selected sprites",
          enabled = true,
          callback = function()
            local MultiSelectController = require("controllers.input_support.multi_select_controller")
            local result = MultiSelectController.deleteSpriteSelection(
              context.win,
              context.layerIndex,
              self.undoRedo
            )
            if result and result.status then
              self:setStatus(result.status)
            end
          end,
        }
      end
    end
  end
  if context and context.win and context.layerIndex then
    self:_appendJumpToLinkedPaletteMenuItem(items, context.win, context.layerIndex)
    self:_appendRemoveRomPaletteLinkMenuItem(items, context.win, context.layerIndex)
    self:_appendPasteContextMenuItem(items, context)
  end
  return items
end

function AppCoreController:showOamSpriteEmptySpaceContextMenu(win, layerIndex, x, y)
  return self:showSpriteEmptySpaceContextMenu(win, layerIndex, x, y)
end

function AppCoreController:showSpriteEmptySpaceContextMenu(win, layerIndex, x, y)
  if not (self.ppuTileContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = self:_buildOamSpriteEmptySpaceContext(win, layerIndex)
  if not context then
    return false
  end
  local items = self:_buildOamSpriteEmptySpaceContextMenuItems(context)
  if not (type(items) == "table" and #items > 0) then
    return false
  end

  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, items)
  return self.ppuTileContextMenu:isVisible()
end

function AppCoreController:_buildTileLayerEmptySpaceContext(win, layerIndex, col, row)
  if not (win and WindowCaps.isStaticOrAnimationArt(win) and type(layerIndex) == "number") then
    return nil
  end
  local layer = win.getLayer and win:getLayer(layerIndex) or (win.layers and win.layers[layerIndex])
  if not (layer and layer.kind == "tile") then
    return nil
  end
  return {
    win = win,
    layerIndex = layerIndex,
    layer = layer,
    col = col,
    row = row,
  }
end

function AppCoreController:_buildTileLayerEmptySpaceContextMenuItems(context)
  local items = {}
  if context and context.win and type(context.layerIndex) == "number" then
    self:_appendJumpToLinkedPaletteMenuItem(items, context.win, context.layerIndex)
    self:_appendRemoveRomPaletteLinkMenuItem(items, context.win, context.layerIndex)
    self:_appendPasteContextMenuItem(items, context)
  end
  return items
end

function AppCoreController:showTileLayerEmptySpaceContextMenu(win, layerIndex, col, row, x, y)
  if not (self.ppuTileContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = self:_buildTileLayerEmptySpaceContext(win, layerIndex, col, row)
  if not context then
    return false
  end
  local items = self:_buildTileLayerEmptySpaceContextMenuItems(context)
  if not (type(items) == "table" and #items > 0) then
    return false
  end

  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, items)
  return self.ppuTileContextMenu:isVisible()
end

function AppCoreController:showPpuFrameRangeModal(win)
  if not (self.ppuFrameRangeModal and win and win.kind == "ppu_frame") then
    return false
  end

  local layer = PpuRange.getPpuNametableLayer(win)
  local initialStart = (layer and type(layer.nametableStartAddr) == "number")
    and string.format("0x%06X", layer.nametableStartAddr) or ""
  local initialEnd = (layer and type(layer.nametableEndAddr) == "number")
    and string.format("0x%06X", layer.nametableEndAddr) or ""
  self.ppuFrameRangeModal:show({
    title = "Set tile range",
    window = win,
    initialStartAddress = initialStart,
    initialEndAddress = initialEnd,
    onConfirm = function(startText, endText, targetWindow)
      local startAddr, startErr = Shared.parseHexAddress(startText)
      if not startAddr then
        self:setStatus(startErr)
        self:showToast("error", startErr)
        return false
      end

      local endAddr, endErr = Shared.parseHexAddress(endText)
      if not endAddr then
        self:setStatus(endErr)
        self:showToast("error", endErr)
        return false
      end

      if endAddr < startAddr then
        local message = "End address must be greater than or equal to start address"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local targetLayer, targetLayerIndex = PpuRange.getPpuNametableLayer(targetWindow)
      if not targetLayer then
        local message = "PPU frame window is missing a tile layer"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      local beforeRangeState = PpuRange.snapshotPpuFrameRangeState(targetWindow, targetLayerIndex)

      targetLayer.codec = targetLayer.codec or "konami"
      targetLayer.nametableStartAddr = startAddr
      targetLayer.nametableEndAddr = endAddr
      local hydrated, hydrateErr = hydrateNametableLayerIfReady(self, targetWindow, targetLayer, targetLayerIndex)
      if not hydrated and targetWindow.invalidateNametableLayerCanvas then
        targetWindow:invalidateNametableLayerCanvas(targetLayerIndex)
      end
      if targetWindow.syncNametableLayerMetadata then
        targetWindow:syncNametableLayerMetadata()
      end
      if targetWindow.specializedToolbar and targetWindow.specializedToolbar.updateIcons then
        targetWindow.specializedToolbar:updateIcons()
      end
      local afterRangeState = PpuRange.snapshotPpuFrameRangeState(targetWindow, targetLayerIndex)
      if self.undoRedo and self.undoRedo.addPpuFrameRangeEvent
        and PpuRange.didPpuFrameRangeSettingsChange(beforeRangeState, afterRangeState)
      then
        self.undoRedo:addPpuFrameRangeEvent({
          type = "ppu_frame_range",
          win = targetWindow,
          layerIndex = targetLayerIndex,
          beforeState = beforeRangeState,
          afterState = afterRangeState,
        })
      end

      if hydrated then
        self:setStatus(string.format("Set nametable address range 0x%06X-0x%06X", startAddr, endAddr))
      else
        self:setStatus(string.format(
          "Set nametable address range 0x%06X-0x%06X (waiting: %s)",
          startAddr,
          endAddr,
          tostring(hydrateErr or "incomplete setup")
        ))
      end
      return true
    end,
  })

  return true
end

function AppCoreController:showPpuFramePatternRangeModal(win)
  if not (self.ppuFramePatternRangeModal and win and win.kind == "ppu_frame") then
    return false
  end

  local targetLayer = getPpuPatternTableTargetLayer(win)
  if not targetLayer then
    self:setStatus("PPU frame window is missing a target tile layer")
    self:showToast("error", "PPU frame window is missing a target tile layer")
    return false
  end
  local existingPatternTable = type(targetLayer.patternTable) == "table" and targetLayer.patternTable or {}
  local existingRanges = type(existingPatternTable.ranges) == "table" and existingPatternTable.ranges or {}

  local initialBank = "1"
  local initialPage = 1
  local initialFrom = "0"
  local initialTo = "255"
  local lastRange = existingRanges[#existingRanges]
  if type(lastRange) == "table" then
    initialBank = tostring(tonumber(lastRange.bank) or tonumber(initialBank) or 1)
    initialPage = tonumber(lastRange.page) or initialPage
    local lastFrom, lastTo = PpuRange.parsePatternRangeBounds(lastRange)
    if lastFrom ~= nil and lastTo ~= nil then
      initialFrom = tostring(lastFrom)
      initialTo = tostring(lastTo)
    end
  end

  self.ppuFramePatternRangeModal:show({
    title = "Add tile range",
    window = win,
    initialBank = initialBank,
    initialPage = initialPage,
    initialFrom = initialFrom,
    initialTo = initialTo,
    onConfirm = function(bankText, pageValue, fromText, toText, targetWindow)
      local function activatePatternLayerView()
        if targetWindow and targetWindow.setPatternLayerSoloMode then
          targetWindow:setPatternLayerSoloMode(true)
        end
        if targetWindow and targetWindow.specializedToolbar and targetWindow.specializedToolbar.updateIcons then
          targetWindow.specializedToolbar:updateIcons()
        end
      end

      local layer, layerIndex = getPpuPatternTableTargetLayer(targetWindow)
      if not layer then
        local message = "PPU frame window is missing a target tile layer"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local bankIndex, bankErr = Shared.parsePositiveDecimalInteger(bankText, "Bank")
      if not bankIndex then
        self:setStatus(bankErr)
        self:showToast("error", bankErr)
        return false
      end
      local pageIndex = math.floor(tonumber(pageValue) or 1)
      if pageIndex ~= 1 and pageIndex ~= 2 then
        local message = "Page must be 1 or 2"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      local fromTile, fromErr = Shared.parseNonNegativeInteger(fromText, "From")
      if not fromTile then
        self:setStatus(fromErr)
        self:showToast("error", fromErr)
        return false
      end
      local toTile, toErr = Shared.parseNonNegativeInteger(toText, "To")
      if not toTile then
        self:setStatus(toErr)
        self:showToast("error", toErr)
        return false
      end
      if fromTile > 255 or toTile > 255 then
        local message = "From/To must be between 0 and 255"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      if toTile < fromTile then
        local message = "To must be greater than or equal to From"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local beforeState = PpuRange.snapshotPpuFrameRangeState(targetWindow, layerIndex)
      layer.patternTable = type(layer.patternTable) == "table" and layer.patternTable or {}
      layer.patternTable.ranges = type(layer.patternTable.ranges) == "table" and layer.patternTable.ranges or {}
      local currentTotal = PpuRange.patternTableLogicalSize(layer.patternTable) or 0
      local nextTotal = currentTotal + (toTile - fromTile + 1)
      if nextTotal > 256 then
        local message = string.format("Range exceeds 256 logical tiles (%d/256)", nextTotal)
        self:setStatus(message)
        self:showToast("error", message)
        activatePatternLayerView()
        return false
      end
      layer.patternTable.ranges[#layer.patternTable.ranges + 1] = {
        bank = bankIndex,
        page = pageIndex,
        tileRange = {
          from = fromTile,
          to = toTile,
        },
      }
      local hydrated, hydrateErr = hydrateNametableLayerIfReady(self, targetWindow, layer, layerIndex)
      if not hydrated and targetWindow.invalidateNametableLayerCanvas then
        targetWindow:invalidateNametableLayerCanvas(layerIndex)
      end
      self:_ensurePpuPatternTableReferenceLayer({
        win = targetWindow,
        layer = layer,
        layerIndex = layerIndex,
      }, {
        keepActiveLayer = true,
      })

      local total = PpuRange.patternTableLogicalSize(layer.patternTable)
      if total == 256 then
        self:showToast("success", "Pattern table ranges complete (256/256).")
      end
      if targetWindow.specializedToolbar and targetWindow.specializedToolbar.updateIcons then
        targetWindow.specializedToolbar:updateIcons()
      end
      activatePatternLayerView()

      local afterState = PpuRange.snapshotPpuFrameRangeState(targetWindow, layerIndex)
      if self.undoRedo and self.undoRedo.addPpuFrameRangeEvent
        and PpuRange.didPpuFrameRangeSettingsChange(beforeState, afterState)
      then
        self.undoRedo:addPpuFrameRangeEvent({
          type = "ppu_frame_range",
          win = targetWindow,
          layerIndex = layerIndex,
          beforeState = beforeState,
          afterState = afterState,
        })
      end

      if hydrated then
        self:setStatus(string.format(
          "Added tile range [%d..%d] bank %d page %d (%d/256)",
          fromTile,
          toTile,
          bankIndex,
          pageIndex,
          tonumber(total) or 0
        ))
      else
        self:setStatus(string.format(
          "Added tile range [%d..%d] bank %d page %d (%d/256, waiting: %s)",
          fromTile,
          toTile,
          bankIndex,
          pageIndex,
          tonumber(total) or 0,
          tostring(hydrateErr or "incomplete setup")
        ))
      end
      return true
    end,
  })

  return true
end

function AppCoreController:applyPpuFrameRangeState(rangeState)
  if not (rangeState and rangeState.win and rangeState.win.kind == "ppu_frame") then
    return false
  end

  local win = rangeState.win
  local li = tonumber(rangeState.layerIndex) or select(2, PpuRange.getPpuNametableLayer(win)) or win.activeLayer or 1
  local layer = win.layers and win.layers[li] or nil
  local layerState = rangeState.layerState or nil
  if not (layer and layerState) then
    return false
  end

  win.cols = tonumber(rangeState.cols) or win.cols
  win.rows = tonumber(rangeState.rows) or win.rows
  win.nametableStart = rangeState.nametableStart
  win.nametableBytes = copyNumberArray(rangeState.nametableBytes)
  win.nametableAttrBytes = copyNumberArray(rangeState.nametableAttrBytes)
  win._originalNametableBytes = copyNumberArray(rangeState.originalNametableBytes)
  win._originalNametableAttrBytes = copyNumberArray(rangeState.originalNametableAttrBytes)
  win._originalCompressedBytes = copyNumberArray(rangeState.originalCompressedBytes)
  win._tileSwaps = TableUtils.deepcopy(rangeState.tileSwapsMap)
  win.originalTotalByteNumber = rangeState.originalTotalByteNumber
  win._nametableOriginalSize = rangeState.nametableOriginalSize
  win._nametableCompressedSize = rangeState.nametableCompressedSize

  layer.kind = layerState.kind
  layer.mode = layerState.mode
  layer.codec = layerState.codec
  layer.nametableStartAddr = layerState.nametableStartAddr
  layer.nametableEndAddr = layerState.nametableEndAddr
  layer.noOverflowSupported = layerState.noOverflowSupported
  layer.patternTable = TableUtils.deepcopy(layerState.patternTable)
  layer.attrMode = layerState.attrMode
  layer.tileSwaps = TableUtils.deepcopy(layerState.tileSwaps)
  layer.items = {}

  local state = self.appEditState or {}
  if state.chrBanksBytes and type(layer.patternTable) == "table" and type(layer.patternTable.ranges) == "table" then
    local ensuredBanks = {}
    for _, range in ipairs(layer.patternTable.ranges) do
      local bankIndex = type(range) == "table" and tonumber(range.bank) or nil
      if bankIndex and bankIndex >= 1 and not ensuredBanks[bankIndex] and state.chrBanksBytes[bankIndex] then
        ensuredBanks[bankIndex] = true
        BankViewController.ensureBankTiles(state, bankIndex)
      end
    end
  end

  if NametableTilesController.extractPaletteNumbersFromAttributes then
    NametableTilesController.extractPaletteNumbersFromAttributes(win, layer, win.cols, win.rows)
  end

  local hydrated, _ = hydrateNametableLayerIfReady(self, win, layer, li)
  if not hydrated and win.invalidateNametableLayerCanvas then
    win:invalidateNametableLayerCanvas(li)
  end

  -- Keep runtime pattern-table reference layer in sync so undo/redo is visible
  -- immediately when the PPU frame is in pattern-layer solo mode.
  if self._ensurePpuPatternTableReferenceLayer and type(layer.patternTable) == "table" then
    self:_ensurePpuPatternTableReferenceLayer({
      win = win,
      layer = layer,
      layerIndex = li,
    }, {
      keepActiveLayer = true,
    })
  end

  if win.syncNametableLayerMetadata then
    win:syncNametableLayerMetadata()
  end
  if win.specializedToolbar and win.specializedToolbar.updateIcons then
    win.specializedToolbar:updateIcons()
  end

  return true
end

end
