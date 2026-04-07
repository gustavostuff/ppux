-- sprite_controller.lua
-- Centralized sprite handling for PPUX:
--  - Hydrates sprite layers from ROM + project data
--  - Keeps track of per-sprite displacements (dx, dy) relative to ROM OAM bytes
--  - Renders sprite layers (with optional originX/originY offsets)
--  - Hit-tests and drag-moves sprites in NES pixel space
--  - Applies displacements back into romRaw when saving

local SpriteDragSelectionController = require("controllers.sprite.drag_selection_controller")
local SpriteHydrationController = require("controllers.sprite.hydration_controller")
local SpritePngImportController = require("controllers.sprite.png_import_controller")
local SpritePlacementController = require("controllers.sprite.placement_controller")
local SpriteRomPersistenceController = require("controllers.sprite.rom_persistence_controller")
local SpriteSelectionController = require("controllers.sprite.selection_controller")
local SpriteTransformController = require("controllers.sprite.transform_controller")

local SpriteController = {}

SpriteController.SPRITE_X_RANGE = 256
SpriteController.SPRITE_Y_RANGE = 256


----------------------------------------------------------------------
-- Runtime hydration
----------------------------------------------------------------------

--- Initialize / refresh all sprite items for a given layer.
--  This:
--    - Reads base OAM bytes (Y, tile, attr, X) from romRaw at startAddr
--    - Establishes baseX/baseY, oamTile, attr
--    - Sets worldX/worldY (current in-editor position, without origin)
--    - Computes dx/dy = world - base (for project/ROM purposes)
--    - Resolves topRef/botRef from tilesPool
--
--  layer: the actual layer table on a Window (win.layers[i])
--  opts:
--    romRaw     : full ROM string
--    tilesPool  : tilesPool[bank][tileIndex] → Tile ref
--    keepWorld  : if true, keeps existing item.worldX/Y when refreshing
function SpriteController.hydrateSpriteLayer(layer, opts)
  return SpriteHydrationController.hydrateSpriteLayer(layer, opts)
end

--- Convenience: hydrate all sprite layers of a window.
function SpriteController.hydrateWindowSpriteLayers(win, opts)
  return SpriteHydrationController.hydrateWindowSpriteLayers(win, opts)
end

--- Add a sprite to a sprite layer from a tile drag.
-- This is used when dropping a tile from CHR window onto a sprite layer.
-- @param layer The sprite layer to add the sprite to
-- @param tile The tile object being placed (from drag.item)
-- @param pixelX The X pixel coordinate (in window content space, accounting for scroll)
-- @param pixelY The Y pixel coordinate (in window content space, accounting for scroll)
-- @param tilesPool The tiles pool for resolving tile references
-- @return itemIndex The index of the newly created sprite item, or nil on failure
function SpriteController.addSpriteToLayer(layer, tile, pixelX, pixelY, tilesPool)
  return SpritePlacementController.addSpriteToLayer(layer, tile, pixelX, pixelY, tilesPool)
end

-- Returns:
--   layerIndex, itemIndex, offsetXFromCenter, offsetYFromCenter
--   OR nil if no sprite hit.
--
--  x,y are absolute screen coordinates from love.mouse.
--  activeLayerIndex: optional; defaults to win:getActiveLayerIndex().
function SpriteController.pickSpriteAt(win, x, y, activeLayerIndex)
  return SpriteDragSelectionController.pickSpriteAt(SpriteController, win, x, y, activeLayerIndex)
end

----------------------------------------------------------------------
-- Dragging
----------------------------------------------------------------------

-- === Selection helpers (multi-selection lives on the layer as a set) ===
function SpriteController.clearSpriteSelection(layer)
  return SpriteSelectionController.clearSpriteSelection(layer)
end

function SpriteController.setSpriteSelection(layer, indices)
  return SpriteSelectionController.setSpriteSelection(layer, indices)
end

function SpriteController.toggleSpriteSelection(layer, idx)
  return SpriteSelectionController.toggleSpriteSelection(layer, idx)
end

function SpriteController.getSelectedSpriteIndices(layer)
  return SpriteSelectionController.getSelectedSpriteIndices(layer)
end

function SpriteController.getSelectedSpriteIndicesInOrder(layer)
  return SpriteSelectionController.getSelectedSpriteIndicesInOrder(layer)
end

-- Sync fields for all sprite items across OAM animation windows and PPU Frame
-- sprite layers that reference the same ROM OAM sprite (identified by startAddr).
-- opts:
--   syncPosition (default true)
--   syncVisual   (default true) -> paletteNumber / mirrorX / mirrorY
--   syncAttr     (default true) -> normalized attr from current sprite state
-- Returns number of sprites updated (including the source sprite).
function SpriteController.syncSharedOAMSpriteState(win, sourceSprite, opts)
  return SpriteTransformController.syncSharedOAMSpriteState(win, sourceSprite, opts)
