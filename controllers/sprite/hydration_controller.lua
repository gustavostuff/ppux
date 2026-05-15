-- sprite_hydration_controller.lua
-- Sprite layer hydration and project snapshot/reapply helpers.

local chr = require("chr")
local Tile = require("user_interface.windows_system.tile_item")
local TableUtils = require("utils.table_utils")
local PatternTableMapping = require("utils.pattern_table_mapping")

local M = {}

local function resolve8x16Pair(tileIndex, tileBelow)
  local topIndex = tonumber(tileIndex)
  if type(topIndex) ~= "number" then return nil, nil end
  topIndex = math.floor(topIndex)

  local belowIndex = tonumber(tileBelow)
  if type(belowIndex) == "number" then
    belowIndex = math.floor(belowIndex)
    return topIndex, belowIndex
  end

  -- NES 8x16 sprite selection uses bit 0 to select the pattern table.
  -- The top tile index is always even, with the bottom tile at +1.
  topIndex = topIndex - (topIndex % 2)
  return topIndex, topIndex + 1
end

-- NES 8x16 OAM uses an even logical pattern index (0–255) with the bottom half at +1.
local function resolve8x16PairLogical(tileIndex, tileBelow)
  local topIdx = tonumber(tileIndex)
  if type(topIdx) ~= "number" then
    return nil, nil
  end
  topIdx = math.floor(topIdx % 256)
  if topIdx < 0 then topIdx = topIdx + 256 end

  local belowIdx = tonumber(tileBelow)
  if type(belowIdx) == "number" then
    belowIdx = math.floor(belowIdx % 256)
    if belowIdx < 0 then belowIdx = belowIdx + 256 end
    -- Duplicate / useless bottom index (often stale after switching to pattern-table OAM sprites):
    -- would map both halves to the same logical slot and repeat the top CHR.
    if belowIdx ~= topIdx then
      return topIdx, belowIdx
    end
  end

  local evenTop = topIdx - (topIdx % 2)
  local botLogical = evenTop + 1
  if botLogical > 255 then
    botLogical = 255
  end
  return evenTop, botLogical
end

local function getAppEditStateHint(overrideState)
  if overrideState then return overrideState end
  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app or nil
  return app and app.appEditState or nil
end

local function resolveTileRef(tilesPool, appEditState, bankIndex, tileIndex)
  if type(bankIndex) ~= "number" or type(tileIndex) ~= "number" then
    return nil
  end

  tilesPool[bankIndex] = tilesPool[bankIndex] or {}
  local bankPool = tilesPool[bankIndex]
  if bankPool[tileIndex] then
    return bankPool[tileIndex]
  end

  local state = getAppEditStateHint(appEditState)
  local bankBytes = state and state.chrBanksBytes and state.chrBanksBytes[bankIndex] or nil
  if not bankBytes then
    return nil
  end

  local created = Tile.fromCHR(bankBytes, tileIndex)
  created._bankBytesRef = bankBytes
  created._bankIndex = bankIndex
  bankPool[tileIndex] = created
  return created
end

-- Resolve tile refs: CHR/bank path uses tilesPool[bank][tileIndex] only when ROM OAM sprites have no
-- valid layer pattern map (legacy). Normal OAM + pattern-table layers: ROM byte 2 is the logical
-- pattern-table index (same 256-slot ordering as populateTileLayerItemsFromPatternTable).
function M.ensureTileRefsForSpriteItem(item, layerMode, tilesPool, appEditState, layer)
  if not (item and tilesPool) then
    return
  end

  local usePatternTable = type(item.startAddr) == "number"
      and layer ~= nil
      and PatternTableMapping.validate(layer.patternTable)

  if usePatternTable then
    if layerMode == "8x16" then
      local pairBelow =
        (type(item.startAddr) ~= "number") and item.tileBelow or nil
      local topLogical, botLogical = resolve8x16PairLogical(item.tile, pairBelow)
      if topLogical == nil then
        item.topRef = nil
        item.botRef = nil
        return
      end
      item.tile = topLogical
      item.tileBelow = botLogical
      item.topRef = select(1, PatternTableMapping.resolveTile(tilesPool, layer, topLogical))
      item.botRef = select(1, PatternTableMapping.resolveTile(tilesPool, layer, botLogical))
    else
      local lg = tonumber(item.tile) or 0
      lg = math.floor(lg % 256)
      if lg < 0 then lg = lg + 256 end
      item.tile = lg
      item.tileBelow = nil
      item.topRef = select(1, PatternTableMapping.resolveTile(tilesPool, layer, lg))
      item.botRef = nil
    end
    return
  end

  if not (item.bank and item.tile) then
    return
  end

  if layerMode == "8x16" then
    local topIndex, belowIndex = resolve8x16Pair(item.tile, item.tileBelow)
    if topIndex == nil then
      item.topRef = nil
      item.botRef = nil
      return
    end
    item.tile = topIndex
    item.tileBelow = belowIndex
    item.topRef = resolveTileRef(tilesPool, appEditState, item.bank, topIndex)
    item.botRef = resolveTileRef(tilesPool, appEditState, item.bank, belowIndex)
  else
    item.topRef = resolveTileRef(tilesPool, appEditState, item.bank, item.tile)
    item.botRef = nil
  end
