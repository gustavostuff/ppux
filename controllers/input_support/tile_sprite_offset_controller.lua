local chr = require("chr")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local GameArtController = require("controllers.game_art.game_art_controller")
local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local PIXEL_OFFSET_DEFAULTS = {
  wrap = false,  -- Non-wrapping by default; set true to wrap around tile edges.
  fillValue = 0,
}

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

local function materializeFocusTile(focus, item, layerIndex)
  if item == nil then
    return nil
  end
  if focus and focus.materializeTileHandle then
    local resolved = focus:materializeTileHandle(item, layerIndex)
    if resolved ~= nil then
      return resolved
    end
  end
  return item
end

local function ensureAppEdits(app)
  if not app then return nil end
  if type(app.edits) ~= "table" then
    app.edits = GameArtController.newEdits()
  end
  app.edits.banks = app.edits.banks or {}
  return app.edits
end

local function recordTileRefSnapshot(edits, tileRef, bankOverride, tileIndexOverride)
  if not (edits and tileRef and tileRef.pixels) then return end

  local bankIdx = bankOverride
  if type(bankIdx) ~= "number" then
    bankIdx = tileRef._bankIndex
  end

  local tileIdx = tileIndexOverride
  if type(tileIdx) ~= "number" then
    tileIdx = tileRef.index
  end

  if type(bankIdx) ~= "number" or type(tileIdx) ~= "number" then
    return
  end

  for y = 0, 7 do
    for x = 0, 7 do
      local idx = y * 8 + x + 1
      local pixel = tileRef.pixels[idx]
      if pixel == nil then pixel = 0 end
      GameArtController.recordEdit(edits, bankIdx, tileIdx, x, y, pixel)
    end
  end
end

