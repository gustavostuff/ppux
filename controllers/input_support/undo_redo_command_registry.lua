-- undo_redo_command_registry.lua
-- Per-type undo/redo describe labels and apply handlers (registry for undo_redo_controller).

local M = {}

local GameArtEditsController = require("controllers.game_art.edits_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local WindowCaps = require("controllers.window.window_capabilities")
local AnimationWindowUndo = require("controllers.input_support.animation_window_undo")
local GridLayoutUndo = require("controllers.input_support.grid_layout_undo")
local SpriteController = require("controllers.sprite.sprite_controller")
local TableUtils = require("utils.table_utils")

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

local function undoRedoFindWindowById(wm, id)
  if type(id) ~= "string" or id == "" or not wm or not wm.getWindows then
    return nil
  end
  for _, w in ipairs(wm:getWindows()) do
    if w and w._id == id then
      return w
    end
  end
  return nil
end

local function applyPatternTableLinkEvent(event, direction, app)
  if not (event and event.type == "pattern_table_link" and type(event.actions) == "table" and app) then
    return false
  end

  local applied = 0
  for _, act in ipairs(event.actions) do
    local win = act.win
    local li = act.layerIndex
    local layer = win and win.layers and li and win.layers[li] or nil
    if layer then
      -- Do not use `cond and a or b` here: when undoing, `before*` may be nil/false and must win.
      local linkedId
      if direction == "undo" then
        linkedId = act.beforeLinkedId
      else
        linkedId = act.afterLinkedId
      end
      local ptSnapshot
      if direction == "undo" then
        ptSnapshot = act.beforePatternTable
      else
        ptSnapshot = act.afterPatternTable
      end

      linkedId = (type(linkedId) == "string" and linkedId ~= "") and linkedId or nil

      if linkedId then
        local ptWin = undoRedoFindWindowById(app.wm, linkedId)
        local srcLayer = ptWin and ptWin.layers and ptWin.layers[1]
        layer.linkedPatternTableWindowId = linkedId
        if srcLayer and type(srcLayer.patternTable) == "table" then
          layer.patternTable = srcLayer.patternTable
        elseif type(ptSnapshot) == "table" then
          layer.patternTable = TableUtils.deepcopy(ptSnapshot)
        else
          layer.patternTable = { ranges = {} }
        end
      else
        layer.linkedPatternTableWindowId = nil
        if type(ptSnapshot) == "table" then
          layer.patternTable = TableUtils.deepcopy(ptSnapshot)
        else
          layer.patternTable = { ranges = {} }
        end
      end

      if type(app._afterPatternTableLinkChange) == "function" then
        app:_afterPatternTableLinkChange(win, li)
      end
      applied = applied + 1
    end
  end

  return applied > 0
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
      if layer.kind == "sprite" then
        local editState = app and app.appEditState
        if SpriteController and SpriteController.hydrateSpriteLayer then
          SpriteController.hydrateSpriteLayer(layer, {
            romRaw = editState and editState.romRaw,
            tilesPool = editState and editState.tilesPool,
            appEditState = editState,
            keepWorld = true,
          })
        end
      else
        if app and app.invalidatePpuFramePaletteLayer then
          app:invalidatePpuFramePaletteLayer(win, li)
        end
        if layer.kind == "tile" and win.invalidateTileLayerCanvas then
          win:invalidateTileLayerCanvas(li)
        end
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

local function applyPatternTableAppendEvent(event, direction, app)
  if not (event and event.type == "pattern_table_append" and app and app.applyPatternTableWindowPatternSnapshot) then
    return false
  end
  local win = event.win
  if win and win._closed then
    return false
  end
  local snap = (direction == "undo") and event.beforePatternTable or event.afterPatternTable
  local li = math.floor(tonumber(event.layerIndex) or 1)
  local ptm = event.patternTableTileModes
  if type(ptm) == "table" then
    local m = (direction == "undo") and ptm.before or ptm.after
    return app:applyPatternTableWindowPatternSnapshot(win, li, snap, {
      applyTileLayerMode = true,
      tileLayerMode = m,
    })
  end
  return app:applyPatternTableWindowPatternSnapshot(win, li, snap)
end

local function applySpriteLayerOriginEvent(event, direction)
  if not event or event.type ~= "sprite_layer_origin" then
    return false
  end
  local win = event.win
  if not win or win._closed then
    return false
  end
  local li = event.layerIndex
  local layer = win.layers and win.layers[li]
  if not (layer and layer.kind == "sprite") then
    return false
  end
  local useAfter = direction == "redo"
  local ox = useAfter and event.afterOriginX or event.beforeOriginX
  local oy = useAfter and event.afterOriginY or event.beforeOriginY
  ox = math.floor(tonumber(ox) or 0)
  oy = math.floor(tonumber(oy) or 0)
  if ox < 0 then ox = 0 elseif ox > 255 then ox = 255 end
  if oy < 0 then oy = 0 elseif oy > 239 then oy = 239 end
  layer.originX = ox
  layer.originY = oy
  local tb = win.specializedToolbar
  if tb and tb.updateOriginButtons then
    tb:updateOriginButtons()
  end
  return true
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

local function invalidateTileLayerCanvasAfterPaletteUndo(win, li, ch)
  if not (win and win.invalidateTileLayerCanvas) then
    return
  end
  local cols = win.cols or 1
  if type(ch.col) == "number" and type(ch.row) == "number" then
    win:invalidateTileLayerCanvas(li, ch.col, ch.row)
  elseif type(ch.linearIndex) == "number" then
    local idx = ch.linearIndex
    local col = idx % cols
    local row = math.floor(idx / cols)
    win:invalidateTileLayerCanvas(li, col, row)
  end
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
            invalidateTileLayerCanvasAfterPaletteUndo(win, li, ch)
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
        if win.invalidateTileLayerCanvas then
          win:invalidateTileLayerCanvas(li, ch.col, ch.row)
        end
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

  if event.subtype == "ppu" then
    local tilesPool = app and app.appEditState and app.appEditState.tilesPool
    local applied = 0
    local winOrder = {}
    local byWin = {}
    for _, act in ipairs(event.actions) do
      local win = act.win
      if win and not win._closed and win.setNametableByteAt then
        local li = act.layerIndex or (win.getActiveLayerIndex and win:getActiveLayerIndex()) or 1
        local val = (direction == "undo") and act.prevByte or act.newByte
        if val ~= nil then
          if not byWin[win] then
            byWin[win] = {}
            winOrder[#winOrder + 1] = win
          end
          local list = byWin[win]
          list[#list + 1] = { act = act, li = li, val = val }
        end
      end
    end
    for _, win in ipairs(winOrder) do
      if type(win.beginNametableRomBatch) == "function" then
        win:beginNametableRomBatch()
      end
      for _, entry in ipairs(byWin[win]) do
        local act = entry.act
        win:setNametableByteAt(act.col, act.row, entry.val, tilesPool, entry.li)
        DebugController.log("debug", "SPRITE_REMOVAL", "[PPU] dir=%s col=%s row=%s val=%s", direction, tostring(act.col), tostring(act.row), tostring(entry.val))
        applied = applied + 1
      end
      if type(win.endNametableRomBatch) == "function" then
        win:endNametableRomBatch()
      end
    end
    return applied > 0
  end

  local applied = 0
  for _, act in ipairs(event.actions) do
    local win = act.win
    if win and not win._closed then
      local li = act.layerIndex or (win.getActiveLayerIndex and win:getActiveLayerIndex()) or 1

      if event.subtype == "sprite" then
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
          if win.invalidateTileLayerCanvas then
            win:invalidateTileLayerCanvas(li, act.col, act.row)
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

local function windowCanReceiveFocus(win)
  return win and not win._closed and not win._minimized and win._groupHidden ~= true
end

--- Undo: restore all minimized targets, then focus `beforeFocusedWin` when valid.
--- Redo: minimize all targets again, then focus/bring `keepWin` forward.
local function applyWindowMinimizeBatchEvent(event, direction, app)
  if not (event and event.type == "window_minimize_batch") then
    return false
  end
  local wm = event.wm or (app and app.wm)
  if not wm then
    return false
  end
  local keepWin = event.keepWin
  local targets = event.targets or {}
  local beforeFocusedWin = event.beforeFocusedWin

  if direction == "undo" then
    for i = 1, #targets do
      local w = targets[i]
      if w and not w._closed and w._minimized and wm.restoreMinimizedWindow then
        wm:restoreMinimizedWindow(w, { recordUndo = false, focus = false })
      end
    end
    if wm.setFocus then
      if windowCanReceiveFocus(beforeFocusedWin) then
        wm:setFocus(beforeFocusedWin)
      elseif windowCanReceiveFocus(keepWin) then
        wm:setFocus(keepWin)
      end
    end
  else
    for i = 1, #targets do
      local w = targets[i]
      if w and not w._closed and wm.minimizeWindow then
        wm:minimizeWindow(w, { recordUndo = false })
      end
    end
    if windowCanReceiveFocus(keepWin) then
      if wm.bringToFront then
        wm:bringToFront(keepWin)
      end
      if wm.setFocus then
        wm:setFocus(keepWin)
      end
    end
  end
  return true
end

local function applyWindowMinimizeAllEvent(event, direction, app)
  if not (event and event.type == "window_minimize_all") then
    return false
  end
  local wm = event.wm or (app and app.wm)
  if not wm then
    return false
  end
  local targets = event.targets or {}
  local beforeFocusedWin = event.beforeFocusedWin
  if direction == "undo" then
    for i = 1, #targets do
      local w = targets[i]
      if w and not w._closed and w._minimized and wm.restoreMinimizedWindow then
        wm:restoreMinimizedWindow(w, { recordUndo = false, focus = false })
      end
    end
    if wm.setFocus then
      wm:setFocus(beforeFocusedWin)
    end
  else
    for i = 1, #targets do
      local w = targets[i]
      if w and not w._closed and wm.minimizeWindow then
        wm:minimizeWindow(w, { recordUndo = false })
      end
    end
  end
  return true
end

local function applyWindowRestoreMinimizedAllEvent(event, direction, app)
  if not (event and event.type == "window_restore_minimized_all") then
    return false
  end
  local wm = event.wm or (app and app.wm)
  if not wm then
    return false
  end
  local targets = event.targets or {}
  local beforeFocusedWin = event.beforeFocusedWin
  local afterFocusedWin = event.afterFocusedWin
  if direction == "undo" then
    for i = 1, #targets do
      local w = targets[i]
      if w and not w._closed and wm.minimizeWindow then
        wm:minimizeWindow(w, { recordUndo = false })
      end
    end
    if wm.setFocus then
      wm:setFocus(beforeFocusedWin)
    end
  else
    for i = 1, #targets do
      local w = targets[i]
      if w and not w._closed and wm.restoreMinimizedWindow then
        wm:restoreMinimizedWindow(w, { recordUndo = false, focus = false })
      end
    end
    if wm.setFocus then
      wm:setFocus(afterFocusedWin)
    end
  end
  return true
end

local function applyWindowExpandAllEvent(event, direction, app)
  if not (event and event.type == "window_expand_all") then
    return false
  end
  local wm = event.wm or (app and app.wm)
  if not wm or not wm._setCollapsedWithToolbarIcon then
    return false
  end
  local targets = event.targets or {}
  if direction == "undo" then
    for i = 1, #targets do
      wm:_setCollapsedWithToolbarIcon(targets[i], true)
    end
  else
    for i = 1, #targets do
      wm:_setCollapsedWithToolbarIcon(targets[i], false)
    end
  end
  return true
end

local function applyWindowCollapseAllEvent(event, direction, app)
  if not (event and event.type == "window_collapse_all") then
    return false
  end
  local wm = event.wm or (app and app.wm)
  if not wm or not wm._restoreWindowsArrayOrder or not wm._applyChromeLayoutSnapshot then
    return false
  end
  local useBefore = (direction == "undo")
  local order = useBefore and event.beforeOrder or event.afterOrder
  local layout = useBefore and event.beforeLayout or event.afterLayout
  local focusWin = useBefore and event.beforeFocusedWin or event.afterFocusedWin
  if type(order) ~= "table" or type(layout) ~= "table" then
    return false
  end
  wm:_restoreWindowsArrayOrder(order)
  for win, snap in pairs(layout) do
    if win and snap then
      wm:_applyChromeLayoutSnapshot(win, snap)
    end
  end
  if wm.setFocus then
    wm:setFocus(focusWin)
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

local function describePaint(_event)
  return "Paint"
end

local function describeComposite(event)
  if type(event.events) == "table" then
    return string.format("Composite (%d actions)", #event.events)
  end
  return "Composite"
end

local function describeRemoveTile(event)
  local s = event.subtype
  if s == "sprite" then
    return "Remove sprite"
  elseif s == "ppu" then
    return "Remove PPU tile"
  elseif s == "animation" then
    return "Remove animation tile"
  elseif s == "static" then
    return "Remove tile"
  end
  return "Remove tile"
end

local function describeTileDrag(event)
  local mode = event.mode
  if mode == "copy" then
    return "Tile copy"
  elseif mode == "palette" then
    return "Tile palette"
  end
  return "Tile move"
end

local function describeSpriteDrag(event)
  local mode = event.mode
  if mode == "copy" then
    return "Sprite copy"
  elseif mode == "mirror" then
    return "Sprite mirror"
  elseif mode == "palette" then
    return "Sprite palette"
  elseif mode == "sprite_binding" then
    return "Sprite binding"
  end
  return "Sprite move"
end

local function describeStatic(label)
  return function(_event)
    return label
  end
end

M.COMMANDS = {
  paint = { describe = describePaint },
  composite = { describe = describeComposite },
  remove_tile = { describe = describeRemoveTile, apply = applyRemovalEvent },
  tile_drag = { describe = describeTileDrag, apply = applyTileDragEvent },
  sprite_drag = { describe = describeSpriteDrag, apply = applySpriteDragEvent },
  sprite_layer_origin = { describe = describeStatic("Sprite origin"), apply = applySpriteLayerOriginEvent },
  palette_color = { describe = describeStatic("Palette color"), apply = applyPaletteColorEvent },
  window_rename = { describe = describeStatic("Rename window"), apply = applyWindowRenameEvent },
  rom_palette_address = { describe = describeStatic("ROM palette address"), apply = applyRomPaletteAddressEvent },
  palette_link = { describe = describeStatic("Palette link"), apply = applyPaletteLinkEvent },
  pattern_table_link = { describe = describeStatic("Pattern table link"), apply = applyPatternTableLinkEvent },
  window_create = { describe = describeStatic("New window"), apply = applyWindowCreateEvent },
  ppu_frame_range = { describe = describeStatic("PPU pattern table"), apply = applyPpuFrameRangeEvent },
  pattern_table_append = { describe = describeStatic("Pattern table drop"), apply = applyPatternTableAppendEvent },
  animation_window_state = {
    describe = describeStatic("Animation edit"),
    apply = function(event, direction, _app)
      local snap = (direction == "undo") and event.beforeState or event.afterState
      if not (event.win and snap) then
        return false
      end
      return AnimationWindowUndo.apply(event.win, snap)
    end,
  },
  grid_layout = {
    describe = describeStatic("Window layout"),
    apply = function(event, direction, _app)
      local snap = (direction == "undo") and event.beforeState or event.afterState
      if not (event.win and snap) then
        return false
      end
      return GridLayoutUndo.apply(event.win, snap)
    end,
  },
  chr_tile_revert = { describe = describeStatic("Revert tile"), apply = applyChrTileRevertEvent },
  window_minimize_batch = { describe = describeStatic("Minimize others"), apply = applyWindowMinimizeBatchEvent },
  window_minimize_all = { describe = describeStatic("Minimize all"), apply = applyWindowMinimizeAllEvent },
  window_restore_minimized_all = { describe = describeStatic("Maximize all"), apply = applyWindowRestoreMinimizedAllEvent },
  window_collapse_all = { describe = describeStatic("Collapse all"), apply = applyWindowCollapseAllEvent },
  window_expand_all = { describe = describeStatic("Expand all"), apply = applyWindowExpandAllEvent },
  window_minimize = { describe = describeStatic("Minimize window"), apply = applyWindowMinimizeEvent },
  window_close = { describe = describeStatic("Close window"), apply = applyWindowCloseEvent },
}

function M.describeEvent(event)
  if not event or type(event) ~= "table" then
    return "Edit"
  end
  local cmd = M.COMMANDS[event.type]
  if cmd and cmd.describe then
    return cmd.describe(event)
  end
  return tostring(event.type or "edit")
end

function M.applyEvent(event, direction, app)
  local cmd = event and M.COMMANDS[event.type]
  if not cmd or not cmd.apply then
    return false
  end
  return cmd.apply(event, direction, app)
end

function M.applyComposite(event, direction, app, applyChild)
  if not (event and event.type == "composite" and type(event.events) == "table" and applyChild) then
    return false
  end
  local applied = false
  if direction == "undo" then
    for i = #event.events, 1, -1 do
      applied = applyChild(event.events[i], direction, app) or applied
    end
  else
    for i = 1, #event.events do
      applied = applyChild(event.events[i], direction, app) or applied
    end
  end
  return applied
end

return M
