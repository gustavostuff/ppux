-- pattern_table_display_controller.lua
-- Populate pattern_table window tile grids, resolve linked patternTable references, helpers for linking.

local BankViewController = require("controllers.chr.bank_view_controller")
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
      local bank = type(r) == "table" and tonumber(r.bank) or nil
      if bank and state.chrBanksBytes[bank] then
        BankViewController.ensureBankTiles(state, bank)
      end
    end
  end
  if opts and type(opts.ensureTiles) == "function" and type(layer.patternTable.ranges) == "table" then
    for _, r in ipairs(layer.patternTable.ranges) do
      local bank = type(r) == "table" and tonumber(r.bank) or nil
      if bank then
        pcall(opts.ensureTiles, bank)
      end
    end
  end

  layer.items = {}
  local cols = math.max(1, math.floor(tonumber(win.cols) or 16))
  local rows = math.max(1, math.floor(tonumber(win.rows) or 16))

  for logicalIndex = 0, 255 do
    local entry = map[logicalIndex]
    local col = logicalIndex % 16
    local row = math.floor(logicalIndex / 16)
    if row < rows and col < cols then
      local idx = row * cols + col + 1
      if entry then
        local bankTiles = tilesPool[entry.bank]
        local tileRef = bankTiles and bankTiles[entry.tileIndex] or nil
        layer.items[idx] = tileRef
      else
        layer.items[idx] = nil
      end
    end
  end

  if win.invalidateTileLayerCanvas then
    win:invalidateTileLayerCanvas(layerIndex)
  end
  return true
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

--- After editing a shared patternTable table in-place (same table ref), refresh PPU runtime ref layers.
function M.invalidateConsumersUsingPatternTable(app, patternTableRef)
  if not (app and patternTableRef and app.wm and app.wm.getWindows) then
    return
  end
  if type(patternTableRef) ~= "table" then
    return
  end
  if type(app._ensurePpuPatternTableReferenceLayer) ~= "function" then
    return
  end

  for _, win in ipairs(app.wm:getWindows()) do
    if win and win.layers and WindowCaps.isPpuFrame(win) then
      for li, layer in ipairs(win.layers) do
        if layer
          and layer.kind == "tile"
          and layer.patternTable == patternTableRef
          and layer._runtimePatternTableRefLayer ~= true
        then
          app:_ensurePpuPatternTableReferenceLayer({
            win = win,
            layer = layer,
            layerIndex = li,
          }, { keepActiveLayer = true })
        end
      end
    end
  end
end

function M.unlinkContentLayerPatternTable(contentWin, layerIndex)
  layerIndex = math.floor(tonumber(layerIndex) or 1)
  local layer = contentWin.layers and contentWin.layers[layerIndex]
  if not layer then
    return false
  end
  layer.linkedPatternTableWindowId = nil
  if type(layer.patternTable) == "table" then
    layer.patternTable = TableUtils.deepcopy(layer.patternTable)
  else
    layer.patternTable = { ranges = {} }
  end
  return true
end

return M
