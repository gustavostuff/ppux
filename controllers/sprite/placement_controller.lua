local SpriteHydrationController = require("controllers.sprite.hydration_controller")

local SpritePlacementController = {}

function SpritePlacementController.addSpriteToLayer(layer, tile, pixelX, pixelY, tilesPool)
  if not (layer and layer.kind == "sprite" and tile and tilesPool) then
    return nil
  end

  local bankIndex = tile._bankIndex
  local tileIndex = tile.index
  if not (bankIndex and tileIndex ~= nil) then
    return nil
  end

  layer.items = layer.items or {}
  local mode = layer.mode or "8x8"

  local spriteItem = {
    bank = bankIndex,
    tile = tileIndex,
    tileBelow = nil,
    paletteNumber = nil,
    mirrorX = false,
    mirrorY = false,
    x = pixelX,
    y = pixelY,
  }

  local pool = tilesPool[bankIndex]
  if not pool then
    return nil
  end

  SpriteHydrationController.ensureTileRefsForSpriteItem(spriteItem, mode, tilesPool)

  pixelX = math.floor(pixelX + 0.5)
  pixelY = math.floor(pixelY + 0.5)

  spriteItem.worldX = pixelX
  spriteItem.worldY = pixelY
  spriteItem.baseX = pixelX
  spriteItem.baseY = pixelY
  spriteItem.x = pixelX
  spriteItem.y = pixelY
  spriteItem.dx = 0
  spriteItem.dy = 0
  spriteItem.hasMoved = false

  if not spriteItem.topRef then
    return nil
  end

  table.insert(layer.items, spriteItem)
  return #layer.items
end

return SpritePlacementController