end

function M.hydrateSpriteLayer(layer, opts)
  if not layer or layer.kind ~= "sprite" then return end
  opts = opts or {}
  local romRaw = opts.romRaw or ""
  local tilesPool = opts.tilesPool
  local keepWorld = opts.keepWorld

  local items = layer.items or {}
  local mode = layer.mode or "8x8"

  for _, s in ipairs(items) do
    if type(s.startAddr) == "number" then
      if s._mirrorXOverrideSet == nil then
        s._mirrorXOverrideSet = false
      end
      if s._mirrorYOverrideSet == nil then
        s._mirrorYOverrideSet = false
      end

      local bytes = chr.readBytesFromRange(romRaw, s.startAddr, s.startAddr + 3)
      if bytes and #bytes >= 4 then
        local baseY = bytes[1] or 0
        local baseTile = bytes[2] or 0
        local attr = bytes[3] or 0
        local baseX = bytes[4] or 0

        local palNumFromLayout = s.paletteNumber
        local palNumFromAttr = (attr % 4) + 1
        local palNum = palNumFromLayout or palNumFromAttr
        local mirrorXFromAttr = (math.floor(attr / 64) % 2) == 1
        local mirrorYFromAttr = (math.floor(attr / 128) % 2) == 1
        local mirrorX = mirrorXFromAttr
        local mirrorY = mirrorYFromAttr

        -- For OAM-backed sprites, explicit project mirror flags (true or false)
        -- are authoritative UI overrides when present; otherwise we reflect ROM.
        if s._mirrorXOverrideSet == true and s.mirrorX ~= nil then
          mirrorX = (s.mirrorX == true)
        end
        if s._mirrorYOverrideSet == true and s.mirrorY ~= nil then
          mirrorY = (s.mirrorY == true)
        end

        s.baseX = baseX
        s.baseY = baseY
        s.oamTile = baseTile
        local layerPtOk = PatternTableMapping.validate(layer.patternTable)
        if layerPtOk then
          -- Stale `{ bank, tile }` from Lua / old projects must not drive CHR once a sprite layer
          -- pattern map exists — ROM byte 2 selects the mapped tile grid slot.
          s.bank = nil
          s.tile = baseTile
          -- OAM only carries one tile byte; an explicit leftover `tileBelow` from CHR / layout can
          -- duplicate the top logical index in 8x16 + pattern-table mode (both halves resolve same).
          if mode == "8x16" then
            s.tileBelow = nil
          end
        else
          if s.bank == nil then
            s.tile = baseTile
          elseif s.tile == nil then
            s.tile = baseTile
          end
        end
        s.attr = attr
        s.paletteNumber = palNum
        s.mirrorX = mirrorX
        s.mirrorY = mirrorY

        local dx = s.dx or 0
        local dy = s.dy or 0
        if keepWorld and s.worldX and s.worldY then
          dx = s.worldX - baseX
          dy = s.worldY - baseY
        end

        s.dx = dx
        s.dy = dy

        local worldX = baseX + dx
        local worldY = baseY + dy

        s.worldX = worldX
        s.worldY = worldY
        s.x = worldX
        s.y = worldY
        s.hasMoved = (dx ~= 0 or dy ~= 0)
      end
    elseif (s.x ~= nil or s.y ~= nil) and not s.startAddr then
      local worldX = s.x or 0
      local worldY = s.y or 0

      s.worldX = worldX
      s.worldY = worldY
      s.baseX = worldX
      s.baseY = worldY
      s.x = worldX
      s.y = worldY
      s.dx = 0
      s.dy = 0
      s.hasMoved = false
    end

    M.ensureTileRefsForSpriteItem(s, mode, tilesPool, opts.appEditState, layer)

    if s.mirrorX == nil then s.mirrorX = false end
    if s.mirrorY == nil then s.mirrorY = false end
  end
end

function M.hydrateWindowSpriteLayers(win, opts)
  if not win or not win.layers then return end
  for _, info in ipairs(win:getSpriteLayers()) do
    M.hydrateSpriteLayer(info.layer, opts)
  end
end

