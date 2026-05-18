local WindowCaps = require("controllers.window.window_capabilities")
local PatternTableMapping = require("utils.pattern_table_mapping")

return function(AppCoreController)

function AppCoreController:invalidateChrBankCanvas(bankIdx)
  if not self.chrBankCanvasController then
    return false
  end
  self.chrBankCanvasController:invalidateBank(bankIdx)
  return true
end

local function layerMayReferenceBankTile(layer, targetBank, targetTileIndex)
  if type(layer) ~= "table" then
    return false
  end
  local pt = layer.patternTable
  if type(pt) ~= "table" or type(pt.ranges) ~= "table" then
    return false
  end

  for _, r in ipairs(pt.ranges) do
    if type(r) ~= "table" then
    elseif type(r.tiles) == "table" and #r.tiles > 0 then
      local db = math.floor(tonumber(r.bank) or 1)
      for _, t in ipairs(r.tiles) do
        local tb = math.floor(tonumber(t.bank) or db)
        local ti = t.tileIndex or t.startTileIndex
        if ti ~= nil then
          ti = math.floor(tonumber(ti) or -1)
          if tb == targetBank and ti == targetTileIndex then
            return true
          end
        else
          local pg = math.floor(tonumber(t.page) or 1)
          if pg < 1 then pg = 1 elseif pg > 2 then pg = 2 end
          local b = math.floor(tonumber(t.byte or t.tileByte) or -1)
          local tti = (pg == 2) and (256 + b) or b
          if tb == targetBank and tti == targetTileIndex then
            return true
          end
        end
      end
    elseif PatternTableMapping.isGlobalChrFromToRange(r) then
      local a, b = PatternTableMapping.globalChrFromToBounds(r)
      local rangeBank = math.floor(tonumber(r.bank) or -1)
      if rangeBank == targetBank and a ~= nil and b ~= nil then
        if targetTileIndex >= a and targetTileIndex <= b then
          return true
        end
      end
    end
  end
  return false
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

  local touched = false

  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win and win.kind == "ppu_frame" and win.layers and win.invalidateNametableLayerCanvas then
      for li, layer in ipairs(win.layers) do
        if layer and layer.kind ~= "sprite" and layer.items then
          local hitInItems = false
          for idx, item in pairs(layer.items) do
            if item and item.index == tile and tonumber(item._bankIndex) == bank then
              local z = (tonumber(idx) or 1) - 1
              local cols = win.cols or 32
              local col = z % cols
              local row = math.floor(z / cols)
              win:invalidateNametableLayerCanvas(li, col, row)
              touched = true
              hitInItems = true
            end
          end
          if not hitInItems and layerMayReferenceBankTile(layer, bank, tile) then
            -- Fallback for cached layers where edited tile currently has no item instances
            -- (for example after mapping changes or hidden/cleared cells); force full layer repaint.
            win:invalidateNametableLayerCanvas(li)
            touched = true
          end
        end
      end
    end
  end

  return touched
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

  local touched = false
  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win and win.layers and WindowCaps.isStartAddrSpriteSyncWindow(win) then
      for _, layer in ipairs(win.layers) do
        if layer and layer.kind == "sprite" and layer.items then
          for _, s in ipairs(layer.items) do
            if s.removed ~= true then
              for _, ref in ipairs({ s.topRef, s.botRef }) do
                if ref and ref.loadFromCHR and tonumber(ref._bankIndex) == bank and tonumber(ref.index) == tile then
                  ref:loadFromCHR(bankBytes, tile)
                  touched = true
                end
              end
            end
          end
        end
      end
    end
  end

  return touched
end

function AppCoreController:invalidateStaticAnimationTileLayerCanvasForChrTile(bankIdx, tileIndex)
  if not (self.wm and self.wm.getWindows) then
    return false
  end

  local WindowCaps = require("controllers.window.window_capabilities")
  local bank = math.floor(tonumber(bankIdx) or -1)
  local tile = math.floor(tonumber(tileIndex) or -1)
  if bank < 1 or tile < 0 then
    return false
  end

  local touched = false
  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win
      and win.layers
      and win.invalidateTileLayerCanvas
      and (WindowCaps.isStaticOrAnimationArt(win) or WindowCaps.isPatternTable(win))
    then
      for li, layer in ipairs(win.layers) do
        if layer and layer.kind == "tile" and layer.items then
          local hitInItems = false
          for idx, item in pairs(layer.items) do
            if item and item.index == tile and tonumber(item._bankIndex) == bank then
              local z = (tonumber(idx) or 1) - 1
              local cols = win.cols or 32
              local col = z % cols
              local row = math.floor(z / cols)
              win:invalidateTileLayerCanvas(li, col, row)
              touched = true
              hitInItems = true
            end
          end
          if not hitInItems and layerMayReferenceBankTile(layer, bank, tile) then
            win:invalidateTileLayerCanvas(li)
            touched = true
          end
        end
      end
    end
  end

  return touched
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

  return touched
end

end
