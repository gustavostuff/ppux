-- app_settings_controller.lua
-- App settings persistence via LÖVE's save directory.

local AppSettingsController = {}
AppSettingsController.__index = AppSettingsController

local TableUtils = require("utils.table_utils")
local SETTINGS_FILE = "settings.lua"
local DEFAULT_SETTINGS = {
  skipSplash = false,
  theme = "dark",
  tooltipsEnabled = true,
  canvasImageMode = "pixel_perfect",
  canvasFilter = "sharp",
  paletteLinks = "auto_hide",
  separateToolbar = false,
  groupedPaletteWindows = false,
  recentProjects = {},
}

local MAX_RECENT_PROJECTS = 4

local function splitPath(p)
  local d, b = tostring(p or ""):match("^(.*)[/\\]([^/\\]+)$")
  if not d then return "", tostring(p or "") end
  return d, b
end

local function stripExt(name)
  return (tostring(name or ""):gsub("%.[^%.]+$", ""))
end

local function canonicalProjectStem(name)
  local stem = stripExt(name or "project")
  stem = stem:gsub("_edited$", "")
  stem = stem:gsub("_project$", "")
  return stem
end

local function joinPath(dir, name)
  local sep = (package.config:sub(1,1) == "\\" and "\\") or "/"
  if dir == "" then return name end
  if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then return dir .. name end
  return dir .. sep .. name
end

