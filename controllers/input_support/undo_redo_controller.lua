local M = {}

----------------------------------------------------------------
-- Undo/Redo Manager
----------------------------------------------------------------

local UndoRedoController = {}
UndoRedoController.__index = UndoRedoController
local GameArtController = require("controllers.game_art.game_art_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")

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

-- Finish tracking the current paint operation (called on mouse release)
-- Returns true if the event was stored, false if it was empty
function UndoRedoController:finishPaintEvent()
  if not self.activeEvent then return false end
  
  -- Check if any pixels were actually changed
  local pixelCount = 0
  for _ in pairs(self.activeEvent.pixels) do
    pixelCount = pixelCount + 1
  end
  
  -- If no pixels were changed, discard the event
  if pixelCount == 0 then
    self.activeEvent = nil
    return false
  end

  local pushed = self:_pushEvent(self.activeEvent)
  if pushed then
    self:_notifyUnsaved("pixel_edit")
  end
  self.activeEvent = nil
  return pushed
end

-- Cancel the current paint event (e.g., if mouse was released without painting)
function UndoRedoController:cancelPaintEvent()
  self.activeEvent = nil
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
function UndoRedoController:addDragEvent(event)
  if not event then return false end
  if event.type ~= "tile_drag" and event.type ~= "sprite_drag" then return false end
  local pushed = self:_pushEvent(event)
  if pushed then
    if event.type == "tile_drag" and (event.mode == nil or event.mode == "move") then
      self:_notifyUnsaved("tile_move")
    elseif event.type == "sprite_drag" and (event.mode == nil or event.mode == "move" or event.mode == "mirror") then
      self:_notifyUnsaved("sprite_move")
    end
  end
  return pushed
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

local function applySpriteState(sprite, state)
  if not (sprite and state) then return false end

  if state.worldX ~= nil then sprite.worldX = state.worldX end
  if state.worldY ~= nil then sprite.worldY = state.worldY end
  if state.x ~= nil then sprite.x = state.x end
  if state.y ~= nil then sprite.y = state.y end
  if state.dx ~= nil then sprite.dx = state.dx end
  if state.dy ~= nil then sprite.dy = state.dy end
  if state.hasMoved ~= nil then
    sprite.hasMoved = state.hasMoved and true or false
  elseif sprite.dx ~= nil and sprite.dy ~= nil then
    sprite.hasMoved = (sprite.dx ~= 0 or sprite.dy ~= 0)
  end
  if state.removed ~= nil then
    sprite.removed = state.removed and true or false
  end
  if state.mirrorXSet ~= nil then
    if state.mirrorXSet then
      sprite.mirrorX = state.mirrorX and true or false
    else
      sprite.mirrorX = nil
    end
  elseif state.mirrorX ~= nil then
    sprite.mirrorX = state.mirrorX and true or false
  end
  if state.mirrorYSet ~= nil then
    if state.mirrorYSet then
      sprite.mirrorY = state.mirrorY and true or false
    else
      sprite.mirrorY = nil
    end
  elseif state.mirrorY ~= nil then
    sprite.mirrorY = state.mirrorY and true or false
  end
  if state.attrSet ~= nil then
    if state.attrSet then
      sprite.attr = state.attr
    else
      sprite.attr = nil
    end
  elseif state.attr ~= nil then
    sprite.attr = state.attr
  end
  if state.paletteNumberSet ~= nil then
    if state.paletteNumberSet then
      sprite.paletteNumber = state.paletteNumber
    else
      sprite.paletteNumber = nil
    end
  elseif state.paletteNumber ~= nil then
    sprite.paletteNumber = state.paletteNumber
  end
  return true
end

local function applySpriteDragEvent(event, direction)
  if not (event and event.type == "sprite_drag" and event.actions) then
    return false
  end

  local sync = event.sync or {}
  local syncPosition = true
  if sync.syncPosition ~= nil then
    syncPosition = sync.syncPosition == true
  end
  local syncVisual = false
  if sync.syncVisual ~= nil then
    syncVisual = sync.syncVisual == true
  end
  local syncAttr = false
  if sync.syncAttr ~= nil then
    syncAttr = sync.syncAttr == true
  end

  local SpriteController = nil
  local applied = 0
  for _, act in ipairs(event.actions) do
    local sprite = act.sprite
    if sprite then
      local state = (direction == "undo") and act.before or act.after
      if applySpriteState(sprite, state) then
        if act.win then
          if not SpriteController then
            SpriteController = require("controllers.sprite.sprite_controller")
          end
          if SpriteController and SpriteController.syncSharedOAMSpriteState then
            SpriteController.syncSharedOAMSpriteState(act.win, sprite, {
              syncPosition = syncPosition,
              syncVisual = syncVisual,
              syncAttr = syncAttr,
            })
          end
        end
        applied = applied + 1
      end
    end
  end
  return applied > 0
