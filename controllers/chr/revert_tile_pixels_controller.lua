-- Revert CHR tile bytes for specific tile indices to originalChrBanksBytes (load baseline).
-- Independent of Ctrl+Z / undo-redo paint events.

local BankCanvasSupport = require("controllers.chr.bank_canvas_support")
local BankViewController = require("controllers.chr.bank_view_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local GameArtEditsController = require("controllers.game_art.edits_controller")
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

--- Returns list of 0-based tile indices to revert for a context menu target.
function M.collectTileIndicesForContext(context)
  if not (context and context.layer) then
    return nil, nil
  end

  local bankIdx = tonumber(context.sourceBank)
  if not bankIdx then
    return nil, nil
  end

  local layer = context.layer
  local item = context.item
  local win = context.win

  if layer.kind == "sprite" then
    local mode = layer.mode or "8x8"
    if mode == "8x16" then
      local top, bot = resolve8x16Pair(item and item.tile, item and item.tileBelow)
      if top == nil then
        return nil, bankIdx
      end
      return { top, bot }, bankIdx
    end
    local idx = normalizeItemTileIndex(item)
    if idx == nil then
      return nil, bankIdx
    end
    return { idx }, bankIdx
  end

  if layer.kind == "tile" then
    if WindowCaps.isChrLike(win) and win.orderMode == "oddEven" and type(context.col) == "number" and type(context.row) == "number" then
      local topRow = context.row - (context.row % 2)
      local li = context.layerIndex or 1
      if win.getTileIndexAt then
        local a = win:getTileIndexAt(context.col, topRow)
        local b = win:getTileIndexAt(context.col, topRow + 1)
        if a ~= nil and b ~= nil then
          return { a, b }, bankIdx
        end
      end
    end
    local idx = normalizeItemTileIndex(item)
    if idx == nil then
      return nil, bankIdx
    end
    return { idx }, bankIdx
  end

  return nil, bankIdx
end

function M.hasOriginalBaseline(app)
  local state = app and app.appEditState
  return not not (state and state.originalChrBanksBytes and state.chrBanksBytes)
end

function M.canRevertContext(app, context)
  if not M.hasOriginalBaseline(app) then
    return false
  end
  local indices, bankIdx = M.collectTileIndicesForContext(context)
  if not indices or not bankIdx then
    return false
  end
  local state = app.appEditState
  local orig = state.originalChrBanksBytes[bankIdx]
  local cur = state.chrBanksBytes[bankIdx]
  if not (orig and cur) then
    return false
  end
  for _, tileIndex0 in ipairs(indices) do
    if not tileBytesMatch(orig, cur, tileIndex0) then
      return true
    end
  end
  return false
end

--- Copy original CHR bytes for listed 0-based tile indices into current banks, refresh pool + canvas.
function M.revertTiles(app, bankIdx, tileIndices0)
  if not (app and app.appEditState) then
    return false, "no app state"
  end
  local state = app.appEditState
  local origBanks = state.originalChrBanksBytes
  local curBanks = state.chrBanksBytes
  if not (origBanks and curBanks) then
    return false, "no original CHR baseline"
  end

  bankIdx = math.floor(tonumber(bankIdx) or 0)
  if bankIdx < 1 then
    return false, "bad bank"
  end

  local origBank = origBanks[bankIdx]
  local curBank = curBanks[bankIdx]
  if not (origBank and curBank) then
    return false, "bank not loaded"
  end

  local seen = {}
  local targets = {}
  local undoTiles = {}
  for _, ti in ipairs(tileIndices0 or {}) do
    local tileIndex0 = math.floor(tonumber(ti) or -1)
    if tileIndex0 >= 0 and tileIndex0 < 512 and not seen[tileIndex0] then
      seen[tileIndex0] = true
      if not tileBytesMatch(origBank, curBank, tileIndex0) then
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

function M.revertForContext(app, context)
  local indices, bankIdx = M.collectTileIndicesForContext(context)
  if not indices then
    return false, "no tiles"
  end
  return M.revertTiles(app, bankIdx, indices)
end

return M
