-- Shared filesystem path helpers (OS paths, not love.filesystem virtual paths).

local M = {}

local function trim(text)
  return tostring(text or ""):match("^%s*(.-)%s*$")
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
  local handle = io.popen(isWindows and "cd" or "pwd")
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

return M
