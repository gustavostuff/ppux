local M = {}

local UndoRedoCommandRegistry = require("controllers.input_support.undo_redo_command_registry")
local GameArtController = require("controllers.game_art.game_art_controller")
local GameArtEditsController = require("controllers.game_art.edits_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local AnimationWindowUndo = require("controllers.input_support.animation_window_undo")
local GridLayoutUndo = require("controllers.input_support.grid_layout_undo")
local TableUtils = require("utils.table_utils")

local function setUndoRedoStatus(app, text)
  if app and type(app.setStatus) == "function" then
    app:setStatus(text)
  end
end

local function describeUndoRedoEvent(event)
  return UndoRedoCommandRegistry.describeEvent(event)
end

----------------------------------------------------------------
-- Undo/Redo Manager
----------------------------------------------------------------

local UndoRedoController = {}
UndoRedoController.__index = UndoRedoController

-- Create a new undo/redo manager
function UndoRedoController.new(maxDepth)
  local self = setmetatable({}, UndoRedoController)
  self.maxDepth = maxDepth
  self.stack = {}  -- Stack of undo events
  self.currentIndex = 0  -- Current position in stack (0 = no undo available, 1 = top of stack)
  self.activeEvent = nil  -- Current paint event being tracked (from mouse press to release)
  self._unsavedTracker = nil
  return self
end

function UndoRedoController:setUnsavedTracker(fn)
  self._unsavedTracker = fn
end

function UndoRedoController:_notifyUnsaved(eventType)
  if self._unsavedTracker then
    self._unsavedTracker(eventType)
  end
end

-- Internal helper to push an event onto the stack and reset redo history
function UndoRedoController:_pushEvent(ev)
  if not ev then return false end

  -- Remove any redo events above current index (new action invalidates redo)
  if self.currentIndex > 0 then
    for _ = 1, self.currentIndex do
      table.remove(self.stack, 1)
    end
    self.currentIndex = 0
  end

  table.insert(self.stack, 1, ev)
  self.currentIndex = 0

  -- Limit stack depth
  if #self.stack > self.maxDepth then
    self.stack[self.maxDepth + 1] = nil  -- Remove oldest event
  end

  return true
end

-- Start tracking a new paint operation (called on mouse press)
function UndoRedoController:startPaintEvent()
  self.activeEvent = {
    pixels = {},  -- Key-value structure: "bank:tileIndex:px:py" -> {before, after}
    type = "paint"
  }
end

local function paintEventHasChanges(event)
  if not event then return false end
  if type(event.pixels) == "table" then
    for _ in pairs(event.pixels) do
      return true
    end
  end
  return false
end

-- Record a pixel change during painting
-- bank: bank index in tilesPool
-- tileIndex: tile index within the bank
-- px, py: pixel coordinates within the tile (0-7)
-- beforeValue: pixel value before painting
-- afterValue: pixel value after painting
function UndoRedoController:recordPixelChange(bank, tileIndex, px, py, beforeValue, afterValue)
  if not self.activeEvent then return end
  
  -- Create unique key for this pixel
  local key = string.format("%d:%d:%d:%d", bank, tileIndex, px, py)
  
  -- Only store if we haven't seen this pixel before (keep original "before" value)
  if not self.activeEvent.pixels[key] then
    self.activeEvent.pixels[key] = {
      bank = bank,
      tileIndex = tileIndex,
      px = px,
      py = py,
      before = beforeValue,
      after = afterValue
    }
  else
    -- Update the "after" value (multiple paints on same pixel)
    self.activeEvent.pixels[key].after = afterValue
  end
end

function UndoRedoController:recordDirectPixelChange(item, px, py, beforeValue, afterValue)
  if not self.activeEvent or not item then return end

  local key = string.format("direct:%s:%d:%d", tostring(item), px, py)
  if not self.activeEvent.pixels[key] then
    self.activeEvent.pixels[key] = {
      item = item,
      px = px,
      py = py,
      before = beforeValue,
      after = afterValue,
      direct = true,
    }
  else
    self.activeEvent.pixels[key].after = afterValue
  end
end

-- Finish tracking the current paint operation (called on mouse release)
-- Returns true if the event was stored, false if it was empty
function UndoRedoController:finishPaintEvent()
  if not self.activeEvent then return false end

  local event = self.activeEvent
  self.activeEvent = nil
  return self:addPaintEvent(event)
end

-- Cancel the current paint event (e.g., if mouse was released without painting)
function UndoRedoController:cancelPaintEvent()
  self.activeEvent = nil
end

function UndoRedoController:takePaintEvent()
  local event = self.activeEvent
  self.activeEvent = nil
  return event
end

function UndoRedoController:addPaintEvent(event)
  if not event or event.type ~= "paint" then return false end
  if not paintEventHasChanges(event) then
    return false
  end

  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("pixel_edit")
  end
  return pushed
end

function UndoRedoController:addCompositeEvent(event)
  if not event or event.type ~= "composite" then return false end
  if type(event.events) ~= "table" or #event.events == 0 then return false end

  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved(event.unsavedType or "pixel_edit")
  end
  return pushed
end

-- Add a tile removal event (static, animation, or PPU) to the undo stack.
-- event format:
-- {
--   type    = "remove_tile",
--   subtype = "static" | "animation" | "ppu",
--   actions = {
--     {
--       win = <window>,
--       layerIndex = <number>,
--       col = <number>,
--       row = <number>,
--       prevRemoved = <bool>,   -- for static/animation
--       prevByte    = <number>, -- for ppu
--       newByte     = <number>, -- for ppu
--     },
--     ...
--   }
-- }
function UndoRedoController:addRemovalEvent(event)
  if not event or event.type ~= "remove_tile" then return false end
  local pushed = self:_pushEvent(event)
  if pushed and event.subtype == "sprite" then
    self:_notifyUnsaved("sprite_remove")
  end
  return pushed
end

-- Add a drag/move/copy event to the undo stack.
-- Supported types:
--   tile_drag   -> { changes = { {win, layerIndex, col, row, before, after}, ... } }
--   sprite_drag -> { actions = { {sprite, before, after}, ... } }
-- Separate entry point: sprite_layer_origin (sprite layer originX/originY), see addSpriteLayerOriginEvent.
function UndoRedoController:addDragEvent(event)
  if not event then return false end
  if event.type ~= "tile_drag" and event.type ~= "sprite_drag" then return false end
  local pushed = self:_pushEvent(event)
  if pushed then
    if event.type == "tile_drag" and (event.mode == nil or event.mode == "move" or event.mode == "palette") then
      self:_notifyUnsaved("tile_move")
    elseif event.type == "sprite_drag"
      and (
        event.mode == nil
        or event.mode == "move"
        or event.mode == "mirror"
        or event.mode == "copy"
        or event.mode == "palette"
        or event.mode == "sprite_binding"
      )
    then
      self:_notifyUnsaved("sprite_move")
    end
  end
  return pushed
end

function UndoRedoController:addSpriteLayerOriginEvent(event)
  if not event or event.type ~= "sprite_layer_origin" then
    return false
  end
  local win = event.win
  local li = event.layerIndex
  if not (win and win._closed ~= true and win.layers and type(li) == "number") then
    return false
  end
  local layer = win.layers[li]
  if not (layer and layer.kind == "sprite") then
    return false
  end
  local bx = math.floor(tonumber(event.beforeOriginX) or 0)
  local by = math.floor(tonumber(event.beforeOriginY) or 0)
  local ax = math.floor(tonumber(event.afterOriginX) or 0)
  local ay = math.floor(tonumber(event.afterOriginY) or 0)
  if bx < 0 then bx = 0 elseif bx > 255 then bx = 255 end
  if by < 0 then by = 0 elseif by > 239 then by = 239 end
  if ax < 0 then ax = 0 elseif ax > 255 then ax = 255 end
  if ay < 0 then ay = 0 elseif ay > 239 then ay = 239 end
  if bx == ax and by == ay then
    return false
  end
  event.beforeOriginX, event.beforeOriginY = bx, by
  event.afterOriginX, event.afterOriginY = ax, ay
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("sprite_move")
  end
  return pushed
end

function UndoRedoController:addAnimationWindowStateEvent(event)
  if not event or event.type ~= "animation_window_state" then
    return false
  end
  if not (event.win and event.beforeState and event.afterState) then
    return false
  end
  if AnimationWindowUndo.snapshotsEqual(event.beforeState, event.afterState) then
    return false
  end
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("animation_timeline_change")
  end
  return pushed
end

function UndoRedoController:addGridLayoutEvent(event)
  if not event or event.type ~= "grid_layout" then
    return false
  end
  if not (event.win and event.beforeState and event.afterState) then
    return false
  end
  if GridLayoutUndo.snapshotsEqual(event.beforeState, event.afterState) then
    return false
  end
  return self:_pushEvent(event)
end

-- Add a window close event to the undo stack.
-- event format:
-- {
--   type = "window_close",
--   win = <window>,
--   wm = <window_manager|nil>,
--   prevClosed = <bool>,
--   prevMinimized = <bool>,
--   prevFocused = <bool>,
-- }
function UndoRedoController:addWindowEvent(event)
  if not event or event.type ~= "window_close" or not event.win then
    return false
  end
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("window_close")
  end
  return pushed
end

function UndoRedoController:addWindowMinimizeEvent(event)
  if not event or event.type ~= "window_minimize" or not event.win then
    return false
  end
  local pushed = self:_pushEvent(event)
  -- Minimize/restore is transient UI state (not project data); do not mark dirty or block quit.
  return pushed
end

--- Single stack entry for "minimize all but this" (targets = windows minimized in the forward action).
function UndoRedoController:addWindowMinimizeBatchEvent(event)
  if not event or event.type ~= "window_minimize_batch" or not event.keepWin then
    return false
  end
  if type(event.targets) ~= "table" or #event.targets == 0 then
    return false
  end
  return self:_pushEvent(event)
end

function UndoRedoController:addWindowMinimizeAllEvent(event)
  if not event or event.type ~= "window_minimize_all" then
    return false
  end
  if type(event.targets) ~= "table" or #event.targets == 0 then
    return false
  end
  return self:_pushEvent(event)
end

function UndoRedoController:addWindowRestoreMinimizedAllEvent(event)
  if not event or event.type ~= "window_restore_minimized_all" then
    return false
  end
  if type(event.targets) ~= "table" or #event.targets == 0 then
    return false
  end
  return self:_pushEvent(event)
end

function UndoRedoController:addWindowExpandAllEvent(event)
  if not event or event.type ~= "window_expand_all" then
    return false
  end
  if type(event.targets) ~= "table" or #event.targets == 0 then
    return false
  end
  return self:_pushEvent(event)
end

function UndoRedoController:addWindowCollapseAllEvent(event)
  if not event or event.type ~= "window_collapse_all" then
    return false
  end
  if type(event.beforeOrder) ~= "table" or type(event.afterOrder) ~= "table" then
    return false
  end
  if type(event.beforeLayout) ~= "table" or type(event.afterLayout) ~= "table" then
    return false
  end
  return self:_pushEvent(event)
end

function UndoRedoController:addPaletteLinkEvent(event)
  if not event or event.type ~= "palette_link" then return false end
  if type(event.actions) ~= "table" or #event.actions == 0 then return false end
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("palette_link_change")
  end
  return pushed
end

function UndoRedoController:addPatternTableLinkEvent(event)
  if not event or event.type ~= "pattern_table_link" then
    return false
  end
  if type(event.actions) ~= "table" or #event.actions == 0 then
    return false
  end
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("pattern_table_link_change")
  end
  return pushed
end

function UndoRedoController:addPaletteColorEvent(event)
  if not event or event.type ~= "palette_color" then return false end
  if type(event.actions) ~= "table" or #event.actions == 0 then return false end
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("palette_color_change")
  end
  return pushed
end

function UndoRedoController:addWindowRenameEvent(event)
  if not event or event.type ~= "window_rename" or not event.win then return false end
  if event.beforeTitle == event.afterTitle then return false end
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("window_rename")
  end
  return pushed
end

function UndoRedoController:addRomPaletteAddressEvent(event)
  if not event or event.type ~= "rom_palette_address" or not event.win then return false end
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("rom_palette_address_change")
  end
  return pushed
end

function UndoRedoController:addWindowCreateEvent(event)
  if not event or event.type ~= "window_create" or not event.win then return false end
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("window_create")
  end
  return pushed
end

function UndoRedoController:addPpuFrameRangeEvent(event)
  if not event or event.type ~= "ppu_frame_range" or not event.win then
    return false
  end
  if not (event.beforeState and event.afterState) then
    return false
  end
  local pushed = self:_pushEvent(event)
  if pushed then
    self:_notifyUnsaved("ppu_frame_range_change")
  end
  return pushed
end

--- Standalone pattern table window: append ranges via CHR drag-drop (logical snapshot before / after append).
function UndoRedoController:addPatternTableAppendEvent(event)
  if not event or event.type ~= "pattern_table_append" or not event.win then
    return false
  end
  if type(event.beforePatternTable) ~= "table" or type(event.afterPatternTable) ~= "table" then
    return false
  end
  local stored = {
    type = "pattern_table_append",
    win = event.win,
    layerIndex = math.floor(tonumber(event.layerIndex) or 1),
    beforePatternTable = TableUtils.deepcopy(event.beforePatternTable),
    afterPatternTable = TableUtils.deepcopy(event.afterPatternTable),
  }
  local ptm = event.patternTableTileModes
  if type(ptm) == "table" then
    stored.patternTableTileModes = {
      before = ptm.before,
      after = ptm.after,
    }
  end
  local pushed = self:_pushEvent(stored)
  if pushed then
    self:_notifyUnsaved("pattern_table_append")
  end
  return pushed
end

-- Menu "Undo pixel edits": before = CHR bytes before revert, after = baseline bytes (from originalChrBanksBytes).
-- Undo (Ctrl+Z) restores before; redo (Ctrl+Y) restores after.
function UndoRedoController:addChrTileRevertEvent(event)
  if not event or event.type ~= "chr_tile_revert" then
    return false
  end
  if type(event.tiles) ~= "table" or #event.tiles == 0 then
    return false
  end

  local stored = { type = "chr_tile_revert", tiles = {} }
  for i, t in ipairs(event.tiles) do
    if type(t.bank) ~= "number" or type(t.tileIndex) ~= "number" then
      return false
    end
    if type(t.before) ~= "table" or type(t.after) ~= "table" then
      return false
    end
    local before = {}
    local after = {}
    for j = 1, 16 do
      before[j] = t.before[j] or 0
      after[j] = t.after[j] or 0
    end
    stored.tiles[i] = { bank = t.bank, tileIndex = t.tileIndex, before = before, after = after }
  end

  local pushed = self:_pushEvent(stored)
  if pushed then
    self:_notifyUnsaved("pixel_edit")
  end
  return pushed
end

-- Apply an undo operation
-- app: AppCoreController instance (needs appEditState.chrBanksBytes)
-- Returns true if undo was applied, false if no undo available
function UndoRedoController:undo(app)
  if self.currentIndex >= #self.stack then
    setUndoRedoStatus(app, "Nothing to undo")
    return false
  end

  self.currentIndex = self.currentIndex + 1
  local event = self.stack[self.currentIndex]

  local applied = self:_applyEvent(event, "undo", app)
  if not applied then
    self.currentIndex = self.currentIndex - 1
    setUndoRedoStatus(app, "Undo failed")
    return false
  end
  setUndoRedoStatus(app, "Undo: " .. describeUndoRedoEvent(event))
  return true
end

-- Apply a redo operation
-- app: AppCoreController instance (needs appEditState.chrBanksBytes)
-- Returns true if redo was applied, false if no redo available
function UndoRedoController:redo(app)
  if self.currentIndex <= 0 then
    setUndoRedoStatus(app, "Nothing to redo")
    return false
  end

  local event = self.stack[self.currentIndex]

  local applied = self:_applyEvent(event, "redo", app)

  self.currentIndex = self.currentIndex - 1
  if not applied then
    self.currentIndex = self.currentIndex + 1
    setUndoRedoStatus(app, "Redo failed")
    return false
  end
  setUndoRedoStatus(app, "Redo: " .. describeUndoRedoEvent(event))
  return true
end

-- Shared event dispatcher for undo/redo directions.
function UndoRedoController:_applyEvent(event, direction, app)
  if not event then return false end

  if event.type == "paint" then
    return self:_applyPaintEvent(event, direction, app)
  elseif event.type == "composite" then
    return UndoRedoCommandRegistry.applyComposite(event, direction, app, function(child, dir, a)
      return self:_applyEvent(child, dir, a)
    end)
  end

  return UndoRedoCommandRegistry.applyEvent(event, direction, app)
end

-- Apply paint event for undo/redo.
function UndoRedoController:_applyPaintEvent(event, direction, app)
  if not (event and event.pixels) then return false end
  local chr = require("chr")
  local applied = 0
  local useAfter = direction == "redo"

  for _, pixelData in pairs(event.pixels) do
    local px = pixelData.px
    local py = pixelData.py
    local value = useAfter and pixelData.after or pixelData.before

    if pixelData.item and pixelData.item.edit then
      pixelData.item:edit(px, py, value)
      applied = applied + 1
    else
      local bank = pixelData.bank
      local tileIndex = pixelData.tileIndex
      if app.appEditState and 
         app.appEditState.chrBanksBytes and 
         app.appEditState.chrBanksBytes[bank] then
        chr.setTilePixel(app.appEditState.chrBanksBytes[bank], tileIndex, px, py, value)
        if app.edits then
          GameArtController.recordEdit(app.edits, bank, tileIndex, px, py, value)
        end
        applied = applied + 1
      end
    end
  end

  if applied > 0 and app.appEditState and app.appEditState.tilesPool and app.appEditState.chrBanksBytes then
    local tilesPool = app.appEditState.tilesPool
    local banks = app.appEditState.chrBanksBytes
    local affectedTiles = {}

    for _, pixelData in pairs(event.pixels) do
      if pixelData.bank ~= nil and pixelData.tileIndex ~= nil then
        local tileKey = string.format("%d:%d", pixelData.bank, pixelData.tileIndex)
        if not affectedTiles[tileKey] then
          affectedTiles[tileKey] = {bank = pixelData.bank, tileIndex = pixelData.tileIndex}
        end
      end
    end

    for _, tileInfo in pairs(affectedTiles) do
      local bank = tileInfo.bank
      local tileIndex = tileInfo.tileIndex
      if tilesPool[bank] and tilesPool[bank][tileIndex] and banks[bank] then
        local tileRef = tilesPool[bank][tileIndex]
        if tileRef and tileRef.loadFromCHR then
          tileRef:loadFromCHR(banks[bank], tileIndex)
        end
      end
    end

    if app.appEditState then
      local targets = {}
      for _, info in pairs(affectedTiles) do
        targets[#targets + 1] = info
      end
      ChrDuplicateSync.updateTiles(app.appEditState, targets)
    end

    for _, info in pairs(affectedTiles) do
      BankCanvasSupport.invalidateTile(app, info.bank, info.tileIndex)
    end
  end

  return applied > 0
end

-- Check if undo is available
function UndoRedoController:canUndo()
  return self.currentIndex < #self.stack
end

-- Check if redo is available
function UndoRedoController:canRedo()
  return self.currentIndex > 0
end

-- Clear all undo/redo history
function UndoRedoController:clear()
  self.stack = {}
  self.currentIndex = 0
  self.activeEvent = nil
end

M.new = function(maxDepth)
  return UndoRedoController.new(maxDepth)
end

return M
