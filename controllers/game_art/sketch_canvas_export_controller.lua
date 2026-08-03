-- sketch_canvas_export_controller.lua
-- Encode / write CHR + nametable binaries from a packed sketch canvas.
-- Gallery ROM assembly consumes these buffers (see sketch_canvas_gallery_rom_controller
-- and asm/gallery/).

local chr = require("chr")
local WindowCaps = require("controllers.window.window_capabilities")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")

local M = {}

M.CHR_BANK_4K = 4096
M.CHR_BANK_8K = 8192
M.PT_SLOT_COUNT = 256
M.NAMETABLE_TILES = 960
M.NAMETABLE_ATTRS = 64
M.NAMETABLE_FULL = M.NAMETABLE_TILES + M.NAMETABLE_ATTRS

local function splitPath(p)
  local dir, base = tostring(p or ""):match("^(.*)[/\\]([^/\\]+)$")
  if not dir then
    return "", tostring(p or "")
  end
  return dir, base
end

local function stripExt(name)
  return (tostring(name or ""):gsub("%.[^%.]+$", ""))
end

local function sanitizeStem(title)
  local s = tostring(title or "sketch"):gsub("%s+", "_")
  s = s:gsub("[^%w%_%-]+", "")
  if s == "" then
    s = "sketch"
  end
  return s
end

local function pathSep()
  return (package.config:sub(1, 1) == "\\") and "\\" or "/"
end

local function joinDir(dir, name)
  dir = tostring(dir or "")
  if dir == "" or dir == "." then
    return name
  end
  local sep = pathSep()
  if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then
    return dir .. name
  end
  return dir .. sep .. name
end

function M.defaultExportDir(app)
  -- Prefer the folder of the currently loaded / last-saved project.
  if app then
    for _, key in ipairs({ "projectPath", "encodedProjectPath" }) do
      local path = app[key]
      if type(path) == "string" and path ~= "" then
        local dir = splitPath(path)
        if dir and dir ~= "" then
          return dir
        end
      end
    end
  end
  local path = app and app.appEditState and app.appEditState.romOriginalPath
  if type(path) == "string" and path ~= "" then
    local dir = splitPath(path)
    if dir and dir ~= "" then
      return dir
    end
  end
  -- No project/ROM path: prefer the user home directory so exports are easy to find.
  if love and love.filesystem and type(love.filesystem.getUserDirectory) == "function" then
    local home = love.filesystem.getUserDirectory()
    if type(home) == "string" and home ~= "" then
      return (home:gsub("[/\\]+$", ""))
    end
  end
  return "."
end

function M.defaultChrPath(app, win)
  local stem = sanitizeStem(win and win.title)
  return joinDir(M.defaultExportDir(app), stem .. ".chr")
end

function M.defaultNametablePath(app, win)
  local stem = sanitizeStem(win and win.title)
  return joinDir(M.defaultExportDir(app), stem .. ".nam")
end

--- Write binary data (Lua string or 1-based byte array) to path.
function M.writeBinaryFile(path, data)
  if type(path) ~= "string" or path == "" then
    return false, "missing path"
  end
  local payload
  if type(data) == "string" then
    payload = data
  elseif type(data) == "table" then
    payload = chr.bytesToString(data)
  else
    return false, "data must be string or byte table"
  end
  local fh, err = io.open(path, "wb")
  if not fh then
    return false, err or "open failed"
  end
  local okWrite, errWrite = fh:write(payload)
  fh:close()
  if not okWrite then
    return false, errWrite or "write failed"
  end
  return true, path
end

