local M = {}

----------------------------------------------------------------
-- Undo/Redo Manager
----------------------------------------------------------------

local UndoRedoController = {}
UndoRedoController.__index = UndoRedoController
local GameArtController = require("controllers.game_art.game_art_controller")
local GameArtEditsController = require("controllers.game_art.edits_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local WindowCaps = require("controllers.window.window_capabilities")
local AnimationWindowUndo = require("controllers.input_support.animation_window_undo")
local GridLayoutUndo = require("controllers.input_support.grid_layout_undo")

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
  if pushed then
    self:_notifyUnsaved("window_minimize")
  end
  return pushed
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

local function deepCopy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[deepCopy(k, seen)] = deepCopy(v, seen)
  end
  return copy
end

local function applyPaletteLinkEvent(event, direction)
  if not (event and event.type == "palette_link" and event.actions) then
    return false
  end

  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app or nil
  local applied = 0
  for _, act in ipairs(event.actions) do
    local win = act.win
    local li = act.layerIndex
    local layer = win and win.layers and li and win.layers[li] or nil
    if layer then
      local state = (direction == "undo") and act.beforePaletteData or act.afterPaletteData
      layer.paletteData = deepCopy(state)
      if app and app.invalidatePpuFramePaletteLayer then
        app:invalidatePpuFramePaletteLayer(win, li)
      end
      applied = applied + 1
    end
  end

  return applied > 0
end

local function paletteStateForWin(event, win, direction)
  local states = event and event.paletteStates
  if type(states) ~= "table" then
    return nil
  end
  for _, entry in ipairs(states) do
    if entry and entry.win == win then
      if direction == "undo" then
        return entry.beforePaletteData
      end
      return entry.afterPaletteData
    end
  end
  return nil
end

local function applyPaletteColorEvent(event, direction)
  if not (event and event.type == "palette_color" and event.actions) then
    return false
  end

  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app or nil
  local touchedWins = {}
  local applied = 0
  for _, act in ipairs(event.actions) do
    local win = act.win
    local row = act.row
    local col = act.col
    local code = (direction == "undo") and act.beforeCode or act.afterCode
    if win and type(row) == "number" and type(col) == "number" and type(code) == "string" then
      win.codes2D = win.codes2D or {}
      win.codes2D[row] = win.codes2D[row] or {}
      win.codes2D[row][col] = code
      if win.set then
        win:set(col, row, code)
      end
      if win.kind == "rom_palette" and win.writeColorToROM then
        win:writeColorToROM(row, col, code)
      end
      touchedWins[win] = true
      applied = applied + 1
    end
  end

  for win in pairs(touchedWins) do
    if win.kind == "rom_palette" then
      local paletteData = paletteStateForWin(event, win, direction)
      if paletteData ~= nil then
        win.paletteData = deepCopy(paletteData)
      end
      if win.initializeFromROMOrUserCodes then
        win:initializeFromROMOrUserCodes()
      end
    elseif win.activePalette and win.syncToGlobalPalette then
      win:syncToGlobalPalette()
    end
    if app and app.invalidatePpuFrameLayersAffectedByPaletteWin then
      app:invalidatePpuFrameLayersAffectedByPaletteWin(win)
    end
  end

  return applied > 0
end

local function applyWindowRenameEvent(event, direction)
  if not (event and event.type == "window_rename" and event.win) then
    return false
  end

  local title = (direction == "undo") and event.beforeTitle or event.afterTitle
  event.win.title = title
  return true
end

local function applyRomPaletteAddressEvent(event, direction)
  if not (event and event.type == "rom_palette_address" and event.win) then
    return false
  end

  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app or nil
  local state = (direction == "undo") and event.beforeState or event.afterState
  if not state then
    return false
  end

  local win = event.win
  win.paletteData = deepCopy(state.paletteData or {})
  if win.initializeFromROMOrUserCodes then
    win:initializeFromROMOrUserCodes()
  end
  if state.selected
    and type(state.selected.col) == "number"
    and type(state.selected.row) == "number"
    and win.setSelected
  then
    win:setSelected(state.selected.col, state.selected.row)
  elseif win.clearSelected then
    win:clearSelected()
  end
  if app and app.invalidatePpuFrameLayersAffectedByPaletteWin then
    app:invalidatePpuFrameLayersAffectedByPaletteWin(win)
  end
  return true
end

local function applyWindowCreateEvent(event, direction, app)
  if not (event and event.type == "window_create" and event.win) then
    return false
  end

  local win = event.win
  local wm = event.wm or (app and app.wm) or nil
  if not wm then
    return false
  end

  if direction == "undo" then
    local closed = wm.closeWindow and wm:closeWindow(win) or false
    if closed and event.prevFocusedWin and wm.setFocus then
      local prev = event.prevFocusedWin
      if prev and not prev._closed and not prev._minimized then
        wm:setFocus(prev)
      end
    end
    return closed
  end

  if wm.reopenWindow then
    return wm:reopenWindow(win, {
      minimized = false,
      focus = true,
    })
  end

  win._closed = false
  win._minimized = false
  if wm.setFocus then
    wm:setFocus(win)
  end
  return true
end

local function applyPpuFrameRangeEvent(event, direction, app)
  if not (event and event.type == "ppu_frame_range" and app and app.applyPpuFrameRangeState) then
    return false
  end

  local state = (direction == "undo") and event.beforeState or event.afterState
  if not state then
    return false
  end

  return app:applyPpuFrameRangeState(state)
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
  if state.mirrorXOverrideSet ~= nil then
    sprite._mirrorXOverrideSet = (state.mirrorXOverrideSet == true)
  end
  if state.mirrorYOverrideSet ~= nil then
    sprite._mirrorYOverrideSet = (state.mirrorYOverrideSet == true)
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

local function applySpriteBindingState(sprite, state)
  if not (sprite and state) then
    return false
  end
  sprite.bank = state.bank
  sprite.tile = state.tile
  sprite.startAddr = state.startAddr
  sprite.tileBelow = state.tileBelow
  return true
end

local function applySpriteDragEvent(event, direction, app)
  if not (event and event.type == "sprite_drag" and event.actions) then
    return false
  end

  if event.mode == "sprite_binding" then
    local SpriteController = require("controllers.sprite.sprite_controller")
    local layersToHydrate = {}
    local applied = 0
    for _, act in ipairs(event.actions) do
      local sprite = act.sprite
      if sprite then
        local state = (direction == "undo") and act.before or act.after
        if applySpriteBindingState(sprite, state) then
          applied = applied + 1
          local win = act.win
          local li = act.layerIndex
          if win and win.layers and type(li) == "number" then
            local layer = win.layers[li]
            if layer and layer.kind == "sprite" then
              layersToHydrate[layer] = true
            end
          end
        end
      end
    end
    if applied == 0 then
      return false
    end
    local editState = app and app.appEditState
    local romRaw = (editState and editState.romRaw) or ""
    local tilesPool = editState and editState.tilesPool
    for layer in pairs(layersToHydrate) do
      SpriteController.hydrateSpriteLayer(layer, {
        romRaw = romRaw,
        tilesPool = tilesPool,
        appEditState = editState,
        keepWorld = true,
      })
    end
    return true
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

  local batchedPpu = {}
  local batchedOrder = {}
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
      if ch.isNametableByte and win.setNametableByteAt then
        local batchKey = tostring(win) .. ":" .. tostring(li)
        local batch = batchedPpu[batchKey]
        if not batch then
          batch = {
            win = win,
            layerIndex = li,
            tilesPool = ch.tilesPool or event.tilesPool,
            swaps = {},
          }
          batchedPpu[batchKey] = batch
          batchedOrder[#batchedOrder + 1] = batch
        end
        batch.swaps[#batch.swaps + 1] = {
          col = ch.col,
          row = ch.row,
          val = value,
        }
      elseif ch.isPaletteNumber then
        local L = win.layers and win.layers[li]
        if L then
          L.paletteNumbers = L.paletteNumbers or {}
          local idx = ch.linearIndex
          if type(idx) == "number" then
            local val
            if direction == "undo" then
              val = ch.before
            else
              val = ch.after
            end
            if val == nil then
              L.paletteNumbers[idx] = nil
            else
              L.paletteNumbers[idx] = val
            end
            applied = applied + 1
          end
        end
      elseif win.set then
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

  for _, batch in ipairs(batchedOrder) do
    if batch.win.applyTileSwapsFrom then
      batch.win:applyTileSwapsFrom(batch.swaps, batch.tilesPool)
      applied = applied + #batch.swaps
    else
      for _, swap in ipairs(batch.swaps) do
        batch.win:setNametableByteAt(swap.col, swap.row, swap.val, batch.tilesPool, batch.layerIndex)
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
          if WindowCaps.isPpuFrame(win) and L.kind == "tile" then
            goto continue_action
          end
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
      ::continue_action::
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

local function applyWindowMinimizeEvent(event, direction, app)
  if not (event and event.type == "window_minimize" and event.win) then
    return false
  end

  local win = event.win
  local wm = event.wm or (app and app.wm) or nil
  local targetMinimized
  local targetFocusedWin
  if direction == "undo" then
    targetMinimized = (event.beforeMinimized == true)
    targetFocusedWin = event.beforeFocusedWin
  else
    targetMinimized = (event.afterMinimized == true)
    targetFocusedWin = event.afterFocusedWin
  end
  local applied = false

  if wm then
    if targetMinimized then
      if not win._closed and not win._minimized then
        if wm.minimizeWindow then
          applied = wm:minimizeWindow(win, { recordUndo = false }) or applied
        else
          win._minimized = true
          applied = true
        end
      end
    else
      if not win._closed and win._minimized then
        if wm.restoreMinimizedWindow then
          applied = wm:restoreMinimizedWindow(win, {
            recordUndo = false,
            focus = false,
          }) or applied
        else
          win._minimized = false
          applied = true
        end
      end
    end

    if wm.setFocus then
      if targetFocusedWin and not targetFocusedWin._closed and not targetFocusedWin._minimized then
        wm:setFocus(targetFocusedWin)
        applied = true
      elseif targetFocusedWin == nil then
        local focused = wm.getFocus and wm:getFocus() or wm.focused
        if focused == win and targetMinimized then
          wm:setFocus(nil)
          applied = true
        end
      end
    end
  else
    if win._closed then
      return false
    end
    if win._minimized ~= targetMinimized then
      win._minimized = targetMinimized
      applied = true
    end
  end

  return applied
end

local function applyChrTileRevertEvent(event, direction, app)
  local state = app and app.appEditState
  if not (state and state.chrBanksBytes and state.originalChrBanksBytes) then
    return false
  end

  local useAfter = (direction == "redo")
  local appliedAny = false
  local targets = {}

  for _, t in ipairs(event.tiles or {}) do
    local bank = t.bank
    local tileIndex = t.tileIndex
    local bytes = useAfter and t.after or t.before
    if type(bank) == "number" and type(tileIndex) == "number" and type(bytes) == "table" then
      local curBank = state.chrBanksBytes[bank]
      local origBank = state.originalChrBanksBytes[bank]
      if curBank and origBank then
        local base = tileIndex * 16
        if base + 16 <= #curBank and base + 16 <= #origBank then
          for i = 1, 16 do
            curBank[base + i] = bytes[i] or 0
          end
          if app.edits then
            GameArtEditsController.resyncTileEditsForTile(app.edits, origBank, curBank, bank, tileIndex)
          end
          local tileRef = BankViewController.getTileRef(state, bank, tileIndex)
          if tileRef and tileRef.loadFromCHR then
            tileRef:loadFromCHR(curBank, tileIndex)
          end
          targets[#targets + 1] = { bank = bank, tileIndex = tileIndex }
          appliedAny = true
        end
      end
    end
  end

  if #targets > 0 then
    ChrDuplicateSync.updateTiles(state, targets)
    for _, info in ipairs(targets) do
      BankCanvasSupport.invalidateTile(app, info.bank, info.tileIndex)
    end
  end

  return appliedAny
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
  elseif event.type == "composite" then
    local applied = false
    if direction == "undo" then
      for i = #event.events, 1, -1 do
        applied = self:_applyEvent(event.events[i], direction, app) or applied
      end
    else
      for i = 1, #event.events do
        applied = self:_applyEvent(event.events[i], direction, app) or applied
      end
    end
    return applied
  elseif event.type == "remove_tile" then
    return applyRemovalEvent(event, direction, app)
  elseif event.type == "tile_drag" then
    return applyTileDragEvent(event, direction)
  elseif event.type == "sprite_drag" then
    return applySpriteDragEvent(event, direction, app)
  elseif event.type == "palette_color" then
    return applyPaletteColorEvent(event, direction)
  elseif event.type == "window_rename" then
    return applyWindowRenameEvent(event, direction)
  elseif event.type == "rom_palette_address" then
    return applyRomPaletteAddressEvent(event, direction)
  elseif event.type == "palette_link" then
    return applyPaletteLinkEvent(event, direction)
  elseif event.type == "window_create" then
    return applyWindowCreateEvent(event, direction, app)
  elseif event.type == "ppu_frame_range" then
    return applyPpuFrameRangeEvent(event, direction, app)
  elseif event.type == "animation_window_state" then
    local snap = (direction == "undo") and event.beforeState or event.afterState
    if not (event.win and snap) then
      return false
    end
    return AnimationWindowUndo.apply(event.win, snap)
  elseif event.type == "grid_layout" then
    local snap = (direction == "undo") and event.beforeState or event.afterState
    if not (event.win and snap) then
      return false
    end
    return GridLayoutUndo.apply(event.win, snap)
  elseif event.type == "chr_tile_revert" then
    return applyChrTileRevertEvent(event, direction, app)
  elseif event.type == "window_minimize" then
    return applyWindowMinimizeEvent(event, direction, app)
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