end

--- Toggle horizontal/vertical mirror on selected sprites.
-- For multi-selection (2+), also mirrors world positions around the selection
-- bounding box so group layout is reflected as a whole.
-- axis: "h" or "v"
-- Returns: updatedCount, singleSpriteOrNil
function SpriteController.toggleMirrorForSelection(win, layer, axis)
  return SpriteTransformController.toggleMirrorForSelection(SpriteController, win, layer, axis)
end

-- Start/stop/update marquee selection (screen coords)
function SpriteController.startSpriteMarquee(win, layerIndex, startX, startY, append)
  SpriteSelectionController.startSpriteMarquee(win, layerIndex, startX, startY, append)
end

function SpriteController.updateSpriteMarquee(x, y)
  SpriteSelectionController.updateSpriteMarquee(x, y)
end

function SpriteController.finishSpriteMarquee(x, y)
  return SpriteSelectionController.finishSpriteMarquee(x, y)
end

function SpriteController.getSpriteMarquee()
  return SpriteSelectionController.getSpriteMarquee()
end

-- Select all sprites intersecting a content-space rectangle.
-- rect: {x1,y1,x2,y2} in content pixels (after scroll/zoom adjusted).
-- append: keep existing selection if true.
function SpriteController.selectSpritesInRect(win, layerIndex, rect, append)
  return SpriteSelectionController.selectSpritesInRect(win, layerIndex, rect, append)
end

-- Begin dragging sprite(s). anchorIndex is the sprite under the cursor.
-- Uses layer.multiSpriteSelection if present; otherwise drags only anchor.
function SpriteController.beginDrag(win, layerIndex, anchorIndex, grabOffsetX, grabOffsetY, copyMode)
  return SpriteDragSelectionController.beginDrag(
    SpriteController, win, layerIndex, anchorIndex, grabOffsetX, grabOffsetY, copyMode
  )
end

function SpriteController.isDragging()
  return SpriteDragSelectionController.isDragging()
end

--- Bring a sprite to the front by moving it to the end of the items array
-- This affects rendering order (last item renders on top)
-- Returns: new itemIndex (always #items after move)
function SpriteController.bringSpriteToFront(layer, itemIndex)
  return SpriteDragSelectionController.bringSpriteToFront(layer, itemIndex)
end

--- Update currently dragged sprite position based on mouse (x, y) in screen coords.
--  This:
--    - Computes new worldX/worldY in NES pixel space
--    - Clamps within window/layer bounds
--    - Updates dx/dy relative to baseX/baseY
--    - Marks hasMoved when needed
function SpriteController.updateDrag(mouseX, mouseY)
  return SpriteDragSelectionController.updateDrag(SpriteController, mouseX, mouseY)
end

function SpriteController.finishDrag(copyStillPressed, undoRedo)
  return SpriteDragSelectionController.finishDrag(SpriteController, copyStillPressed, undoRedo)
end

function SpriteController.endDrag()
  return SpriteDragSelectionController.endDrag(SpriteController)
end

----------------------------------------------------------------------
-- Project serialization helpers (displacements only)
----------------------------------------------------------------------

--- Build a project-ready table for a sprite layer, storing only dx/dy
--  for sprites that moved. This mirrors the layout.lua format.
function SpriteController.snapshotSpriteLayer(layer)
  return SpriteHydrationController.snapshotSpriteLayer(layer)
end

--- Rehydrate a sprite layer from a project entry that uses dx/dy.
--  This expects that layer.items already exists and matches entry.items order.
function SpriteController.applySnapshotToSpriteLayer(layer, snapshot, opts)
  return SpriteHydrationController.applySnapshotToSpriteLayer(layer, snapshot, opts)
end

----------------------------------------------------------------------
-- ROM write-back helpers
----------------------------------------------------------------------

function SpriteController.applyDisplacementsToROMForLayer(layer, romRaw)
  return SpriteRomPersistenceController.applyDisplacementsToROMForLayer(layer, romRaw)
end

function SpriteController.applyDisplacementsToROMForWindows(windows, romRaw)
  return SpriteRomPersistenceController.applyDisplacementsToROMForWindows(windows, romRaw)
end

----------------------------------------------------------------------
-- PNG import for sprite layers
----------------------------------------------------------------------
function SpriteController.handleSpritePngDrop(app, file, win)
  return SpritePngImportController.handleSpritePngDrop(SpriteController, app, file, win)
end

return SpriteController
