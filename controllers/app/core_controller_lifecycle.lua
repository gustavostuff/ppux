local ResolutionController = require("controllers.app.resolution_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local BankCanvasController = require("controllers.chr.bank_canvas_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local AppSettingsController = require("controllers.app.settings_controller")
local CursorsController = require("controllers.input_support.cursors_controller")
local Taskbar = require("user_interface.taskbar")
local UiScale = require("user_interface.ui_scale")
local ToastController = require("controllers.ui.toast_controller")
local UserInput = require("controllers.input")
local RomProjectController = require("controllers.rom.rom_project_controller")
local Splash = require("splash")
local Text = require("utils.text_utils")
local Timer = require("utils.timer_utils")
local katsudo = require("lib.katsudo")
local colors = require("app_colors")
local images = require("images")

local anyModalVisible
local chooseBankTileRefForLabel
local firstSelectedTargetForWindow

return function(AppCoreController)
function AppCoreController:_buildCtx()
  local selfRef = self
  local function setAppStatus(text)
    return selfRef:setStatus(text)
  end
  return {
    app          = selfRef,
    getMode      = function() return selfRef.mode end,
    setMode      = function(m)
      selfRef.mode = (m == "edit") and "edit" or "tile"
      CursorsController.applyModeCursor(selfRef, selfRef.mode)
    end,

    getPainting  = function() return selfRef.isPainting end,
    setPainting  = function(v) selfRef.isPainting = not not v end,

    wm           = function() return selfRef.wm end,
    getFocus     = function() return selfRef.wm:getFocus() or selfRef.winBank end,
    setStatus    = function(s) return setAppStatus(s) end,
    getStatus    = function()
      return selfRef.lastEventText or selfRef.statusText
    end,
    showBankTileLabel = function(target)
      local bankWindow = selfRef.winBank
      local toolbar = bankWindow and bankWindow.specializedToolbar or nil
      local currentBank = (bankWindow and bankWindow.currentBank)
        or (selfRef.appEditState and selfRef.appEditState.currentBank)
      if type(currentBank) ~= "number" then return false end

      local tileRef = chooseBankTileRefForLabel(target, currentBank)
      if not (tileRef and type(tileRef.index) == "number") then
        return false
      end

      if toolbar and toolbar.showTileLabel then
        toolbar:showTileLabel(tileRef.index)
        return true
      end
      return false
    end,
    showBankTileLabelForWindowSelection = function(win)
      local target = firstSelectedTargetForWindow(win)
      if not target then return false end
      local bankWindow = selfRef.winBank
      local toolbar = bankWindow and bankWindow.specializedToolbar or nil
      local currentBank = (bankWindow and bankWindow.currentBank)
        or (selfRef.appEditState and selfRef.appEditState.currentBank)
      if type(currentBank) ~= "number" then return false end

      local tileRef = chooseBankTileRefForLabel(target, currentBank)
      if not (tileRef and type(tileRef.index) == "number") then
        return false
      end

      if toolbar and toolbar.showTileLabel then
        toolbar:showTileLabel(tileRef.index)
        return true
      end
      return false
    end,
    scaledMouse  = function() return ResolutionController:getScaledMouse(true) end,

    rebuildChrBankWindow = function(chrWin)
      if not WindowCaps.isChrLike(chrWin) then return end
      local app = selfRef.appEditState
      if not app.chrBanksBytes then return end
      
      -- Update app state's currentBank to match the CHR window
      app.currentBank = chrWin.currentBank or 1
      
      BankViewController.rebuildBankWindowItems(
        chrWin,
        app,
        chrWin.orderMode or "normal",
        function(txt) setAppStatus(txt) end
      )
    end,

    getBankInfo  = function()
      local app = selfRef.appEditState
      local focus = selfRef.wm:getFocus() or selfRef.winBank
      if WindowCaps.isChrLike(focus) then
        return app.chrBanksBytes, focus.currentBank or app.currentBank
      end
      return app.chrBanksBytes, app.currentBank
    end,

    getSyncDuplicates = function()
      return selfRef.syncDuplicateTiles
    end,

    setSyncDuplicates = function(enabled)
      selfRef.syncDuplicateTiles = not not enabled
      return selfRef.syncDuplicateTiles
    end,

    getSpaceHighlightActive = function()
      return selfRef.spaceHighlightActive == true
    end,

    getSpaceHighlightSourceWindow = function()
      return selfRef.spaceHighlightSourceWin
    end,

    setSpaceHighlightActive = function(enabled)
      selfRef.spaceHighlightActive = (enabled == true)
      if selfRef.spaceHighlightActive then
        local wm = selfRef.wm
        local focus = wm and wm.getFocus and wm:getFocus() or nil
        selfRef.spaceHighlightSourceWin = focus
      else
        selfRef.spaceHighlightSourceWin = nil
      end
      return selfRef.spaceHighlightActive
    end,

    toggleSpaceHighlightActive = function()
      selfRef.spaceHighlightActive = not (selfRef.spaceHighlightActive == true)
      if selfRef.spaceHighlightActive then
        local wm = selfRef.wm
        local focus = wm and wm.getFocus and wm:getFocus() or nil
        selfRef.spaceHighlightSourceWin = focus
      else
        selfRef.spaceHighlightSourceWin = nil
      end
      return selfRef.spaceHighlightActive
    end,

    setColor     = function(c)
      selfRef.currentColor = math.max(0, math.min(3, c))
    end,

    paintAt      = function(win, col, row, lx, ly, pickOnly)
      return selfRef:paintAt(win, col, row, lx, ly, pickOnly)
    end,

    showToast    = function(kind, text, opts)
      return selfRef:showToast(kind, text, opts)
    end,

    saveEdited   = function()
      return selfRef:saveEdited()
    end,

    isDraggingTile = function()
      return UserInput.isDraggingTile()
    end,
  }
end

------------------------------------------------------------
-- LOVE lifecycle
------------------------------------------------------------

local STANDARD_CANVAS_W = 640
local STANDARD_CANVAS_H = 360

local STANDARD_FONT_SIZE = 16
local STANDARD_EMPTY_FONT_SIZE = 16

local function resolveCanvasSize(app)
  if app and app.canvas and app.canvas.getWidth and app.canvas.getHeight then
    local w = tonumber(app.canvas:getWidth()) or STANDARD_CANVAS_W
    local h = tonumber(app.canvas:getHeight()) or STANDARD_CANVAS_H
    if w > 0 and h > 0 then
      return w, h
    end
  end
  return STANDARD_CANVAS_W, STANDARD_CANVAS_H
end

local function loadAppFont(size)
  local candidates = {
    "user_interface/fonts/AsepriteFont.ttf",
    "../user_interface/fonts/AsepriteFont.ttf",
    "user_interface/fonts/proggy-tiny.ttf",
    "../user_interface/fonts/proggy-tiny.ttf",
    "user_interface/fonts/proggy-clean-sz.ttf",
    "../user_interface/fonts/proggy-clean-sz.ttf",
    "user_interface/fonts/Tiny5-Regular.ttf",
  }

  for _, candidate in ipairs(candidates) do
    local ok, font = pcall(love.graphics.newFont, candidate, size)
    if ok and font then
      return font
    end
  end

  return love.graphics.newFont(size)
end

local function initGraphics(self, opts)
  opts = opts or {}
  local crtMode = (opts.crtMode == true)
  local previousResolutionMode = ResolutionController.mode
  local canvasW, canvasH = resolveCanvasSize(self)

  self.canvas = love.graphics.newCanvas(canvasW, canvasH)
  self.canvas:setFilter("nearest", "nearest")
  self.canvasFilterMode = self.canvasFilterMode or "sharp"
  self.crtModeEnabled = crtMode
  self.font = loadAppFont(STANDARD_FONT_SIZE)
  self.font:setFilter("nearest", "nearest")
  self.emptyStateFont = loadAppFont(STANDARD_EMPTY_FONT_SIZE)
  self.emptyStateFont:setFilter("nearest", "nearest")
  love.graphics.setFont(self.font)

  ResolutionController:init(self.canvas)
  if previousResolutionMode ~= nil then
    ResolutionController:setMode(previousResolutionMode)
  end
  if ResolutionController.setCanvasCrtShaderEnabled then
    ResolutionController:setCanvasCrtShaderEnabled(crtMode)
  end
  if ResolutionController.setCanvasCrtFlat then
    ResolutionController:setCanvasCrtFlat(rawget(_G, "__PPUX_CRT_FLAT__") == true)
  end
  if ResolutionController.setCanvasCrtDistortion then
    ResolutionController:setCanvasCrtDistortion(tonumber(rawget(_G, "__PPUX_CRT_DISTORTION__")) or 0.15)
  end
  -- ResolutionController:setMode(ResolutionController.PIXEL_PERFECT)

  love.graphics.setBackgroundColor(colors.gray10)
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(2)
end

local function drawEmptyStatePrompt(app)
  if app:hasLoadedROM() then return end

  -- Text.printCenter("Drop an NES ROM here", {
  --   canvas = app.canvas,
  --   font = app.emptyStateFont or app.font,
  --   shadowColor = colors.transparent,
  --   color = colors.gray20
  -- })
end

anyModalVisible = function(app)
  return (app.quitConfirmModal and app.quitConfirmModal:isVisible())
    or (app.saveOptionsModal and app.saveOptionsModal:isVisible())
    or (app.genericActionsModal and app.genericActionsModal:isVisible())
    or (app.settingsModal and app.settingsModal:isVisible())
    or (app.newWindowTypeModal and app.newWindowTypeModal:isVisible())
    or (app.newWindowModal and app.newWindowModal:isVisible())
    or (app.openProjectModal and app.openProjectModal:isVisible())
    or (app.renameWindowModal and app.renameWindowModal:isVisible())
    or (app.romPaletteAddressModal and app.romPaletteAddressModal:isVisible())
    or (app.ppuFrameSpriteLayerModeModal and app.ppuFrameSpriteLayerModeModal:isVisible())
    or (app.ppuFrameAddSpriteModal and app.ppuFrameAddSpriteModal:isVisible())
    or (app.ppuFrameRangeModal and app.ppuFrameRangeModal:isVisible())
    or (app.textFieldDemoModal and app.textFieldDemoModal:isVisible())
end

chooseBankTileRefForLabel = function(target, currentBank)
  if not target then return nil end

  local function matches(tileRef)
    return tileRef
      and type(tileRef._bankIndex) == "number"
      and type(tileRef.index) == "number"
      and tileRef._bankIndex == currentBank
  end

  if matches(target) then
    return target
  end
  if matches(target.topRef) then
    return target.topRef
  end
  if matches(target.botRef) then
    return target.botRef
  end
  return nil
end

firstSelectedTargetForWindow = function(win)
  if not (win and win.layers) then return nil end
  local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  local layer = win.layers[li]
  if not layer then return nil end

  if layer.kind == "sprite" then
    local idx = nil
    if type(layer.multiSpriteSelectionOrder) == "table" and type(layer.multiSpriteSelectionOrder[1]) == "number" then
      idx = layer.multiSpriteSelectionOrder[1]
    elseif type(layer.selectedSpriteIndex) == "number" then
      idx = layer.selectedSpriteIndex
    elseif type(layer.multiSpriteSelection) == "table" then
      for k, on in pairs(layer.multiSpriteSelection) do
        if on == true and (idx == nil or k < idx) then
          idx = k
        end
      end
    end
    return idx and layer.items and layer.items[idx] or nil
  end

  if layer.kind ~= "tile" then
    return nil
  end

  local sel = win.getLayerSelection and win:getLayerSelection(li) or nil
  if sel and sel.col and sel.row then
    if win.getVirtualTileHandle then
      local target = win:getVirtualTileHandle(sel.col, sel.row, li)
      if target ~= nil then
        return target
      end
    end
    if win.get then
      return win:get(sel.col, sel.row, li)
    end
  end

  local firstIdx = nil
  if type(layer.multiTileSelection) == "table" then
    for idx, on in pairs(layer.multiTileSelection) do
      if on == true and (firstIdx == nil or idx < firstIdx) then
        firstIdx = idx
      end
    end
  end
  if firstIdx then
    local zeroBased = firstIdx - 1
    local cols = win.cols or 1
    local col = zeroBased % cols
    local row = math.floor(zeroBased / cols)
    if win.getVirtualTileHandle then
      local target = win:getVirtualTileHandle(col, row, li)
      if target ~= nil then
        return target
      end
    end
    if win.get then
      return win:get(col, row, li)
    end
  end
  return firstIdx and layer.items and layer.items[firstIdx] or nil
end

function AppCoreController:load()
  local initialCrtMode = (rawget(_G, "__PPUX_ENABLE_CRT_SHADER__") == true)
  initGraphics(self, { crtMode = initialCrtMode })
  self.chrBankCanvasController = BankCanvasController.new()

  local settings = AppSettingsController.load()
  self.recentProjects = AppSettingsController.normalizeRecentProjects(settings and settings.recentProjects)
  if self._applyThemeSetting then
    self:_applyThemeSetting((settings and settings.theme) or "dark", false)
  end
  self:_applyCanvasImageModeSetting((settings and settings.canvasImageMode) or "pixel_perfect", false)
  if settings and settings.canvasFilter ~= nil then
    self:_applyCanvasFilterSetting(settings.canvasFilter, false)
  end
  self:_applyPaletteLinksSetting((settings and settings.paletteLinks) or "auto_hide", false)
  self:_applyTooltipsEnabledSetting((settings and settings.tooltipsEnabled) ~= false, false)
  self:_applySeparateToolbarSetting((settings and settings.separateToolbar) == true, false)
  self:_applyGroupedPaletteWindowsSetting(settings and settings.groupedPaletteWindows == true, false)
  ResolutionController:recalculate()
  local splashConfig = {}
  if settings then
    for k, v in pairs(settings) do splashConfig[k] = v end
  end
  splashConfig.buttonIcon = images.do_not_show_again
  splashConfig.saveFn = function()
    AppSettingsController.save({ skipSplash = true })
  end
  self.splash = Splash.new(splashConfig)

  -- Initialize debug manager
  local DebugController = require("controllers.dev.debug_controller")
  DebugController.init(false)
  -- DebugController.setCategoryFilter({"PERF", "LOAD_PERF"})

  local ctx = self:_buildCtx()
  ctx.app = self  -- Add app reference to context
  _G.ctx = ctx

  CursorsController.init(self)
  UserInput.setup(ctx, self)
  self.taskbar = Taskbar.new(self, { h = UiScale.taskbarHeight() })
  self.wm.taskbar = self.taskbar
  self.taskbar:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
  self.toastController = ToastController.new(self)
  self.toastController:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
end

function AppCoreController:setCrtModeEnabled(enabled)
  local target = (enabled == true)
  if self.crtModeEnabled == target then
    return self.crtModeEnabled
  end

  local imageModeKey = nil
  if self._getCanvasImageModeForSettings then
    imageModeKey = self:_getCanvasImageModeForSettings()
  end
  local filterKey = nil
  if self._getCanvasFilterForSettings then
    filterKey = self:_getCanvasFilterForSettings()
  end

  initGraphics(self, { crtMode = target })

  if imageModeKey and self._applyCanvasImageModeSetting then
    self:_applyCanvasImageModeSetting(imageModeKey, false)
  else
    ResolutionController:recalculate()
  end
  if filterKey and self._applyCanvasFilterSetting then
    self:_applyCanvasFilterSetting(filterKey, false)
  end

  if self.taskbar and self.canvas then
    self.taskbar:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
  end
  if self.toastController and self.canvas then
    self.toastController:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
  end
  if self.tooltipController then
    self.tooltipController.visible = false
  end

  CursorsController.applyModeCursor(self, self.mode)
  return self.crtModeEnabled
end

function AppCoreController:toggleCrtMode()
  local enabled = self:setCrtModeEnabled(not (self.crtModeEnabled == true))
  if self.setStatus then
    self:setStatus(enabled and "CRT mode enabled" or "CRT mode disabled")
  end
  return enabled
end

local function collectWindowSnapshot(app)
  if not (love and love.window and love.window.getMode) then return nil end
  local w, h, flags = love.window.getMode()
  local fullscreen = false
  if flags and flags.fullscreen ~= nil then
    fullscreen = (flags.fullscreen == true)
  elseif love.window.getFullscreen then
    fullscreen = (love.window.getFullscreen() == true)
  end
  local x, y = nil, nil
  if love.window.getPosition then
    x, y = love.window.getPosition()
  end
  return {
    w = tonumber(w) or 0,
    h = tonumber(h) or 0,
    x = tonumber(x),
    y = tonumber(y),
    fullscreen = fullscreen,
    resizable = (flags and flags.resizable == true) or false,
  }
end

local function windowSnapshotChanged(a, b)
  if (a == nil) ~= (b == nil) then return true end
  if not a and not b then return false end
  local keys = { "w", "h", "x", "y", "fullscreen", "resizable" }
  for _, k in ipairs(keys) do
    if a[k] ~= b[k] then
      return true
    end
  end
  return false
end

function AppCoreController:_persistWindowSnapshotIfNeeded(force)
  return nil
end

function AppCoreController:update(dt)
  Timer.update(dt)
  katsudo.update(dt)
  -- Update window manager (skip closed windows)
  for _, w in ipairs(self.wm:getWindows()) do
    if not w._closed and not w._minimized then
      w:update(dt)
      
      -- Update toolbar positions
      if w.headerToolbar then
        w.headerToolbar:updatePosition()
      end
    end
  end

  if self.taskbar and self.canvas then
    if self.taskbar.update then
      self.taskbar:update(dt)
    end
    self.taskbar:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
  end

  if self.toastController and self.canvas then
    self.toastController:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
    local toastDt = dt
    self.toastController:update(toastDt)
  end

  if self.tooltipController and self.canvas then
    local mouse = ResolutionController:getScaledMouse(true)
    local candidate = nil
    if mouse then
      candidate = self:getTooltipCandidateAt(mouse.x, mouse.y)
      self.tooltipController:update(dt, mouse.x, mouse.y, candidate)
    end
  end

  local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
  AppTopToolbarController.syncLayout(self)
end

------------------------------------------------------------
-- ROM / project load & project save (delegates)
------------------------------------------------------------

function AppCoreController:filedropped(file)
  RomProjectController.handleFileDropped(self, file)
end

end
