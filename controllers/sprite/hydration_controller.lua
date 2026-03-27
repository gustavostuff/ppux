-- sprite_hydration_controller.lua
-- Sprite layer hydration and project snapshot/reapply helpers.

local chr = require("chr")

local M = {}

-- Resolve tile references for a sprite item using tilesPool[bank][tileIndex]
function M.ensureTileRefsForSpriteItem(item, layerMode, tilesPool)
  if not (item and item.bank and item.tile and tilesPool) then return end
  local pool = tilesPool[item.bank]
  if not pool then return end

  item.topRef = pool[item.tile]

  if layerMode == "8x16" then
    local belowIndex = item.tileBelow or (item.tile + 1)
    item.tileBelow = belowIndex
    item.botRef = pool[belowIndex]
  else
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
      local bytes = chr.readBytesFromRange(romRaw, s.startAddr, s.startAddr + 3)
      if bytes and #bytes >= 4 then
        local baseY = bytes[1] or 0
        local baseTile = bytes[2] or 0
        local attr = bytes[3] or 0
        local baseX = bytes[4] or 0

        local palNumFromLayout = s.paletteNumber
        local palNumFromAttr = (attr % 4) + 1
        local palNum = palNumFromLayout or palNumFromAttr

        s.baseX = baseX
        s.baseY = baseY
        s.oamTile = baseTile
        if s.tile == nil then
          s.tile = baseTile
        end
        if mode == "8x16" and s.tileBelow == nil and s.tile ~= nil then
          s.tileBelow = s.tile + 1
        end
        s.attr = attr
        s.paletteNumber = palNum

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

    M.ensureTileRefsForSpriteItem(s, mode, tilesPool)

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
      bank = s.bank,
      tile = s.tile,
      paletteNumber = s.paletteNumber,
      mirrorX = (s.mirrorX ~= nil) and s.mirrorX or nil,
      mirrorY = (s.mirrorY ~= nil) and s.mirrorY or nil,
    }

    if s.startAddr then
      entry.startAddr = s.startAddr
      local dx = s.dx or 0
      local dy = s.dy or 0
      if dx ~= 0 or dy ~= 0 then
        entry.dx = dx
        entry.dy = dy
      end
    else
      entry.x = s.x or s.worldX or 0
      entry.y = s.y or s.worldY or 0
    end

    table.insert(out.items, entry)
    ::continue::
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
      s.mirrorX = (entry.mirrorX ~= nil) and entry.mirrorX or false
      s.mirrorY = (entry.mirrorY ~= nil) and entry.mirrorY or false

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
          mirrorX = (entry.mirrorX ~= nil) and entry.mirrorX or false,
          mirrorY = (entry.mirrorY ~= nil) and entry.mirrorY or false,
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
    keepWorld = false,
  })
end

return M
