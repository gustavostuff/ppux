-- OAM X/Y are bytes (mod 256). Editor dx/dy must use the shortest wrap delta;
-- raw values like ±256 are identity no-ops that break project reload / ROM bake.

local M = {}

local RANGE = 256
local HALF = 128

--- Fold an axis delta into (-HALF, HALF] so ±RANGE becomes 0.
function M.normalizeAxisDelta(delta)
  delta = math.floor(tonumber(delta) or 0)
  while delta > HALF do
    delta = delta - RANGE
  end
  while delta <= -HALF do
    delta = delta + RANGE
  end
  return delta
end

--- Apply normalized dx/dy from world vs base; rewrite world to base+dx.
--- Returns dx, dy.
function M.applyNormalizedDisplacement(sprite)
  if not sprite then
    return 0, 0
  end
  local baseX = tonumber(sprite.baseX)
  local baseY = tonumber(sprite.baseY)
  if baseX == nil then
    baseX = tonumber(sprite.worldX) or tonumber(sprite.x) or 0
  end
  if baseY == nil then
    baseY = tonumber(sprite.worldY) or tonumber(sprite.y) or 0
  end
  baseX = math.floor(baseX + 0.5)
  baseY = math.floor(baseY + 0.5)

  local worldX = tonumber(sprite.worldX) or tonumber(sprite.x) or baseX
  local worldY = tonumber(sprite.worldY) or tonumber(sprite.y) or baseY
  local dx = M.normalizeAxisDelta(worldX - baseX)
  local dy = M.normalizeAxisDelta(worldY - baseY)

  sprite.baseX = baseX
  sprite.baseY = baseY
  sprite.dx = dx
  sprite.dy = dy
  sprite.worldX = baseX + dx
  sprite.worldY = baseY + dy
  sprite.x = sprite.worldX
  sprite.y = sprite.worldY
  sprite.hasMoved = (dx ~= 0 or dy ~= 0)
  return dx, dy
end

return M