local function normalizeRecentProjectBasePath(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local dir, base = splitPath(path)
  local stem = canonicalProjectStem(base)
  if stem == "" then
    return nil
  end
  return joinPath(dir, stem)
end

local function normalizeRecentProjects(list)
  local out = {}
  local seen = {}
  for _, path in ipairs(list or {}) do
    local normalized = normalizeRecentProjectBasePath(path)
    if normalized and not seen[normalized] then
      seen[normalized] = true
      out[#out + 1] = normalized
      if #out >= MAX_RECENT_PROJECTS then
        break
      end
    end
  end
  return out
end

local function normalizeCanvasImageModeKey(key)
  if key == "pixel_perfect" then return "pixel_perfect" end
  if key == "keep_aspect" then return "keep_aspect" end
  return "stretch"
end

local function normalizeCanvasFilterKey(key)
  if key == "soft" then return "soft" end
  return "sharp"
end

local function normalizeThemeKey(key)
  if key == "light" then return "light" end
  return "dark"
end

local function normalizePaletteLinksKey(key)
  if key == "always" then return "always" end
  if key == "on_hover" or key == "never" then return "on_hover" end
  if key == "auto_hide" then return "auto_hide" end
  return "auto_hide"
end

local APPEARANCE_CHROME_SLOTS = {
  "dark_focused",
  "light_focused",
  "dark_non_focused",
  "light_non_focused",
  "dark_text_icons",
  "light_text_icons",
}

-- Older builds / mistaken saves sometimes stored neutral gray for "focused" chrome; defaults are #5b6ee1.
local function isLegacyNeutralFocusedChrome(r, g, b)
  local maxc = math.max(r, g, b)
  local minc = math.min(r, g, b)
  if (maxc - minc) > 0.045 then
    return false
  end
  local lum = (maxc + minc) * 0.5
  if lum <= 0.11 or lum >= 0.9 then
    return false
  end
  return true
end

local function normalizeAppearanceChrome(data)
  local out = {}
  if type(data) ~= "table" then
    return out
  end
  for _, id in ipairs(APPEARANCE_CHROME_SLOTS) do
    local e = data[id]
    if type(e) == "table" then
      local r = tonumber(e[1] ~= nil and e[1] or e.r)
      local g = tonumber(e[2] ~= nil and e[2] or e.g)
      local b = tonumber(e[3] ~= nil and e[3] or e.b)
      if r and g and b then
        r = math.max(0, math.min(1, r))
        g = math.max(0, math.min(1, g))
        b = math.max(0, math.min(1, b))
        if (id == "dark_focused" or id == "light_focused") and isLegacyNeutralFocusedChrome(r, g, b) then
          -- Drop so appearanceChromeResolved uses builtin focused blue.
        else
          out[id] = { r, g, b }
        end
      end
    end
  end
  return out
end

local function withDefaults(data)
  local out = TableUtils.deepcopy(DEFAULT_SETTINGS)
  out.skipSplash = (data and data.skipSplash == true)
  out.theme = normalizeThemeKey(data and data.theme)
  out.tooltipsEnabled = not (data and data.tooltipsEnabled == false)
  out.canvasImageMode = normalizeCanvasImageModeKey(data and data.canvasImageMode)
  out.canvasFilter = normalizeCanvasFilterKey(data and data.canvasFilter)
  out.paletteLinks = normalizePaletteLinksKey(data and data.paletteLinks)
  out.separateToolbar = (data and data.separateToolbar == true)
  out.groupedPaletteWindows = (data and data.groupedPaletteWindows == true)
  out.recentProjects = normalizeRecentProjects(data and data.recentProjects)
  out.appearanceChrome = normalizeAppearanceChrome(data and data.appearanceChrome)
  return out
end

local function loadSettingsChunk(path)
  if not (love and love.filesystem and love.filesystem.getInfo and love.filesystem.load) then
    return nil
  end

  if not love.filesystem.getInfo(path) then
    return nil
  end

  local chunk = love.filesystem.load(path)
  if not chunk then return nil end

  local ok, data = pcall(chunk)
  if ok and type(data) == "table" then
    return withDefaults(data)
  end
  return nil
end

local function writeFile(data)
  local contents = TableUtils.serialize_lua_table(withDefaults(data)) or "return {}"
  if contents:sub(-1) ~= "\n" then
    contents = contents .. "\n"
  end

  if not (love and love.filesystem and love.filesystem.write) then
    return false, "love.filesystem.write unavailable"
  end

  local ok, err = love.filesystem.write(SETTINGS_FILE, contents)
  if ok == true or type(ok) == "number" then
    return true
  end
  return false, err
end

local function readFile()
  local data = loadSettingsChunk(SETTINGS_FILE)
  if data then return data end
  return withDefaults()
end

function AppSettingsController.load()
  return readFile()
end

function AppSettingsController.defaults()
  return TableUtils.deepcopy(DEFAULT_SETTINGS)
end

function AppSettingsController.save(opts)
  opts = opts or {}
  local data = readFile()
  if opts.skipSplash ~= nil then data.skipSplash = (opts.skipSplash == true) end
  if opts.theme ~= nil then data.theme = normalizeThemeKey(opts.theme) end
  if opts.tooltipsEnabled ~= nil then data.tooltipsEnabled = (opts.tooltipsEnabled ~= false) end
  if opts.canvasImageMode ~= nil then data.canvasImageMode = opts.canvasImageMode end
  if opts.canvasFilter ~= nil then data.canvasFilter = opts.canvasFilter end
  if opts.paletteLinks ~= nil then data.paletteLinks = normalizePaletteLinksKey(opts.paletteLinks) end
  if opts.separateToolbar ~= nil then data.separateToolbar = (opts.separateToolbar == true) end
  if opts.groupedPaletteWindows ~= nil then data.groupedPaletteWindows = (opts.groupedPaletteWindows == true) end
  if opts.recentProjects ~= nil then data.recentProjects = normalizeRecentProjects(opts.recentProjects) end
  if opts.appearanceChrome ~= nil then data.appearanceChrome = normalizeAppearanceChrome(opts.appearanceChrome) end
  return writeFile(data)
end

function AppSettingsController.normalizeRecentProjects(list)
  return normalizeRecentProjects(list)
end

function AppSettingsController.normalizeRecentProjectBasePath(path)
  return normalizeRecentProjectBasePath(path)
end

function AppSettingsController.addRecentProject(path, currentList, maxCount)
  local normalized = normalizeRecentProjectBasePath(path)
  if not normalized then
    return normalizeRecentProjects(currentList)
  end

  local out = { normalized }
  local seen = {
    [normalized] = true,
  }
  for _, existing in ipairs(currentList or {}) do
    local candidate = normalizeRecentProjectBasePath(existing)
    if candidate and not seen[candidate] then
      seen[candidate] = true
      out[#out + 1] = candidate
      if #out >= math.max(1, math.floor(maxCount or MAX_RECENT_PROJECTS)) then
        break
      end
    end
  end
  return out
end

function AppSettingsController.loadDisplaySettings()
  return AppSettingsController.load()
end

function AppSettingsController.saveDisplaySettings(opts)
  return AppSettingsController.save(opts)
end

function AppSettingsController.saveCurrentState(baseW, baseH)
  return true
end

function AppSettingsController.applyWindowSettings(settings, baseW, baseH)
  return settings
end

return AppSettingsController
