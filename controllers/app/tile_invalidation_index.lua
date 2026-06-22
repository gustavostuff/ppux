-- tile_invalidation_index.lua
-- (bank, tileIndex) -> affected nametable/tile-layer cells, pattern-table fallbacks, and sprite refs.
-- Rebuilt lazily when window structure or layer items change; used on CHR paint invalidation.

local WindowCaps = require("controllers.window.window_capabilities")
local PatternTableMapping = require("utils.pattern_table_mapping")

local M = {}

local function tileKey(bank, tile)
  return string.format("%d:%d", math.floor(tonumber(bank) or -1), math.floor(tonumber(tile) or -1))
end

local function newEntry()
  return {
    nametableCells = {},
    tileLayerCells = {},
    nametableFallbacks = {},
    tileLayerFallbacks = {},
    spriteRefs = {},
  }
end

function M.layerMayReferenceBankTile(layer, targetBank, targetTileIndex)
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

local function foreachPatternTableBankTile(layer, callback)
  if type(layer) ~= "table" or type(callback) ~= "function" then
    return
  end
  local pt = layer.patternTable
  if type(pt) ~= "table" or type(pt.ranges) ~= "table" then
    return
  end

  for _, r in ipairs(pt.ranges) do
    if type(r) ~= "table" then
    elseif type(r.tiles) == "table" and #r.tiles > 0 then
      local db = math.floor(tonumber(r.bank) or 1)
      for _, t in ipairs(r.tiles) do
        local tb = math.floor(tonumber(t.bank) or db)
        local ti = t.tileIndex or t.startTileIndex
        if ti ~= nil then
          callback(tb, math.floor(tonumber(ti) or -1))
        else
          local pg = math.floor(tonumber(t.page) or 1)
          if pg < 1 then pg = 1 elseif pg > 2 then pg = 2 end
          local b = math.floor(tonumber(t.byte or t.tileByte) or -1)
          local tti = (pg == 2) and (256 + b) or b
          callback(tb, tti)
        end
      end
    elseif PatternTableMapping.isGlobalChrFromToRange(r) then
      local a, b = PatternTableMapping.globalChrFromToBounds(r)
      local rangeBank = math.floor(tonumber(r.bank) or -1)
      if rangeBank >= 1 and a ~= nil and b ~= nil then
        for ti = a, b do
          callback(rangeBank, ti)
        end
      end
    end
  end
end

local function layerItemKeySet(layer)
  local set = {}
  for _, item in pairs(layer.items or {}) do
    if item and item.index ~= nil and item._bankIndex ~= nil then
      set[tileKey(item._bankIndex, item.index)] = true
    end
  end
  return set
end