local function offsetTileRefPixels(tileRef, dx, dy, opts)
  if tileRef and tileRef.offsetPixels then
    return tileRef:offsetPixels(dx, dy, opts)
  end
  if not (tileRef and tileRef.pixels and type(tileRef.pixels) == "table" and #tileRef.pixels == 64) then
    return false
  end

  opts = opts or {}
  local wrap = opts.wrap == true
  local fillValue = math.floor(tonumber(opts.fillValue) or 0)
  if fillValue < 0 then fillValue = 0 end
  if fillValue > 3 then fillValue = 3 end

  dx = math.floor(tonumber(dx) or 0)
  dy = math.floor(tonumber(dy) or 0)

  if dx == 0 and dy == 0 then
    return true
  end

  local source = tileRef.pixels
  local shifted = {}
  local tileW, tileH = 8, 8

  for y = 0, tileH - 1 do
    for x = 0, tileW - 1 do
      local sx = x - dx
      local sy = y - dy
      local value = fillValue

      if wrap then
        sx = ((sx % tileW) + tileW) % tileW
        sy = ((sy % tileH) + tileH) % tileH
        value = source[sy * tileW + sx + 1] or fillValue
      elseif sx >= 0 and sx < tileW and sy >= 0 and sy < tileH then
        value = source[sy * tileW + sx + 1] or fillValue
      end

      shifted[y * tileW + x + 1] = value
    end
  end

  for i = 1, tileW * tileH do
    tileRef.pixels[i] = shifted[i]
  end

  if tileRef.refreshImage then
    tileRef:refreshImage()
  end

  if tileRef._bankBytesRef and type(tileRef.index) == "number" then
    for y = 0, 7 do
      for x = 0, 7 do
        local idx = y * 8 + x + 1
        local pixelValue = tileRef.pixels[idx]
        if pixelValue then
          chr.setTilePixel(tileRef._bankBytesRef, tileRef.index, x, y, pixelValue)
        end
      end
    end
  end

  return true
end

local function writeTileRefPixelsToCHR(tileRef)
  if not (tileRef and tileRef._bankBytesRef and type(tileRef.index) == "number") then
    return
  end
  for y = 0, 7 do
    for x = 0, 7 do
      local idx = y * 8 + x + 1
      local pixelValue = tileRef.pixels and tileRef.pixels[idx]
      if pixelValue then
        chr.setTilePixel(tileRef._bankBytesRef, tileRef.index, x, y, pixelValue)
      end
    end
  end
end

local function resetTileRefOffsetState(tileRef)
  if not tileRef then return end
  tileRef._offsetStorage = nil
  tileRef._offsetViewportX = 0
  tileRef._offsetViewportY = 0
end

local function pairOffsetKey(x, y)
  return string.format("%d,%d", x, y)
end

local function getPairOffsetPixel(storage, x, y, fillValue)
  local value = storage and storage[pairOffsetKey(x, y)]
  if value == nil then
    return fillValue
  end
  return value
end

local function setPairOffsetPixel(storage, x, y, value, fillValue)
  if not storage then return end
  local key = pairOffsetKey(x, y)
  if value == fillValue then
    storage[key] = nil
  else
    storage[key] = value
  end
end

local function ensureSpritePairOffsetState(sprite, topRef, botRef, fillValue)
  local state = sprite and sprite._pixelOffset16State
  if state and state.topRef == topRef and state.botRef == botRef then
    return state
  end

  state = {
    topRef = topRef,
    botRef = botRef,
    ox = 0,
    oy = 0,
    pixels = {},
  }

  for y = 0, 7 do
    for x = 0, 7 do
      local topIdx = y * 8 + x + 1
      local botIdx = y * 8 + x + 1
      setPairOffsetPixel(state.pixels, x, y, (topRef.pixels and topRef.pixels[topIdx]) or fillValue, fillValue)
      setPairOffsetPixel(state.pixels, x, y + 8, (botRef.pixels and botRef.pixels[botIdx]) or fillValue, fillValue)
    end
  end

  if sprite then
    sprite._pixelOffset16State = state
  end
  return state
end

local function syncVisibleWindowToSpritePairState(state, topRef, botRef, fillValue)
  if not state then return end
  local ox = state.ox or 0
  local oy = state.oy or 0

  for y = 0, 7 do
    for x = 0, 7 do
      local topIdx = y * 8 + x + 1
      local botIdx = y * 8 + x + 1
      setPairOffsetPixel(state.pixels, x - ox, y - oy, (topRef.pixels and topRef.pixels[topIdx]) or fillValue, fillValue)
      setPairOffsetPixel(state.pixels, x - ox, (y + 8) - oy, (botRef.pixels and botRef.pixels[botIdx]) or fillValue, fillValue)
    end
  end
end

local function renderSpritePairStateToTileRefs(state, topRef, botRef, fillValue)
  if not state then return end
  local ox = state.ox or 0
  local oy = state.oy or 0

  topRef.pixels = topRef.pixels or {}
  botRef.pixels = botRef.pixels or {}

  for y = 0, 15 do
    for x = 0, 7 do
      local value = getPairOffsetPixel(state.pixels, x - ox, y - oy, fillValue)
      if y < 8 then
        topRef.pixels[y * 8 + x + 1] = value
      else
        botRef.pixels[(y - 8) * 8 + x + 1] = value
      end
    end
  end
end

local function offsetSprite8x16Pixels(sprite, dx, dy, opts)
  local topRef = sprite and sprite.topRef
  local botRef = sprite and sprite.botRef
  if not (topRef and botRef and topRef.pixels and botRef.pixels) then
    return false
  end

  opts = opts or {}
  local fillValue = math.floor(tonumber(opts.fillValue) or 0)
  if fillValue < 0 then fillValue = 0 end
  if fillValue > 3 then fillValue = 3 end

  local state = ensureSpritePairOffsetState(sprite, topRef, botRef, fillValue)
  syncVisibleWindowToSpritePairState(state, topRef, botRef, fillValue)

  state.ox = (state.ox or 0) + dx
  state.oy = (state.oy or 0) + dy

  renderSpritePairStateToTileRefs(state, topRef, botRef, fillValue)

  resetTileRefOffsetState(topRef)
  resetTileRefOffsetState(botRef)

  if topRef.refreshImage then topRef:refreshImage() end
  if botRef.refreshImage then botRef:refreshImage() end
  writeTileRefPixelsToCHR(topRef)
  writeTileRefPixelsToCHR(botRef)

  return true
end

local function copyTileRefPixels(sourceRef, targetRef)
  if not (sourceRef and targetRef and sourceRef.pixels and targetRef.pixels) then
    return false
  end

  for i = 1, 64 do
    targetRef.pixels[i] = sourceRef.pixels[i] or 0
  end

  if targetRef.refreshImage then
    targetRef:refreshImage()
  end
  writeTileRefPixelsToCHR(targetRef)
  return true
end

local function offsetTileRefPairPixels(topRef, botRef, dx, dy, opts)
  if not (topRef and botRef and topRef.pixels and botRef.pixels) then
    return false
  end

  opts = opts or {}
  local wrap = opts.wrap == true
  local fillValue = math.floor(tonumber(opts.fillValue) or 0)
  if fillValue < 0 then fillValue = 0 end
  if fillValue > 3 then fillValue = 3 end

  dx = math.floor(tonumber(dx) or 0)
  dy = math.floor(tonumber(dy) or 0)

  if dx == 0 and dy == 0 then
    return true
  end

  local source = {}
  for y = 0, 15 do
    for x = 0, 7 do
      local value = fillValue
      if y < 8 then
        value = (topRef.pixels and topRef.pixels[y * 8 + x + 1]) or fillValue
      else
        value = (botRef.pixels and botRef.pixels[(y - 8) * 8 + x + 1]) or fillValue
      end
      source[y * 8 + x + 1] = value
    end
  end

  local shifted = {}
  local pairW, pairH = 8, 16
  for y = 0, pairH - 1 do
    for x = 0, pairW - 1 do
      local sx = x - dx
      local sy = y - dy
      local value = fillValue

      if wrap then
        sx = ((sx % pairW) + pairW) % pairW
        sy = ((sy % pairH) + pairH) % pairH
        value = source[sy * pairW + sx + 1] or fillValue
      elseif sx >= 0 and sx < pairW and sy >= 0 and sy < pairH then
        value = source[sy * pairW + sx + 1] or fillValue
      end

      shifted[y * pairW + x + 1] = value
    end
  end

  for y = 0, 15 do
    for x = 0, 7 do
      local value = shifted[y * 8 + x + 1]
      if y < 8 then
        topRef.pixels[y * 8 + x + 1] = value
      else
        botRef.pixels[(y - 8) * 8 + x + 1] = value
      end
    end
  end

  if topRef.refreshImage then topRef:refreshImage() end
  if botRef.refreshImage then botRef:refreshImage() end
  writeTileRefPixelsToCHR(topRef)
  writeTileRefPixelsToCHR(botRef)
  return true
end

local function isChr8x16Mode(win)
  return WindowCaps.isChrLike(win) and win.orderMode == "oddEven"
end

function M.handleKey(key, focus, ctx, utils)
  if key ~= "left" and key ~= "right" and key ~= "up" and key ~= "down" then
    return false
  end
  if not (utils and utils.altDown and utils.altDown()) then return false end
  if utils.ctrlDown and utils.ctrlDown() then return false end
  if ctx.getMode() == "edit" then return false end
  if not focus or focus.isPalette then return false end
  if not (focus.layers and focus.getActiveLayerIndex) then return false end

  local dx, dy = 0, 0
  if key == "left" then dx = -1
  elseif key == "right" then dx = 1
  elseif key == "up" then dy = -1
  elseif key == "down" then dy = 1
  end

  local li = focus:getActiveLayerIndex()
  local layer = focus.layers[li]
  if not layer then return false end

  local directionLabel = key
  local app = ctx.app
  local state = app and app.appEditState
  local tilesPool = state and state.tilesPool or {}
  local changedTileRefs = {}
  local changedTileRefKeys = {}

  local function markChangedTileRef(tileRef, bankOverride, tileIndexOverride)
    if not tileRef then return end
    local bankIdx = bankOverride
    if type(bankIdx) ~= "number" then bankIdx = tileRef._bankIndex end
    local tileIdx = tileIndexOverride
    if type(tileIdx) ~= "number" then tileIdx = tileRef.index end
    if type(bankIdx) ~= "number" or type(tileIdx) ~= "number" then return end

    local keyId = string.format("%d:%d", bankIdx, tileIdx)
    if changedTileRefKeys[keyId] then return end
    changedTileRefKeys[keyId] = true
    changedTileRefs[#changedTileRefs + 1] = {
      tileRef = tileRef,
      bank = bankIdx,
      tileIndex = tileIdx,
    }
  end

  local function recordChangedTilesToEdits()
    local edits = ensureAppEdits(app)
    if not edits then return end
    for _, entry in ipairs(changedTileRefs) do
      recordTileRefSnapshot(edits, entry.tileRef, entry.bank, entry.tileIndex)
    end
  end

  if layer.kind == "tile" then
    if not (focus.getSelected and focus.get) then return false end
    local col, row, selectedLayer = focus:getSelected()
    if selectedLayer and selectedLayer ~= li then return false end
    local success = false
    local changedUnitsCount = 0

    local function offsetTileWithSync(tile)
      if not tile then return false end

      local tileChanged = false
      local targets = {}
      local bankIdx = tile._bankIndex
      local tileIdx = tile.index
      if type(bankIdx) == "number" and type(tileIdx) == "number" then
        targets = ChrDuplicateSync.getSyncGroup(state, bankIdx, tileIdx, ChrDuplicateSync.isEnabledForWindow(app, focus))
      end

      if #targets > 0 then
        for _, target in ipairs(targets) do
          local poolBank = tilesPool[target.bank]
          local tRef = poolBank and poolBank[target.tileIndex] or nil
          if (not tRef) and target.bank == bankIdx and target.tileIndex == tileIdx then
            tRef = tile
          end
          if tRef and offsetTileRefPixels(tRef, dx, dy, PIXEL_OFFSET_DEFAULTS) then
            success = true
            tileChanged = true
            markChangedTileRef(tRef, target.bank, target.tileIndex)
          end
        end
        if tileChanged and state then
          ChrDuplicateSync.updateTiles(state, targets)
        end
      else
        tileChanged = offsetTileRefPixels(tile, dx, dy, PIXEL_OFFSET_DEFAULTS)
        if tileChanged then
          success = true
          markChangedTileRef(tile, bankIdx, tileIdx)
        end
      end

      return tileChanged
    end

    if isChr8x16Mode(focus) then
      local pairs = MultiSelectController.getSelectedChr8x16Pairs(focus, li, col, row)
      if not pairs or #pairs == 0 then return false end

      local function propagateTileRefToSyncGroup(tileRef)
        if not tileRef then return false end
        local bankIdx = tileRef._bankIndex
        local tileIdx = tileRef.index
        local targets = {}
        if type(bankIdx) == "number" and type(tileIdx) == "number" then
          targets = ChrDuplicateSync.getSyncGroup(state, bankIdx, tileIdx, ChrDuplicateSync.isEnabledForWindow(app, focus))
        end

        local propagated = false
        if #targets > 0 then
          for _, target in ipairs(targets) do
            local poolBank = tilesPool[target.bank]
            local tRef = poolBank and poolBank[target.tileIndex] or nil
            if (not tRef) and target.bank == bankIdx and target.tileIndex == tileIdx then
              tRef = tileRef
            end
            if tRef then
              if tRef ~= tileRef then
                copyTileRefPixels(tileRef, tRef)
              end
              markChangedTileRef(tRef, target.bank, target.tileIndex)
              propagated = true
            end
          end
          if propagated and state then
            ChrDuplicateSync.updateTiles(state, targets)
          end
        else
          markChangedTileRef(tileRef, bankIdx, tileIdx)
        end

        return true
      end

      for _, pair in ipairs(pairs) do
        local topItem = materializeFocusTile(focus, pair.topItem, li)
        local bottomItem = materializeFocusTile(focus, pair.bottomItem, li)
        local pairChanged = false
        if topItem and bottomItem then
          pairChanged = offsetTileRefPairPixels(topItem, bottomItem, dx, dy, PIXEL_OFFSET_DEFAULTS)
          if pairChanged then
            success = true
            propagateTileRefToSyncGroup(topItem)
            propagateTileRefToSyncGroup(bottomItem)
          end
        else
          for _, tile in ipairs({ topItem, bottomItem }) do
            pairChanged = offsetTileWithSync(tile) or pairChanged
          end
        end
        if pairChanged then
          changedUnitsCount = changedUnitsCount + 1
        end
      end
    else
      local cells = nil
      if WindowCaps.isChrLike(focus) then
        cells = MultiSelectController.getSelectedTileCells(focus, li, col, row)
      end
      if not cells or #cells == 0 then
        if not (col and row) then return false end
        cells = { { col = col, row = row } }
      end

      for _, cell in ipairs(cells) do
        local tile = focus:get(cell.col, cell.row, li)
        if offsetTileWithSync(tile) then
          changedUnitsCount = changedUnitsCount + 1
        end
      end
    end

    if success then
      recordChangedTilesToEdits()
      if app and app.markUnsaved then
        app:markUnsaved("pixel_edit")
      end
      if changedUnitsCount > 1 then
        local unitLabel = isChr8x16Mode(focus) and "items" or "tiles"
        setStatus(ctx, string.format("Offset pixels on %d %s %s", changedUnitsCount, unitLabel, directionLabel))
      else
        setStatus(ctx, string.format("Offset tile pixels %s", directionLabel))
      end
      return true
    end
    return false
  end

  if layer.kind == "sprite" then
    local SpriteController = require("controllers.sprite.sprite_controller")
    local selected = SpriteController.getSelectedSpriteIndices(layer)
    if (#selected == 0) and layer.selectedSpriteIndex then
      selected = { layer.selectedSpriteIndex }
    end
    if #selected == 0 then return false end

    local mode = layer.mode or "8x8"
    local selectedSpritesCount = 0

    local changedTargets = {}
    local changedTargetSet = {}
    local function addChangedTarget(bank, tileIndex)
      if type(bank) ~= "number" or type(tileIndex) ~= "number" then return end
      local keyId = string.format("%d:%d", bank, tileIndex)
      if changedTargetSet[keyId] then return end
      changedTargetSet[keyId] = true
      changedTargets[#changedTargets + 1] = { bank = bank, tileIndex = tileIndex }
    end

    local function addTileRefTargetAndGroup(targets, targetSet, fallbackRefs, tileRef)
      if not tileRef then return end
      local bank = tileRef._bankIndex
      local tileIndex = tileRef.index
      if type(bank) ~= "number" or type(tileIndex) ~= "number" then return end

      local keyId = string.format("%d:%d", bank, tileIndex)
      fallbackRefs[keyId] = fallbackRefs[keyId] or tileRef

      local group = ChrDuplicateSync.getSyncGroup(state, bank, tileIndex, ChrDuplicateSync.isEnabledForWindow(app, focus))
      if #group == 0 then
        if not targetSet[keyId] then
          targetSet[keyId] = true
          targets[#targets + 1] = { bank = bank, tileIndex = tileIndex }
        end
      else
        for _, target in ipairs(group) do
          local tKey = string.format("%d:%d", target.bank, target.tileIndex)
          if not targetSet[tKey] then
            targetSet[tKey] = true
            targets[#targets + 1] = { bank = target.bank, tileIndex = target.tileIndex }
          end
        end
      end
    end

    local changed = false
    local items = layer.items or {}
    if mode == "8x16" then
      local processedPairs = {}
      local function pairAlreadyProcessed(topRef, botRef)
        processedPairs[topRef] = processedPairs[topRef] or {}
        if processedPairs[topRef][botRef] then return true end
        processedPairs[topRef][botRef] = true
        return false
      end

      for _, idx in ipairs(selected) do
        local sprite = items[idx]
        if sprite and sprite.removed ~= true then
          selectedSpritesCount = selectedSpritesCount + 1
          if sprite.topRef and sprite.botRef and not pairAlreadyProcessed(sprite.topRef, sprite.botRef) then
            if offsetSprite8x16Pixels(sprite, dx, dy, PIXEL_OFFSET_DEFAULTS) then
              changed = true
              addChangedTarget(sprite.topRef._bankIndex, sprite.topRef.index)
              addChangedTarget(sprite.botRef._bankIndex, sprite.botRef.index)
              markChangedTileRef(sprite.topRef)
              markChangedTileRef(sprite.botRef)
            end
          end
        end
      end
    else
      local targets = {}
      local targetSet = {}
      local fallbackRefs = {}

      for _, idx in ipairs(selected) do
        local sprite = items[idx]
        if sprite and sprite.removed ~= true then
          selectedSpritesCount = selectedSpritesCount + 1
          addTileRefTargetAndGroup(targets, targetSet, fallbackRefs, sprite.topRef)
          addTileRefTargetAndGroup(targets, targetSet, fallbackRefs, sprite.botRef)
        end
      end

      if #targets > 0 then
        for _, target in ipairs(targets) do
          local keyId = string.format("%d:%d", target.bank, target.tileIndex)
          local poolBank = tilesPool[target.bank]
          local tRef = (poolBank and poolBank[target.tileIndex]) or fallbackRefs[keyId]
          if tRef and offsetTileRefPixels(tRef, dx, dy, PIXEL_OFFSET_DEFAULTS) then
            changed = true
            addChangedTarget(target.bank, target.tileIndex)
            markChangedTileRef(tRef, target.bank, target.tileIndex)
          end
        end
      end
    end

    if not changed then return false end
    recordChangedTilesToEdits()
    if state and #changedTargets > 0 then
      ChrDuplicateSync.updateTiles(state, changedTargets)
    end
    if app and app.markUnsaved then
      app:markUnsaved("pixel_edit")
    end

    if selectedSpritesCount > 1 then
      setStatus(ctx, string.format("Offset pixels on %d sprites %s", selectedSpritesCount, directionLabel))
    else
      setStatus(ctx, string.format("Offset sprite pixels %s", directionLabel))
    end
    return true
  end

  return false
end

return M
