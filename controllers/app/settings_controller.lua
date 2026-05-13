-- app_settings_controller.lua
-- App settings persistence via LOVE's save directory.

local AppSettingsController = {}
AppSettingsController.__index = AppSettingsController

local TableUtils = require("utils.table_utils")
local AppColors = require("app_colors")
local SETTINGS_FILE = "settings.lua"
local DEFAULT_SETTINGS = {
  skipSplash = false,
  theme = "dark",
  tooltipsEnabled = true,
  canvasImageMode = "keep_aspect",
  canvasFilter = "sharp",
  paletteLinks = "auto_hide",
  separateToolbar = false,
  --- Window-attached toolbar strip: top | left | right | bottom | auto.
  windowToolbarPlacement = "auto",
  --- When true, the resize-corner glyph is never drawn (resize hotspot/cursor unchanged).
  --- When false, the glyph hides while the pointer is over the handle or during resize drag.
  neverShowResizeHandle = false,
  --- Soft blurred drop shadow behind each window (shader).
  windowShadowEnabled = true,
  --- 0 = sharp edge, 1 = softest falloff (maps to feather range in pixels).
  windowShadowBlur = 0.2,
  --- Opacity multiplier for drop shadows (0-100% of theme base).
  windowShadowStrength = 0.5,
  groupedPaletteWindows = false,
  crtEnabled = false,
  crtFilterKind = "crt",
  crtDistortion = 0.1,
  crtCanvasResolution = "640x360",
  --- CRT layer visualizer: visibility, per-window distortion, ref stack + pans (windowIds are best-effort across sessions).
  crtLayerViz = {
    visible = false,
    distortion = 0.1,
    activeLayer = 1,
    refs = {},
  },
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

local function normalizeWindowShadowBlur(n)
  local v = tonumber(n)
  if v == nil then
    return 0.2
  end
  return math.max(0, math.min(1, v))
end

local function normalizeWindowShadowStrength(n)
  local v = tonumber(n)
  if v == nil then
    return 0.5
  end
  return math.max(0, math.min(1, v))
end

local function normalizePaletteLinksKey(key)
  if key == "always" then return "always" end
  if key == "on_hover" or key == "never" then return "on_hover" end
  if key == "auto_hide" then return "auto_hide" end
  return "auto_hide"
end

local function normalizeWindowToolbarPlacementKey(key)
  if key == "left" then return "left" end
  if key == "right" then return "right" end
  if key == "bottom" then return "bottom" end
  if key == "auto" then return "auto" end
  if key == "top" then return "top" end
  return "auto"
end

local function normalizeCrtDistortion(n)
  local v = tonumber(n)
  if not v then
    return 0.1
  end
  return math.max(0, math.min(0.45, v))
end

local function normalizeCrtCanvasResolutionKey(key)
  if key == "320x180" then
    return "320x180"
  end
  return "640x360"
end

local function normalizeCrtFilterKind(key)
  if key == "composite" then
    return "composite"
  end
  return "crt"
end

local function normalizeCrtLayerViz(data)
  if type(data) ~= "table" then
    return {
      visible = false,
      distortion = normalizeCrtDistortion(nil),
      activeLayer = 1,
      refs = {},
    }
  end
  local out = {
    visible = (data.visible == true),
    distortion = normalizeCrtDistortion(data.distortion),
    activeLayer = math.max(1, math.floor(tonumber(data.activeLayer) or 1)),
    refs = {},
  }
  for _, r in ipairs(type(data.refs) == "table" and data.refs or {}) do
    if type(r) == "table" and r.windowId ~= nil then
      local op = tonumber(r.opacity)
      if not op then
        op = 1
      end
      op = math.max(0, math.min(1, op))
      out.refs[#out.refs + 1] = {
        windowId = tostring(r.windowId),
        layerIndex = math.max(1, math.floor(tonumber(r.layerIndex) or 1)),
        panX = tonumber(r.panX) or 0,
        panY = tonumber(r.panY) or 0,
        opacity = op,
      }
    end
  end
  return out
end

local APPEARANCE_CHROME_SLOTS = {
  "dark_background",
  "light_background",
  "dark_focused",
  "light_focused",
  "dark_non_focused",
  "light_non_focused",
  "dark_text_icons_focused",
  "light_text_icons_focused",
  "dark_text_icons_non_focused",
  "light_text_icons_non_focused",
}

-- Older builds sometimes stored mid neutral gray for "focused" chrome by mistake; drop so defaults apply.
-- Do not treat dark near-blacks (e.g. #242424) or near-whites as legacy.
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
  if lum < 0.22 or lum > 0.78 then
    return false
  end
  return true
end

local function normalizeAppearanceChrome(data)
  local out = {}
  local raw = type(data) == "table" and data or {}
  for _, id in ipairs(APPEARANCE_CHROME_SLOTS) do
    local e = raw[id]
    if type(e) == "table" then
      local r = tonumber(e[1] ~= nil and e[1] or e.r)
      local g = tonumber(e[2] ~= nil and e[2] or e.g)
      local b = tonumber(e[3] ~= nil and e[3] or e.b)
      if r and g and b then
        r = math.max(0, math.min(1, r))
        g = math.max(0, math.min(1, g))
        b = math.max(0, math.min(1, b))
        if (id == "dark_focused" or id == "light_focused") and isLegacyNeutralFocusedChrome(r, g, b) then
          -- Drop so defaults apply.
        else
          out[id] = { r, g, b }
        end
      end
    end
  end
  -- Older saves used a single {dark,light}_text_icons for all chrome ink.
  for _, mode in ipairs({ "dark", "light" }) do
    local kF = mode .. "_text_icons_focused"
    local kN = mode .. "_text_icons_non_focused"
    if not out[kF] and not out[kN] then
      local e = raw[mode .. "_text_icons"]
      if type(e) == "table" then
        local r = tonumber(e[1] ~= nil and e[1] or e.r)
        local g = tonumber(e[2] ~= nil and e[2] or e.g)
        local b = tonumber(e[3] ~= nil and e[3] or e.b)
        if r and g and b then
          r = math.max(0, math.min(1, r))
          g = math.max(0, math.min(1, g))
          b = math.max(0, math.min(1, b))
          out[kF] = { r, g, b }
          out[kN] = { r, g, b }
        end
      end
    end
  end
  -- Fill any missing slot from app default hex palette (first run or partial saves).
  local defRgb = AppColors.defaultAppearanceChromeAsRgb and AppColors.defaultAppearanceChromeAsRgb() or nil
  if defRgb then
    for _, id in ipairs(APPEARANCE_CHROME_SLOTS) do
      if not out[id] and defRgb[id] then
        local e = defRgb[id]
        out[id] = { e[1], e[2], e[3] }
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
  out.windowToolbarPlacement = normalizeWindowToolbarPlacementKey(data and data.windowToolbarPlacement)
  out.neverShowResizeHandle = (data and data.neverShowResizeHandle == true)
  out.windowShadowEnabled = not (data and data.windowShadowEnabled == false)
  out.windowShadowBlur = normalizeWindowShadowBlur(data and data.windowShadowBlur)
  out.windowShadowStrength = normalizeWindowShadowStrength(data and data.windowShadowStrength)
  out.groupedPaletteWindows = (data and data.groupedPaletteWindows == true)
  out.crtEnabled = (data and data.crtEnabled == true)
  out.crtFilterKind = normalizeCrtFilterKind(data and data.crtFilterKind)
  out.crtDistortion = normalizeCrtDistortion(data and data.crtDistortion)
  out.crtCanvasResolution = normalizeCrtCanvasResolutionKey(data and data.crtCanvasResolution)
  out.crtLayerViz = normalizeCrtLayerViz(data and data.crtLayerViz)
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
  if opts.windowToolbarPlacement ~= nil then
    data.windowToolbarPlacement = normalizeWindowToolbarPlacementKey(opts.windowToolbarPlacement)
  end
  if opts.neverShowResizeHandle ~= nil then data.neverShowResizeHandle = (opts.neverShowResizeHandle == true) end
  if opts.windowShadowEnabled ~= nil then data.windowShadowEnabled = (opts.windowShadowEnabled == true) end
  if opts.windowShadowBlur ~= nil then data.windowShadowBlur = normalizeWindowShadowBlur(opts.windowShadowBlur) end
  if opts.windowShadowStrength ~= nil then data.windowShadowStrength = normalizeWindowShadowStrength(opts.windowShadowStrength) end
  if opts.groupedPaletteWindows ~= nil then data.groupedPaletteWindows = (opts.groupedPaletteWindows == true) end
  if opts.crtEnabled ~= nil then data.crtEnabled = (opts.crtEnabled == true) end
  if opts.crtFilterKind ~= nil then data.crtFilterKind = normalizeCrtFilterKind(opts.crtFilterKind) end
  if opts.crtDistortion ~= nil then data.crtDistortion = normalizeCrtDistortion(opts.crtDistortion) end
  if opts.crtCanvasResolution ~= nil then data.crtCanvasResolution = normalizeCrtCanvasResolutionKey(opts.crtCanvasResolution) end
  if opts.crtLayerViz ~= nil then data.crtLayerViz = normalizeCrtLayerViz(opts.crtLayerViz) end
  if opts.recentProjects ~= nil then data.recentProjects = normalizeRecentProjects(opts.recentProjects) end
  -- appearanceChrome: merge into existing file data by default (partial updates from UI).
  -- mergeAppearanceChrome = false: replace chrome from opts.appearanceChrome only (e.g. reset with {}).
  if opts.appearanceChrome ~= nil then
    local merged
    if opts.mergeAppearanceChrome == false then
      merged = TableUtils.deepcopy(opts.appearanceChrome)
    else
      local prev = type(data.appearanceChrome) == "table" and data.appearanceChrome or {}
      merged = TableUtils.deepcopy(prev)
      for k, v in pairs(opts.appearanceChrome) do
        merged[k] = v
      end
    end
    data.appearanceChrome = normalizeAppearanceChrome(merged)
  end
  return writeFile(data)
end

function AppSettingsController.normalizeWindowShadowStrength(n)
  return normalizeWindowShadowStrength(n)
end

function AppSettingsController.normalizeWindowShadowBlur(n)
  return normalizeWindowShadowBlur(n)
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