end

local function applyTileDragEvent(event, direction)
  if not (event and event.type == "tile_drag" and event.changes) then
    return false
  end

  local applied = 0
  for _, ch in ipairs(event.changes) do
    local win = ch.win
    if win and not win._closed then
      local li = ch.layerIndex or (win.getActiveLayerIndex and win:getActiveLayerIndex()) or 1
      local value
      if direction == "undo" then
        value = ch.before
      else
        value = ch.after
      end
      if win.set then
        win:set(ch.col, ch.row, value, li)
        applied = applied + 1
      elseif win.layers and win.layers[li] and win.cols then
        local idx = (ch.row * (win.cols or 0) + ch.col) + 1
        win.layers[li].items = win.layers[li].items or {}
        win.layers[li].items[idx] = value
        applied = applied + 1
      end
    end
  end

  return applied > 0
end

local function applyRemovalEvent(event, direction, app)
  if not (event and event.type == "remove_tile" and event.actions) then
    return false
  end
  local DebugController = require("controllers.dev.debug_controller")

  local applied = 0
  for _, act in ipairs(event.actions) do
    local win = act.win
    if win and not win._closed then
      local li = act.layerIndex or (win.getActiveLayerIndex and win:getActiveLayerIndex()) or 1

      if event.subtype == "ppu" then
        local val = (direction == "undo") and act.prevByte or act.newByte
        if val ~= nil and win.setNametableByteAt then
          local tilesPool = app and app.appEditState and app.appEditState.tilesPool
          win:setNametableByteAt(act.col, act.row, val, tilesPool, li)
          DebugController.log("debug", "SPRITE_REMOVAL", "[PPU] dir=%s col=%s row=%s val=%s", direction, tostring(act.col), tostring(act.row), tostring(val))
          applied = applied + 1
        end
      elseif event.subtype == "sprite" then
        local layer = win.layers and win.layers[li]
        if layer then
          local s = act.sprite or (layer.items and act.spriteIndex and layer.items[act.spriteIndex])
          if not s then
            DebugController.log("debug", "SPRITE_REMOVAL", "[SPRITE] dir=%s idx=%s missing sprite", direction, tostring(act.spriteIndex))
            applied = applied + 1 -- consider consumed even if sprite missing
          else
            local prevFlag = (act.prevRemoved == true)
            if direction == "undo" then
              s.removed = prevFlag
              DebugController.log("debug", "SPRITE_REMOVAL", "[SPRITE] undo idx=%s prev=%s -> removed=%s", tostring(act.spriteIndex), tostring(prevFlag), tostring(s.removed))
            else
              s.removed = true
              if layer.selectedSpriteIndex == act.spriteIndex then
                layer.selectedSpriteIndex = nil
              end
              if layer.multiSpriteSelection and act.spriteIndex then
                layer.multiSpriteSelection[act.spriteIndex] = nil
              end
              if layer.multiSpriteSelectionOrder and act.spriteIndex then
                for i = #layer.multiSpriteSelectionOrder, 1, -1 do
                  if layer.multiSpriteSelectionOrder[i] == act.spriteIndex then
                    table.remove(layer.multiSpriteSelectionOrder, i)
                  end
                end
                if #layer.multiSpriteSelectionOrder == 0 then
                  layer.multiSpriteSelectionOrder = nil
                end
              end
              if layer.hoverSpriteIndex == act.spriteIndex then
                layer.hoverSpriteIndex = nil
              end
              DebugController.log("debug", "SPRITE_REMOVAL", "[SPRITE] redo idx=%s prev=%s -> removed=%s", tostring(act.spriteIndex), tostring(prevFlag), tostring(s.removed))
            end
            applied = applied + 1
          end
        end
      else
        local L = win.layers and win.layers[li]
        if L then
          L.removedCells = L.removedCells or {}
          local idx = (act.row * (win.cols or 0) + act.col) + 1
          if direction == "undo" then
            if act.prevRemoved then
              L.removedCells[idx] = true
            else
              L.removedCells[idx] = nil
            end
          else
            L.removedCells[idx] = true
          end
          applied = applied + 1
        end
      end
    end
  end

  return applied > 0