function M.snapshotSpriteLayer(layer)
  if not (layer and layer.kind == "sprite") then return nil end

  local out = {
    name = layer.name,
    kind = "sprite",
    opacity = (layer.opacity ~= nil) and layer.opacity or 1.0,
    mode = layer.mode,
    originX = layer.originX,
    originY = layer.originY,
    items = {},
  }

  for _, s in ipairs(layer.items or {}) do
    if s.removed == true then
      goto continue
    end

    local entry = {
      paletteNumber = s.paletteNumber,
    }

    if s.startAddr then
      entry.startAddr = s.startAddr
      if s.bank ~= nil then
        entry.bank = s.bank
        entry.tile = s.tile
      end
      if s._mirrorXOverrideSet == true then
        entry.mirrorX = (s.mirrorX == true)
      end
      if s._mirrorYOverrideSet == true then
        entry.mirrorY = (s.mirrorY == true)
      end
      local dx = s.dx or 0
      local dy = s.dy or 0
      if dx ~= 0 or dy ~= 0 then
        entry.dx = dx
        entry.dy = dy
      end
    else
      entry.bank = s.bank
      entry.tile = s.tile
      entry.mirrorX = (s.mirrorX ~= nil) and s.mirrorX or nil
      entry.mirrorY = (s.mirrorY ~= nil) and s.mirrorY or nil
      entry.x = s.x or s.worldX or 0
      entry.y = s.y or s.worldY or 0
    end

    table.insert(out.items, entry)
    ::continue::
  end

  local linkedPt =
    type(layer.linkedPatternTableWindowId) == "string" and layer.linkedPatternTableWindowId ~= ""

  if linkedPt then
    out.linkedPatternTableWindowId = layer.linkedPatternTableWindowId
  elseif type(layer.patternTable) == "table" then
    out.patternTable = TableUtils.deepcopy(layer.patternTable)
  end

  return out
end

function M.applySnapshotToSpriteLayer(layer, snapshot, opts)
  if not (layer and snapshot and layer.kind == "sprite" and snapshot.kind == "sprite") then
    return
  end

  layer.originX = snapshot.originX
  layer.originY = snapshot.originY
  layer.mode = snapshot.mode or layer.mode

  if snapshot.paletteData ~= nil then
    local TableUtils = require("utils.table_utils")
    layer.paletteData = TableUtils.deepcopy(snapshot.paletteData)
  end

  if type(snapshot.linkedPatternTableWindowId) == "string" and snapshot.linkedPatternTableWindowId ~= "" then
    layer.linkedPatternTableWindowId = snapshot.linkedPatternTableWindowId
  else
    layer.linkedPatternTableWindowId = nil
  end
  if snapshot.patternTable ~= nil then
    local TableUtils = require("utils.table_utils")
    layer.patternTable = TableUtils.deepcopy(snapshot.patternTable)
  end

  local romRaw = opts and opts.romRaw or ""
  local tilesPool = opts and opts.tilesPool

  local items = layer.items or {}
  for idx, entry in ipairs(snapshot.items or {}) do
    local s = items[idx]
    if s then
      s.bank = entry.bank
      s.tile = entry.tile
      s.tileBelow = nil
      s.paletteNumber = entry.paletteNumber
      s._mirrorXOverrideSet = (entry.mirrorX ~= nil)
      s._mirrorYOverrideSet = (entry.mirrorY ~= nil)
      s.mirrorX = entry.mirrorX
      s.mirrorY = entry.mirrorY

      if entry.startAddr then
        s.startAddr = entry.startAddr
        s.dx = entry.dx or 0
        s.dy = entry.dy or 0
      else
        s.startAddr = nil
        s.x = entry.x or 0
        s.y = entry.y or 0
      end
    else
      if entry.startAddr then
        s = {
          startAddr = entry.startAddr,
          bank = entry.bank,
          tile = entry.tile,
          paletteNumber = entry.paletteNumber,
          mirrorX = entry.mirrorX,
          mirrorY = entry.mirrorY,
          _mirrorXOverrideSet = (entry.mirrorX ~= nil),
          _mirrorYOverrideSet = (entry.mirrorY ~= nil),
          dx = entry.dx or 0,
          dy = entry.dy or 0,
        }
      else
        s = {
          bank = entry.bank,
          tile = entry.tile,
          paletteNumber = entry.paletteNumber,
          mirrorX = (entry.mirrorX ~= nil) and entry.mirrorX or false,
          mirrorY = (entry.mirrorY ~= nil) and entry.mirrorY or false,
          x = entry.x or 0,
          y = entry.y or 0,
        }
      end
      items[idx] = s
    end
  end
  layer.items = items

  M.hydrateSpriteLayer(layer, {
    romRaw = romRaw,
    tilesPool = tilesPool,
    appEditState = opts and opts.appEditState or nil,
    keepWorld = false,
  })
end

return M
