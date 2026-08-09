-- Swap two palette indices (0..3) on CHR-backed tile pixels.
-- Preview uses the right-clicked context item; apply expands multi-selection.

local BankViewController = require("controllers.chr.bank_view_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local RevertTilePixelsController = require("controllers.chr.revert_tile_pixels_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local StatusHelpers = require("utils.status_helpers")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local function clampIndex(v)
  local n = math.floor(tonumber(v) or -1)
  if n < 0 or n > 3 then
    return nil
  end
  return n
end

local function resolve8x16Pair(tileIndex, tileBelow)
  local topIndex = tonumber(tileIndex)
  if type(topIndex) ~= "number" then
    return nil, nil
  end
  topIndex = math.floor(topIndex)
  local belowIndex = tonumber(tileBelow)
  if type(belowIndex) == "number" then
    return topIndex, math.floor(belowIndex)
  end
  topIndex = topIndex - (topIndex % 2)
  return topIndex, topIndex + 1
end

local function normalizeItemTileIndex(item)
  if not item then
    return nil
  end
  local tileIndex = tonumber(item.index)
  if type(tileIndex) ~= "number" then
    tileIndex = tonumber(item.tile)
  end
  if type(tileIndex) ~= "number" and item.topRef then
    tileIndex = tonumber(item.topRef.index)
  end
  if type(tileIndex) ~= "number" then
    return nil
  end
  tileIndex = math.floor(tileIndex)
  if tileIndex < 0 or tileIndex >= 512 then
    tileIndex = tileIndex % 512
  end
  return tileIndex
end

--- Whether the context item should preview/edit as an 8x16 visual unit.
local function isContext8x16(context)
  local layer = context and context.layer
  local win = context and context.win
  if not layer then
    return false
  end
  if layer.kind == "sprite" then
    return layer.mode == "8x16"
  end
  if win and WindowCaps.isChrLike(win) and win.orderMode == "oddEven" then
    return true
  end
  local mode = layer.mode
  return mode == "8x16" or mode == "oddEven"
end

local function tileItemAt(win, layerIndex, col, row)
  if not win then
    return nil
  end
  if win.get then
    local item = win:get(col, row, layerIndex)
    if item then
      return item
    end
  end
  if win.getVirtualTileHandle and win.materializeTileHandle then
    local h = win:getVirtualTileHandle(col, row, layerIndex)
    if h then
      return win:materializeTileHandle(h, layerIndex)
    end
  end
  return nil
end

local function tileRefFromItemOrPool(app, item, bank, tileIndex)
  if item and item.pixels and #item.pixels == 64 then
    return item
  end
  local state = app and app.appEditState
  if state and type(tileIndex) == "number" then
    return BankViewController.getTileRef(state, bank, tileIndex)
  end
  return nil
end

--- CHR oddEven / pattern-table 8x16: top+bot tile refs for the right-clicked cell.
local function resolveTileLayerPreviewPair(app, context)
  local win = context.win
  local layer = context.layer
  local item = context.item
  local li = context.layerIndex or (win and win.getActiveLayerIndex and win:getActiveLayerIndex()) or (win and win.activeLayer) or 1
  local bank = tonumber(item and item._bankIndex)
    or tonumber(context.sourceBank)
    or tonumber(layer and layer.bank)
    or tonumber(win and win.currentBank)
    or 1

  -- CHR/ROM oddEven: pair by grid column + even top row.
  if win and WindowCaps.isChrLike(win) and win.orderMode == "oddEven"
      and type(context.col) == "number" and type(context.row) == "number" then
    local topRow = context.row - (context.row % 2)
    local topItem = tileItemAt(win, li, context.col, topRow)
    local botItem = tileItemAt(win, li, context.col, topRow + 1)
    local topIndex = (win.getTileIndexAt and win:getTileIndexAt(context.col, topRow))
      or normalizeItemTileIndex(topItem)
    local botIndex = (win.getTileIndexAt and win:getTileIndexAt(context.col, topRow + 1))
      or normalizeItemTileIndex(botItem)
    bank = tonumber(topItem and topItem._bankIndex) or bank
    local top = tileRefFromItemOrPool(app, topItem, bank, topIndex)
    local bot = tileRefFromItemOrPool(app, botItem, bank, botIndex)
    if top then
      return { top = top, bot = bot, mode = "8x16" }
    end
  end

  -- Pattern table / other tile layers in 8x16: NES even/odd tile index pair.
  local idx = normalizeItemTileIndex(item) or tonumber(context.tileIndex)
  if type(idx) ~= "number" then
    return nil
  end
  local topIndex, botIndex = resolve8x16Pair(idx, nil)
  bank = tonumber(item and item._bankIndex) or bank
  local top = tileRefFromItemOrPool(app, (normalizeItemTileIndex(item) == topIndex) and item or nil, bank, topIndex)
  local bot = tileRefFromItemOrPool(app, nil, bank, botIndex)
  -- If the clicked item is the bottom half, still use it as bot when indices match.
  if bot == nil and item and normalizeItemTileIndex(item) == botIndex then
    bot = tileRefFromItemOrPool(app, item, bank, botIndex)
  end
  if not top then
    return nil
  end
  return { top = top, bot = bot, mode = "8x16" }
end

local function bankForSpriteItem(item, layer, contextSourceBank)
  return tonumber(item and item._bankIndex)
    or tonumber(item and item.bank)
    or tonumber(item and item.topRef and item.topRef._bankIndex)
    or tonumber(contextSourceBank)
    or tonumber(layer and layer.bank)
    or 1
end

local function addTarget(out, seen, bank, tileIndex)
  bank = math.floor(tonumber(bank) or 0)
  tileIndex = math.floor(tonumber(tileIndex) or -1)
  if bank < 1 or tileIndex < 0 or tileIndex >= 512 then
    return
  end
  local key = bank .. ":" .. tileIndex
  if seen[key] then
    return
  end
  seen[key] = true
  out[#out + 1] = { bank = bank, tileIndex = tileIndex }
end

local function appendSpriteItemTargets(item, layer, contextSourceBank, out, seen)
  if not item or item.removed == true then
    return
  end
  local bank = bankForSpriteItem(item, layer, contextSourceBank)
  local mode = (layer and layer.mode) or "8x8"
  if mode == "8x16" then
    local top, bot = resolve8x16Pair(item.tile, item.tileBelow)
    if top == nil then
      top = normalizeItemTileIndex(item)
      if top ~= nil then
        top = top - (top % 2)
        bot = top + 1
      end
    end
    if top ~= nil then
      addTarget(out, seen, bank, top)
      addTarget(out, seen, bank, bot)
    end
    return
  end
  local idx = normalizeItemTileIndex(item)
  if idx ~= nil then
    addTarget(out, seen, bank, idx)
  end
end

local function collectSpriteSwapTargets(context)
  local layer = context.layer
  local out = {}
  local seen = {}
  local defaultBank = tonumber(context.sourceBank) or 1

  local indices = SpriteController.getSelectedSpriteIndices(layer)
  local useMulti = false
  if type(context.itemIndex) == "number" and #indices > 0 then
    for _, idx in ipairs(indices) do
      if idx == context.itemIndex then
        useMulti = true
        break
      end
    end
  end
  if not useMulti then
    if type(context.itemIndex) == "number" then
      indices = { context.itemIndex }
    elseif context.item then
      appendSpriteItemTargets(context.item, layer, defaultBank, out, seen)
      return (#out > 0) and out or nil
    else
      return nil
    end
  end

  for _, idx in ipairs(indices) do
    local item = layer.items and layer.items[idx]
    appendSpriteItemTargets(item, layer, defaultBank, out, seen)
  end
  if #out == 0 then
    return nil
  end
  return out
end

--- Bank/tileIndex pairs to mutate. Tile layers reuse revert multi-select rules;
--- sprite layers expand multi-sprite selection when the context item is included.
function M.collectSwapTargets(context)
  if not (context and context.layer) then
    return nil
  end
  if context.layer.kind == "sprite" then
    return collectSpriteSwapTargets(context)
  end
  return RevertTilePixelsController.collectTileRevertPairs(context)
end

--- Palette number (1..4) used to render the context item's color ramp.
function M.resolveContextPaletteNumber(context)
  local layer = context and context.layer
  local item = context and context.item
  if not layer then
    return 1
  end
  if layer.kind == "sprite" then
    local n = tonumber(item and item.paletteNumber)
    if type(n) == "number" and n >= 1 and n <= 4 then
      return math.floor(n)
    end
    return 1
  end
  if type(context.col) == "number" and type(context.row) == "number" and layer.paletteNumbers then
    local win = context.win
    local cols = (win and win.cols) or 1
    local idx0 = context.row * cols + context.col
    local n = tonumber(layer.paletteNumbers[idx0])
    if type(n) == "number" and n >= 1 and n <= 4 then
      return math.floor(n)
    end
  end
  return 1
end

--- Tile refs for modal preview of the right-clicked item only (not multi-select).
-- Returns { top = Tile?, bot = Tile?, mode = "8x8"|"8x16" }
function M.resolvePreviewTiles(app, context)
  local layer = context and context.layer
  local item = context and context.item
  if not layer then
    return nil
  end

  local state = app and app.appEditState
  local want16 = isContext8x16(context)

  if layer.kind == "sprite" then
    local bank = bankForSpriteItem(item, layer, context.sourceBank)
    local mode = want16 and "8x16" or "8x8"

    if item and item.topRef and item.topRef.pixels then
      local out = { top = item.topRef, mode = mode }
      if mode == "8x16" then
        if item.botRef and item.botRef.pixels then
          out.bot = item.botRef
        else
          local topIndex, botIndex = resolve8x16Pair(item.tile, item.tileBelow)
          if botIndex ~= nil and state then
            out.bot = BankViewController.getTileRef(state, bank, botIndex)
          end
        end
      end
      return out
    end

    local topIndex, botIndex
    if mode == "8x16" then
      topIndex, botIndex = resolve8x16Pair(item and item.tile, item and item.tileBelow)
    else
      topIndex = normalizeItemTileIndex(item)
    end
    if topIndex == nil or not state then
      return nil
    end
    local out = {
      top = BankViewController.getTileRef(state, bank, topIndex),
      mode = mode,
    }
    if mode == "8x16" and botIndex ~= nil then
      out.bot = BankViewController.getTileRef(state, bank, botIndex)
    end
    if not out.top then
      return nil
    end
    return out
  end

  -- Tile layers (CHR oddEven, pattern table 8x16, nametable, etc.)
  if want16 then
    local pair = resolveTileLayerPreviewPair(app, context)
    if pair and pair.top then
      return pair
    end
  end

  local bank = tonumber(item and item._bankIndex) or tonumber(context.sourceBank) or 1
  if item and item.pixels and #item.pixels == 64 then
    return { top = item, mode = "8x8" }
  end
  local topIndex = normalizeItemTileIndex(item) or tonumber(context.tileIndex)
  if topIndex == nil or not state then
    return nil
  end
  local top = BankViewController.getTileRef(state, bank, topIndex)
  if not top then
    return nil
  end
  return { top = top, mode = "8x8" }
end

local function remapPixelValue(value, a, b)
  if value == a then
    return b
  end
  if value == b then
    return a
  end
  return value
end

--- Apply index swap a<->b to a copied pixel table (does not mutate source).
function M.remapPixelsCopy(pixels, indexA, indexB)
  local a = clampIndex(indexA)
  local b = clampIndex(indexB)
  if not (pixels and a and b and a ~= b) then
    return nil
  end
  local out = {}
  for i = 1, 64 do
    out[i] = remapPixelValue(pixels[i] or 0, a, b)
  end
  return out
end

local function swapTileWithSync(tile, indexA, indexB, app, state, tilesPool, sourceWin, paintUndo)
  if not (tile and tile.pixels and type(tile.pixels) == "table" and #tile.pixels == 64) then
    return false
  end

  local bankIdx = tile._bankIndex
  local targets = ChrDuplicateSync.getSyncGroup(
    state,
    bankIdx,
    tile.index,
    ChrDuplicateSync.isEnabledForWindow(app, sourceWin)
  )
  if #targets == 0 then
    targets = {
      { bank = bankIdx, tileIndex = tile.index },
    }
  end

  local swappedAny = false
  for _, target in ipairs(targets) do
    local tRef = nil
    if tilesPool[target.bank] and tilesPool[target.bank][target.tileIndex] then
      tRef = tilesPool[target.bank][target.tileIndex]
    elseif target.bank == bankIdx and target.tileIndex == tile.index then
      tRef = tile
    end

    if tRef then
      local snap = nil
      if paintUndo and tRef.pixels and type(tRef._bankIndex) == "number" and type(tRef.index) == "number" then
        snap = {}
        for i = 1, 64 do
          snap[i] = tRef.pixels[i] or 0
        end
      end

      local swapped = false
      if tRef.swapPaletteIndices then
        swapped = tRef:swapPaletteIndices(indexA, indexB) == true
      end

      if snap and paintUndo and swapped and type(tRef._bankIndex) == "number" and type(tRef.index) == "number" then
        for iy = 0, 7 do
          for ix = 0, 7 do
            local i = iy * 8 + ix + 1
            local beforeV = snap[i] or 0
            local afterV = (tRef.pixels and tRef.pixels[i]) or 0
            if beforeV ~= afterV then
              paintUndo:recordPixelChange(tRef._bankIndex, tRef.index, ix, iy, beforeV, afterV)
            end
          end
        end
      end

      swappedAny = swappedAny or swapped
    end
  end

  if swappedAny and state then
    ChrDuplicateSync.updateTiles(state, targets)
  end
  return swappedAny
end

function M.canSwapContext(app, context)
  local pairs = M.collectSwapTargets(context)
  if not pairs or #pairs == 0 then
    return false
  end
  local preview = M.resolvePreviewTiles(app, context)
  return preview ~= nil and preview.top ~= nil
end

--- Apply a<->b swap to all collected targets. One paint undo event for the batch.
-- Returns ok, statusMessage
function M.applySwap(app, context, indexA, indexB, opts)
  opts = opts or {}
  local a = clampIndex(indexA)
  local b = clampIndex(indexB)
  if not (a and b and a ~= b) then
    return false, "Pick two different colors to swap"
  end

  local pairs = M.collectSwapTargets(context)
  if not pairs or #pairs == 0 then
    return false, "No tiles to swap"
  end

  local state = app and app.appEditState
  if not state then
    return false, "No app state"
  end

  local tilesPool = state.tilesPool or {}
  local undoRedo = app.undoRedo
  local sourceWin = context.win
  local swappedCount = 0

  if undoRedo and undoRedo.startPaintEvent then
    undoRedo:startPaintEvent()
  end

  for _, p in ipairs(pairs) do
    local tileRef = BankViewController.getTileRef(state, p.bank, p.tileIndex)
    if tileRef and swapTileWithSync(tileRef, a, b, app, state, tilesPool, sourceWin, undoRedo) then
      swappedCount = swappedCount + 1
    end
  end

  if swappedCount > 0 then
    if undoRedo and undoRedo.finishPaintEvent then
      undoRedo:finishPaintEvent()
    end
    if opts.setStatus ~= false then
      local msg
      if swappedCount > 1 then
        msg = string.format("Swapped colors %d↔%d on %d tiles", a, b, swappedCount)
      else
        msg = string.format("Swapped colors %d↔%d", a, b)
      end
      if opts.ctx then
        StatusHelpers.setStatus(opts.ctx, msg)
      elseif app and app.setStatus then
        app:setStatus(msg)
      end
    end
    return true, swappedCount
  end

  if undoRedo and undoRedo.cancelPaintEvent then
    undoRedo:cancelPaintEvent()
  end
  return false, "No pixels used those colors"
end

return M
