local SpriteTransformController = {}
local WindowCaps = require("controllers.window.window_capabilities")

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function mergePaletteIntoAttr(attr, paletteNumber)
  attr = clamp(attr or 0, 0, 255)
  if not paletteNumber then return attr end
  local palBits = (math.floor(paletteNumber) - 1) % 4
  return (attr - (attr % 4)) + palBits
end

local function applyMirrorToAttr(attr, mirrorX, mirrorY)
  attr = clamp(attr or 0, 0, 255)
  local function setBit(byte, bitIndex, on)
    local pow = 2 ^ bitIndex
    local cur = math.floor(byte / pow) % 2
    if on and cur == 0 then
      byte = byte + pow
    elseif (not on) and cur == 1 then
      byte = byte - pow
    end
    return byte
  end
  if mirrorX ~= nil then
    attr = setBit(attr, 6, mirrorX and true or false)
  end
  if mirrorY ~= nil then
    attr = setBit(attr, 7, mirrorY and true or false)
  end
  return attr
end

local function getSpriteWorldPosition(sprite)
  local worldX = sprite.worldX
  if worldX == nil then worldX = sprite.baseX end
  if worldX == nil then worldX = sprite.x end
  if worldX == nil then worldX = 0 end

  local worldY = sprite.worldY
  if worldY == nil then worldY = sprite.baseY end
  if worldY == nil then worldY = sprite.y end
  if worldY == nil then worldY = 0 end

  return worldX, worldY
end

local function setSpriteWorldPosition(sprite, worldX, worldY)
  worldX = math.floor((worldX or 0) + 0.5)
  worldY = math.floor((worldY or 0) + 0.5)
  sprite.worldX = worldX
  sprite.worldY = worldY
  sprite.x = worldX
  sprite.y = worldY

  local baseX = sprite.baseX
  if baseX == nil then baseX = worldX end
  local baseY = sprite.baseY
  if baseY == nil then baseY = worldY end

  local dx = worldX - baseX
  local dy = worldY - baseY
  sprite.dx = dx
  sprite.dy = dy
  sprite.hasMoved = (dx ~= 0 or dy ~= 0)
end

local function normalizeOAMAttrFromSpriteState(sprite)
  if not sprite then return end
  local attr = tonumber(sprite.attr) or 0
  attr = math.floor(attr)
  attr = mergePaletteIntoAttr(attr, sprite.paletteNumber)
  attr = applyMirrorToAttr(attr, sprite.mirrorX, sprite.mirrorY)
  sprite.attr = attr
end

local function syncSharedOAMFieldsIntoTarget(target, source, opts)
  if not (target and source) then return end
  opts = opts or {}

  local syncPosition = (opts.syncPosition ~= false)
  local syncVisual = (opts.syncVisual ~= false)
  local syncAttr = (opts.syncAttr ~= false)

  if syncPosition then
    local dx = math.floor(tonumber(source.dx) or 0)
    local dy = math.floor(tonumber(source.dy) or 0)
    target.dx = dx
    target.dy = dy

    local baseX = target.baseX
    if baseX == nil then
      baseX = source.baseX
      if baseX == nil then
        local currentX = target.worldX
        if currentX == nil then currentX = target.x end
        if currentX == nil then currentX = 0 end
        baseX = currentX - dx
      end
    end

    local baseY = target.baseY
    if baseY == nil then
      baseY = source.baseY
      if baseY == nil then
        local currentY = target.worldY
        if currentY == nil then currentY = target.y end
        if currentY == nil then currentY = 0 end
        baseY = currentY - dy
      end
    end

    local worldX = math.floor((baseX + dx) + 0.5)
    local worldY = math.floor((baseY + dy) + 0.5)
    target.worldX = worldX
    target.worldY = worldY
    target.x = worldX
    target.y = worldY
    target.hasMoved = (dx ~= 0 or dy ~= 0)
  end

  if syncVisual then
    if source.paletteNumber ~= nil then
      target.paletteNumber = source.paletteNumber
    end
    if source.mirrorX ~= nil then
      target.mirrorX = source.mirrorX and true or false
    end
    if source.mirrorY ~= nil then
      target.mirrorY = source.mirrorY and true or false
    end
  end

  if syncAttr then
    if source.attr ~= nil then
      target.attr = source.attr
    end
    normalizeOAMAttrFromSpriteState(target)
  end
end

function SpriteTransformController.syncSharedOAMSpriteState(win, sourceSprite, opts)
  if not WindowCaps.isOamAnimation(win) then return 0 end
  if not (win.layers and sourceSprite) then return 0 end
  if type(sourceSprite.startAddr) ~= "number" then return 0 end

  opts = opts or {}
  local startAddr = sourceSprite.startAddr
  local updated = 0

  syncSharedOAMFieldsIntoTarget(sourceSprite, sourceSprite, opts)
  updated = 1

  for _, layer in ipairs(win.layers or {}) do
    if layer and layer.kind == "sprite" then
      for _, item in ipairs(layer.items or {}) do
        if item ~= sourceSprite
          and type(item.startAddr) == "number"
          and item.startAddr == startAddr
        then
          syncSharedOAMFieldsIntoTarget(item, sourceSprite, opts)
          updated = updated + 1
        end
      end
    end
  end

  return updated
end

function SpriteTransformController.toggleMirrorForSelection(SpriteController, win, layer, axis)
  if not layer or layer.kind ~= "sprite" then
    return 0, nil
  end
  if axis ~= "h" and axis ~= "v" then
    return 0, nil
  end

  local selected = SpriteController.getSelectedSpriteIndices(layer)
  if (#selected == 0) and layer.selectedSpriteIndex then
    selected = { layer.selectedSpriteIndex }
  end
  if #selected == 0 then
    return 0, nil
  end

  local valid = {}
  local items = layer.items or {}
  for _, idx in ipairs(selected) do
    local sprite = items[idx]
    if sprite and sprite.removed ~= true then
      valid[#valid + 1] = sprite
    end
  end
  if #valid == 0 then
    return 0, nil
  end

  for _, sprite in ipairs(valid) do
    if sprite.mirrorX == nil then sprite.mirrorX = false end
    if sprite.mirrorY == nil then sprite.mirrorY = false end
    if axis == "h" then
      sprite.mirrorX = not sprite.mirrorX
    else
      sprite.mirrorY = not sprite.mirrorY
    end
  end

  if #valid >= 2 then
    local cw = (win and win.cellW) or 8
    local ch = (win and win.cellH) or 8
    local mode = layer.mode or "8x8"
    local spriteW = cw
    local spriteH = (mode == "8x16") and (2 * ch) or ch

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    for _, sprite in ipairs(valid) do
      local x, y = getSpriteWorldPosition(sprite)
      if x < minX then minX = x end
      if y < minY then minY = y end
      if (x + spriteW) > maxX then maxX = x + spriteW end
      if (y + spriteH) > maxY then maxY = y + spriteH end
    end

    for _, sprite in ipairs(valid) do
      local x, y = getSpriteWorldPosition(sprite)
      if axis == "h" then
        x = minX + maxX - (x + spriteW)
      else
        y = minY + maxY - (y + spriteH)
      end
      setSpriteWorldPosition(sprite, x, y)
    end
  end

  for _, sprite in ipairs(valid) do
    SpriteController.syncSharedOAMSpriteState(win, sprite, {
      syncPosition = (#valid >= 2),
      syncVisual = true,
      syncAttr = true,
    })
  end

  return #valid, (#valid == 1) and valid[1] or nil
end

return SpriteTransformController
