local SpriteDragSelectionController = {}
local WindowCaps = require("controllers.window.window_capabilities")

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function alignWrappedToReference(value, reference, range)
  if type(value) ~= "number" then return value end
  if type(reference) ~= "number" then return value end
  if type(range) ~= "number" or range <= 0 then return value end

  local wraps = math.floor(((reference - value) / range) + 0.5)
  return value + (wraps * range)
end

local drag = {
  active = false,
  win = nil,
  layerIndex = nil,
  anchorIndex = nil,
  items = nil,
  grabOffsetX = 0,
  grabOffsetY = 0,
  copyMode = false,
  lastAlignedWorldX = nil,
  lastAlignedWorldY = nil,
}

local function resetDrag()
  drag.active = false
  drag.win = nil
  drag.layerIndex = nil
  drag.anchorIndex = nil
  drag.items = nil
  drag.grabOffsetX = 0
  drag.grabOffsetY = 0
  drag.copyMode = false
  drag.lastAlignedWorldX = nil
  drag.lastAlignedWorldY = nil
end

local function captureSpriteState(s)
  if not s then return nil end
  return {
    worldX = s.worldX or s.x or 0,
    worldY = s.worldY or s.y or 0,
    x = s.x or s.worldX or 0,
    y = s.y or s.worldY or 0,
    dx = s.dx or 0,
    dy = s.dy or 0,
    hasMoved = s.hasMoved == true,
    removed = s.removed == true,
  }
end

local function statesEqual(a, b)
  if not (a and b) then return false end
  return a.worldX == b.worldX
    and a.worldY == b.worldY
    and a.x == b.x
    and a.y == b.y
    and a.dx == b.dx
    and a.dy == b.dy
    and (a.hasMoved == true) == (b.hasMoved == true)
    and (a.removed == true) == (b.removed == true)
end

function SpriteDragSelectionController.pickSpriteAt(SpriteController, win, x, y, activeLayerIndex)
  if not win or not win.layers then return nil end

  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local cw = win.cellW or 8
  local ch = win.cellH or 8
  local scol = win.scrollCol or 0
  local srow = win.scrollRow or 0

  local li = activeLayerIndex or win:getActiveLayerIndex() or win.activeLayer or 1
  local L = win.layers[li]
  if not (L and L.kind == "sprite" and L.items) then
    return nil
  end

  local originX = L.originX or 0
  local originY = L.originY or 0
  local mode = L.mode or "8x8"
  local wTile = cw
  local hSprite = (mode == "8x16") and (2 * ch) or ch

  local NES_W = SpriteController.SPRITE_X_RANGE
  local NES_H = SpriteController.SPRITE_Y_RANGE

  local cx = (x - win.x) / z
  local cy = (y - win.y) / z
  local cxAbs = cx + scol * cw
  local cyAbs = cy + srow * ch

  local items = L.items
  for idx = #items, 1, -1 do
    local s = items[idx]
    if s.removed == true then
      goto continue
    end
    local worldX = s.worldX or s.baseX or s.x or 0
    local worldY = s.worldY or s.baseY or s.y or 0
    local sx = (originX + worldX) % NES_W
    local sy = (originY + worldY) % NES_H

    if cxAbs >= sx and cxAbs < sx + wTile and
       cyAbs >= sy and cyAbs < sy + hSprite then
      local centerX = sx + wTile * 0.5
      local centerY = sy + hSprite * 0.5
      return li, idx, cxAbs - centerX, cyAbs - centerY
    end
    ::continue::
  end

  return nil
end

