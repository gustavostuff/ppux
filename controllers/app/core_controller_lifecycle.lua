local ResolutionController = require("controllers.app.resolution_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local BankCanvasController = require("controllers.chr.bank_canvas_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local AppSettingsController = require("controllers.app.settings_controller")
local CursorsController = require("controllers.input_support.cursors_controller")
local Taskbar = require("user_interface.taskbar")
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
  return {
    getMode      = function() return selfRef.mode end,
    setMode      = function(m)
      selfRef.mode = (m == "edit") and "edit" or "tile"
      CursorsController.applyModeCursor(selfRef, selfRef.mode)
    end,

    getPainting  = function() return selfRef.isPainting end,
    setPainting  = function(v) selfRef.isPainting = not not v end,

    wm           = function() return selfRef.wm end,
    getFocus     = function() return selfRef.wm:getFocus() or selfRef.winBank end,
    setStatus    = function(s) selfRef:setStatus(s) end,
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
        function(txt) selfRef:setStatus(txt) end
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

    setSpaceHighlightActive = function(enabled)
      selfRef.spaceHighlightActive = (enabled == true)
      return selfRef.spaceHighlightActive
    end,

    toggleSpaceHighlightActive = function()
      selfRef.spaceHighlightActive = not (selfRef.spaceHighlightActive == true)
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

local function initGraphics(self)
  self.canvas = love.graphics.newCanvas(640, 360)
  -- self.canvas = love.graphics.newCanvas(320, 180)
  self.canvas:setFilter("nearest", "nearest")
  self.canvasFilterMode = "sharp"
  ResolutionController:init(self.canvas)
  -- ResolutionController:setMode(ResolutionController.PIXEL_PERFECT)

  local function loadAppFont(size)
    local candidates = {
      "user_interface/fonts/proggy-tiny.ttf",
      "../user_interface/fonts/proggy-tiny.ttf",
    }

    for _, path in ipairs(candidates) do
      local ok, font = pcall(love.graphics.newFont, path, size)
      if ok and font then
        return font
      end
    end

    return love.graphics.newFont(size)
  end

  self.font = loadAppFont(16)
  self.font:setFilter("nearest", "nearest")
  self.emptyStateFont = loadAppFont(32)
  self.emptyStateFont:setFilter("nearest", "nearest")
  love.graphics.setFont(self.font)

  love.graphics.setBackgroundColor(0.10, 0.11, 0.12)
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(2)
end

local function drawEmptyStatePrompt(app)
  if app:hasLoadedROM() then return end

  Text.printCenter("Drop an NES ROM here", {
    canvas = app.canvas,
    font = app.emptyStateFont or app.font,
    shadowColor = colors.transparent,
    color = colors.gray20
  })
end

anyModalVisible = function(app)
  return (app.quitConfirmModal and app.quitConfirmModal:isVisible())
    or (app.saveOptionsModal and app.saveOptionsModal:isVisible())
    or (app.genericActionsModal and app.genericActionsModal:isVisible())
    or (app.settingsModal and app.settingsModal:isVisible())
    or (app.newWindowModal and app.newWindowModal:isVisible())
    or (app.renameWindowModal and app.renameWindowModal:isVisible())
    or (app.romPaletteAddressModal and app.romPaletteAddressModal:isVisible())
end

local function updateModalCursorLock(app)
  if not (love and love.mouse and love.mouse.setCursor) then return end

  local modalOpen = anyModalVisible(app)
  if modalOpen then
    if not app._modalCursorLockActive then
      app._modalCursorRestore = app.activeHardwareCursor
      app._modalCursorLockActive = true
    end

    local arrowCursor = app.hardwareCursors and app.hardwareCursors.arrow or nil
    if app.activeHardwareCursor ~= arrowCursor then
      if arrowCursor then
        love.mouse.setCursor(arrowCursor)
      else
        love.mouse.setCursor()
      end
      app.activeHardwareCursor = arrowCursor
    end
    return
  end

  if app._modalCursorLockActive then
    local restore = app._modalCursorRestore
    app._modalCursorLockActive = false
    app._modalCursorRestore = nil

    if restore ~= nil then
      love.mouse.setCursor(restore)
      app.activeHardwareCursor = restore
    else
      CursorsController.applyModeCursor(app, app.mode)
    end
  end
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
  initGraphics(self)
  self.chrBankCanvasController = BankCanvasController.new()

  local settings = AppSettingsController.load()
  self.recentProjects = AppSettingsController.normalizeRecentProjects(settings and settings.recentProjects)
  self:_applyCanvasImageModeSetting((settings and settings.canvasImageMode) or "pixel_perfect", false)
  if settings and settings.canvasFilter ~= nil then
    self:_applyCanvasFilterSetting(settings.canvasFilter, false)
  end
  self:_applyTooltipsEnabledSetting((settings and settings.tooltipsEnabled) ~= false, false)
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
  DebugController.init(true)
  DebugController.setCategoryFilter({"PERF", "LOAD_PERF"})

  local ctx = self:_buildCtx()
  ctx.app = self  -- Add app reference to context
  _G.ctx = ctx

  CursorsController.init(self)
  UserInput.setup(ctx, self)
  self.taskbar = Taskbar.new(self, { h = 15 })
  self.wm.taskbar = self.taskbar
  self.taskbar:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
  self.toastController = ToastController.new(self)
  self.toastController:updateLayout(self.canvas:getWidth(), self.canvas:getHeight())
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
  CursorsController.update(self)
  updateModalCursorLock(self)
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
end

------------------------------------------------------------
-- ROM / project load & project save (delegates)
------------------------------------------------------------

function AppCoreController:filedropped(file)
  RomProjectController.handleFileDropped(self, file)
end

end
