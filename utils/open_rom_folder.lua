--- Open the native file manager on the folder that contains the loaded ROM.
-- Prefer love.system.openURL(file://…) when available (no shell); fall back to OS-specific helpers.
local M = {}

local function trimmed(s)
  s = type(s) == "string" and s or ""
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function stripTrailingSep(path)
  return (trimmed(path):gsub("[\\/]+$", ""))
end

local function parentDir(path)
  path = stripTrailingSep(path)
  if path == "" then
    return nil
  end
  local slashAt = nil
  for i = #path, 1, -1 do
    local c = path:byte(i)
    if c == 47 or c == 92 then -- '/' or '\'
      slashAt = i
      break
    end
  end
  if not slashAt then
    return nil
  end
  if slashAt <= 1 then
    -- "/foo" -> "/"
    return "/"
  end
  return stripTrailingSep(path:sub(1, slashAt - 1))
end

local function pathLooksAbsolute(path)
  if path:match("^[\\/]") then
    return true
  end
  if path:match("^[a-zA-Z]:[\\/]") then
    return true
  end
  return false
end

local function hasUnsafeShellChars(path)
  if path:find("[%c`'\"`;|&<>%^%$%!]") then
    return true
  end
  return false
end

local function shellSingleQuoted(posixPath)
  return "'" .. posixPath:gsub("'", "'\\''") .. "'"
end

local function pctEncodeMinimal(uri)
  return uri:gsub("#", "%%23"):gsub(" ", "%%20")
end

local function toFileUriForDirectory(directory)
  if love and love.system and love.system.getOS then
    local osys = love.system.getOS()
    if osys == "Windows" then
      local norm = directory:gsub("\\", "/")
      if norm:match("^%a:/") then
        return pctEncodeMinimal(("file:///%s"):format(norm))
      end
      return nil
    end
    if directory:sub(1, 1) == "/" then
      return pctEncodeMinimal(("file://%s"):format(directory))
    end
  elseif directory:sub(1, 1) == "/" then
    -- Tests / headless LOVE without full system APIs
    return pctEncodeMinimal(("file://%s"):format(directory))
  end
  return nil
end

local function openViaLoveUrl(directory)
  if not (love and love.system and love.system.openURL) then
    return false
  end
  local uri = toFileUriForDirectory(directory)
  if not uri then
    return false
  end
  local ok, opened = pcall(function()
    return love.system.openURL(uri)
  end)
  return ok and opened == true
end

local function osExecuteSucceeded(code)
  return code == true or code == 0 or code == nil
end

local function openViaOsFallback(directory)
  if type(directory) ~= "string" or directory == "" or hasUnsafeShellChars(directory) then
    return false
  end
  local code
  local osys = love and love.system and love.system.getOS and love.system.getOS()
  if osys == "Windows" then
    local w = directory:gsub("/", "\\")
    local q = '"' .. w:gsub('"', "") .. '"'
    code = os.execute('cmd.exe /c start "" explorer ' .. q)
    return osExecuteSucceeded(code)
  elseif osys == "OS X" then
    code = os.execute("/usr/bin/open " .. shellSingleQuoted(directory))
    return osExecuteSucceeded(code)
  end
  code = os.execute(("xdg-open %s >/dev/null 2>&1 &"):format(shellSingleQuoted(directory)))
  return osExecuteSucceeded(code)
end

function M.canOpenParentOfRom(romFilePath)
  local path = trimmed(romFilePath or "")
  if path == "" or not pathLooksAbsolute(path) then
    return false
  end
  local dir = parentDir(path)
  return dir ~= nil and dir ~= ""
end

function M.openParentFolderOfRomPath(romFilePath)
  local path = trimmed(romFilePath or "")
  if path == "" then
    return false, "No ROM loaded"
  end
  if not pathLooksAbsolute(path) then
    return false, "ROM folder is unavailable for this session"
  end
  local dir = parentDir(path)
  if not dir or dir == "" then
    return false, "Could not locate ROM folder"
  end
  if hasUnsafeShellChars(path) or hasUnsafeShellChars(dir) then
    return false, "Path cannot be opened from the UI safely"
  end
  if openViaLoveUrl(dir) then
    return true, nil
  end
  if openViaOsFallback(dir) then
    return true, nil
  end
  return false, "Could not open folder (desktop integration unavailable)"
end

return M
