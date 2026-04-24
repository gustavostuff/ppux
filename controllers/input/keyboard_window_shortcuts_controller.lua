local ResolutionController = require("controllers.app.resolution_controller")
local GridModeUtils = require("controllers.grid_mode_utils")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}
local EXIT_FULLSCREEN_SCALE = 2

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

local function invalidateVolatileWindowCanvases(app)
  if app and app.invalidateAllPpuFrameNametableCanvases then
    app:invalidateAllPpuFrameNametableCanvases()
  end
  if app and app.invalidateAllStaticAnimationTileLayerCanvases then
    app:invalidateAllStaticAnimationTileLayerCanvases()
  end
end

local function copyWindowFlags(flags)
  local out = {}
  for k, v in pairs(flags or {}) do
    out[k] = v
  end
  return out
end

local function windowFlagsEquivalent(currentFlags, desiredFlags)
  currentFlags = currentFlags or {}
  desiredFlags = desiredFlags or {}
  local booleanKeys = {
    fullscreen = true, resizable = true, borderless = true, centered = true,
    highdpi = true, usedpiscale = true,
  }
  local keys = {
    "fullscreen", "vsync", "msaa", "resizable", "borderless",
    "centered", "display", "highdpi", "usedpiscale", "minwidth", "minheight",
  }
  for _, k in ipairs(keys) do
    local a = currentFlags[k]
    local b = desiredFlags[k]
    if booleanKeys[k] then
      a = (a == true)
      b = (b == true)
    end
    if a ~= b then
      return false
    end
  end
  return true
end

local function applyWindowMode(targetW, targetH, currentFlags, overrides)
  local flags = copyWindowFlags(currentFlags)
  for k, v in pairs(overrides or {}) do
    flags[k] = v
  end
  flags.x = nil
  flags.y = nil

  local curW, curH = love.window.getMode()
  if curW ~= targetW or curH ~= targetH or (not windowFlagsEquivalent(currentFlags, flags)) then
    love.window.updateMode(targetW, targetH, flags)
  end

  return flags
end

function M.handleWindowScaling(ctx, utils, key, AppCoreControllerRef)
  if (key == "1" or key == "2" or key == "3") and utils.ctrlDown() then
    local numerScale = tonumber(key)
    local _, _, currentFlags = love.window.getMode()
    local targetW = AppCoreControllerRef.canvas:getWidth() * numerScale
    local targetH = AppCoreControllerRef.canvas:getHeight() * numerScale

    applyWindowMode(targetW, targetH, currentFlags, {
      fullscreen = false,
    })
    ResolutionController:recalculate()
    if AppCoreControllerRef then
      AppCoreControllerRef._windowedScalePreference = numerScale
      invalidateVolatileWindowCanvases(AppCoreControllerRef)
    end
    return true
  end
  return false
end

function M.handleCascade(ctx, utils, key)
  if not (key == "a" and utils.ctrlDown() and utils.altDown()) then return false end
  local wm = ctx.wm and ctx.wm()
  if wm and wm.cascade then
    wm:cascade()
    return true
  end
  return false
end

function M.handleFullscreen(ctx, utils, key)
  if key == "f" and utils.ctrlDown() then
    local newVal = not love.window.getFullscreen()
    local app = ctx.app
    local curW, curH, currentFlags = love.window.getMode()
    if newVal then
      if app and app._getWindowScaleForSettings then
        app._windowedScalePreference = app:_getWindowScaleForSettings()
      end
      applyWindowMode(curW, curH, currentFlags, {
        fullscreen = true,
      })
      ResolutionController:recalculate()
      invalidateVolatileWindowCanvases(app)
    else
      local baseW = ResolutionController.canvasWidth or (app and app.canvas and app.canvas:getWidth()) or love.graphics.getWidth()
      local baseH = ResolutionController.canvasHeight or (app and app.canvas and app.canvas:getHeight()) or love.graphics.getHeight()
      local targetW = baseW * EXIT_FULLSCREEN_SCALE
      local targetH = baseH * EXIT_FULLSCREEN_SCALE

      applyWindowMode(targetW, targetH, currentFlags, {
        fullscreen = false,
      })
      if app then
        app._windowedScalePreference = EXIT_FULLSCREEN_SCALE
        invalidateVolatileWindowCanvases(app)
      end
      ResolutionController:recalculate()
    end
    return true
  end
  return false
end

function M.handleModeSwitch(ctx, key)
  if key == "tab" and not love.mouse.isDown(1) then
    ctx.setMode(ctx.getMode() == "tile" and "edit" or "tile")
    return true
  end
  return false
end

function M.handleSpaceHighlightToggle(ctx, utils, key)
  if key ~= "space" then return false end
  if utils.ctrlDown and utils.ctrlDown() then return false end
  if utils.altDown and utils.altDown() then return false end

  local enabled = false
  if ctx.toggleSpaceHighlightActive then
    enabled = ctx.toggleSpaceHighlightActive()
  elseif ctx.setSpaceHighlightActive and ctx.getSpaceHighlightActive then
    enabled = not ctx.getSpaceHighlightActive()
    ctx.setSpaceHighlightActive(enabled)
  else
    return false
  end

  if ctx.setStatus then
    setStatus(ctx, enabled and "Show all items: on" or "Show all items: off")
  end
  return true
end

function M.handleWindowZoom(ctx, utils, key)
  if utils.ctrlDown() and (key == "1" or key == "2" or key == "3") then
    local wm = ctx.wm()
    local focus = wm and wm:getFocus()
    if WindowCaps.isAnyPaletteWindow(focus) then
      return false
    end
    if focus and focus.setZoomLevel then
      local zoomLevel = tonumber(key)
      focus:setZoomLevel(zoomLevel)
      setStatus(ctx, string.format("Zoom: %dx", zoomLevel))
      return true
    end
  end
  return false
end

function M.handleGridToggleInWindow(ctx, utils, key, focus)
  if not focus then return false end
  if key ~= "g" then
    return false
  end
  if not (utils and utils.ctrlDown and utils.ctrlDown()) then
    return false
  end
  focus.showGrid = GridModeUtils.next(focus.showGrid)
  setStatus(ctx, string.format("Grid: %s", focus.showGrid))
  return true
end

return M
