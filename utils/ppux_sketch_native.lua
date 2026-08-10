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

int ppux_copy_flat(const uint8_t *src, uint8_t *dst, int n);

int ppux_blit_flat(
  const uint8_t *src,
  int src_w,
  int src_h,
  uint8_t *dst,
  int dst_w,
  int dst_h,
  int dx,
  int dy
);

int ppux_fill_flat_rect(
  uint8_t *flat,
  int w,
  int h,
  int x,
  int y,
  int rw,
  int rh,
  uint8_t value
);

int ppux_compose_nametable(
  const uint8_t *paint,
  int w,
  int h,
  const int32_t *pool_x,
  const int32_t *pool_y,
  const int32_t *solid_shade,
  int pool_count,
  const uint16_t *nametable,
  uint8_t *out_flat
);

int ppux_average_nametable_rgb(
  const uint8_t *paint,
  int w,
  int h,
  const int32_t *pool_x,
  const int32_t *pool_y,
  const int32_t *solid_shade,
  int pool_count,
  const uint16_t *nametable,
  const uint8_t *attr_row,
  const double *palette_rgb_48,
  double *out_rgb
);

int ppux_average_flat_rgb(
  const uint8_t *flat,
  int w,
  int h,
  const uint8_t *attr_row,
  const double *palette_rgb_48,
  double *out_rgb
);

int ppux_flood_fill(
  uint8_t *flat,
  int w,
  int h,
  int sx,
  int sy,
  uint8_t fill,
  const uint8_t *allow_mask,
  int32_t *out_indices,
  int32_t *out_count
);

int ppux_build_shade_mask(
  const uint8_t *flat,
  int w,
  int h,
  uint8_t shade,
  uint8_t *out_mask,
  int32_t *out_count
);