function SpriteDragSelectionController.beginDrag(SpriteController, win, layerIndex, anchorIndex, grabOffsetX, grabOffsetY, copyMode)
  if not (win and layerIndex and anchorIndex) then
    resetDrag()
    return
  end

  local layer = win.layers and win.layers[layerIndex]
  if not (layer and layer.kind == "sprite" and layer.items) then
    resetDrag()
    return
  end

  local indices = SpriteController.getSelectedSpriteIndicesInOrder(layer)
  local foundAnchor = false
  for _, idx in ipairs(indices) do
    if idx == anchorIndex then foundAnchor = true break end
  end
  if not foundAnchor then
    indices[#indices + 1] = anchorIndex
  end

  local items = {}
  local useCopyMode = not not copyMode
  if useCopyMode and WindowCaps.isOamAnimation(win) then
    useCopyMode = false
  end
  local effectiveAnchor = anchorIndex

  if useCopyMode then
    local cloneIndices = {}
    local anchorCloneIndex = nil

    for _, idx in ipairs(indices) do
      local original = layer.items[idx]
      if original and original.removed ~= true then
        local clone = {}
        for k, v in pairs(original) do
          clone[k] = v
        end

        table.insert(layer.items, clone)
        local cloneIndex = #layer.items
        cloneIndices[#cloneIndices + 1] = cloneIndex

        items[#items + 1] = {
          itemIndex = cloneIndex,
          cloneIndex = cloneIndex,
          sprite = clone,
          startWorldX = clone.worldX or clone.baseX or clone.x or 0,
          startWorldY = clone.worldY or clone.baseY or clone.y or 0,
          startX = clone.x or clone.worldX or clone.baseX or 0,
          startY = clone.y or clone.worldY or clone.baseY or 0,
          startDX = clone.dx or 0,
          startDY = clone.dy or 0,
          startHasMoved = clone.hasMoved == true,
          startRemoved = clone.removed == true,
          baseX = clone.baseX or 0,
          baseY = clone.baseY or 0,
          originalSprite = original,
          originalIndex = idx,
        }

        if idx == anchorIndex then
          anchorCloneIndex = cloneIndex
        end
      end
    end

    if #cloneIndices > 0 then
      SpriteController.setSpriteSelection(layer, cloneIndices)
      effectiveAnchor = anchorCloneIndex or cloneIndices[1]
      layer.selectedSpriteIndex = effectiveAnchor
      layer.hoverSpriteIndex = effectiveAnchor
    end
  else
    for _, idx in ipairs(indices) do
      local s = layer.items[idx]
      if s and s.removed ~= true then
        items[#items + 1] = {
          itemIndex = idx,
          sprite = s,
          startWorldX = s.worldX or s.baseX or s.x or 0,
          startWorldY = s.worldY or s.baseY or s.y or 0,
          startX = s.x or s.worldX or s.baseX or 0,
          startY = s.y or s.worldY or s.baseY or 0,
          startDX = s.dx or 0,
          startDY = s.dy or 0,
          startHasMoved = s.hasMoved == true,
          startRemoved = s.removed == true,
          baseX = s.baseX or 0,
          baseY = s.baseY or 0,
        }
      end
    end
  end

  if #items == 0 then
    resetDrag()
    return
  end

  drag.active = true
  drag.win = win
  drag.layerIndex = layerIndex
  drag.anchorIndex = effectiveAnchor
  drag.grabOffsetX = grabOffsetX or 0
  drag.grabOffsetY = grabOffsetY or 0
  drag.items = items
  drag.copyMode = useCopyMode
  drag.lastAlignedWorldX = nil
  drag.lastAlignedWorldY = nil
end

function SpriteDragSelectionController.isDragging()
  return drag.active
end

function SpriteDragSelectionController.bringSpriteToFront(layer, itemIndex)
  if not (layer and layer.items and itemIndex) then return nil end
  if itemIndex < 1 or itemIndex > #layer.items then return nil end
  if itemIndex == #layer.items then return itemIndex end

  local sprite = table.remove(layer.items, itemIndex)
  table.insert(layer.items, sprite)
  return #layer.items
end

function SpriteDragSelectionController.updateDrag(SpriteController, mouseX, mouseY)
  if not drag.active then return end

  local win = drag.win
  if not win or not win.layers then
    drag.active = false
    return
  end

  local L = win.layers[drag.layerIndex]
  if not (L and L.kind == "sprite" and drag.items and #drag.items > 0) then
    drag.active = false
    return
  end

  local anchorEntry
  for _, entry in ipairs(drag.items) do
    if entry.itemIndex == drag.anchorIndex then
      anchorEntry = entry
      break
    end
  end
  if not anchorEntry then
    drag.active = false
    return
  end

  local cw = win.cellW or 8
  local ch = win.cellH or 8
  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local scol = win.scrollCol or 0
  local srow = win.scrollRow or 0

  local originX = L.originX or 0
  local originY = L.originY or 0
  local mode = L.mode or "8x8"
  local spriteW = cw
  local spriteH = (mode == "8x16") and (2 * ch) or ch

  local cx = (mouseX - win.x) / z
  local cy = (mouseY - win.y) / z
  local cxAbs = cx + scol * cw
  local cyAbs = cy + srow * ch

  local centerX = cxAbs - drag.grabOffsetX
  local centerY = cyAbs - drag.grabOffsetY
  local spriteRangeW = SpriteController.SPRITE_X_RANGE or 256
  local spriteRangeH = SpriteController.SPRITE_Y_RANGE or 256
  local desiredWorldX = (centerX - spriteW * 0.5) - originX
  local desiredWorldY = (centerY - spriteH * 0.5) - originY
  local alignRefX = drag.lastAlignedWorldX or anchorEntry.startWorldX
  local alignRefY = drag.lastAlignedWorldY or anchorEntry.startWorldY
  desiredWorldX = alignWrappedToReference(desiredWorldX, alignRefX, spriteRangeW)
  desiredWorldY = alignWrappedToReference(desiredWorldY, alignRefY, spriteRangeH)
  drag.lastAlignedWorldX = desiredWorldX
  drag.lastAlignedWorldY = desiredWorldY

  local minDX, maxDX = -math.huge, math.huge
  local minDY, maxDY = -math.huge, math.huge

  local minWorldX = -originX
  local minWorldY = -originY
  local maxWorldX = minWorldX + spriteRangeW - spriteW
  local maxWorldY = minWorldY + spriteRangeH - spriteH

  for _, entry in ipairs(drag.items) do
    local startX = entry.startWorldX
    local startY = entry.startWorldY
    minDX = math.max(minDX, minWorldX - startX)
    maxDX = math.min(maxDX, maxWorldX - startX)
    minDY = math.max(minDY, minWorldY - startY)
    maxDY = math.min(maxDY, maxWorldY - startY)
  end

  -- Keep the initial pose stable: even if some selected sprites start outside
  -- the current bounds, we should not force an instant jump on drag start.
  minDX = math.min(minDX, 0)
  maxDX = math.max(maxDX, 0)
  minDY = math.min(minDY, 0)
  maxDY = math.max(maxDY, 0)

  local desiredDX = desiredWorldX - anchorEntry.startWorldX
  local desiredDY = desiredWorldY - anchorEntry.startWorldY
  local clampedDX, clampedDY
  if WindowCaps.isStartAddrSpriteSyncWindow(win) then
    -- OAM/PPU sprite positions are byte-wrapped on ROM write-back; with origin
    -- offsets enabled, hard clamping creates "invisible walls". Keep drag
    -- continuous in editor space for both synced window kinds.
    clampedDX = desiredDX
    clampedDY = desiredDY
  else
    clampedDX = clamp(desiredDX, minDX, maxDX)
    clampedDY = clamp(desiredDY, minDY, maxDY)
  end

  for _, entry in ipairs(drag.items) do
    local s = entry.sprite
    local worldX = math.floor((entry.startWorldX + clampedDX) + 0.5)
    local worldY = math.floor((entry.startWorldY + clampedDY) + 0.5)

    s.worldX = worldX
    s.worldY = worldY
    s.x = worldX
    s.y = worldY

    local baseX = s.baseX or 0
    local baseY = s.baseY or 0
    local dx = worldX - baseX
    local dy = worldY - baseY
    s.dx = dx
    s.dy = dy
    s.hasMoved = (dx ~= 0 or dy ~= 0)

    SpriteController.syncSharedOAMSpriteState(win, s, {
      syncPosition = true,
      syncVisual = false,
      syncAttr = false,
    })
  end
end

function SpriteDragSelectionController.finishDrag(SpriteController, copyStillPressed, undoRedo)
  if not drag.active then return false end

  local win = drag.win
  local layerIndex = drag.layerIndex
  local layer = (win and win.layers and layerIndex) and win.layers[layerIndex] or nil
  if not layer or layer.kind ~= "sprite" then
    resetDrag()
    return true
  end

  local shouldCopy = drag.copyMode and (copyStillPressed ~= false)
  if drag.copyMode and not shouldCopy then
    local originalIndices = {}
    local cloneIndices = {}

    for _, entry in ipairs(drag.items or {}) do
      local clone = entry.sprite
      local original = entry.originalSprite
      if clone and original and clone.removed ~= true and original.removed ~= true then
        local worldX = clone.worldX or clone.x or entry.startWorldX or 0
        local worldY = clone.worldY or clone.y or entry.startWorldY or 0

        original.worldX = worldX
        original.worldY = worldY
        original.x = worldX
        original.y = worldY

        local baseX = original.baseX or 0
        local baseY = original.baseY or 0
        original.dx = worldX - baseX
        original.dy = worldY - baseY
        original.hasMoved = (original.dx ~= 0 or original.dy ~= 0)
        SpriteController.syncSharedOAMSpriteState(win, original, {
          syncPosition = true,
          syncVisual = false,
          syncAttr = false,
        })
      end

      if entry.originalIndex then
        originalIndices[#originalIndices + 1] = entry.originalIndex
      end
      if entry.cloneIndex then
        cloneIndices[#cloneIndices + 1] = entry.cloneIndex
      elseif entry.itemIndex then
        cloneIndices[#cloneIndices + 1] = entry.itemIndex
      end
    end

    table.sort(cloneIndices, function(a, b) return a > b end)
    local removed = {}
    for _, idx in ipairs(cloneIndices) do
      if not removed[idx] and idx >= 1 and idx <= #layer.items then
        table.remove(layer.items, idx)
        removed[idx] = true
      end
    end

    if #originalIndices > 0 then
      SpriteController.setSpriteSelection(layer, originalIndices)
      layer.selectedSpriteIndex = originalIndices[1]
      layer.hoverSpriteIndex = originalIndices[1]
    end
  elseif shouldCopy and drag.copyMode then
    local cloneIndices = {}
    for _, entry in ipairs(drag.items or {}) do
      cloneIndices[#cloneIndices + 1] = entry.itemIndex
    end
    if #cloneIndices > 0 then
      SpriteController.setSpriteSelection(layer, cloneIndices)
      layer.selectedSpriteIndex = cloneIndices[1]
      layer.hoverSpriteIndex = cloneIndices[1]
    end
  end

  if not (drag.copyMode and not shouldCopy)
    and undoRedo and undoRedo.addDragEvent
    and drag.items and #drag.items > 0
  then
    local actions = {}

    if shouldCopy and drag.copyMode then
      for _, entry in ipairs(drag.items) do
        local sprite = entry.sprite
        if sprite then
          local beforeState = {
            worldX = entry.startWorldX or 0,
            worldY = entry.startWorldY or 0,
            x = entry.startX or entry.startWorldX or 0,
            y = entry.startY or entry.startWorldY or 0,
            dx = entry.startDX or 0,
            dy = entry.startDY or 0,
            hasMoved = entry.startHasMoved == true,
            removed = true,
          }
          local afterState = captureSpriteState(sprite)
          if afterState and not statesEqual(beforeState, afterState) then
            actions[#actions + 1] = {
              win = win,
              layerIndex = layerIndex,
              sprite = sprite,
              created = true,
              before = beforeState,
              after = afterState,
            }
          end
        end
      end
    else
      for _, entry in ipairs(drag.items) do
        local sprite = entry.sprite
        if sprite then
          local beforeState = {
            worldX = entry.startWorldX or 0,
            worldY = entry.startWorldY or 0,
            x = entry.startX or entry.startWorldX or 0,
            y = entry.startY or entry.startWorldY or 0,
            dx = entry.startDX or 0,
            dy = entry.startDY or 0,
            hasMoved = entry.startHasMoved == true,
            removed = entry.startRemoved == true,
          }
          local afterState = captureSpriteState(sprite)
          if afterState and not statesEqual(beforeState, afterState) then
            actions[#actions + 1] = {
              win = win,
              layerIndex = layerIndex,
              sprite = sprite,
              before = beforeState,
              after = afterState,
            }
          end
        end
      end
    end

    if #actions > 0 then
      undoRedo:addDragEvent({
        type = "sprite_drag",
        mode = (shouldCopy and drag.copyMode) and "copy" or "move",
        actions = actions,
      })
    end
  end

  resetDrag()
  return true
end

function SpriteDragSelectionController.endDrag(SpriteController)
  if drag.active and drag.copyMode then
    local win = drag.win
    local layerIndex = drag.layerIndex
    local layer = (win and win.layers and layerIndex) and win.layers[layerIndex] or nil
    if layer and layer.kind == "sprite" then
      local originalIndices = {}
      local cloneIndices = {}
      for _, entry in ipairs(drag.items or {}) do
        if entry.originalIndex then
          originalIndices[#originalIndices + 1] = entry.originalIndex
        end
        if entry.cloneIndex then
          cloneIndices[#cloneIndices + 1] = entry.cloneIndex
        elseif entry.itemIndex then
          cloneIndices[#cloneIndices + 1] = entry.itemIndex
        end
      end

      table.sort(cloneIndices, function(a, b) return a > b end)
      local removed = {}
      for _, idx in ipairs(cloneIndices) do
        if not removed[idx] and idx >= 1 and idx <= #layer.items then
          table.remove(layer.items, idx)
          removed[idx] = true
        end
      end

      if #originalIndices > 0 then
        SpriteController.setSpriteSelection(layer, originalIndices)
        layer.selectedSpriteIndex = originalIndices[1]
        layer.hoverSpriteIndex = originalIndices[1]
      end
    end
  end

  resetDrag()
end

return SpriteDragSelectionController
