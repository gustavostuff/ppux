local WindowCaps = require("controllers.window.window_capabilities")

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

  local targetPage = (targetTileIndex >= 256) and 2 or 1
  local targetByte = targetTileIndex % 256
  for _, r in ipairs(pt.ranges) do
    if type(r) == "table" then
      local from = r.from
      local to = r.to
      local tr = r.tileRange
      if type(tr) == "table" then
        if from == nil then from = tr.from or tr.start end
        if to == nil then to = tr.to or tr["end"] end
      end
      if from == nil then from = r.start end
      if to == nil then to = r["end"] end
      from = math.floor(tonumber(from) or -1)
      to = math.floor(tonumber(to) or -1)
      local rangeBank = math.floor(tonumber(r.bank) or 1)
      local rangePage = math.floor(tonumber(r.page) or 1)
      if rangePage < 1 then rangePage = 1 elseif rangePage > 2 then rangePage = 2 end
      if rangeBank == targetBank and rangePage == targetPage and from >= 0 and to >= from and targetByte >= from and targetByte <= to then
        return true
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
      and (WindowCaps.isStaticArt(win) or WindowCaps.isAnimationLike(win))
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
  if not (win and win.kind == "ppu_frame" and win.layers and win.invalidateNametableLayerCanvas) then
    return false
  end

  local li = tonumber(layerIndex) or (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  local layer = win.layers[li]
  if not (layer and layer.kind == "tile") then
    return false
  end

  win:invalidateNametableLayerCanvas(li)
  return true
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
      and (WindowCaps.isStaticArt(win) or WindowCaps.isAnimationLike(win))
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
