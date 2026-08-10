-- utils/ppux_sketch_native.lua
-- LuaJIT FFI bridge to native/ppux_sketch (libppux_sketch).
-- Falls back silently when the shared library or FFI is unavailable.

local M = {}

local ffi
local C
local loadState = "untried" -- untried | ok | missing
local loadError = nil

local cdef = [[
typedef struct PpuxPoolEntry {
  int32_t x;
  int32_t y;
  int32_t solid_shade;
  int32_t exact_solid;
} PpuxPoolEntry;

int ppux_rgba_u8_to_indexed(
  const uint8_t *rgba,
  int w,
  int h,
  const float *palette_rgb_12,
  uint8_t *out_flat
);

int ppux_pack_flat(
  const uint8_t *flat,
  int w,
  int h,
  int tolerance,
  PpuxPoolEntry *out_pool,
  int32_t *out_unique_count,
  uint16_t *out_nametable
);

int ppux_pack_flat_tol0(
  const uint8_t *flat,
  int w,
  int h,
  PpuxPoolEntry *out_pool,
  int32_t *out_unique_count,
  uint16_t *out_nametable
);

const char *ppux_sketch_last_error(void);
]]

local function candidatePaths()
  local names = {
    "libppux_sketch.so",
    "ppux_sketch.dll",
    "libppux_sketch.dylib",
    "ppux_sketch.so",
  }
  local dirs = {}
  local function addDir(d)
    if type(d) ~= "string" or d == "" then
      return
    end
    d = d:gsub("\\", "/"):gsub("/+$", "")
    dirs[#dirs + 1] = d
  end

  -- Fused portable: .so beside the executable.
  do
    local okF, ffiLocal = pcall(require, "ffi")
    if okF and ffiLocal then
      pcall(function()
        ffiLocal.cdef[[
          long readlink(const char *path, char *buf, size_t bufsiz);
        ]]
        local buf = ffiLocal.new("char[4096]")
        local n = ffiLocal.C.readlink("/proc/self/exe", buf, 4095)
        if n and n > 0 then
          local exe = ffiLocal.string(buf, n)
          local dir = exe:match("^(.*)/[^/]+$")
          addDir(dir)
          if dir then
            addDir(dir .. "/lib")
          end
        end
      end)
    end
  end

  if love and love.filesystem then
    if love.filesystem.getSourceBaseDirectory then
      local base = love.filesystem.getSourceBaseDirectory()
      addDir(base)
      addDir((base or "") .. "/lib")
    end
    if love.filesystem.getSource then
      addDir(love.filesystem.getSource())
    end
  end

  addDir(".")
  addDir("./lib")
  addDir("native/ppux_sketch")
  addDir("../native/ppux_sketch")

  local out = {}
  local seen = {}
  for _, dir in ipairs(dirs) do
    for _, name in ipairs(names) do
      local path = (dir .. "/" .. name):gsub("/+", "/")
      if not seen[path] then
        seen[path] = true
        out[#out + 1] = path
      end
    end
  end
  for _, name in ipairs(names) do
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

local function tryLoad()
  if loadState ~= "untried" then
    return loadState == "ok"
  end
  loadState = "missing"

  local okFfi
  okFfi, ffi = pcall(require, "ffi")
  if not okFfi or not ffi then
    loadError = "ffi unavailable"
    return false
  end

  pcall(ffi.cdef, cdef)

  for _, path in ipairs(candidatePaths()) do
    local ok, lib = pcall(ffi.load, path)
    if ok and lib and (lib.ppux_pack_flat or lib.ppux_pack_flat_tol0) then
      C = lib
      loadState = "ok"
      loadError = nil
      return true
    end
    if not ok and type(lib) == "string" then
      loadError = lib
    end
  end
  return false
end

function M.isAvailable()
  return tryLoad()
end

function M.loadError()
  tryLoad()
  return loadError
end

local function paletteToFloat12(paletteColors)
  if type(paletteColors) ~= "table" then
    return nil
  end
  local buf = ffi.new("float[12]")
  for i = 0, 3 do
    local rgb = paletteColors[i + 1]
    if type(rgb) ~= "table" then
      return nil
    end
    buf[i * 3 + 0] = tonumber(rgb[1]) or 0
    buf[i * 3 + 1] = tonumber(rgb[2]) or 0
    buf[i * 3 + 2] = tonumber(rgb[3]) or 0
  end
  return buf
end

local function packResultFromNative(pool, uniqueCount, nametable, tolerance)
  local n = tonumber(uniqueCount[0]) or 0
  local tilesPool = {}
  for i = 0, n - 1 do
    local e = pool[i]
    local entry = {
      x = tonumber(e.x) or 0,
      y = tonumber(e.y) or 0,
    }
    if e.solid_shade >= 0 then
      entry.solidShade = tonumber(e.solid_shade)
      if e.exact_solid ~= 0 then
        entry.exactSolid = true
      end
    end
    tilesPool[i + 1] = entry
  end

  local nametableBytes = {}
  for i = 0, 959 do
    nametableBytes[i + 1] = tonumber(nametable[i]) or 0
  end

  return {
    tilesPool = tilesPool,
    nametableBytes = nametableBytes,
    uniqueCount = n,
    tolerance = math.floor(tonumber(tolerance) or 0),
  }
end

--- Pack a flat 1-based indexed buffer (256x240, values 0-3) at the given tolerance.
--- @return pack table or nil, err
function M.packFlat(flat, width, height, tolerance)
  if not tryLoad() then
    return nil, loadError or "native_unavailable"
  end
  width = math.floor(tonumber(width) or 0)
  height = math.floor(tonumber(height) or 0)
  if width ~= 256 or height ~= 240 then
    return nil, "bad_dimensions"
  end
  if type(flat) ~= "table" then
    return nil, "no_flat"
  end
  tolerance = math.floor(tonumber(tolerance) or 0)
  if tolerance < 0 then
    tolerance = 0
  elseif tolerance > 32 then
    tolerance = 32
  end

  local flatBuf = ffi.new("uint8_t[?]", width * height)
  for i = 0, width * height - 1 do
    local v = math.floor(tonumber(flat[i + 1]) or 0)
    if v < 0 then
      v = 0
    elseif v > 3 then
      v = 3
    end
    flatBuf[i] = v
  end

  local pool = ffi.new("PpuxPoolEntry[256]")
  local uniqueCount = ffi.new("int32_t[1]")
  local nametable = ffi.new("uint16_t[960]")
  local rc
  if C.ppux_pack_flat then
    rc = C.ppux_pack_flat(flatBuf, width, height, tolerance, pool, uniqueCount, nametable)
  elseif tolerance == 0 and C.ppux_pack_flat_tol0 then
    rc = C.ppux_pack_flat_tol0(flatBuf, width, height, pool, uniqueCount, nametable)
  else
    return nil, "native_pack_unsupported"
  end
  if rc ~= 0 then
    local err = ffi.string(C.ppux_sketch_last_error())
    if err == "" then
      err = "native_pack_failed_" .. tostring(rc)
    end
    return nil, err
  end
  return packResultFromNative(pool, uniqueCount, nametable, tolerance)
end

--- Pack a PixelCanvas (or any table with .pixels/.width/.height) via native helper.
--- @return pack table or nil, err
function M.packPixelCanvas(canvas, tolerance)
  if not tryLoad() then
    return nil, loadError or "native_unavailable"
  end
  if type(canvas) ~= "table" or type(canvas.pixels) ~= "table" then
    return nil, "no_canvas_pixels"
  end
  local w = math.floor(tonumber(canvas.width) or 0)
  local h = math.floor(tonumber(canvas.height) or 0)
  if w ~= 256 or h ~= 240 then
    return nil, "bad_dimensions"
  end
  tolerance = math.floor(tonumber(tolerance) or 0)
  if tolerance < 0 then
    tolerance = 0
  elseif tolerance > 32 then
    tolerance = 32
  end

  local flatBuf = ffi.new("uint8_t[?]", w * h)
  local pixels = canvas.pixels
  for i = 0, w * h - 1 do
    local v = math.floor(tonumber(pixels[i + 1]) or 0)
    if v < 0 then
      v = 0
    elseif v > 3 then
      v = 3
    end
    flatBuf[i] = v
  end

  local pool = ffi.new("PpuxPoolEntry[256]")
  local uniqueCount = ffi.new("int32_t[1]")
  local nametable = ffi.new("uint16_t[960]")
  local rc
  if C.ppux_pack_flat then
    rc = C.ppux_pack_flat(flatBuf, w, h, tolerance, pool, uniqueCount, nametable)
  elseif tolerance == 0 and C.ppux_pack_flat_tol0 then
    rc = C.ppux_pack_flat_tol0(flatBuf, w, h, pool, uniqueCount, nametable)
  else
    return nil, "native_pack_unsupported"
  end
  if rc ~= 0 then
    local err = ffi.string(C.ppux_sketch_last_error())
    if err == "" then
      err = "native_pack_failed_" .. tostring(rc)
    end
    return nil, err
  end
  return packResultFromNative(pool, uniqueCount, nametable, tolerance)
end

--- Decode LOVE ImageData (rgba8) + pack at tolerance 0.
--- @return flat (1-based Lua table), pack table, or nil, err
function M.imageDataToIndexedAndPack(imgData, paletteColors)
  if not tryLoad() then
    return nil, loadError or "native_unavailable"
  end
  if not imgData then
    return nil, "no_imagedata"
  end

  local w = imgData:getWidth()
  local h = imgData:getHeight()
  if w ~= 256 or h ~= 240 then
    return nil, "bad_dimensions"
  end

  local pointer = nil
  if imgData.getFFIPointer then
    pointer = imgData:getFFIPointer()
  end
  if not pointer then
    return nil, "no_ffi_pointer"
  end

  local rgba = ffi.cast("const uint8_t *", pointer)
  local flatBuf = ffi.new("uint8_t[?]", w * h)
  local pal = paletteToFloat12(paletteColors)
  local rc = C.ppux_rgba_u8_to_indexed(rgba, w, h, pal, flatBuf)
  if rc ~= 0 then
    local err = ffi.string(C.ppux_sketch_last_error())
    if err == "" then
      err = "native_index_failed_" .. tostring(rc)
    end
    return nil, err
  end

  local pool = ffi.new("PpuxPoolEntry[256]")
  local uniqueCount = ffi.new("int32_t[1]")
  local nametable = ffi.new("uint16_t[960]")
  if C.ppux_pack_flat then
    rc = C.ppux_pack_flat(flatBuf, w, h, 0, pool, uniqueCount, nametable)
  else
    rc = C.ppux_pack_flat_tol0(flatBuf, w, h, pool, uniqueCount, nametable)
  end
  if rc ~= 0 then
    local err = ffi.string(C.ppux_sketch_last_error())
    if err == "" then
      err = "native_pack_failed_" .. tostring(rc)
    end
    return nil, err
  end

  local n = tonumber(uniqueCount[0]) or 0
  local flat = {}
  for i = 0, w * h - 1 do
    flat[i + 1] = flatBuf[i]
  end

  return flat, packResultFromNative(pool, uniqueCount, nametable, 0), w, h
end

return M
