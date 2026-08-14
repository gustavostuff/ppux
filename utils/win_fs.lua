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
    DWORD GetFileAttributesW(const WCHAR* lpFileName);
    BOOL CreateDirectoryW(const WCHAR* lpPathName, void* lpSecurityAttributes);
    DWORD GetLastError(void);
  ]])

  pcall(ffi.cdef, [[
    typedef unsigned long DWORD;
    typedef int BOOL;
    typedef void* HANDLE;
    typedef unsigned short WCHAR;

    DWORD SearchPathW(const WCHAR* lpPath, const WCHAR* lpFileName, const WCHAR* lpExtension,
      DWORD nBufferLength, WCHAR* lpBuffer, WCHAR** lpFilePart);

    typedef struct _STARTUPINFOW {
      DWORD cb;
      WCHAR* lpReserved;
      WCHAR* lpDesktop;
      WCHAR* lpTitle;
      DWORD dwX;
      DWORD dwY;
      DWORD dwXSize;
      DWORD dwYSize;
      DWORD dwXCountChars;
      DWORD dwYCountChars;
      DWORD dwFillAttribute;
      DWORD dwFlags;
      unsigned short wShowWindow;
      unsigned short cbReserved2;
      unsigned char* lpReserved2;
      HANDLE hStdInput;
      HANDLE hStdOutput;
      HANDLE hStdError;
    } STARTUPINFOW;

    typedef struct _PROCESS_INFORMATION {
      HANDLE hProcess;
      HANDLE hThread;
      DWORD dwProcessId;
      DWORD dwThreadId;
    } PROCESS_INFORMATION;

    BOOL CreateProcessW(const WCHAR* lpApplicationName, WCHAR* lpCommandLine,
      void* lpProcessAttributes, void* lpThreadAttributes, BOOL bInheritHandles,
      DWORD dwCreationFlags, void* lpEnvironment, const WCHAR* lpCurrentDirectory,
      STARTUPINFOW* lpStartupInfo, PROCESS_INFORMATION* lpProcessInformation);
    DWORD WaitForSingleObject(HANDLE hHandle, DWORD dwMilliseconds);
    BOOL GetExitCodeProcess(HANDLE hProcess, DWORD* lpExitCode);
    BOOL CloseHandle(HANDLE hObject);
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

local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
local ERROR_ALREADY_EXISTS = 183

--- Create a directory and its parents without spawning a console.
--- @return boolean
function M.ensureDirectory(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  path = path:gsub("[/\\]+$", "")
  if path == "" then
    return false
  end
  if path:match("^%a:$") then
    return true
  end
  if not ensureReady() then
    return false
  end

  local wpath = utf8ToWide(path)
  if not wpath then
    return false
  end

  local okAttrs, attrs = pcall(kernel32.GetFileAttributesW, wpath)
  if okAttrs and attrs ~= nil and tonumber(attrs) ~= INVALID_FILE_ATTRIBUTES then
    if isDirectoryAttr(attrs) then
      return true
    end
    return false
  end

  local parent = path:match("^(.*)[/\\][^/\\]+$")
  if parent and parent ~= "" and parent ~= path and not parent:match("^%a:$") then
    if not M.ensureDirectory(parent) then
      return false
    end
  end

  local okCreate, created = pcall(kernel32.CreateDirectoryW, wpath, nil)
  if okCreate and created ~= 0 then
    return true
  end
  local okErr, err = pcall(kernel32.GetLastError)
  err = (okErr and tonumber(err)) or 0
  return err == ERROR_ALREADY_EXISTS
end

--- Locate an executable on PATH without spawning a console (`where` flashes cmd).
--- @param fileName string e.g. "ca65" or "ca65.exe"
--- @param extension string|nil e.g. ".exe" when fileName has no extension
--- @return string|nil absolute path
function M.searchPath(fileName, extension)
  if type(fileName) ~= "string" or fileName == "" then
    return nil
  end
  if not ensureReady() then
    return nil
  end
  local wname = utf8ToWide(fileName)
  if not wname then
    return nil
  end
  local wext = nil
  if type(extension) == "string" and extension ~= "" then
    wext = utf8ToWide(extension)
  end
  local bufSize = 32768
  local buf = ffi.new("WCHAR[?]", bufSize)
  local okCall, n = pcall(kernel32.SearchPathW, nil, wname, wext, bufSize, buf, nil)
  if not okCall or not n or n <= 0 or n >= bufSize then
    return nil
  end
  return wideToUtf8(buf)
end

local CREATE_NO_WINDOW = 0x08000000
local STARTF_USESHOWWINDOW = 0x00000001

--- Run a process with no console window. `commandLine` is the full argv string.
--- @return boolean ok, number|nil exitCode
function M.runHidden(commandLine, currentDirectory)
  if type(commandLine) ~= "string" or commandLine == "" then
    return false, nil
  end
  if not ensureReady() then
    return false, nil
  end

  local wcmd = utf8ToWide(commandLine)
  if not wcmd then
    return false, nil
  end
  -- CreateProcessW may write to the command-line buffer.
  local cmdLen = 0
  while wcmd[cmdLen] ~= 0 do
    cmdLen = cmdLen + 1
  end
  local cmdBuf = ffi.new("WCHAR[?]", cmdLen + 1)
  ffi.copy(cmdBuf, wcmd, (cmdLen + 1) * ffi.sizeof("WCHAR"))

  local wdir = nil
  if type(currentDirectory) == "string" and currentDirectory ~= "" then
    wdir = utf8ToWide(currentDirectory)
  end

  local si = ffi.new("STARTUPINFOW")
  ffi.fill(si, ffi.sizeof(si), 0)
  si.cb = ffi.sizeof(si)
  si.dwFlags = STARTF_USESHOWWINDOW
  si.wShowWindow = 0

  local pi = ffi.new("PROCESS_INFORMATION")
  ffi.fill(pi, ffi.sizeof(pi), 0)

  local okCall, ok = pcall(
    kernel32.CreateProcessW,
    nil,
    cmdBuf,
    nil,
    nil,
    0,
    CREATE_NO_WINDOW,
    nil,
    wdir,
    si,
    pi
  )
  if not okCall or ok == 0 then
    return false, nil
  end

  kernel32.WaitForSingleObject(pi.hProcess, 0xFFFFFFFF)
  local codeBuf = ffi.new("DWORD[1]")
  kernel32.GetExitCodeProcess(pi.hProcess, codeBuf)
  kernel32.CloseHandle(pi.hProcess)
  kernel32.CloseHandle(pi.hThread)
  local exitCode = tonumber(codeBuf[0]) or -1
  return exitCode == 0, exitCode
end

return M
