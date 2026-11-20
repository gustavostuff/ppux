-- utils/ppux_clipboard_native.lua
-- LuaJIT FFI bridge to native/ppux_clipboard (libppux_clipboard).
-- Paste reports a status when the library or an image is missing.

local M = {}

local ffi
local C
local loadState = "untried" -- untried | ok | missing
local loadError = nil

local CLIP_OK = 0
local CLIP_EMPTY = 1
local CLIP_UNAVAILABLE = 2
local FMT_BMP = 2
local FMT_RGBA8 = 3

local cdef = [[
int ppux_clipboard_get_image(
  uint8_t **out_bytes,
  size_t *out_size,
  int32_t *out_format,
  int32_t *out_width,
  int32_t *out_height
);

void ppux_clipboard_free(void *p);

const char *ppux_clipboard_last_error(void);

int ppux_dib_to_rgba(
  const uint8_t *dib,
  size_t dib_size,
  uint8_t **out_rgba,
  int32_t *out_w,
  int32_t *out_h
);

int ppux_clipboard_set_png(const uint8_t *bytes, size_t size);
]]

local function candidatePaths()
  local names = {
    "libppux_clipboard.so",
    "ppux_clipboard.dll",
    "libppux_clipboard.dylib",
    "ppux_clipboard.so",
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
        pcall(ffiLocal.cdef, [[
          long readlink(const char *path, char *buf, size_t bufsiz);
        ]])
        local buf = ffiLocal.new("char[4096]")
        local n = ffiLocal.C.readlink("/proc/self/exe", buf, 4095)
        if n and n > 0 then
          local exe = ffiLocal.string(buf, n)
          local dir = exe:match("^(.*)/[^/]+$")
          addDir(dir)
          if dir then
            addDir(dir .. "/lib")
            addDir(dir .. "/native/ppux_clipboard")
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
      addDir((base or "") .. "/native/ppux_clipboard")
    end
    if love.filesystem.getSource then
      local source = love.filesystem.getSource()
      addDir(source)
      addDir((source or "") .. "/native/ppux_clipboard")
      addDir((source or "") .. "/../native/ppux_clipboard")
    end
  end

  addDir(".")
  addDir("./lib")
  addDir("native/ppux_clipboard")
  addDir("../native/ppux_clipboard")

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
    if ok and lib and lib.ppux_clipboard_get_image then
      C = lib
      loadState = "ok"
      loadError = nil
      return true
    end
    if not ok and type(lib) == "string" then
      loadError = lib
    end
  end
  if not loadError then
    loadError = "libppux_clipboard not found"
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

local function lastError(fallback)
  local err = ""
  if C and C.ppux_clipboard_last_error then
    err = ffi.string(C.ppux_clipboard_last_error()) or ""
  end
  if err == "" then
    err = fallback or "clipboard_read_failed"
  end
  return err
end

local function decodeImage(bytes, format, width, height)
  if format == FMT_RGBA8 then
    local w = tonumber(width) or 0
    local h = tonumber(height) or 0
    if w < 1 or h < 1 or #bytes ~= w * h * 4 then
      return nil, "Failed to decode clipboard image"
    end
    local ok, img = pcall(function()
      return love.image.newImageData(w, h, "rgba8", bytes)
    end)
    if not ok or not img then
      return nil, "Failed to decode clipboard image"
    end
    return img
  end

  local name = format == FMT_BMP and "clipboard.bmp" or "clipboard.png"
  local okFd, fileData = pcall(function()
    return love.filesystem.newFileData(bytes, name)
  end)
  if not okFd or not fileData then
    return nil, "Failed to decode clipboard image"
  end
  local okImg, img = pcall(function()
    return love.image.newImageData(fileData)
  end)
  if not okImg or not img then
    return nil, "Failed to decode clipboard image"
  end
  return img
end

--- Read an OS clipboard image as LOVE ImageData.
--- @return ImageData|nil, string|nil err  "no_image" | "unavailable" | message
function M.getImageData()
  if not tryLoad() then
    return nil, "unavailable"
  end

  local outBytes = ffi.new("uint8_t*[1]")
  local outSize = ffi.new("size_t[1]")
  local outFormat = ffi.new("int32_t[1]")
  local outW = ffi.new("int32_t[1]")
  local outH = ffi.new("int32_t[1]")
  local rc = C.ppux_clipboard_get_image(outBytes, outSize, outFormat, outW, outH)
  if rc == CLIP_EMPTY then
    return nil, "no_image"
  end
  if rc == CLIP_UNAVAILABLE then
    return nil, "unavailable"
  end
  if rc ~= CLIP_OK or outBytes[0] == nil then
    return nil, lastError("clipboard_read_failed")
  end

  local n = tonumber(outSize[0]) or 0
  local bytes = n > 0 and ffi.string(outBytes[0], n) or ""
  C.ppux_clipboard_free(outBytes[0])
  if n < 1 then
    return nil, "Failed to decode clipboard image"
  end
  return decodeImage(bytes, tonumber(outFormat[0]) or 0, tonumber(outW[0]) or 0, tonumber(outH[0]) or 0)
end

--- Decode a CF_DIB blob. Returns the RGBA byte string, width, height.
function M.dibToRgba(dib)
  if type(dib) ~= "string" or not tryLoad() then
    return nil, nil, nil
  end
  local src = ffi.new("uint8_t[?]", #dib)
  ffi.copy(src, dib, #dib)
  local out = ffi.new("uint8_t*[1]")
  local w = ffi.new("int32_t[1]")
  local h = ffi.new("int32_t[1]")
  local rc = C.ppux_dib_to_rgba(src, #dib, out, w, h)
  if rc ~= 0 or out[0] == nil then
    return nil, nil, nil
  end
  local tw = tonumber(w[0]) or 0
  local th = tonumber(h[0]) or 0
  local bytes = ffi.string(out[0], tw * th * 4)
  C.ppux_clipboard_free(out[0])
  return bytes, tw, th
end

--- Copy a PNG byte string to the OS clipboard.
--- @return boolean ok, string|nil err  "unavailable" | "empty" | message
function M.setPng(bytes)
  if type(bytes) ~= "string" or #bytes < 1 then
    return false, "empty"
  end
  if not tryLoad() then
    return false, "unavailable"
  end
  local buf = ffi.new("uint8_t[?]", #bytes)
  ffi.copy(buf, bytes, #bytes)
  local okCall, rc = pcall(function()
    return C.ppux_clipboard_set_png(buf, #bytes)
  end)
  if not okCall then
    return false, "unavailable"
  end
  rc = tonumber(rc)
  if rc == CLIP_OK then
    return true
  end
  if rc == CLIP_UNAVAILABLE then
    return false, "unavailable"
  end
  return false, lastError("clipboard_write_failed")
end

return M
