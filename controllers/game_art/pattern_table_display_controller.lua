-- pattern_table_display_controller.lua
-- Populate pattern_table window tile grids, resolve linked patternTable references, helpers for linking.

local BankViewController = require("controllers.chr.bank_view_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local PatternTableMapping = require("utils.pattern_table_mapping")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")
local TableUtils = require("utils.table_utils")
local WindowCaps = require("controllers.window.window_capabilities")
local DebugController = require("controllers.dev.debug_controller")
local TileInvalidationIndex = require("controllers.app.tile_invalidation_index")

local M = {}

local function getEditState(opts)
  if type(opts) ~= "table" then
    return nil
  end
  return opts.appEditState or opts.state or nil
end

function M.collectPatternTableWindows(wm)
  local out = {}
  if not (wm and wm.getWindows) then
    return out
  end
  for _, w in ipairs(wm:getWindows()) do
    if WindowCaps.isPatternTable(w) and not w._closed then
      out[#out + 1] = w
    end
  end
  table.sort(out, function(a, b)
    return tostring(a.title or a._id or "") < tostring(b.title or b._id or "")
  end)
  return out
end

local function collectNumericLayerKeys(layers)
  local numericKeys = {}
  for key, value in pairs(layers or {}) do
    if type(key) == "number" and value ~= nil then
      numericKeys[#numericKeys + 1] = key
    end
  end
  table.sort(numericKeys)
  return numericKeys
end

--- Layers in layout/PPU/OAM windows that link to this pattern_table window id.
--- Sketch canvas windows link at window level (`linkedPatternTableWindowId`); they are
--- included with `layerIndex = nil` / `kind = "sketch_canvas"`.
function M.getLinkedConsumersForPatternTable(wm, patternTableWin)
  local out = {}
  local ptId = patternTableWin and patternTableWin._id
  if not (wm and wm.getWindows and type(ptId) == "string" and ptId ~= "") then
    return out
  end
  for _, win in ipairs(wm:getWindows()) do
    if win ~= patternTableWin and not win._closed and not WindowCaps.isPatternTable(win) then
      if WindowCaps.isSketchCanvas(win) and win.linkedPatternTableWindowId == ptId then
        out[#out + 1] = { win = win, layerIndex = nil, kind = "sketch_canvas" }
      else
        for _, layerIndex in ipairs(collectNumericLayerKeys(win.layers)) do
          local layer = win.layers[layerIndex]
          if layer and layer.linkedPatternTableWindowId == ptId then
            out[#out + 1] = { win = win, layerIndex = layerIndex }
          end
        end
      end
    end
  end
  return out
end

local function isSketchOwnedPatternTableWindow(win, wm)
  local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
  return SketchCanvasPackController.isSketchOwnedPatternTable(win, wm)
end

--- Fill layer.items for a 16x16-style grid from layer.patternTable + tilesPool.
function M.populateTileLayerItemsFromPatternTable(win, layerIndex, opts)
  if not (win and type(layerIndex) == "number") then
    return false
  end
  layerIndex = math.floor(layerIndex)
  local layer = win.layers and win.layers[layerIndex]
  if not (layer and layer.kind == "tile" and type(layer.patternTable) == "table") then
    return false
  end
  local wm = opts and opts.wm or nil
  if isSketchOwnedPatternTableWindow(win, wm) then
    -- Sketch-owned pattern tables hold scratch tiles; CHR populate must not wipe them.
    return false, "sketch_owned"
  end
  local tilesPool = opts and opts.tilesPool or nil
  if not tilesPool then
    layer.items = {}
    return false
  end

  local map, mapErr = PpuRange.buildPatternTableMapAllowPartial(layer.patternTable)
  if not map then
    layer.items = {}
    return false, mapErr
  end

  local state = getEditState(opts)
  if state and state.chrBanksBytes and type(layer.patternTable.ranges) == "table" then
    for _, r in ipairs(layer.patternTable.ranges) do
      PpuRange.foreachBankInPatternRange(r, function(bank)
        bank = tonumber(bank)
        if bank and state.chrBanksBytes[bank] then
          BankViewController.ensureBankTiles(state, bank)
        end
      end)
    end
  end
  if opts and type(opts.ensureTiles) == "function" and type(layer.patternTable.ranges) == "table" then
    for _, r in ipairs(layer.patternTable.ranges) do
      PpuRange.foreachBankInPatternRange(r, function(bank)
        bank = tonumber(bank)
        if bank then
          pcall(opts.ensureTiles, bank)
        end
      end)
    end
  end

  layer.items = {}
  local cols = math.max(1, math.floor(tonumber(win.cols) or 16))
  local rows = math.max(1, math.floor(tonumber(win.rows) or 16))
  local layoutMode = layer.mode or "8x8"
  local maxPos = math.min(255, rows * cols - 1)

  for pos = 0, maxPos do
    local logicalIndex = BankViewController.chrOrderingIndexForGridPos(layoutMode, pos)
    local entry = map[logicalIndex]
    local idx = pos + 1
    if entry then
      local bankTiles = tilesPool[entry.bank]
      local tileRef = bankTiles and bankTiles[entry.tileIndex] or nil
      layer.items[idx] = tileRef
    else
      layer.items[idx] = nil
    end
  end

  if win.invalidateTileLayerCanvas then
    win:invalidateTileLayerCanvas(layerIndex)
  end
  TileInvalidationIndex.markDirtyFromCtx()
  return true
end

--- Toggle CHR grid ordering between 8×8 row-major vs 8×16 vertical pairs (`BankViewController` mapping).
--- @return `"8×8"|"8×16 pairs"|nil`
function M.toggleTileLayerChrLayout(win, layerIndex, app)
  layerIndex = math.floor(tonumber(layerIndex) or 1)
  local layer = win and win.layers and win.layers[layerIndex]
  if not (layer and layer.kind == "tile") then
    return nil
  end

  local m = layer.mode or "8x8"
  local was16 = (m == "8x16" or m == "oddEven")
  local fromMode = was16 and "8x16" or "8x8"
  layer.mode = was16 and "8x8" or "8x16"
  local toMode = layer.mode

  local wm = app and app.wm or nil
  if isSketchOwnedPatternTableWindow(win, wm) then
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    local sketch = nil
    if type(win.linkedSketchCanvasWindowId) == "string" and win.linkedSketchCanvasWindowId ~= "" then
      sketch = wm and wm.findWindowById and wm:findWindowById(win.linkedSketchCanvasWindowId) or nil
    end
    if sketch
      and type(sketch.tilesPool) == "table"
      and #sketch.tilesPool > 0
    then
      -- Re-place catalog using the new layout mode (logical indices unchanged).
      SketchCanvasPackController.applyPackToLinkedPatternTable(sketch, wm)
    else
      SketchCanvasPackController.relayoutSketchOwnedPatternTableItems(win, fromMode, toMode)
    end
    return ((layer.mode or "8x8") == "8x16") and "8x16 pairs" or "8x8"
  end

  local pool = app and app.appEditState and app.appEditState.tilesPool
  if pool then
    M.populateTileLayerItemsFromPatternTable(win, layerIndex, {
      tilesPool = pool,
      appEditState = app and app.appEditState,
      wm = wm,
      ensureTiles = function(bankIdx)
        local st = app and app.appEditState
        if st and st.chrBanksBytes and st.chrBanksBytes[bankIdx] then
          BankViewController.ensureBankTiles(st, bankIdx)
        end
      end,
    })
  elseif win.invalidateTileLayerCanvas then
    win:invalidateTileLayerCanvas(layerIndex)
  end

  return ((layer.mode or "8x8") == "8x16") and "8x16 pairs" or "8x8"
end

function M.resolveLinkedPatternTableLayers(wm)
  if not (wm and wm.getWindows) then
    return
  end
  local byId = {}
  for _, w in ipairs(wm:getWindows()) do
    if w._id then
      byId[w._id] = w
    end
  end

  local linked = 0
  local filled = 0
  for _, w in ipairs(wm:getWindows()) do
    if w.layers then
      for li, L in ipairs(w.layers) do
        if type(L.linkedPatternTableWindowId) == "string" and L.linkedPatternTableWindowId ~= "" then
          linked = linked + 1
          local src = byId[L.linkedPatternTableWindowId]
          local srcLayer = src and src.layers and src.layers[1]
          if not src then
            DebugController.log(
              "warning",
              "PATTERN_TABLE",
              "resolveLinked: no window with id=%q (consumer win=%q layer=%d)",
              L.linkedPatternTableWindowId,
              tostring(w._id or w.title or "?"),
              li
            )
          elseif not (srcLayer and type(srcLayer.patternTable) == "table") then
            DebugController.log(
              "warning",
              "PATTERN_TABLE",
              "resolveLinked: pattern_table window %q has no layer[1].patternTable",
              L.linkedPatternTableWindowId
            )
          end
          if srcLayer and type(srcLayer.patternTable) == "table" then
            L.patternTable = srcLayer.patternTable
            filled = filled + 1
          end
        end
      end
    end
  end
  DebugController.log(
    "info",
    "PATTERN_TABLE",
    "resolveLinkedPatternTableLayers: linked_layers=%d patternTable_assigned=%d",
    linked,
    filled
  )
end

function M.refreshAllPatternTableWindows(wm, opts)
  if not wm then
    return
  end
  opts = type(opts) == "table" and opts or {}
  if opts.wm == nil then
    opts.wm = wm
  end
  local list = M.collectPatternTableWindows(wm)
  local total = #list
  DebugController.log("info", "PATTERN_TABLE", "refreshAllPatternTableWindows: pattern_table count=%d", total)
  for _, w in ipairs(list) do
    if isSketchOwnedPatternTableWindow(w, wm) then
      DebugController.log(
        "info",
        "PATTERN_TABLE",
        "refresh skip sketch-owned id=%s title=%q",
        tostring(w._id or "?"),
        tostring(w.title or "")
      )
    else
      local ok, err = M.populateTileLayerItemsFromPatternTable(w, 1, opts)
      DebugController.log(
        "info",
        "PATTERN_TABLE",
        "refresh populate id=%s title=%q ok=%s err=%s",
        tostring(w._id or "?"),
        tostring(w.title or ""),
        tostring(ok),
        err and tostring(err) or ""
      )
    end
  end
end

function M.linkContentLayerToPatternTableWindow(contentWin, layerIndex, patternTableWin)
  if not (contentWin and patternTableWin and WindowCaps.isPatternTable(patternTableWin)) then
    return false, "invalid_pattern_table_window"
  end
  layerIndex = math.floor(tonumber(layerIndex) or 1)
  local layer = contentWin.layers and contentWin.layers[layerIndex]
  if not (layer and (layer.kind == "tile" or layer.kind == "sprite")) then
    return false, "invalid_layer"
  end
  local srcLayer = patternTableWin.layers and patternTableWin.layers[1]
  if not (srcLayer and type(srcLayer.patternTable) == "table") then
    return false, "pattern_table_window_has_no_table"
  end
  layer.linkedPatternTableWindowId = patternTableWin._id
  layer.patternTable = srcLayer.patternTable
  return true
end

--- Copy an existing sprite-layer pattern-table link onto any OAM frame layers that lack one.
function M.syncOamAnimationSpriteLayerPatternTables(contentWin)
  if not WindowCaps.isOamAnimation(contentWin) then
    return false
  end

  local PatternTableMapping = require("utils.pattern_table_mapping")
  local donor = nil
  for _, layer in ipairs(contentWin.layers or {}) do
    if layer and layer.kind == "sprite" then
      if type(layer.linkedPatternTableWindowId) == "string" and layer.linkedPatternTableWindowId ~= "" then
        donor = layer
        break
      end
      local ok = PatternTableMapping.validate(layer.patternTable)
      if ok then
        donor = layer
        break
      end
    end
  end
  if not donor then
    return false
  end

  local changed = false
  for _, layer in ipairs(contentWin.layers or {}) do
    if layer and layer.kind == "sprite" and layer ~= donor then
      local ok = PatternTableMapping.validate(layer.patternTable)
      if not ok then
        if type(donor.linkedPatternTableWindowId) == "string" and donor.linkedPatternTableWindowId ~= "" then
          layer.linkedPatternTableWindowId = donor.linkedPatternTableWindowId
        end
        if type(donor.patternTable) == "table" then
          layer.patternTable = donor.patternTable
        end
        changed = true
      end
    end
  end
  return changed
end

--- ROM OAM animations: tie every sprite frame layer to the same pattern-table window CHR map.
function M.linkAllOamSpriteLayersToPatternTableWindow(contentWin, patternTableWin)
  if not (contentWin and patternTableWin and WindowCaps.isOamAnimation(contentWin)) then
    return false
  end
  for li, layer in ipairs(contentWin.layers or {}) do
    if layer and layer.kind == "sprite" then
      local ok = M.linkContentLayerToPatternTableWindow(contentWin, li, patternTableWin)
      if ok ~= true then
        return ok
      end
    end
  end
  return true
end

function M.unlinkAllOamSpriteLayersPatternTable(contentWin)
  if not (contentWin and WindowCaps.isOamAnimation(contentWin)) then
    return false
  end
  for li, layer in ipairs(contentWin.layers or {}) do
    if layer and layer.kind == "sprite" then
      M.unlinkContentLayerPatternTable(contentWin, li)
    end
  end
  return true
end

--- After editing a shared patternTable table in-place (same table ref), refresh PPU runtime ref layers,
--- nametable CHR cells, and any linked sprite layers that resolve ROM OAM tiles through this map.
function M.invalidateConsumersUsingPatternTable(app, patternTableRef)
  if not (app and patternTableRef and app.wm and app.wm.getWindows) then
    return
  end
  if type(patternTableRef) ~= "table" then
    return
  end

  -- Re-apply link targets first: some code paths (e.g. nametable hydrate with opts.patternTable)
  -- can replace a linked layer's patternTable with a detached copy, so edits on the pattern_table
  -- window no longer propagate until we re-stitch references.
  M.resolveLinkedPatternTableLayers(app.wm)

  local SpriteController = require("controllers.sprite.sprite_controller")
  local state = app.appEditState or {}
  local romRaw = type(state.romRaw) == "string" and state.romRaw or ""
  local tilesPool = state.tilesPool

  --- Which standalone pattern-table window owns this `patternTable` object (layer[1]).
  local patternTableOwnerId = nil
  for _, w in ipairs(app.wm:getWindows()) do
    if WindowCaps.isPatternTable(w) and not w._closed then
      local L1 = w.layers and w.layers[1]
      if L1 and L1.patternTable == patternTableRef and type(w._id) == "string" and w._id ~= "" then
        patternTableOwnerId = w._id
        break
      end
    end
  end

  local function syncSpriteLayerPatternTableRef(layer)
    if not (layer and layer.kind == "sprite") then
      return false
    end
    if layer.patternTable == patternTableRef then
      return true
    end
    if patternTableOwnerId and layer.linkedPatternTableWindowId == patternTableOwnerId then
      layer.patternTable = patternTableRef
      return true
    end
    return false
  end

  --- PPU nametable tile layers may still hold an outdated `patternTable` copy until the map is complete.
  local function syncConsumerTileLayerPatternTableRef(layer)
    if not (layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true) then
      return
    end
    if patternTableOwnerId and layer.linkedPatternTableWindowId == patternTableOwnerId then
      layer.patternTable = patternTableRef
    end
  end

  local function hydrateLinkedSprite(layer)
    if syncSpriteLayerPatternTableRef(layer) then
      -- keepWorld: after ROM write-back, stale dx must not re-apply on top of new bases.
      SpriteController.hydrateSpriteLayer(layer, {
        romRaw = romRaw,
        tilesPool = tilesPool,
        appEditState = state,
        keepWorld = true,
      })
    end
  end

  for _, win in ipairs(app.wm:getWindows()) do
    if not (win and win.layers) then
      goto continue
    end

    if WindowCaps.isOamAnimation(win) then
      for _, layer in ipairs(win.layers) do
        hydrateLinkedSprite(layer)
      end
      goto continue
    end

    if WindowCaps.isPpuFrame(win) and type(app._ensurePpuPatternTableReferenceLayer) == "function" then
      if win.patternLayerSoloMode == true then
        for li, layer in ipairs(win.layers) do
          syncConsumerTileLayerPatternTableRef(layer)
          if layer
            and layer.kind == "tile"
            and layer.patternTable == patternTableRef
            and layer._runtimePatternTableRefLayer ~= true
          then
            app:_ensurePpuPatternTableReferenceLayer({
              win = win,
              layer = layer,
              layerIndex = li,
            }, { keepActiveLayer = true, allowReferenceLayer = true })
          end
        end
      elseif win.removePatternReferenceLayers then
        win:removePatternReferenceLayers()
      end
    end

    if WindowCaps.isPpuFrame(win) and type(tilesPool) == "table" and type(win.refreshNametableVisuals) == "function" then
      for li, layer in ipairs(win.layers) do
        syncConsumerTileLayerPatternTableRef(layer)
        if layer
          and layer.kind == "tile"
          and layer._runtimePatternTableRefLayer ~= true
          and layer.patternTable == patternTableRef
          and type(layer.nametableStartAddr) == "number"
          and type(layer.nametableEndAddr) == "number"
        then
          local didLateHydrate = false
          if #(win.nametableBytes or {}) == 0 then
            local mapOk = PatternTableMapping.validate(layer.patternTable)
            if mapOk and type(romRaw) == "string" and romRaw ~= "" then
              local okH, errH = NametableTilesController.hydrateWindowNametable(win, layer, {
                romRaw = romRaw,
                tilesPool = tilesPool,
                ensureTiles = function(bank)
                  local st = state.chrBanksBytes
                  if not (st and st[bank]) then
                    return false
                  end
                  BankViewController.ensureBankTiles(state, bank)
                  return true
                end,
                nametableStartAddr = layer.nametableStartAddr,
                nametableEndAddr = layer.nametableEndAddr,
                tileSwaps = layer.tileSwaps,
                userDefinedAttrs = layer.userDefinedAttrs,
                onTheFlyReplacements = layer.onTheFlyReplacements,
                codec = layer.codec,
              })
              if okH then
                didLateHydrate = true
              else
                DebugController.log(
                  "warning",
                  "PATTERN_TABLE",
                  "invalidateConsumers: late nametable hydrate for %q failed: %s",
                  tostring(win.title or win._id or "?"),
                  tostring(errH or "?")
                )
              end
            end
          end
          if not didLateHydrate then
            win:refreshNametableVisuals(tilesPool, li)
          end
        end
        hydrateLinkedSprite(layer)
      end
    elseif WindowCaps.isPpuFrame(win) then
      for _, layer in ipairs(win.layers) do
        hydrateLinkedSprite(layer)
      end
    end

    ::continue::
  end
  TileInvalidationIndex.markDirtyFromCtx()
end

function M.unlinkContentLayerPatternTable(contentWin, layerIndex)
  layerIndex = math.floor(tonumber(layerIndex) or 1)
  local layer = contentWin.layers and contentWin.layers[layerIndex]
  if not layer then
    return false
  end
  layer.linkedPatternTableWindowId = nil
  -- PPU nametable + sprite layers: unlink means stop using linked CHR ranges here.
  -- A detached deepcopy keeps the old mapping and leaves nametable tiles / sprites looking linked.
  if WindowCaps.isPpuFrame(contentWin)
    and (
      (layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true)
      or layer.kind == "sprite"
    )
  then
    layer.patternTable = { ranges = {} }
    if layer.kind == "tile" then
      layer.items = {}
      layer._ppuxNametableVisualsFresh = false
      if contentWin.clearNametableLayerCanvasContents then
        contentWin:clearNametableLayerCanvasContents(layerIndex)
      elseif contentWin.invalidateNametableLayerCanvas then
        contentWin:invalidateNametableLayerCanvas(layerIndex)
      end
      if contentWin.invalidateNametableShadowPreview then
        contentWin:invalidateNametableShadowPreview()
      end
    end
  elseif type(layer.patternTable) == "table" then
    layer.patternTable = TableUtils.deepcopy(layer.patternTable)
  else
    layer.patternTable = { ranges = {} }
  end
  return true
end

local function copyByteArray(arr)
  if type(arr) ~= "table" then
    return nil
  end
  local out = {}
  for i = 1, #arr do
    out[i] = arr[i]
  end
  return out
end

local function capturePpuNametableUndoState(win, layer)
  if not (WindowCaps.isPpuFrame(win) and layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true) then
    return nil
  end
  return {
    nametableBytes = copyByteArray(win.nametableBytes),
    nametableAttrBytes = copyByteArray(win.nametableAttrBytes),
    originalNametableBytes = copyByteArray(win._originalNametableBytes),
    originalNametableAttrBytes = copyByteArray(win._originalNametableAttrBytes),
    romDecodedNametableAttrBytes = copyByteArray(win._romDecodedNametableAttrBytes),
    tileSwapsWin = TableUtils.deepcopy(win._tileSwaps),
    tileSwapsLayer = TableUtils.deepcopy(layer.tileSwaps),
    userDefinedAttrs = layer.userDefinedAttrs,
    onTheFlyReplacements = TableUtils.deepcopy(layer.onTheFlyReplacements),
    nametableStart = win.nametableStart,
    originalTotalByteNumber = win.originalTotalByteNumber,
  }
end

local function restorePpuNametableUndoState(win, layer, snap)
  if not (win and layer and type(snap) == "table") then
    return
  end
  if snap.nametableBytes then
    win.nametableBytes = copyByteArray(snap.nametableBytes)
  end
  if snap.nametableAttrBytes then
    win.nametableAttrBytes = copyByteArray(snap.nametableAttrBytes)
  end
  if snap.originalNametableBytes then
    win._originalNametableBytes = copyByteArray(snap.originalNametableBytes)
  end
  if snap.originalNametableAttrBytes then
    win._originalNametableAttrBytes = copyByteArray(snap.originalNametableAttrBytes)
  end
  if snap.romDecodedNametableAttrBytes then
    win._romDecodedNametableAttrBytes = copyByteArray(snap.romDecodedNametableAttrBytes)
  end
  if snap.tileSwapsWin ~= nil then
    win._tileSwaps = TableUtils.deepcopy(snap.tileSwapsWin)
  end
  if snap.tileSwapsLayer ~= nil then
    layer.tileSwaps = TableUtils.deepcopy(snap.tileSwapsLayer)
  end
  layer.userDefinedAttrs = snap.userDefinedAttrs
  if snap.onTheFlyReplacements ~= nil then
    layer.onTheFlyReplacements = TableUtils.deepcopy(snap.onTheFlyReplacements)
  end
  if snap.nametableStart ~= nil then
    win.nametableStart = snap.nametableStart
  end
  if snap.originalTotalByteNumber ~= nil then
    win.originalTotalByteNumber = snap.originalTotalByteNumber
  end
end

local function refreshConsumerAfterPatternTableRelink(win, layerIndex, app)
  local layer = win and win.layers and win.layers[layerIndex]
  if not layer then
    return
  end
  local state = app and app.appEditState or nil
  if WindowCaps.isPpuFrame(win)
    and layer.kind == "tile"
    and layer._runtimePatternTableRefLayer ~= true
    and win.refreshNametableVisuals
  then
    local tilesPool = state and state.tilesPool or nil
    if tilesPool and type(layer.patternTable) == "table" and type(layer.patternTable.ranges) == "table" then
      local ensured = {}
      for _, r in ipairs(layer.patternTable.ranges) do
        PpuRange.foreachBankInPatternRange(r, function(bankIdx)
          local b = math.floor(tonumber(bankIdx) or -1)
          if b >= 1 and ensured[b] == nil and state and state.chrBanksBytes and state.chrBanksBytes[b] then
            ensured[b] = true
            BankViewController.ensureBankTiles(state, b)
          end
        end)
      end
    end
    win:refreshNametableVisuals(tilesPool, layerIndex)
  elseif layer.kind == "sprite" and state then
    local SpriteController = require("controllers.sprite.sprite_controller")
    SpriteController.hydrateSpriteLayer(layer, {
      romRaw = state.romRaw or "",
      tilesPool = state.tilesPool,
      appEditState = state,
      keepWorld = true,
    })
  end
  if win.specializedToolbar and win.specializedToolbar.updateIcons then
    win.specializedToolbar:updateIcons()
  end
end

--- Snapshot PPU / OAM (non-sketch) links before a pattern table window is closed.
function M.capturePatternTableConsumerCloseRestore(ptWin, wm)
  local actions = {}
  if not (WindowCaps.isPatternTable(ptWin) and wm) then
    return nil
  end
  local ptId = ptWin._id
  if type(ptId) ~= "string" or ptId == "" then
    return nil
  end
  for _, entry in ipairs(M.getLinkedConsumersForPatternTable(wm, ptWin)) do
    if entry.kind ~= "sketch_canvas" and type(entry.layerIndex) == "number" then
      local layer = entry.win and entry.win.layers and entry.win.layers[entry.layerIndex]
      if layer then
        local pt = layer.patternTable
        actions[#actions + 1] = {
          win = entry.win,
          layerIndex = entry.layerIndex,
          linkedId = ptId,
          patternTable = type(pt) == "table" and TableUtils.deepcopy(pt) or { ranges = {} },
          nametable = capturePpuNametableUndoState(entry.win, layer),
        }
      end
    end
  end
  if #actions == 0 then
    return nil
  end
  return actions
end

--- Re-link PPU / OAM consumers after undoing a pattern table window close.
--- Restores in-memory nametable bytes/attrs and refreshes visuals. Do not ROM-rehydrate:
--- that path ran with an empty pattern table on close and wiped tile swaps / attrs.
function M.restorePatternTableConsumerCloseUndo(actions, wm, app)
  if type(actions) ~= "table" or #actions == 0 then
    return false
  end
  local restored = 0
  for _, act in ipairs(actions) do
    local win = act.win
    local li = act.layerIndex
    local layer = win and win.layers and li and win.layers[li] or nil
    if layer then
      restorePpuNametableUndoState(win, layer, act.nametable)
      local linkedId = (type(act.linkedId) == "string" and act.linkedId ~= "") and act.linkedId or nil
      layer.linkedPatternTableWindowId = linkedId
      local ptWin = linkedId and wm and wm.findWindowById and wm:findWindowById(linkedId) or nil
      local srcLayer = ptWin and ptWin.layers and ptWin.layers[1]
      if srcLayer and type(srcLayer.patternTable) == "table" then
        layer.patternTable = srcLayer.patternTable
      elseif type(act.patternTable) == "table" then
        layer.patternTable = TableUtils.deepcopy(act.patternTable)
      else
        layer.patternTable = { ranges = {} }
      end
      refreshConsumerAfterPatternTableRelink(win, li, app)
      restored = restored + 1
    end
  end
  return restored > 0
end

--- Pattern table window closed: detach PPU / OAM consumers (sketch handled separately).
function M.onPatternTableWindowClosed(ptWin, wm, app)
  if not (WindowCaps.isPatternTable(ptWin) and wm) then
    return 0
  end
  -- Stash for window_close undo (HeaderToolbar reads this after closeWindow returns).
  ptWin._ptConsumerCloseUndoRestore = M.capturePatternTableConsumerCloseRestore(ptWin, wm)
  local consumers = M.getLinkedConsumersForPatternTable(wm, ptWin)
  local n = 0
  for _, entry in ipairs(consumers) do
    if entry.kind ~= "sketch_canvas" and type(entry.layerIndex) == "number" then
      if M.unlinkContentLayerPatternTable(entry.win, entry.layerIndex) then
        n = n + 1
        local win = entry.win
        -- Do not call `_afterPatternTableLinkChange`: it ROM-rehydrates with an empty
        -- pattern table and overwrites nametableBytes / attrs / tile swaps.
        if win and win.removePatternReferenceLayers then
          win:removePatternReferenceLayers(entry.layerIndex)
        end
        if win and win.specializedToolbar and win.specializedToolbar.updateIcons then
          win.specializedToolbar:updateIcons()
        end
      end
    end
  end
  if n > 0 and app and app.wm and app.wm.getWindows then
    for _, w in ipairs(app.wm:getWindows()) do
      if WindowCaps.isPatternTable(w) and w.specializedToolbar and w.specializedToolbar.updateIcons then
        w.specializedToolbar:updateIcons()
      end
    end
  end
  return n
end

return M
