-- pattern_table_display_controller.lua
-- Populate pattern_table window tile grids, resolve linked patternTable references, helpers for linking.

local BankViewController = require("controllers.chr.bank_view_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local PatternTableMapping = require("utils.pattern_table_mapping")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")
local TableUtils = require("utils.table_utils")
local WindowCaps = require("controllers.window.window_capabilities")
local DebugController = require("controllers.dev.debug_controller")

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
function M.getLinkedConsumersForPatternTable(wm, patternTableWin)
  local out = {}
  local ptId = patternTableWin and patternTableWin._id
  if not (wm and wm.getWindows and type(ptId) == "string" and ptId ~= "") then
    return out
  end
  for _, win in ipairs(wm:getWindows()) do
    if win ~= patternTableWin and not win._closed and not WindowCaps.isPatternTable(win) then
      for _, layerIndex in ipairs(collectNumericLayerKeys(win.layers)) do
        local layer = win.layers[layerIndex]
        if layer and layer.linkedPatternTableWindowId == ptId then
          out[#out + 1] = { win = win, layerIndex = layerIndex }
        end
      end
    end
  end
  return out
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
  layer.mode = was16 and "8x8" or "8x16"

  local pool = app and app.appEditState and app.appEditState.tilesPool
  if pool then
    M.populateTileLayerItemsFromPatternTable(win, layerIndex, {
      tilesPool = pool,
      appEditState = app and app.appEditState,
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
  local list = M.collectPatternTableWindows(wm)
  DebugController.log("info", "PATTERN_TABLE", "refreshAllPatternTableWindows: pattern_table count=%d", #list)
  for _, w in ipairs(list) do
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
      SpriteController.hydrateSpriteLayer(layer, {
        romRaw = romRaw,
        tilesPool = tilesPool,
        appEditState = state,
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
  elseif type(layer.patternTable) == "table" then
    layer.patternTable = TableUtils.deepcopy(layer.patternTable)
  else
    layer.patternTable = { ranges = {} }
  end
  return true
end

return M
