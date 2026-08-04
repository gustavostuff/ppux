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

local function copyCodes4x4(codes)
  local out = {}
  for r = 1, 4 do
    out[r] = {}
    for c = 1, 4 do
      out[r][c] = codes[r][c]
    end
  end
  return out
end

local function paletteCodes4x4FromSketch(win, wm)
  local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")
  local pal = SketchPalette.getLinkedSketchPalette(win, wm)
  local bytes = SketchPalette.encodePaletteBlob32(pal)
  local codes = {}
  for row = 1, 4 do
    codes[row] = {}
    for col = 1, 4 do
      local b = bytes[(row - 1) * 4 + col] or 0x0F
      codes[row][col] = string.format("%02X", math.floor(b) % 256)
    end
  end
  return codes
end

local function paletteBlob32FromCodes4x4(codes)
  local bytes = {}
  for row = 1, 4 do
    for col = 1, 4 do
      bytes[#bytes + 1] = tonumber(codes[row][col], 16) or 0x0F
    end
  end
  local bg0 = bytes[1] or 0x07
  for _ = 1, 4 do
    bytes[#bytes + 1] = bg0
    bytes[#bytes + 1] = 0x0F
    bytes[#bytes + 1] = 0x0F
    bytes[#bytes + 1] = 0x0F
  end
  local chars = {}
  for i = 1, #bytes do
    chars[i] = string.char(bytes[i] % 256)
  end
  return table.concat(chars)
end

local function resolveSketchCanvas(win)
  if type(win.getActiveCanvas) == "function" then
    local canvas = win:getActiveCanvas()
    if canvas and type(canvas.extractTilePixels) == "function" then
      return canvas
    end
  end
  return nil
end

--- NES BG color index 0 always uses $3F00. Sketch mode shows each sub-palette's
--  color 0, so Gallery export must promote non-backdrop color-0 pixels to a
--  visible index (1-3) and adjust the exported palette when needed.
local function collectUsedNonZeroIndices(win, canvas, palNum)
  local used = { [1] = false, [2] = false, [3] = false }
  local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")
  local nt = win.nametableBytes
  local cols = win.cols or 32
  local seenSlots = {}
  for i = 1, M.NAMETABLE_TILES do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local cellPal = SketchPalette.getTilePaletteNumber(win, col, row) or 1
    if cellPal == palNum then
      local slot = math.floor(tonumber(nt[i]) or 0)
      if not seenSlots[slot] then
        seenSlots[slot] = true
        local entry = SketchCanvasPackController.poolEntryForLogicalSlot(win, slot)
        local pixels = entry and SketchCanvasPackController.pixelsForPoolEntry(canvas, entry)
        if pixels then
          for p = 1, #pixels do
            local v = math.floor(tonumber(pixels[p]) or 0)
            if v >= 1 and v <= 3 then
              used[v] = true
            end
          end
        end
      end
    end
  end
  return used
end

local function tryColor0HardwarePlan(codes, win, canvas, backdrop)
  local remapped = copyCodes4x4(codes)
  local remap0 = {}
  for p = 1, 4 do
    local want = codes[p][1]
    remapped[p][1] = backdrop
    if want == backdrop then
      remap0[p] = 0
    else
      local found = nil
      for k = 2, 4 do
        if remapped[p][k] == want then
          found = k - 1
          break
        end
      end
      if found then
        remap0[p] = found
      else
        local used = collectUsedNonZeroIndices(win, canvas, p)
        local slot = nil
        for k = 1, 3 do
          if not used[k] then
            slot = k
            break
          end
        end
        if not slot then
          return nil
        end
        remapped[p][slot + 1] = want
        remap0[p] = slot
      end
    end
  end
  return {
    backdrop = backdrop,
    remap0 = remap0,
    codes = remapped,
  }
end

local function buildColor0HardwarePlan(win, canvas, wm)
  local codes = paletteCodes4x4FromSketch(win, wm)
  local candidates = {}
  local seen = {}
  for p = 1, 4 do
    local c = codes[p][1]
    if not seen[c] then
      seen[c] = true
      candidates[#candidates + 1] = c
    end
  end
  -- Prefer original BG0, then remaining unique color-0 values.
  local preferred = codes[1][1]
  table.sort(candidates, function(a, b)
    if a == preferred then
      return true
    end
    if b == preferred then
      return false
    end
    return a < b
  end)

  for _, backdrop in ipairs(candidates) do
    local plan = tryColor0HardwarePlan(codes, win, canvas, backdrop)
    if plan then
      return plan
    end
  end

  -- Last resort: keep BG0 and overwrite least-used index 3 when needed.
  local remapped = copyCodes4x4(codes)
  local remap0 = {}
  local backdrop = preferred
  for p = 1, 4 do
    local want = codes[p][1]
    remapped[p][1] = backdrop
    if want == backdrop then
      remap0[p] = 0
    else
      local found = nil
      for k = 2, 4 do
        if remapped[p][k] == want then
          found = k - 1
          break
        end
      end
      if found then
        remap0[p] = found
      else
        remapped[p][4] = want
        remap0[p] = 3
      end
    end
  end
  return {
    backdrop = backdrop,
    remap0 = remap0,
    codes = remapped,
  }
end

local function remapColor0Pixels(pixels, toIndex)
  if not toIndex or toIndex < 1 then
    return pixels
  end
  local out = {}
  for i = 1, #pixels do
    local v = math.floor(tonumber(pixels[i]) or 0)
    if v == 0 then
      out[i] = toIndex
    else
      out[i] = v
    end
  end
  return out
end

local function encodeChrBytesFromPixelList(pixelTiles)
  local out = {}
  for slot = 0, M.PT_SLOT_COUNT - 1 do
    local pixels = pixelTiles[slot + 1]
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

--- Encode 256 logical PT slots (uniques + padding) to a 4096-byte CHR bank string.
function M.encodeChrBankFromSketch(win)
  local ok, err = requirePackedSketch(win)
  if not ok then
    return nil, err
  end

  local canvas = resolveSketchCanvas(win)
  if not canvas then
    return nil, "sketch has no paint canvas"
  end

  local pixelTiles = {}
  for slot = 0, M.PT_SLOT_COUNT - 1 do
    local entry = SketchCanvasPackController.poolEntryForLogicalSlot(win, slot)
    if not entry then
      return nil, string.format("missing pool entry for slot %d", slot)
    end
    local pixels = SketchCanvasPackController.pixelsForPoolEntry(canvas, entry)
    if not pixels then
      return nil, string.format("missing pixels for slot %d", slot)
    end
    pixelTiles[slot + 1] = pixels
  end
  return encodeChrBytesFromPixelList(pixelTiles)
end

--- Encode nametable indices (+ optional 64 attribute bytes).
--  opts.includeAttributes: if true, append 64 attr bytes (real attrs when present, else 0).
--  opts.nametableBytes: optional override table (e.g. hardware color-0 bake).
function M.encodeNametableFromSketch(win, opts)
  local ok, err = requirePackedSketch(win)
  if not ok then
    return nil, err
  end
  opts = opts or {}

  local nt = opts.nametableBytes or win.nametableBytes
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

--- Gallery/hardware export: bake per-subpalette color 0 into CHR + palette so
--  attribute regions survive on real NES / emulators ($3F00 universal backdrop).
--  Returns chr4k, nam1024, pal32 or nil, err.
function M.encodeHardwareSlideFromSketch(win, wm)
  local ok, err = requirePackedSketch(win)
  if not ok then
    return nil, nil, nil, err
  end
  local canvas = resolveSketchCanvas(win)
  if not canvas then
    return nil, nil, nil, "sketch has no paint canvas"
  end

  local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")
  SketchPalette.ensureAttrBytes(win)

  local plan = buildColor0HardwarePlan(win, canvas, wm)
  local needsRemap = false
  for p = 1, 4 do
    if (plan.remap0[p] or 0) > 0 then
      needsRemap = true
      break
    end
  end

  if not needsRemap then
    local chr4k, chrErr = M.encodeChrBankFromSketch(win)
    if not chr4k then
      return nil, nil, nil, chrErr
    end
    local nam, namErr = M.encodeNametableFromSketch(win, { includeAttributes = true })
    if not nam then
      return nil, nil, nil, namErr
    end
    return chr4k, nam, paletteBlob32FromCodes4x4(plan.codes), nil
  end

  local cols = win.cols or 32
  local srcNt = win.nametableBytes
  local variantKeyToSlot = {}
  local pixelTiles = {}
  local nextSlot = 0
  local outNt = {}

  local function allocVariant(srcSlot, remapTo)
    local key = string.format("%d:%d", srcSlot, remapTo)
    local existing = variantKeyToSlot[key]
    if existing ~= nil then
      return existing
    end
    if nextSlot >= M.PT_SLOT_COUNT then
      return nil, "too many CHR variants after color-0 bake (max 256)"
    end
    local entry = SketchCanvasPackController.poolEntryForLogicalSlot(win, srcSlot)
    if not entry then
      return nil, string.format("missing pool entry for slot %d", srcSlot)
    end
    local pixels = SketchCanvasPackController.pixelsForPoolEntry(canvas, entry)
    if not pixels then
      return nil, string.format("missing pixels for slot %d", srcSlot)
    end
    pixelTiles[nextSlot + 1] = remapColor0Pixels(pixels, remapTo)
    local slot = nextSlot
    variantKeyToSlot[key] = slot
    nextSlot = nextSlot + 1
    return slot
  end

  for i = 1, M.NAMETABLE_TILES do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local palNum = SketchPalette.getTilePaletteNumber(win, col, row) or 1
    local remapTo = plan.remap0[palNum] or 0
    local srcSlot = math.floor(tonumber(srcNt[i]) or 0)
    local newSlot, allocErr = allocVariant(srcSlot, remapTo)
    if newSlot == nil then
      return nil, nil, nil, allocErr or "CHR variant allocation failed"
    end
    outNt[i] = newSlot
  end

  -- Pad remaining CHR slots with blank tiles.
  local blank = {}
  for i = 1, 64 do
    blank[i] = 0
  end
  while nextSlot < M.PT_SLOT_COUNT do
    pixelTiles[nextSlot + 1] = blank
    nextSlot = nextSlot + 1
  end

  local chr4k, chrErr = encodeChrBytesFromPixelList(pixelTiles)
  if not chr4k then
    return nil, nil, nil, chrErr
  end
  local nam, namErr = M.encodeNametableFromSketch(win, {
    includeAttributes = true,
    nametableBytes = outNt,
  })
  if not nam then
    return nil, nil, nil, namErr
  end
  return chr4k, nam, paletteBlob32FromCodes4x4(plan.codes), nil
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