int ppux_chr_tiles_to_rgba8(
  const uint8_t *chr,
  int tile_count,
  const int32_t *tile_order,
  int cols,
  int rows,
  uint8_t *out_rgba
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

local function lastErr(rc, fallback)
  local err = ""
  if C and C.ppux_sketch_last_error then
    err = ffi.string(C.ppux_sketch_last_error()) or ""
  end
  if err == "" then
    err = fallback or ("native_failed_" .. tostring(rc))
  end
  return err
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

--- 4 palette rows × 4 shades × rgb → double[48]
local function paletteRowsToDouble48(paletteRows)
  if type(paletteRows) ~= "table" then
    return nil
  end
  local buf = ffi.new("double[48]")
  for row = 0, 3 do
    local colors = paletteRows[row + 1]
    if type(colors) ~= "table" then
      return nil
    end
    for shade = 0, 3 do
      local rgb = colors[shade + 1]
      local base = row * 12 + shade * 3
      if type(rgb) ~= "table" then
        buf[base] = 0
        buf[base + 1] = 0
        buf[base + 2] = 0
      else
        buf[base] = tonumber(rgb[1]) or 0
        buf[base + 1] = tonumber(rgb[2]) or 0
        buf[base + 2] = tonumber(rgb[3]) or 0
      end
    end
  end
  return buf
end

--- Copy 1-based Lua indexed pixels into a new uint8_t FFI buffer.
function M.pixelsToFlatBuf(pixels, width, height)
  if not tryLoad() then
    return nil, loadError or "native_unavailable"
  end
  width = math.floor(tonumber(width) or 0)
  height = math.floor(tonumber(height) or 0)
  if width < 1 or height < 1 or type(pixels) ~= "table" then
    return nil, "bad_pixels"
  end
  local n = width * height
  local buf = ffi.new("uint8_t[?]", n)
  for i = 0, n - 1 do
    local v = math.floor(tonumber(pixels[i + 1]) or 0)
    if v < 0 then
      v = 0
    elseif v > 3 then
      v = 3
    end
    buf[i] = v
  end
  return buf, n
end

--- Write FFI flat buffer back into a 1-based Lua pixels table (in place).
function M.flatBufToPixels(buf, pixels, n)
  n = math.floor(tonumber(n) or 0)
  if not buf or type(pixels) ~= "table" or n < 1 then
    return false
  end
  for i = 0, n - 1 do
    pixels[i + 1] = buf[i]
  end
  return true
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

local function packFlatBuf(flatBuf, width, height, tolerance)
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
    return nil, lastErr(rc, "native_pack_failed")
  end
  return packResultFromNative(pool, uniqueCount, nametable, tolerance)
end

--- Pack a flat 1-based indexed buffer (256x240, values 0-3) at the given tolerance.
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

  local flatBuf, err = M.pixelsToFlatBuf(flat, width, height)
  if not flatBuf then
    return nil, err
  end
  return packFlatBuf(flatBuf, width, height, tolerance)
end

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

  local flatBuf, err = M.pixelsToFlatBuf(canvas.pixels, w, h)
  if not flatBuf then
    return nil, err
  end
  return packFlatBuf(flatBuf, w, h, tolerance)
end

--- Decode LOVE ImageData (rgba8) to indexed flat (any size).
--- @return flat (1-based), w, h or nil, err
function M.imageDataToIndexed(imgData, paletteColors)
  if not tryLoad() then
    return nil, loadError or "native_unavailable"
  end
  if not imgData then
    return nil, "no_imagedata"
  end
  local w = imgData:getWidth()
  local h = imgData:getHeight()
  if w < 1 or h < 1 then
    return nil, "bad_dimensions"
  end
  local pointer = imgData.getFFIPointer and imgData:getFFIPointer()
  if not pointer then
    return nil, "no_ffi_pointer"
  end
  local rgba = ffi.cast("const uint8_t *", pointer)
  local flatBuf = ffi.new("uint8_t[?]", w * h)
  local pal = paletteToFloat12(paletteColors)
  local rc = C.ppux_rgba_u8_to_indexed(rgba, w, h, pal, flatBuf)
  if rc ~= 0 then
    return nil, lastErr(rc, "native_index_failed")
  end
  local flat = {}
  for i = 0, w * h - 1 do
    flat[i + 1] = flatBuf[i]
  end
  return flat, w, h
end

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
    return nil, lastErr(rc, "native_index_failed")
  end

  local pack, packErr = packFlatBuf(flatBuf, w, h, 0)
  if not pack then
    return nil, packErr
  end

  local flat = {}
  for i = 0, w * h - 1 do
    flat[i + 1] = flatBuf[i]
  end

  return flat, pack, w, h
end

--- Bulk-copy indexed pixels from src canvas into dst (marks dst dirty).
function M.copyCanvasPixels(dst, src)
  if not tryLoad() or not C.ppux_copy_flat then
    return false, "native_unavailable"
  end
  if not (dst and src and type(dst.pixels) == "table" and type(src.pixels) == "table") then
    return false, "no_canvas"
  end
  local w = math.min(math.floor(tonumber(dst.width) or 0), math.floor(tonumber(src.width) or 0))
  local h = math.min(math.floor(tonumber(dst.height) or 0), math.floor(tonumber(src.height) or 0))
  if w < 1 or h < 1 then
    return false, "bad_dimensions"
  end
  local n = w * h
  local srcBuf = select(1, M.pixelsToFlatBuf(src.pixels, w, h))
  local dstBuf = ffi.new("uint8_t[?]", n)
  if not srcBuf then
    return false, "marshal_failed"
  end
  local rc = C.ppux_copy_flat(srcBuf, dstBuf, n)
  if rc ~= 0 then
    return false, lastErr(rc, "copy_failed")
  end
  M.flatBufToPixels(dstBuf, dst.pixels, n)
  dst._imageDirty = true
  return true
end

--- Blit source canvas/flat into dest at (dx,dy).
function M.blitIntoCanvas(dst, src, dx, dy, srcW, srcH)
  if not tryLoad() or not C.ppux_blit_flat then
    return false, "native_unavailable"
  end
  if not (dst and type(dst.pixels) == "table") then
    return false, "no_dst"
  end
  dx = math.floor(tonumber(dx) or 0)
  dy = math.floor(tonumber(dy) or 0)
  local sw, sh, srcPixels
  if type(src) == "table" and src.pixels and src.width and src.height then
    sw = math.floor(tonumber(src.width) or 0)
    sh = math.floor(tonumber(src.height) or 0)
    srcPixels = src.pixels
  else
    sw = math.floor(tonumber(srcW) or 0)
    sh = math.floor(tonumber(srcH) or 0)
    srcPixels = src
  end
  local dw = math.floor(tonumber(dst.width) or 0)
  local dh = math.floor(tonumber(dst.height) or 0)
  if sw < 1 or sh < 1 or dw < 1 or dh < 1 or type(srcPixels) ~= "table" then
    return false, "bad_dimensions"
  end
  local srcBuf = select(1, M.pixelsToFlatBuf(srcPixels, sw, sh))
  local dstBuf = select(1, M.pixelsToFlatBuf(dst.pixels, dw, dh))
  if not srcBuf or not dstBuf then
    return false, "marshal_failed"
  end
  local rc = C.ppux_blit_flat(srcBuf, sw, sh, dstBuf, dw, dh, dx, dy)
  if rc ~= 0 then
    return false, lastErr(rc, "blit_failed")
  end
  M.flatBufToPixels(dstBuf, dst.pixels, dw * dh)
  dst._imageDirty = true
  return true
end

function M.fillCanvasRect(dst, x, y, rw, rh, value)
  if not tryLoad() or not C.ppux_fill_flat_rect then
    return false, "native_unavailable"
  end
  if not (dst and type(dst.pixels) == "table") then
    return false, "no_dst"
  end
  local dw = math.floor(tonumber(dst.width) or 0)
  local dh = math.floor(tonumber(dst.height) or 0)
  local dstBuf = select(1, M.pixelsToFlatBuf(dst.pixels, dw, dh))
  if not dstBuf then
    return false, "marshal_failed"
  end
  value = math.max(0, math.min(3, math.floor(tonumber(value) or 0)))
  local rc = C.ppux_fill_flat_rect(
    dstBuf,
    dw,
    dh,
    math.floor(tonumber(x) or 0),
    math.floor(tonumber(y) or 0),
    math.floor(tonumber(rw) or 0),
    math.floor(tonumber(rh) or 0),
    value
  )
  if rc ~= 0 then
    return false, lastErr(rc, "fill_failed")
  end
  M.flatBufToPixels(dstBuf, dst.pixels, dw * dh)
  dst._imageDirty = true
  return true
end

local function poolArraysFromSketch(sketchWin)
  local pool = sketchWin and sketchWin.tilesPool
  if type(pool) ~= "table" or #pool < 1 then
    return nil, "no_pool"
  end
  local n = #pool
  local xs = ffi.new("int32_t[?]", n)
  local ys = ffi.new("int32_t[?]", n)
  local solids = ffi.new("int32_t[?]", n)
  for i = 1, n do
    local e = pool[i] or {}
    xs[i - 1] = math.floor(tonumber(e.x) or 0)
    ys[i - 1] = math.floor(tonumber(e.y) or 0)
    local shade = e.solidShade
    if type(shade) == "number" and shade >= 0 and shade <= 3 then
      solids[i - 1] = math.floor(shade)
    else
      solids[i - 1] = -1
    end
  end
  local nt = sketchWin.nametableBytes
  local nametable = ffi.new("uint16_t[960]")
  for i = 0, 959 do
    nametable[i] = math.floor(tonumber(nt and nt[i + 1]) or 0)
  end
  return xs, ys, solids, n, nametable
end

--- Compose nametable into dest canvas pixels from paint + pack.
function M.composeNametableInto(destCanvas, paintCanvas, sketchWin)
  if not tryLoad() or not C.ppux_compose_nametable then
    return false, "native_unavailable"
  end
  if not (destCanvas and paintCanvas and sketchWin) then
    return false, "bad_args"
  end
  local w = math.floor(tonumber(paintCanvas.width) or 0)
  local h = math.floor(tonumber(paintCanvas.height) or 0)
  if w ~= 256 or h ~= 240 then
    return false, "bad_dimensions"
  end
  local xs, ys, solids, poolCount, nametable = poolArraysFromSketch(sketchWin)
  if not xs then
    return false, ys
  end
  local paintBuf = select(1, M.pixelsToFlatBuf(paintCanvas.pixels, w, h))
  local outBuf = ffi.new("uint8_t[?]", w * h)
  if not paintBuf then
    return false, "marshal_failed"
  end
  local rc = C.ppux_compose_nametable(
    paintBuf, w, h, xs, ys, solids, poolCount, nametable, outBuf
  )
  if rc ~= 0 then
    return false, lastErr(rc, "compose_failed")
  end
  if type(destCanvas.pixels) ~= "table" then
    return false, "no_dest_pixels"
  end
  M.flatBufToPixels(outBuf, destCanvas.pixels, w * h)
  destCanvas._imageDirty = true
  return true
end

--- @return averages {{r,g,b},...}|nil, err
function M.averageTilesRgb(paintCanvas, sketchWin, paletteRows, attrRows)
  if not tryLoad() then
    return nil, loadError or "native_unavailable"
  end
  if not (paintCanvas and type(paintCanvas.pixels) == "table") then
    return nil, "no_paint"
  end
  local w = math.floor(tonumber(paintCanvas.width) or 0)
  local h = math.floor(tonumber(paintCanvas.height) or 0)
  if w ~= 256 or h ~= 240 then
    return nil, "bad_dimensions"
  end
  local pal48 = paletteRowsToDouble48(paletteRows)
  if not pal48 then
    return nil, "bad_palette"
  end
  local attr = nil
  if type(attrRows) == "table" then
    attr = ffi.new("uint8_t[960]")
    for i = 0, 959 do
      local v = math.floor(tonumber(attrRows[i + 1]) or 0)
      if v < 0 then
        v = 0
      elseif v > 3 then
        v = 3
      end
      attr[i] = v
    end
  end
  local paintBuf = select(1, M.pixelsToFlatBuf(paintCanvas.pixels, w, h))
  if not paintBuf then
    return nil, "marshal_failed"
  end
  local outRgb = ffi.new("double[?]", 960 * 3)
  local rc
  local hasPack = sketchWin
    and type(sketchWin.tilesPool) == "table"
    and #sketchWin.tilesPool > 0
    and type(sketchWin.nametableBytes) == "table"
  if hasPack and C.ppux_average_nametable_rgb then
    local xs, ys, solids, poolCount, nametable = poolArraysFromSketch(sketchWin)
    if not xs then
      return nil, ys
    end
    rc = C.ppux_average_nametable_rgb(
      paintBuf, w, h, xs, ys, solids, poolCount, nametable, attr, pal48, outRgb
    )
  elseif C.ppux_average_flat_rgb then
    rc = C.ppux_average_flat_rgb(paintBuf, w, h, attr, pal48, outRgb)
  else
    return nil, "native_average_unsupported"
  end
  if rc ~= 0 then
    return nil, lastErr(rc, "average_failed")
  end
  local averages = {}
  for i = 0, 959 do
    local base = i * 3
    averages[i + 1] = {
      outRgb[base],
      outRgb[base + 1],
      outRgb[base + 2],
    }
  end
  return averages
end

--- Flood fill canvas.pixels. Returns changed linear indices (0-based) or nil.
--- allowBits: optional 1-based sparse/dense table; false/0 blocks paint.
function M.floodFillCanvas(canvas, sx, sy, fill, allowBits)
  if not tryLoad() or not C.ppux_flood_fill then
    return nil, "native_unavailable"
  end
  if not (canvas and type(canvas.pixels) == "table") then
    return nil, "no_canvas"
  end
  local w = math.floor(tonumber(canvas.width) or 0)
  local h = math.floor(tonumber(canvas.height) or 0)
  local n = w * h
  local flatBuf = select(1, M.pixelsToFlatBuf(canvas.pixels, w, h))
  if not flatBuf then
    return nil, "marshal_failed"
  end
  local allow = nil
  if type(allowBits) == "table" then
    allow = ffi.new("uint8_t[?]", n)
    for i = 0, n - 1 do
      local v = allowBits[i + 1]
      if v == false or v == 0 or v == nil then
        allow[i] = 0
      else
        allow[i] = 1
      end
    end
    -- Sparse true-bits: nil means blocked when mask is active.
    -- Callers should pass a dense 0/1 table for mask mode.
  end
  local indices = ffi.new("int32_t[?]", n)
  local count = ffi.new("int32_t[1]")
  fill = math.max(0, math.min(3, math.floor(tonumber(fill) or 0)))
  local rc = C.ppux_flood_fill(
    flatBuf,
    w,
    h,
    math.floor(tonumber(sx) or 0),
    math.floor(tonumber(sy) or 0),
    fill,
    allow,
    indices,
    count
  )
  if rc ~= 0 then
    return nil, lastErr(rc, "flood_failed")
  end
  local painted = tonumber(count[0]) or 0
  if painted < 1 then
    return {}, 0
  end
  M.flatBufToPixels(flatBuf, canvas.pixels, n)
  canvas._imageDirty = true
  local out = {}
  for i = 0, painted - 1 do
    out[i + 1] = indices[i]
  end
  return out, painted
end

--- Build dense 1-based 0/1 mask for pixels == shade.
function M.buildShadeMask(canvas, shade)
  if not tryLoad() or not C.ppux_build_shade_mask then
    return nil, 0, "native_unavailable"
  end
  if not (canvas and type(canvas.pixels) == "table") then
    return nil, 0, "no_canvas"
  end
  local w = math.floor(tonumber(canvas.width) or 0)
  local h = math.floor(tonumber(canvas.height) or 0)
  local n = w * h
  local flatBuf = select(1, M.pixelsToFlatBuf(canvas.pixels, w, h))
  if not flatBuf then
    return nil, 0, "marshal_failed"
  end
  local outMask = ffi.new("uint8_t[?]", n)
  local count = ffi.new("int32_t[1]")
  shade = math.max(0, math.min(3, math.floor(tonumber(shade) or 0)))
  local rc = C.ppux_build_shade_mask(flatBuf, w, h, shade, outMask, count)
  if rc ~= 0 then
    return nil, 0, lastErr(rc, "mask_failed")
  end
  local dense = {}
  local bits = {}
  for i = 0, n - 1 do
    local m = outMask[i]
    dense[i + 1] = m
    if m ~= 0 then
      bits[i + 1] = true
    end
  end
  return {
    dense = dense,
    bits = bits,
    width = w,
    height = h,
    color = shade,
    count = tonumber(count[0]) or 0,
  }, tonumber(count[0]) or 0
end

--- Write CHR bank tiles into LOVE ImageData via FFI pointer.
function M.chrTilesToImageData(imgData, chrBytes, tileOrder, cols, rows)
  if not tryLoad() or not C.ppux_chr_tiles_to_rgba8 then
    return false, "native_unavailable"
  end
  if not imgData then
    return false, "no_imagedata"
  end
  cols = math.floor(tonumber(cols) or 16)
  rows = math.floor(tonumber(rows) or 32)
  local tileCount = cols * rows
  local chrLen
  local chrBuf
  if type(chrBytes) == "string" then
    chrLen = #chrBytes
    if chrLen < tileCount * 16 then
      return false, "chr_too_small"
    end
    chrBuf = ffi.new("uint8_t[?]", chrLen)
    ffi.copy(chrBuf, chrBytes, chrLen)
  elseif type(chrBytes) == "table" then
    chrLen = #chrBytes
    if chrLen < tileCount * 16 then
      return false, "chr_too_small"
    end
    chrBuf = ffi.new("uint8_t[?]", chrLen)
    for i = 1, chrLen do
      chrBuf[i - 1] = math.floor(tonumber(chrBytes[i]) or 0) % 256
    end
  else
    return false, "bad_chr"
  end

  local orderBuf = nil
  if type(tileOrder) == "table" then
    orderBuf = ffi.new("int32_t[?]", tileCount)
    for i = 0, tileCount - 1 do
      orderBuf[i] = math.floor(tonumber(tileOrder[i + 1]) or i)
    end
  end

  local pointer = imgData.getFFIPointer and imgData:getFFIPointer()
  if not pointer then
    return false, "no_ffi_pointer"
  end
  local rgba = ffi.cast("uint8_t *", pointer)
  local rc = C.ppux_chr_tiles_to_rgba8(
    chrBuf,
    math.floor(chrLen / 16),
    orderBuf,
    cols,
    rows,
    rgba
  )
  if rc ~= 0 then
    return false, lastErr(rc, "chr_decode_failed")
  end
  return true
end

return M
