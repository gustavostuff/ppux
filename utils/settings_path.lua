local M = {}

local APP_NAME = "PPUX"
local SETTINGS_FILE = "settings.lua"

local function isWindows()
  return package.config:sub(1, 1) == "\\"
end

local function pathExists(path)
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

local function pathJoin(base, leaf, sep)
  sep = sep or "/"
  if not base or base == "" then
    return leaf
  end
  if base:sub(-1) == sep then
    return base .. leaf
  end
  return base .. sep .. leaf
end

local function getConfigDirWindows()
  local appdata = os.getenv("APPDATA")
  if appdata and appdata ~= "" then
    return pathJoin(appdata, APP_NAME, "\\")
  end
  local home = os.getenv("USERPROFILE")
  if home and home ~= "" then
    return home .. "\\AppData\\Roaming\\" .. APP_NAME
  end
  return nil
end

local function getConfigDirMac()
  local home = os.getenv("HOME")
  if home and home ~= "" then
    return home .. "/Library/Application Support/" .. APP_NAME
  end
  return nil
end

local function getConfigDirLinux()
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if xdg and xdg ~= "" then
    return pathJoin(xdg, APP_NAME, "/")
  end
  local home = os.getenv("HOME")
  if home and home ~= "" then
    return home .. "/.config/" .. APP_NAME
  end
  return nil
end

function M.getConfigDir()
  if isWindows() then
    return getConfigDirWindows()
  end

  local home = os.getenv("HOME")
  if home and home:match("^/Users/") then
    return getConfigDirMac()
  end
  return getConfigDirLinux()
end

function M.getSettingsFilePath()
  local dir = M.getConfigDir()
  if not dir or dir == "" then
    return SETTINGS_FILE
  end
  return pathJoin(dir, SETTINGS_FILE, isWindows() and "\\" or "/")
end

function M.getLegacySettingsFilePath()
  return SETTINGS_FILE
end

function M.getSettingsFileCandidates()
  return {
    M.getSettingsFilePath(),
    M.getLegacySettingsFilePath(),
  }
end

function M.ensureConfigDir()
  local dir = M.getConfigDir()
  if not dir or dir == "" then
    return false
  end

  if pathExists(dir) then
    return true
  end

  if isWindows() then
    local okFfi, ffi = pcall(require, "ffi")
    if okFfi and ffi then
      local okCdef = pcall(ffi.cdef, [[
        int CreateDirectoryA(const char* lpPathName, void* lpSecurityAttributes);
        unsigned long GetLastError(void);
      ]])
      local okKernel, kernel32 = pcall(ffi.load, "kernel32")
      if okCdef and okKernel and kernel32 then
        local created = kernel32.CreateDirectoryA(dir, nil)
        if created ~= 0 then
          return true
        end
        local err = tonumber(kernel32.GetLastError()) or 0
        if err == 183 then
          return true
        end
      end
    end
    os.execute('mkdir "' .. dir .. '" >NUL 2>NUL')
  else
    os.execute('mkdir -p "' .. dir .. '" >/dev/null 2>&1')
  end

  return pathExists(dir)
end

return M
