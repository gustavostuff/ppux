local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local function captureSpriteState(sprite)
  if not sprite then return nil end
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
    attrSet = (sprite.attr ~= nil),
    attr = sprite.attr,
    paletteNumberSet = (sprite.paletteNumber ~= nil),
    paletteNumber = sprite.paletteNumber,
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
    and (a.mirrorXSet == true) == (b.mirrorXSet == true)
    and (a.mirrorYSet == true) == (b.mirrorYSet == true)
    and (a.mirrorX == true) == (b.mirrorX == true)
    and (a.mirrorY == true) == (b.mirrorY == true)
    and (a.attrSet == true) == (b.attrSet == true)
    and a.attr == b.attr
    and (a.paletteNumberSet == true) == (b.paletteNumberSet == true)
    and a.paletteNumber == b.paletteNumber
end

function M.handleSpriteMirror(ctx, key, focus)
  if key ~= "h" and key ~= "v" then return false end
  if ctx.getMode() == "edit" then return false end

  local w = focus
  if not w then return false end
  if not (w.layers and w.getActiveLayerIndex) then return false end

  local li = w:getActiveLayerIndex()
  local layer = w.layers[li]
  if not layer or layer.kind ~= "sprite" then return false end

  local SpriteController = require("controllers.sprite.sprite_controller")
  local selected = SpriteController.getSelectedSpriteIndices(layer)
  if (#selected == 0) and layer.selectedSpriteIndex then
    selected = { layer.selectedSpriteIndex }
  end

  local trackedSprites = {}
  local beforeBySprite = {}
  local items = layer.items or {}
  for _, idx in ipairs(selected) do
    local sprite = items[idx]
    if sprite and sprite.removed ~= true then
      trackedSprites[#trackedSprites + 1] = sprite
      beforeBySprite[sprite] = captureSpriteState(sprite)
    end
  end

  local updated, singleSprite = SpriteController.toggleMirrorForSelection(w, layer, key)
  if updated == 0 then return false end

  local undoRedo = ctx and ctx.app and ctx.app.undoRedo
  if undoRedo and undoRedo.addDragEvent and #trackedSprites > 0 then
    local actions = {}
    for _, sprite in ipairs(trackedSprites) do
      local beforeState = beforeBySprite[sprite]
      local afterState = captureSpriteState(sprite)
      if beforeState and afterState and not statesEqual(beforeState, afterState) then
        actions[#actions + 1] = {
          win = w,
          layerIndex = li,
          sprite = sprite,
          before = beforeState,
          after = afterState,
        }
      end
    end

    if #actions > 0 then
      undoRedo:addDragEvent({
        type = "sprite_drag",
        mode = "mirror",
        sync = {
          syncPosition = (updated >= 2),
          syncVisual = true,
          syncAttr = true,
        },
        actions = actions,
      })
    end
  end

  if updated == 1 and singleSprite then
    if key == "h" then
      ctx.setStatus(singleSprite.mirrorX and "Sprite mirrored horizontally" or "Sprite horizontal mirror removed")
    else
      ctx.setStatus(singleSprite.mirrorY and "Sprite mirrored vertically" or "Sprite vertical mirror removed")
    end
  else
    if key == "h" then
      ctx.setStatus(string.format("Mirrored %d sprites horizontally", updated))
    else
      ctx.setStatus(string.format("Mirrored %d sprites vertically", updated))
    end
  end

  return true
end

function M.handleDeleteKey(ctx, key, focus)
  if ctx.getMode() == "edit" then return false end
  if key ~= "delete" and key ~= "backspace" then return false end

  local w = focus
  if not w then return false end
  if WindowCaps.isChrLike(w) then return false end
  local app = ctx.app
  local undoRedo = app and app.undoRedo

  if w.layers and w.getActiveLayerIndex then
    local li = w:getActiveLayerIndex()
    local layer = w.layers[li]
    if layer and layer.kind == "sprite" then
      local spriteDeleteResult = MultiSelectController.deleteSpriteSelection(w, li, undoRedo)
      if spriteDeleteResult then
        ctx.setStatus(spriteDeleteResult.status)
        return true
      end
    end
  end

  local c, r, L = w:getSelected()
  local layerIndex = L or (w.getActiveLayerIndex and w:getActiveLayerIndex()) or 1
  local layer = w.layers and w.layers[layerIndex]
  if not layer or layer.kind == "sprite" then return false end

  local result = MultiSelectController.deleteTileSelection(w, layerIndex, c, r, app, undoRedo)
  if not result then return false end
  ctx.setStatus(result.status)
  return true
end

function M.handleSelectAll(ctx, utils, key, focus)
  if key ~= "a" then return false end
  if not utils.ctrlDown() then return false end
  if utils.altDown() or utils.shiftDown() then return false end
  if ctx.getMode() == "edit" then return false end
  if not (focus and focus.layers and focus.getActiveLayerIndex) then return false end

  local layerIndex = focus:getActiveLayerIndex()
  local layer = focus.layers[layerIndex]
  if not layer then return false end

  if layer.kind == "sprite" then
    local SpriteController = require("controllers.sprite.sprite_controller")
    local indices = {}
    for idx, item in ipairs(layer.items or {}) do
      if item and item.removed ~= true then
        indices[#indices + 1] = idx
      end
    end

    if #indices == 0 then
      return true
    end

    SpriteController.setSpriteSelection(layer, indices)
    if ctx.showBankTileLabelForWindowSelection then
      ctx.showBankTileLabelForWindowSelection(focus)
    end
    ctx.setStatus((#indices == 1) and "Selected 1 sprite" or string.format("Selected %d sprites", #indices))
    return true
  end

  if layer.kind == "tile" then
    local cols = focus.cols or 0
    local rows = focus.rows or 0
    if cols <= 0 or rows <= 0 then return true end

    local removedCells = layer.removedCells
    local selected = {}
    local selectedCount = 0
    local firstCol, firstRow = nil, nil

    for row = 0, rows - 1 do
      for col = 0, cols - 1 do
        local idx = (row * cols + col) + 1
        local item = nil
        if focus.get then
          item = focus:get(col, row, layerIndex)
        elseif layer.items then
          item = layer.items[idx]
        end
        if item ~= nil and not (removedCells and removedCells[idx]) then
          selected[idx] = true
          selectedCount = selectedCount + 1
          if not firstCol then
            firstCol, firstRow = col, row
          end
        end
      end
    end

    if selectedCount > 1 then
      layer.multiTileSelection = selected
    else
      layer.multiTileSelection = nil
    end

    if firstCol and focus.setSelected then
      focus:setSelected(firstCol, firstRow, layerIndex)
      if ctx.showBankTileLabelForWindowSelection then
        ctx.showBankTileLabelForWindowSelection(focus)
      end
    elseif focus.clearSelected then
      focus:clearSelected(layerIndex)
    end

    if selectedCount > 0 then
      ctx.setStatus((selectedCount == 1) and "Selected 1 tile" or string.format("Selected %d tiles", selectedCount))
    end
    return true
  end

  return false
end

return M