--- Pad a 4KB CHR bank to 8KB (high half zeros) for CNROM gallery banks.
function M.padChrBankTo8KiB(chr4k)
  local s
  if type(chr4k) == "string" then
    s = chr4k
  elseif type(chr4k) == "table" then
    s = chr.bytesToString(chr4k)
  else
    return nil, "CHR bank required"
  end
  if #s ~= M.CHR_BANK_4K then
    return nil, string.format("expected %d-byte CHR bank, got %d", M.CHR_BANK_4K, #s)
  end
  return s .. string.rep("\0", M.CHR_BANK_4K)
end

local function requirePackedSketch(win)
  if not WindowCaps.isSketchCanvas(win) then
    return false, "not a sketch canvas"
  end
  if not SketchCanvasPackController.hasPackData(win) then
    return false, "Generate a pack before exporting"
  end
  return true
end

--- Encode 256 logical PT slots (uniques + padding) to a 4096-byte CHR bank string.
function M.encodeChrBankFromSketch(win)
  local ok, err = requirePackedSketch(win)
  if not ok then
    return nil, err
  end

  local canvas = nil
  if type(win.getActiveCanvas) == "function" then
    canvas = win:getActiveCanvas()
  end
  if not (canvas and type(canvas.extractTilePixels) == "function") then
    return nil, "sketch has no paint canvas"
  end

  local out = {}
  for slot = 0, M.PT_SLOT_COUNT - 1 do
    local entry = SketchCanvasPackController.poolEntryForLogicalSlot(win, slot)
    if not entry then
      return nil, string.format("missing pool entry for slot %d", slot)
    end
    local pixels = SketchCanvasPackController.pixelsForPoolEntry(canvas, entry)
    if not pixels then
      return nil, string.format("missing pixels for slot %d", slot)
    end
    local tileBytes, encErr = chr.encodeTile(pixels)
    if not tileBytes then
      return nil, encErr or "encodeTile failed"
    end
    for i = 1, 16 do
      out[#out + 1] = tileBytes[i]
    end
  end

  if #out ~= M.CHR_BANK_4K then
    return nil, string.format("internal CHR size %d, expected %d", #out, M.CHR_BANK_4K)
  end
  return chr.bytesToString(out)
end

--- Encode nametable indices (+ optional 64 attribute bytes).
--  opts.includeAttributes: if true, append 64 attr bytes (real attrs when present, else 0).
function M.encodeNametableFromSketch(win, opts)
  local ok, err = requirePackedSketch(win)
  if not ok then
    return nil, err
  end
  opts = opts or {}

  local nt = win.nametableBytes
  if type(nt) ~= "table" or #nt ~= M.NAMETABLE_TILES then
    return nil, "invalid nametableBytes"
  end

  local out = {}
  for i = 1, M.NAMETABLE_TILES do
    local v = math.floor(tonumber(nt[i]) or 0)
    if v < 0 then
      v = 0
    elseif v > 255 then
      v = 255
    end
    out[i] = v
  end

  if opts.includeAttributes then
    local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")
    local attrs = win.nametableAttrBytes
    if type(attrs) ~= "table" or #attrs < M.NAMETABLE_ATTRS then
      SketchPalette.ensureAttrBytes(win)
      attrs = win.nametableAttrBytes
    end
    for i = 1, M.NAMETABLE_ATTRS do
      out[#out + 1] = math.floor(tonumber(attrs[i]) or 0) % 256
    end
  end

  local expected = opts.includeAttributes and M.NAMETABLE_FULL or M.NAMETABLE_TILES
  if #out ~= expected then
    return nil, string.format("internal nametable size %d, expected %d", #out, expected)
  end
  return chr.bytesToString(out)
end

--- Encode 32-byte NES palette from linked sketch-mode palette (or hardcoded fallback).
function M.encodePaletteFromSketch(win, wm)
  local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")
  local pal = SketchPalette.getLinkedSketchPalette(win, wm)
  return SketchPalette.encodePaletteBlob32String(pal)
end

function M.exportChrBankToFile(app, win, path)
  local data, err = M.encodeChrBankFromSketch(win)
  if not data then
    return false, err
  end
  path = path or M.defaultChrPath(app, win)
  return M.writeBinaryFile(path, data)
end

function M.exportNametableToFile(app, win, path, opts)
  local data, err = M.encodeNametableFromSketch(win, opts)
  if not data then
    return false, err
  end
  path = path or M.defaultNametablePath(app, win)
  return M.writeBinaryFile(path, data)
end

return M
