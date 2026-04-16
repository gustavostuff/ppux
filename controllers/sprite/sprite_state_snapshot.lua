-- Shared sprite snapshot helpers for undo/redo (sprite_drag events).

local M = {}

function M.captureSpriteState(sprite)
  if not sprite then
    return nil
  end
  return {
    worldX = sprite.worldX or sprite.x or 0,
    worldY = sprite.worldY or sprite.y or 0,
    x = sprite.x or sprite.worldX or 0,
    y = sprite.y or sprite.worldY or 0,
    dx = sprite.dx or 0,
    dy = sprite.dy or 0,
    hasMoved = sprite.hasMoved == true,
    removed = sprite.removed == true,
    mirrorXSet = (sprite.mirrorX ~= nil),
    mirrorX = sprite.mirrorX == true,
    mirrorYSet = (sprite.mirrorY ~= nil),
    mirrorY = sprite.mirrorY == true,
    mirrorXOverrideSet = (sprite._mirrorXOverrideSet == true),
    mirrorYOverrideSet = (sprite._mirrorYOverrideSet == true),
    attrSet = (sprite.attr ~= nil),
    attr = sprite.attr,
    paletteNumberSet = (sprite.paletteNumber ~= nil),
    paletteNumber = sprite.paletteNumber,
  }
end

function M.statesEqual(a, b)
  if not (a and b) then
    return false
  end
  return a.worldX == b.worldX
    and a.worldY == b.worldY
    and a.x == b.x
    and a.y == b.y
    and a.dx == b.dx
    and a.dy == b.dy
    and (a.hasMoved == true) == (b.hasMoved == true)
    and (a.removed == true) == (b.removed == true)
    and (a.mirrorXSet == true) == (b.mirrorXSet == true)
    and (a.mirrorYSet == true) == (b.mirrorYSet == true)
    and (a.mirrorX == true) == (b.mirrorX == true)
    and (a.mirrorY == true) == (b.mirrorY == true)
    and (a.mirrorXOverrideSet == true) == (b.mirrorXOverrideSet == true)
    and (a.mirrorYOverrideSet == true) == (b.mirrorYOverrideSet == true)
    and (a.attrSet == true) == (b.attrSet == true)
    and a.attr == b.attr
    and (a.paletteNumberSet == true) == (b.paletteNumberSet == true)
    and a.paletteNumber == b.paletteNumber
end

return M
