local WindowCaps = require("controllers.window.window_capabilities")
local TileInvalidationIndex = require("controllers.app.tile_invalidation_index")

return function(AppCoreController)

function AppCoreController:invalidateChrBankCanvas(bankIdx)
  if not self.chrBankCanvasController then
    return false
  end
  self.chrBankCanvasController:invalidateBank(bankIdx)
  return true
end

function AppCoreController:markTileInvalidationIndexDirty()
  self._tileInvalidationIndexDirty = true
end

function AppCoreController:ensureTileInvalidationIndex()
  local wm = self.wm
  if not wm then
    return nil
  end

  local generation = (wm.getStructureGeneration and wm:getStructureGeneration()) or 0
  local index = self._tileInvalidationIndex
  if index
    and self._tileInvalidationIndexDirty ~= true
    and index.wmGeneration == generation
  then
    return index
  end

  self._tileInvalidationIndex = TileInvalidationIndex.rebuild(wm)
  self._tileInvalidationIndexDirty = false
  return self._tileInvalidationIndex
end

function AppCoreController:invalidateChrBankTileCanvas(bankIdx, tileIndex)
  if not self.chrBankCanvasController then
    return false
  end
  self.chrBankCanvasController:invalidateTile(bankIdx, tileIndex)
  return true
end

function AppCoreController:invalidatePpuFrameNametableTile(bankIdx, tileIndex)
  if not (self.wm and self.wm.getWindows) then
    return false
  end

  local bank = math.floor(tonumber(bankIdx) or -1)
  local tile = math.floor(tonumber(tileIndex) or -1)
  if bank < 1 or tile < 0 then
    return false
  end

  local index = self:ensureTileInvalidationIndex()
  return TileInvalidationIndex.invalidateNametableFromIndex(index, bank, tile)
end

--- PPU / OAM sprite layers draw tile refs directly; ensure any on-screen sprite using this CHR
--- cell reloads from live bank bytes (sparse tilesPool + missed :edit paths used to leave GPU stale).
function AppCoreController:invalidatePpuFrameSpriteTilesForChrTile(bankIdx, tileIndex)
  if not (self.wm and self.wm.getWindows) then
    return false
  end

  local bank = math.floor(tonumber(bankIdx) or -1)
  local tile = math.floor(tonumber(tileIndex) or -1)
  if bank < 1 or tile < 0 then
    return false
  end

  local state = self.appEditState
  local bankBytes = state and state.chrBanksBytes and state.chrBanksBytes[bank]
  if not bankBytes then
    return false
  end

  local index = self:ensureTileInvalidationIndex()
  return TileInvalidationIndex.invalidateSpritesFromIndex(index, bank, tile, bankBytes)
end

function AppCoreController:invalidateStaticAnimationTileLayerCanvasForChrTile(bankIdx, tileIndex)
  if not (self.wm and self.wm.getWindows) then
    return false
  end

  local bank = math.floor(tonumber(bankIdx) or -1)
  local tile = math.floor(tonumber(tileIndex) or -1)
  if bank < 1 or tile < 0 then
    return false
  end

  local index = self:ensureTileInvalidationIndex()
  return TileInvalidationIndex.invalidateTileLayerFromIndex(index, bank, tile)
end

local function ppuLayerUsesPaletteWin(layer, paletteWin)
  if not (layer and layer.kind == "tile" and paletteWin) then
    return false
  end

  local pd = layer.paletteData
  if pd and pd.winId and paletteWin._id then
    return pd.winId == paletteWin._id
  end

  if paletteWin.kind == "palette" and paletteWin.activePalette == true then
    return not (pd and pd.items)
  end

  return false
end

function AppCoreController:invalidatePpuFramePaletteLayer(win, layerIndex)
  if not (win and win.layers) then
    return false
  end

  local WindowCaps = require("controllers.window.window_capabilities")
  local li = tonumber(layerIndex) or (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  local layer = win.layers[li]
  if not (layer and layer.kind == "tile") then
    return false
  end

  if win.kind == "ppu_frame" and win.invalidateNametableLayerCanvas then
    win:invalidateNametableLayerCanvas(li)
    return true
  end

  if WindowCaps.isStaticOrAnimationArt(win) and win.invalidateTileLayerCanvas then
    win:invalidateTileLayerCanvas(li)
    return true
  end

  if WindowCaps.isPatternTable(win) and win.invalidateTileLayerCanvas then
    win:invalidateTileLayerCanvas(li)
    return true
  end

  return false
end

function AppCoreController:invalidateTileLayerCanvasesAffectedByPaletteWin(paletteWin)
  if not (paletteWin and self.wm and self.wm.getWindows) then
    return false
  end

  local WindowCaps = require("controllers.window.window_capabilities")
  local touched = false
  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win
      and win.layers
      and win.invalidateTileLayerCanvas
      and (
        WindowCaps.isStaticArt(win)
        or WindowCaps.isAnimationLike(win)
        or WindowCaps.isPatternTable(win)
      )
    then
      for li, layer in ipairs(win.layers) do
        if layer and layer.kind == "tile" and ppuLayerUsesPaletteWin(layer, paletteWin) then
          win:invalidateTileLayerCanvas(li)
          touched = true
        end
      end
    end
  end

  return touched
end

function AppCoreController:invalidatePpuFrameLayersAffectedByPaletteWin(paletteWin)
  if not (paletteWin and self.wm and self.wm.getWindows) then
    return false
  end

  local touched = false
  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win and win.kind == "ppu_frame" and win.layers and win.invalidateNametableLayerCanvas then
      for li, layer in ipairs(win.layers) do
        if ppuLayerUsesPaletteWin(layer, paletteWin) then
          win:invalidateNametableLayerCanvas(li)
          touched = true
        end
      end
    end
  end

  if self.invalidateTileLayerCanvasesAffectedByPaletteWin and self:invalidateTileLayerCanvasesAffectedByPaletteWin(paletteWin) then
    touched = true
  end

  return touched
end

function AppCoreController:invalidateAllPpuFrameNametableCanvases()
  if not (self.wm and self.wm.getWindows) then
    return false
  end

  local touched = false
  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win and win.kind == "ppu_frame" and win.layers and win.invalidateNametableLayerCanvas then
      win._nametableLayerCanvas = {}
      for li, layer in ipairs(win.layers) do
        if layer and layer.kind == "tile" then
          win:invalidateNametableLayerCanvas(li)
          touched = true
        end
      end
    end
  end

  self:markTileInvalidationIndexDirty()
  return touched
end

-- Offscreen tile caches (static_art / animation) can go blank after GPU/window changes; force full repaint.
function AppCoreController:invalidateAllStaticAnimationTileLayerCanvases()
  if not (self.wm and self.wm.getWindows) then
    return false
  end

  local touched = false
  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win and win.invalidateAllTileLayerCanvases then
      win:invalidateAllTileLayerCanvases()
      touched = true
    end
  end

  self:markTileInvalidationIndexDirty()
  return touched
end

end
