-- Revert CHR tile bytes for specific tile indices to originalChrBanksBytes (load baseline).
-- Independent of Ctrl+Z / undo-redo paint events.

local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local BankViewController = require("controllers.chr.bank_view_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local GameArtEditsController = require("controllers.game_art.edits_controller")
local MultiSelectController = require("controllers.input_support.multi_select_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local function tileBytesMatch(origBank, curBank, tileIndex0)
  if not (origBank and curBank) then
    return false
  end
  local base = tileIndex0 * 16
  if base + 16 > #curBank or base + 16 > #origBank then
    return false
  end
  for i = 1, 16 do
    if (curBank[base + i] or 0) ~= (origBank[base + i] or 0) then
      return false
    end
  end
  return true
end

local function copyTile16(origBank, curBank, tileIndex0)
  local base = tileIndex0 * 16
  for i = 1, 16 do
    curBank[base + i] = origBank[base + i]
  end
end

local function cloneTile16FromBank(bankBytes, tileIndex0)
  local base = tileIndex0 * 16
  local t = {}
  for i = 1, 16 do
    t[i] = bankBytes[base + i] or 0
  end
  return t
end

local function refreshTileRef(state, bankIdx, tileIndex0)
  if not state then
    return
  end
  local tileRef = BankViewController.getTileRef(state, bankIdx, tileIndex0)
  if tileRef and tileRef.loadFromCHR then
    local bankBytes = state.chrBanksBytes[bankIdx]
    if bankBytes then
      tileRef:loadFromCHR(bankBytes, tileIndex0)
    end
  end
end

--- NES 8x16 pair: even top tile, bottom at +1 (matches sprite hydration).
local function resolve8x16Pair(tileIndex, tileBelow)
  local topIndex = tonumber(tileIndex)
  if type(topIndex) ~= "number" then
    return nil, nil
  end
  topIndex = math.floor(topIndex)
  local belowIndex = tonumber(tileBelow)
  if type(belowIndex) == "number" then
    return topIndex, math.floor(belowIndex)
  end
  topIndex = topIndex - (topIndex % 2)
  return topIndex, topIndex + 1
end

local function normalizeItemTileIndex(item)
  if not item then
    return nil
  end
  local tileIndex = tonumber(item.index)
  if type(tileIndex) ~= "number" then
    tileIndex = tonumber(item.tile)
  end
  if type(tileIndex) ~= "number" and item.topRef then
    tileIndex = tonumber(item.topRef.index)
  end
  if type(tileIndex) ~= "number" then
    return nil
  end
  tileIndex = math.floor(tileIndex)
  if tileIndex < 0 or tileIndex >= 512 then
    tileIndex = tileIndex % 512
  end
  return tileIndex
end

local function tileItemAt(win, layerIndex, col, row)
  if not win then
    return nil
  end
  if win.get then
    local item = win:get(col, row, layerIndex)
    if item then
      return item
    end
  end
  if win.getVirtualTileHandle and win.materializeTileHandle then
    local h = win:getVirtualTileHandle(col, row, layerIndex)
    if h then
      return win:materializeTileHandle(h, layerIndex)
    end
  end
  return nil
end

local function bankForTileItem(item, layer, win, contextSourceBank)
  return tonumber(item and item._bankIndex)
    or tonumber(contextSourceBank)
    or tonumber(layer and layer.bank)
    or tonumber(win and win.currentBank)
    or 1
end

local function appendChrOddEvenPairTargets(win, layer, layerIndex, col, row, contextSourceBank, out, seen)
  local topRow = row - (row % 2)
  if not win.getTileIndexAt then
    return
  end
  local a = win:getTileIndexAt(col, topRow)
  local b = win:getTileIndexAt(col, topRow + 1)
  if a == nil or b == nil then
    return
  end
  local itemTop = tileItemAt(win, layerIndex, col, topRow)
  local bank = bankForTileItem(itemTop, layer, win, contextSourceBank)
  local function add(ti)
    local key = bank .. ":" .. ti
    if seen[key] then
      return
    end
    seen[key] = true
    out[#out + 1] = { bank = bank, tileIndex = ti }
  end
  add(a)
  add(b)
end

local function appendNormalTileTarget(win, layer, layerIndex, col, row, contextSourceBank, out, seen)
  local item = tileItemAt(win, layerIndex, col, row)
  if not item then
    return
  end
  local idx = normalizeItemTileIndex(item)
  if idx == nil then
    return
  end
  local bank = bankForTileItem(item, layer, win, contextSourceBank)
  local key = bank .. ":" .. idx
  if seen[key] then
    return
  end
  seen[key] = true
  out[#out + 1] = { bank = bank, tileIndex = idx }
end

--- Returns a list of { bank = number, tileIndex = number } (0-based tile, 1-based bank) to revert.
--- Respects tile multi-selection when the context menu is opened on a cell inside `multiTileSelection`.
function M.collectTileRevertPairs(context)
  if not (context and context.layer) then
    return nil
  end

  local layer = context.layer
  local item = context.item
  local win = context.win
  local defaultBank = tonumber(context.sourceBank) or 1

  local out = {}
  local seen = {}

  if layer.kind == "sprite" then
    local bankIdx = defaultBank
    local mode = layer.mode or "8x8"
    if mode == "8x16" then
      local top, bot = resolve8x16Pair(item and item.tile, item and item.tileBelow)
      if top == nil then
        return nil
      end
      out[1] = { bank = bankIdx, tileIndex = top }
      out[2] = { bank = bankIdx, tileIndex = bot }
      return out
    end
    local idx = normalizeItemTileIndex(item)
    if idx == nil then
      return nil
    end
    out[1] = { bank = bankIdx, tileIndex = idx }
    return out
  end

  if layer.kind ~= "tile" or not win then
    return nil
  end

  local li = context.layerIndex or (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  if type(context.col) ~= "number" or type(context.row) ~= "number" then
    return nil
  end

  local cells
  if MultiSelectController.isTileCellSelected(win, li, context.col, context.row) then
    cells = MultiSelectController.getSelectedTileCells(win, li, nil, nil)
  end
  if not cells or #cells == 0 then
    local cols = win.cols or 0
    cells = {
      {
        col = context.col,
        row = context.row,
        idx = (context.row * cols + context.col) + 1,
      },
    }
  end

  for _, cell in ipairs(cells) do
    local col, row = cell.col, cell.row
    if WindowCaps.isChrLike(win) and win.orderMode == "oddEven" then
      appendChrOddEvenPairTargets(win, layer, li, col, row, defaultBank, out, seen)
    else
      appendNormalTileTarget(win, layer, li, col, row, defaultBank, out, seen)
    end
  end

  if #out == 0 then
    return nil
  end
  return out
end

function M.hasOriginalBaseline(app)
  local state = app and app.appEditState
  return not not (state and state.originalChrBanksBytes and state.chrBanksBytes)
end

function M.canRevertContext(app, context)
  if not M.hasOriginalBaseline(app) then
    return false
  end
  local pairs = M.collectTileRevertPairs(context)
  if not pairs then
    return false
  end
  local state = app.appEditState
  for _, p in ipairs(pairs) do
    local bankIdx = math.floor(tonumber(p.bank) or 0)
    local tileIndex0 = math.floor(tonumber(p.tileIndex) or -1)
    if bankIdx >= 1 and tileIndex0 >= 0 and tileIndex0 < 512 then
      local orig = state.originalChrBanksBytes[bankIdx]
      local cur = state.chrBanksBytes[bankIdx]
      if orig and cur and not tileBytesMatch(orig, cur, tileIndex0) then
        return true
      end
    end
  end
  return false
end

--- Copy original CHR bytes for each { bank, tileIndex } pair into current banks, refresh pool + canvas.
--- One undo event for the whole operation.
function M.revertTilePairs(app, pairs)
  if not (app and app.appEditState) then
    return false, "no app state"
  end
  if type(pairs) ~= "table" or #pairs == 0 then
    return false, "no tiles"
  end

  local state = app.appEditState
  local origBanks = state.originalChrBanksBytes
  local curBanks = state.chrBanksBytes
  if not (origBanks and curBanks) then
    return false, "no original CHR baseline"
  end

  local globalSeen = {}
  local targets = {}
  local undoTiles = {}

  for _, p in ipairs(pairs) do
    local bankIdx = math.floor(tonumber(p.bank) or 0)
    local tileIndex0 = math.floor(tonumber(p.tileIndex) or -1)
    if bankIdx >= 1 and tileIndex0 >= 0 and tileIndex0 < 512 then
      local gkey = bankIdx .. ":" .. tileIndex0
      if not globalSeen[gkey] then
        globalSeen[gkey] = true
        local origBank = origBanks[bankIdx]
        local curBank = curBanks[bankIdx]
        if origBank and curBank and not tileBytesMatch(origBank, curBank, tileIndex0) then
          undoTiles[#undoTiles + 1] = {
            bank = bankIdx,
            tileIndex = tileIndex0,
            before = cloneTile16FromBank(curBank, tileIndex0),
            after = cloneTile16FromBank(origBank, tileIndex0),
          }
          copyTile16(origBank, curBank, tileIndex0)
          if app.edits then
            GameArtEditsController.resyncTileEditsForTile(app.edits, origBank, curBank, bankIdx, tileIndex0)
          end
          refreshTileRef(state, bankIdx, tileIndex0)
          targets[#targets + 1] = { bank = bankIdx, tileIndex = tileIndex0 }
        end
      end
    end
  end

  if #targets == 0 then
    return false, "nothing to revert"
  end

  ChrDuplicateSync.updateTiles(state, targets)
  for _, t in ipairs(targets) do
    BankCanvasSupport.invalidateTile(app, t.bank, t.tileIndex)
  end

  if app.undoRedo and app.undoRedo.addChrTileRevertEvent then
    app.undoRedo:addChrTileRevertEvent({
      type = "chr_tile_revert",
      tiles = undoTiles,
    })
  elseif app.markUnsaved then
    app:markUnsaved("pixel_edit")
  end

  return true, nil, targets
end

--- Copy original CHR bytes for listed 0-based tile indices into current banks, refresh pool + canvas.
function M.revertTiles(app, bankIdx, tileIndices0)
  bankIdx = math.floor(tonumber(bankIdx) or 0)
  if bankIdx < 1 then
    return false, "bad bank"
  end
  local pairs = {}
  for _, ti in ipairs(tileIndices0 or {}) do
    local t0 = math.floor(tonumber(ti) or -1)
    if t0 >= 0 and t0 < 512 then
      pairs[#pairs + 1] = { bank = bankIdx, tileIndex = t0 }
    end
  end
  return M.revertTilePairs(app, pairs)
end

function M.revertForContext(app, context)
  local pairs = M.collectTileRevertPairs(context)
  if not pairs then
    return false, "no tiles"
  end
  return M.revertTilePairs(app, pairs)
end

return M