end

local function applyWindowCloseEvent(event, direction, app)
  if not (event and event.type == "window_close" and event.win) then
    return false
  end

  local win = event.win
  local wm = event.wm or (app and app.wm) or nil

  if direction == "undo" then
    local targetClosed = (event.prevClosed == true)
    if targetClosed then
      if wm and wm.closeWindow then
        return wm:closeWindow(win)
      end
      if win._closed then
        return false
      end
      win._closed = true
      win._minimized = false
      return true
    end

    if wm and wm.reopenWindow then
      return wm:reopenWindow(win, {
        minimized = (event.prevMinimized == true),
        focus = (event.prevFocused == true),
      })
    end

    win._closed = false
    win._minimized = (event.prevMinimized == true)
    if wm and event.prevFocused == true and wm.setFocus then
      wm:setFocus(win)
    end
    return true
  end

  if wm and wm.closeWindow then
    return wm:closeWindow(win)
  end
  if win._closed then
    return false
  end
  win._closed = true
  win._minimized = false
  if wm and wm.focused == win then
    wm.focused = nil
  end
  return true
end

-- Apply an undo operation
-- app: AppCoreController instance (needs appEditState.chrBanksBytes)
-- Returns true if undo was applied, false if no undo available
function UndoRedoController:undo(app)
  -- Check if we can undo
  if self.currentIndex >= #self.stack then
    return false
  end
  
  -- Move to next event
  self.currentIndex = self.currentIndex + 1
  local event = self.stack[self.currentIndex]
  
  local applied = self:_applyEvent(event, "undo", app)
  if not applied then
    -- Revert index advance if nothing happened
    self.currentIndex = self.currentIndex - 1
  end
  return applied
end

-- Apply a redo operation
-- app: AppCoreController instance (needs appEditState.chrBanksBytes)
-- Returns true if redo was applied, false if no redo available
function UndoRedoController:redo(app)
  -- Check if we can redo
  if self.currentIndex <= 0 then
    return false
  end
  
  local event = self.stack[self.currentIndex]
  
  local applied = self:_applyEvent(event, "redo", app)

  -- Move to previous event
  self.currentIndex = self.currentIndex - 1
  if not applied then
    -- If nothing applied, restore index
    self.currentIndex = self.currentIndex + 1
  end
  
  return applied
end

-- Shared event dispatcher for undo/redo directions.
function UndoRedoController:_applyEvent(event, direction, app)
  if not event then return false end

  if event.type == "paint" then
    return self:_applyPaintEvent(event, direction, app)
  elseif event.type == "remove_tile" then
    return applyRemovalEvent(event, direction, app)
  elseif event.type == "tile_drag" then
    return applyTileDragEvent(event, direction)
  elseif event.type == "sprite_drag" then
    return applySpriteDragEvent(event, direction)
  elseif event.type == "window_close" then
    return applyWindowCloseEvent(event, direction, app)
  end

  return false
end

-- Apply paint event for undo/redo.
function UndoRedoController:_applyPaintEvent(event, direction, app)
  if not (event and event.pixels) then return false end
  local chr = require("chr")
  local applied = 0
  local useAfter = direction == "redo"

  for _, pixelData in pairs(event.pixels) do
    local bank = pixelData.bank
    local tileIndex = pixelData.tileIndex
    local px = pixelData.px
    local py = pixelData.py
    local value = useAfter and pixelData.after or pixelData.before
    
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

  if applied > 0 and app.appEditState and app.appEditState.tilesPool and app.appEditState.chrBanksBytes then
    local tilesPool = app.appEditState.tilesPool
    local banks = app.appEditState.chrBanksBytes
    local affectedTiles = {}

    for _, pixelData in pairs(event.pixels) do
      local tileKey = string.format("%d:%d", pixelData.bank, pixelData.tileIndex)
      if not affectedTiles[tileKey] then
        affectedTiles[tileKey] = {bank = pixelData.bank, tileIndex = pixelData.tileIndex}
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
