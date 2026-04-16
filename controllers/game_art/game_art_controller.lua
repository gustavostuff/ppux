-- game_art_controller.lua
-- Manages per-ROM art layouts and pixel edits.
-- Depends on: window.lua, db/index.lua, chr.lua

local GameArtEditsController = require("controllers.game_art.edits_controller")
local GameArtRomPatchController = require("controllers.game_art.rom_patch_controller")
local GameArtWindowBuilderController = require("controllers.game_art.window_builder_controller")
local GameArtLayoutIOController = require("controllers.game_art.layout_io_controller")

local TableUtils = require("utils.table_utils")
local DB = require("db.index")

local M = {}

local function normalizeSha1Key(sha1)
  if type(sha1) ~= "string" or sha1 == "" then
    return nil
  end
  return sha1:upper()
end

function M.normalizeRomPatches(romPatches)
  return GameArtRomPatchController.normalizeRomPatches(romPatches)
end

function M.applyRomPatches(romRaw, romPatches)
  return GameArtRomPatchController.applyRomPatches(romRaw, romPatches)
end

-------------------------------------------------------
-- DB query
-------------------------------------------------------
function M.hasLayout(sha1)
  local key = normalizeSha1Key(sha1)
  return key ~= nil and DB[key] ~= nil
end

function M.getLayout(sha1)
  local key = normalizeSha1Key(sha1)
  if not key then
    return nil
  end
  return DB[key]
end

function M.snapshotProject(wm, bankWindow, currentBank, edits, app)
  -- snapshotLayout now filters closed windows internally, no need to modify wm
  local layout = M.snapshotLayout(wm, bankWindow, currentBank, app)

  local editsForSave = edits or M.newEdits()
  local state = app and app.appEditState or nil
  if state and state.originalChrBanksBytes and state.chrBanksBytes then
    editsForSave = M.buildEditsFromChrDiff(state.originalChrBanksBytes, state.chrBanksBytes)
  end

  -- attach edits at project level, compressed (runtime uses expanded format)
  layout.edits = M.compressEdits(editsForSave)
  
  -- Save selected pixel brush color
  if app then
    layout.currentColor = app.currentColor or 1
    layout.syncDuplicateTiles = app.syncDuplicateTiles
    layout.romPatches = M.normalizeRomPatches(app.appEditState and app.appEditState.romPatches)
  end

  layout.kind = "project"
  layout.projectVersion = GameArtLayoutIOController.PROJECT_FORMAT_VERSION
  return layout
end

function M.saveProjectLua(path, projectTable)
  return GameArtLayoutIOController.saveProjectLua(path, projectTable)
end

function M.loadProjectLua(path)
  return GameArtLayoutIOController.loadProjectLua(path)
end

function M.loadProjectLuaString(s, path)
  return GameArtLayoutIOController.loadProjectLuaString(s, path)
end

function M.saveProjectPpux(path, projectTable)
  return GameArtLayoutIOController.saveProjectPpux(path, projectTable)
end

function M.loadProjectPpux(path)
  return GameArtLayoutIOController.loadProjectPpux(path)
end

function M.loadProjectPpuxString(s, path)
  return GameArtLayoutIOController.loadProjectPpuxString(s, path)
end

function M.getCompressedDataFrom(win)
  return GameArtLayoutIOController.getCompressedDataFrom(win)
end

function M.buildWindowsFromLayout(layout, opts)
  opts = opts or {}
  opts.decodeUserDefinedCodes = opts.decodeUserDefinedCodes or GameArtLayoutIOController.decodeUserDefinedCodes
  opts.decodePatternCanvasSnapshot = opts.decodePatternCanvasSnapshot or GameArtLayoutIOController.decodePatternCanvasSnapshot
  return GameArtWindowBuilderController.buildWindowsFromLayout(layout, opts)
end

-------------------------------------------------------
-- Snapshot layout (for writing back to DB or user layout)
-------------------------------------------------------
function M.snapshotLayout(wm, bankWindow, currentBank, app, opts)
  return GameArtLayoutIOController.snapshotLayout(wm, bankWindow, currentBank, app, opts)
end

-------------------------------------------------------
-- Layout I/O (pretty Lua)
-------------------------------------------------------
function M.saveLayoutLua(path, layoutTable)
  return GameArtLayoutIOController.saveLayoutLua(path, layoutTable)
end

function M.loadLayoutLua(path)
  return GameArtLayoutIOController.loadLayoutLua(path)
end

function M.compressEditsRLE(edits)
  return GameArtEditsController.compressEditsRLE(edits)
end

function M.decompressEditsRLE(editsRLE)
  return GameArtEditsController.decompressEditsRLE(editsRLE)
end

function M.loadEditsLua(path)
  local s, err = GameArtLayoutIOController.readFile(path)
  if not s then return nil, err end
  local chunk, perr = load(s, "@edits", "t", {})
  if not chunk then return nil, perr end
  local ok, res = pcall(chunk)
  if not ok then return nil, res end
  if type(res) ~= "table" or type(res.banks) ~= "table" then
    return nil, "invalid edits format"
  end
  return GameArtEditsController.decompressEdits(res)
end

function M.applyEdits(edits, tilesPool, chrBanksBytes, ensureTiles)
  return GameArtEditsController.applyEdits(edits, tilesPool, chrBanksBytes, ensureTiles)
end

function M.recordEdit(edits, bankIdx, tileIdx, x, y, color)
  return GameArtEditsController.recordEdit(edits, bankIdx, tileIdx, x, y, color)
end

function M.saveEditsLua(path, editsTable)
  local compressed = GameArtEditsController.compressEdits(editsTable or GameArtEditsController.newEdits())
  local s = TableUtils.serialize_lua_table(compressed)
  return GameArtLayoutIOController.writeFile(path, s)
end

function M.newEdits()
  return GameArtEditsController.newEdits()
end

function M.compressEdits(edits)
  return GameArtEditsController.compressEdits(edits)
end

function M.decompressEdits(edits)
  return GameArtEditsController.decompressEdits(edits)
end

function M.buildEditsFromChrDiff(originalChrBanksBytes, currentChrBanksBytes)
  return GameArtEditsController.buildEditsFromChrDiff(originalChrBanksBytes, currentChrBanksBytes)
end

return M
