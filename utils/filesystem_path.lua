-- Shared filesystem path helpers (OS paths, not love.filesystem virtual paths).

local M = {}

local function trim(text)
  return tostring(text or ""):match("^%s*(.-)%s*$")
end

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

--- Native path separator for the current OS ("\\" on Windows, "/" elsewhere).
function M.separator()
  return IS_WINDOWS and "\\" or "/"
end

--- OS temporary directory (no trailing separator). Falls back sensibly per platform.
function M.getTempDir()
  if IS_WINDOWS then
    local candidate = os.getenv("TEMP") or os.getenv("TMP")
    if type(candidate) == "string" and candidate ~= "" then
      return (candidate:gsub("[/\\]+$", ""))
    end
    return "."
  end
  local candidate = os.getenv("TMPDIR")
  if type(candidate) == "string" and candidate ~= "" then
    return (candidate:gsub("/+$", ""))
  end
  return "/tmp"
end

--- Join path segments using the native separator. Nil/empty segments are skipped.
function M.join(...)
  local sep = M.separator()
  local result = nil
  for _, segment in ipairs({ ... }) do
    segment = tostring(segment or "")
    if segment ~= "" then
      if result == nil then
        result = (segment:gsub("[/\\]+$", ""))
      else
        result = result .. sep .. (segment:gsub("^[/\\]+", ""):gsub("[/\\]+$", ""))
      end
    end
  end
  return result or ""
end

function M.isAbsolutePath(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  if path:sub(1, 1) == "/" or path:sub(1, 1) == "\\" then
    return true
  end
  -- Windows drive letter: C:\ or C:/
  if path:match("^%a:[/\\]") then
    return true
  end
  return false
end

function M.getWorkingDirectory()
  if love and love.filesystem and love.filesystem.getWorkingDirectory then
    local dir = love.filesystem.getWorkingDirectory()
    if type(dir) == "string" and dir ~= "" then
      return dir
    end
  end
  local isWindows = package.config:sub(1, 1) == "\\"
  if isWindows then
    local okWin, WinFs = pcall(require, "utils.win_fs")
    if okWin and WinFs and WinFs.getCurrentDirectory then
      local dir = WinFs.getCurrentDirectory()
      if type(dir) == "string" and dir ~= "" then
        return dir
      end
    end
    return nil
  end
  -- POSIX: pwd via popen does not flash a terminal window.
  local handle = io.popen("pwd")
  if not handle then
    return nil
  end
  local line = handle:read("*l")
  handle:close()
  line = trim((line or ""):gsub("\r", ""))
  if line == "" then
    return nil
  end
  return line
end

--- Resolve a filesystem path to an absolute path when possible.
--- Leaves already-absolute paths unchanged (aside from trim).
function M.toAbsolutePath(path)
  path = trim(path)
  if path == "" then
    return nil
  end
  if M.isAbsolutePath(path) then
    return path
  end
  local cwd = M.getWorkingDirectory()
  if type(cwd) ~= "string" or cwd == "" then
    return path
  end
  local sep = package.config:sub(1, 1)
  if cwd:sub(-1) == "/" or cwd:sub(-1) == "\\" then
    return cwd .. path
  end
  return cwd .. sep .. path
end

function M.pathExists(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local ok = os.rename(path, path)
  if ok then
    return true
  end
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end
  return false
end

--- Create a directory and parents (mkdir -p). Returns true when the path exists afterward.
function M.ensureDir(path)
  path = trim(path)
  if path == "" then
    return false
  end
  path = path:gsub("[/\\]+$", "")
  if path == "" then
    return false
  end
  if M.pathExists(path) then
    return true
  end

  -- Create parents first.
  local parent = path:match("^(.*)[/\\][^/\\]+$")
  if parent and parent ~= "" and parent ~= path and not (IS_WINDOWS and parent:match("^%a:$")) then
    if not M.ensureDir(parent) then
      return false
    end
  end

  if IS_WINDOWS then
    local okFfi, ffi = pcall(require, "ffi")
    if okFfi and ffi then
      pcall(ffi.cdef, [[
        int CreateDirectoryA(const char* lpPathName, void* lpSecurityAttributes);
        unsigned long GetLastError(void);
      ]])
      local okKernel, kernel32 = pcall(ffi.load, "kernel32")
      if okKernel and kernel32 then
        local created = kernel32.CreateDirectoryA(path, nil)
        if created ~= 0 then
          return true
        end
        local err = tonumber(kernel32.GetLastError()) or 0
        -- ERROR_ALREADY_EXISTS
        if err == 183 then
          return true
        end
      end
    end
    -- cmd mkdir creates intermediate dirs; normalize separators.
    local winPath = path:gsub("/", "\\")
    os.execute('mkdir "' .. winPath .. '" >NUL 2>NUL')
  else
    os.execute('mkdir -p "' .. path .. '" >/dev/null 2>&1')
  end

  return M.pathExists(path)
end

return M