local function addUniqueFallback(list, win, li)
  for _, entry in ipairs(list) do
    if entry.win == win and entry.li == li then
      return
    end
  end
  list[#list + 1] = { win = win, li = li }
end

local function indexLayerItems(index, win, li, layer, cols, bucketName)
  if not (layer and layer.items) then
    return
  end
  for idx, item in pairs(layer.items) do
    if item and item.index ~= nil and tonumber(item._bankIndex) then
      local bank = math.floor(tonumber(item._bankIndex))
      local tile = math.floor(tonumber(item.index))
      local z = (tonumber(idx) or 1) - 1
      local col = z % cols
      local row = math.floor(z / cols)
      local key = tileKey(bank, tile)
      local entry = index.byKey[key] or newEntry()
      index.byKey[key] = entry
      entry[bucketName][#entry[bucketName] + 1] = {
        win = win,
        li = li,
        col = col,
        row = row,
      }
    end
  end
end

local function indexPatternFallbacks(index, win, li, layer, fallbackBucket)
  local itemKeys = layerItemKeySet(layer)
  foreachPatternTableBankTile(layer, function(bank, tile)
    if bank < 1 or tile < 0 then
      return
    end
    if itemKeys[tileKey(bank, tile)] then
      return
    end
    local key = tileKey(bank, tile)
    local entry = index.byKey[key] or newEntry()
    index.byKey[key] = entry
    addUniqueFallback(entry[fallbackBucket], win, li)
  end)
end

local function indexSpriteRefs(index, win)
  if not (win and win.layers and WindowCaps.isStartAddrSpriteSyncWindow(win)) then
    return
  end
  for _, layer in ipairs(win.layers) do
    if layer and layer.kind == "sprite" and layer.items then
      for _, s in ipairs(layer.items) do
        if s.removed ~= true then
          for _, ref in ipairs({ s.topRef, s.botRef }) do
            if ref and ref.loadFromCHR and ref._bankIndex ~= nil and ref.index ~= nil then
              local bank = math.floor(tonumber(ref._bankIndex))
              local tile = math.floor(tonumber(ref.index))
              if bank >= 1 and tile >= 0 then
                local key = tileKey(bank, tile)
                local entry = index.byKey[key] or newEntry()
                index.byKey[key] = entry
                entry.spriteRefs[#entry.spriteRefs + 1] = ref
              end
            end
          end
        end
      end
    end
  end
end

function M.rebuild(wm)
  local index = {
    wmGeneration = (wm and wm.getStructureGeneration and wm:getStructureGeneration()) or 0,
    byKey = {},
  }
  if not (wm and wm.getWindows) then
    return index
  end

  for _, win in ipairs(wm:getWindows() or {}) do
    if win and win.layers then
      if win.kind == "ppu_frame" and win.invalidateNametableLayerCanvas then
        local cols = win.cols or 32
        for li, layer in ipairs(win.layers) do
          if layer and layer.kind ~= "sprite" and layer.items then
            indexLayerItems(index, win, li, layer, cols, "nametableCells")
            indexPatternFallbacks(index, win, li, layer, "nametableFallbacks")
          end
        end
      end

      if win.invalidateTileLayerCanvas
        and (WindowCaps.isStaticOrAnimationArt(win) or WindowCaps.isPatternTable(win))
      then
        local cols = win.cols or 32
        for li, layer in ipairs(win.layers) do
          if layer and layer.kind == "tile" and layer.items then
            indexLayerItems(index, win, li, layer, cols, "tileLayerCells")
            indexPatternFallbacks(index, win, li, layer, "tileLayerFallbacks")
          end
        end
      end

      indexSpriteRefs(index, win)
    end
  end

  return index
end

local function trackLayerHit(layerHits, win, li)
  layerHits[win] = layerHits[win] or {}
  layerHits[win][li] = true
end

local function hadLayerHit(layerHits, win, li)
  return layerHits[win] and layerHits[win][li] == true
end

function M.invalidateNametableFromIndex(index, bank, tile)
  bank = math.floor(tonumber(bank) or -1)
  tile = math.floor(tonumber(tile) or -1)
  if bank < 1 or tile < 0 or not index then
    return false
  end

  local entry = index.byKey[tileKey(bank, tile)]
  if not entry then
    return false
  end

  local touched = false
  local layerHits = {}

  for _, target in ipairs(entry.nametableCells) do
    if target.win and target.win.invalidateNametableLayerCanvas then
      target.win:invalidateNametableLayerCanvas(target.li, target.col, target.row)
      trackLayerHit(layerHits, target.win, target.li)
      touched = true
    end
  end

  for _, target in ipairs(entry.nametableFallbacks) do
    if not hadLayerHit(layerHits, target.win, target.li)
      and target.win
      and target.win.invalidateNametableLayerCanvas
    then
      target.win:invalidateNametableLayerCanvas(target.li)
      touched = true
    end
  end

  return touched
end

function M.invalidateTileLayerFromIndex(index, bank, tile)
  bank = math.floor(tonumber(bank) or -1)
  tile = math.floor(tonumber(tile) or -1)
  if bank < 1 or tile < 0 or not index then
    return false
  end

  local entry = index.byKey[tileKey(bank, tile)]
  if not entry then
    return false
  end

  local touched = false
  local layerHits = {}

  for _, target in ipairs(entry.tileLayerCells) do
    if target.win and target.win.invalidateTileLayerCanvas then
      target.win:invalidateTileLayerCanvas(target.li, target.col, target.row)
      trackLayerHit(layerHits, target.win, target.li)
      touched = true
    end
  end

  for _, target in ipairs(entry.tileLayerFallbacks) do
    if not hadLayerHit(layerHits, target.win, target.li)
      and target.win
      and target.win.invalidateTileLayerCanvas
    then
      target.win:invalidateTileLayerCanvas(target.li)
      touched = true
    end
  end

  return touched
end

function M.invalidateSpritesFromIndex(index, bank, tile, bankBytes)
  bank = math.floor(tonumber(bank) or -1)
  tile = math.floor(tonumber(tile) or -1)
  if bank < 1 or tile < 0 or not index or not bankBytes then
    return false
  end

  local entry = index.byKey[tileKey(bank, tile)]
  if not entry then
    return false
  end

  local touched = false
  for _, ref in ipairs(entry.spriteRefs) do
    if ref and ref.loadFromCHR
      and tonumber(ref._bankIndex) == bank
      and tonumber(ref.index) == tile
    then
      ref:loadFromCHR(bankBytes, tile)
      touched = true
    end
  end

  return touched
end

-- Full-window scan paths kept for tests and optional debug parity checks.
function M.scanInvalidateNametable(wm, bank, tile)
  if not (wm and wm.getWindows) then
    return false
  end

  local touched = false
  for _, win in ipairs(wm:getWindows() or {}) do
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
          if not hitInItems and M.layerMayReferenceBankTile(layer, bank, tile) then
            win:invalidateNametableLayerCanvas(li)
            touched = true
          end
        end
      end
    end
  end

  return touched
end

function M.scanInvalidateTileLayer(wm, bank, tile)
  if not (wm and wm.getWindows) then
    return false
  end

  local touched = false
  for _, win in ipairs(wm:getWindows() or {}) do
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
          if not hitInItems and M.layerMayReferenceBankTile(layer, bank, tile) then
            win:invalidateTileLayerCanvas(li)
            touched = true
          end
        end
      end
    end
  end

  return touched
end

function M.scanInvalidateSprites(wm, bank, tile, bankBytes)
  if not (wm and wm.getWindows and bankBytes) then
    return false
  end

  local touched = false
  for _, win in ipairs(wm:getWindows() or {}) do
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

function M.markDirtyFromCtx()
  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app
  if app and app.markTileInvalidationIndexDirty then
    app:markTileInvalidationIndexDirty()
  end
end

return M
