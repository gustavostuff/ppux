-- Silent Windows filesystem helpers via kernel32 FFI.
-- Avoids io.popen / os.execute, which briefly flash a console window on Windows.

local M = {}

local FILE_ATTRIBUTE_DIRECTORY = 0x10
local CP_UTF8 = 65001

local ffi
local kernel32
local INVALID_HANDLE_VALUE
local ready = false

local function ensureReady()
  if ready then
    return kernel32 ~= nil
  end
  ready = true

  local okFfi
  okFfi, ffi = pcall(require, "ffi")
  if not okFfi or not ffi then
    return false
  end

  -- cdef may already exist from another module; ignore redefinition errors.
  pcall(ffi.cdef, [[
    typedef unsigned long DWORD;
    typedef int BOOL;
    typedef void* HANDLE;
    typedef unsigned short WCHAR;

    typedef struct _FILETIME {
      DWORD dwLowDateTime;
      DWORD dwHighDateTime;
    } FILETIME;

    typedef struct _WIN32_FIND_DATAW {
      DWORD dwFileAttributes;
      FILETIME ftCreationTime;
      FILETIME ftLastAccessTime;
      FILETIME ftLastWriteTime;
      DWORD nFileSizeHigh;
      DWORD nFileSizeLow;
      DWORD dwReserved0;
      DWORD dwReserved1;
      WCHAR cFileName[260];
      WCHAR cAlternateFileName[14];
    } WIN32_FIND_DATAW;

    int MultiByteToWideChar(unsigned int CodePage, DWORD dwFlags,
      const char* lpMultiByteStr, int cbMultiByte,
      WCHAR* lpWideCharStr, int cchWideChar);
    int WideCharToMultiByte(unsigned int CodePage, DWORD dwFlags,
      const WCHAR* lpWideCharStr, int cchWideChar,
      char* lpMultiByteStr, int cbMultiByte,
      const char* lpDefaultChar, int* lpUsedDefaultChar);

    HANDLE FindFirstFileW(const WCHAR* lpFileName, WIN32_FIND_DATAW* lpFindFileData);
    BOOL FindNextFileW(HANDLE hFindFile, WIN32_FIND_DATAW* lpFindFileData);
    BOOL FindClose(HANDLE hFindFile);

    DWORD GetCurrentDirectoryW(DWORD nBufferLength, WCHAR* lpBuffer);
  ]])

  local okKernel
  okKernel, kernel32 = pcall(ffi.load, "kernel32")
  if not okKernel or not kernel32 then
    kernel32 = nil
    return false
  end

  INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)
  return true
end

local function utf8ToWide(str)
  str = tostring(str or "")
  local size = kernel32.MultiByteToWideChar(CP_UTF8, 0, str, #str, nil, 0)
  if size <= 0 then
    return nil
  end
  local buf = ffi.new("WCHAR[?]", size + 1)
  if kernel32.MultiByteToWideChar(CP_UTF8, 0, str, #str, buf, size) <= 0 then
    return nil
  end
  buf[size] = 0
  return buf
end

local function wideToUtf8(wstr)
  local size = kernel32.WideCharToMultiByte(CP_UTF8, 0, wstr, -1, nil, 0, nil, nil)
  if size <= 0 then
    return nil
  end
  local buf = ffi.new("char[?]", size)
  if kernel32.WideCharToMultiByte(CP_UTF8, 0, wstr, -1, buf, size, nil, nil) <= 0 then
    return nil
  end
  return ffi.string(buf)
end

local function isDirectoryAttr(attrs)
  attrs = tonumber(attrs) or 0
  if bit and bit.band then
    return bit.band(attrs, FILE_ATTRIBUTE_DIRECTORY) ~= 0
  end
  return math.floor(attrs / FILE_ATTRIBUTE_DIRECTORY) % 2 == 1
end

--- List names in an OS directory without spawning a console.
--- @return table|nil entries `{ { name=string, isDir=bool }, ... }` or nil if unavailable/failed
function M.listDirectory(dir)
  if type(dir) ~= "string" or dir == "" then
    return nil
  end
  if not ensureReady() then
    return nil
  end

  local pattern = dir
  if pattern:sub(-1) == "/" or pattern:sub(-1) == "\\" then
    pattern = pattern .. "*"
  else
    pattern = pattern .. "\\*"
  end

  local wpattern = utf8ToWide(pattern)
  if not wpattern then
    return nil
  end

  local data = ffi.new("WIN32_FIND_DATAW")
  local handle = kernel32.FindFirstFileW(wpattern, data)
  if handle == nil or handle == INVALID_HANDLE_VALUE then
    return nil
  end

  local entries = {}
  repeat
    local name = wideToUtf8(data.cFileName)
    if name and name ~= "" and name ~= "." and name ~= ".." then
      entries[#entries + 1] = {
        name = name,
        isDir = isDirectoryAttr(data.dwFileAttributes),
      }
    end
  until kernel32.FindNextFileW(handle, data) == 0

  kernel32.FindClose(handle)
  return entries
end

--- Current working directory without spawning a console.
--- @return string|nil
function M.getCurrentDirectory()
  if not ensureReady() then
    return nil
  end
  local size = kernel32.GetCurrentDirectoryW(0, nil)
  if size <= 0 then
    return nil
  end
  local buf = ffi.new("WCHAR[?]", size)
  local written = kernel32.GetCurrentDirectoryW(size, buf)
  if written <= 0 then
    return nil
  end
  return wideToUtf8(buf)
end

return M
