local SpriteController = require("controllers.sprite.sprite_controller")
local KeyboardDebugController = require("controllers.input.keyboard_debug_controller")
local KeyboardWindowShortcutsController = require("controllers.input.keyboard_window_shortcuts_controller")
local CursorsController = require("controllers.input_support.cursors_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local AppSettingsController = require("controllers.app.settings_controller")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
local UserInput = require("controllers.input")
local ChrCanvasOnlyMode = require("controllers.chr.chr_canvas_only_mode")

return function(AppCoreController)
------------------------------------------------------------
-- Input
------------------------------------------------------------

local function hasActiveWindowInteraction(app)
  if not app then return false end

  local wm = app.wm
  if wm and wm.getWindows then
    for _, w in ipairs(wm:getWindows() or {}) do
      if not w._closed and not w._minimized and (w.resizing or w.dragging) then
        return true
      end
    end
  end

  if SpriteController and SpriteController.isDragging and SpriteController.isDragging() then
    return true
  end

  if UserInput.isDraggingTile and UserInput.isDraggingTile() then
    return true
  end

  if app.isPainting then
    return true
  end

  if UserInput.getTilePaintState then
    local tilePaintState = UserInput.getTilePaintState()
    if tilePaintState and tilePaintState.active then
      return true
    end
  end

  return false
end

local function modalVisible(modal)
  return modal and modal.isVisible and modal:isVisible()
end

local function modalHandleKey(modal, key)
  if not modal then return end
  if modal.handleKey then
    modal:handleKey(key)
  end
end

local function refreshCursor(app)
  if app and CursorsController and CursorsController.applyModeCursor then
    CursorsController.applyModeCursor(app, app.mode)
  end
end

local function eachAppContextMenu(app, fn)
  if not app or not fn then return end
  local menus = {
    app.windowHeaderContextMenu,
    app.emptySpaceContextMenu,
    app.ppuTileContextMenu,
    app.paletteLinkContextMenu,
  }
  for _, menu in ipairs(menus) do
    if menu then
      fn(menu)
    end
  end
end

local function appContextMenusVisible(app)
  local visible = false
  eachAppContextMenu(app, function(menu)
    if menu.isVisible and menu:isVisible() then
      visible = true
    end
  end)
  return visible
end

local function handleAppContextMenuMousePressed(app, x, y, button)
  local consumed = false
  local clickedInside = false

  eachAppContextMenu(app, function(menu)
    if consumed or not (menu.isVisible and menu:isVisible()) then
      return
    end
    if menu:contains(x, y) then
      clickedInside = true
      consumed = menu:mousepressed(x, y, button) == true
    end
  end)

  if clickedInside then
    return consumed
  end

  if appContextMenusVisible(app) then
    app:hideAppContextMenus()
    if button == 1 then
      return true
    end
  end

  return false
end

local function handleAppContextMenuMouseReleased(app, x, y, button)
  local consumed = false
  eachAppContextMenu(app, function(menu)
    if consumed or not (menu.isVisible and menu:isVisible()) then
      return
    end
    if menu:contains(x, y) or menu:hasPressedButton() then
      consumed = menu:mousereleased(x, y, button) == true
    end
  end)
  return consumed
end

local function handleAppContextMenuMouseMoved(app, x, y)
  local visible = false
  eachAppContextMenu(app, function(menu)
    if menu.isVisible and menu:isVisible() then
      visible = true
      menu:mousemoved(x, y)
    end
  end)
  return visible
end

local function handleAlwaysAvailableWindowShortcuts(app, key)
  local ctx = app:_buildCtx()
  local utils = {
    ctrlDown = function()
      return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    end,
    shiftDown = function()
      return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    end,
    altDown = function()
      return love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")
    end,
  }

  if KeyboardWindowShortcutsController.handleWindowScaling(ctx, utils, key, app) then
    return true
  end
  if KeyboardWindowShortcutsController.handleFullscreen(ctx, utils, key) then
    return true
  end
  return false
end

function AppCoreController:keypressed(k)
  if k == "f1" then
    self.showDebugInfo = not (self.showDebugInfo == true)
    self:setStatus(self.showDebugInfo and "Debug info enabled" or "Debug info disabled")
    return
  end

  local debugCtx = self:_buildCtx()
  local debugUtils = {
    ctrlDown = function()
      return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    end,
    shiftDown = function()
      return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    end,
  }
  if KeyboardDebugController.handleDebugKeys(debugCtx, debugUtils, k) then
    return
  end

  if handleAlwaysAvailableWindowShortcuts(self, k) then
    return
  end

  -- Handle dialog input
  if modalVisible(self.quitConfirmModal) then
    modalHandleKey(self.quitConfirmModal, k)
    refreshCursor(self)
    return
  end
  if modalVisible(self.saveOptionsModal) then
    modalHandleKey(self.saveOptionsModal, k)
    refreshCursor(self)
    return
  end
  if modalVisible(self.genericActionsModal) then
    modalHandleKey(self.genericActionsModal, k)
    return
  end
  if modalVisible(self.settingsModal) then
    modalHandleKey(self.settingsModal, k)
    return
  end
  if modalVisible(self.newWindowTypeModal) then
    modalHandleKey(self.newWindowTypeModal, k)
    return
  end
  if modalVisible(self.newWindowModal) then
    modalHandleKey(self.newWindowModal, k)
    return
  end
  if modalVisible(self.openProjectModal) then
    modalHandleKey(self.openProjectModal, k)
    return
  end
  if modalVisible(self.renameWindowModal) then
    modalHandleKey(self.renameWindowModal, k)
    return
  end
  if modalVisible(self.romPaletteAddressModal) then
    modalHandleKey(self.romPaletteAddressModal, k)
    return
  end
  if modalVisible(self.ppuFrameSpriteLayerModeModal) then
    modalHandleKey(self.ppuFrameSpriteLayerModeModal, k)
    return
  end
  if modalVisible(self.ppuFrameAddSpriteModal) then
    modalHandleKey(self.ppuFrameAddSpriteModal, k)
    return
  end
  if modalVisible(self.ppuFrameRangeModal) then
    modalHandleKey(self.ppuFrameRangeModal, k)
    return
  end
  if modalVisible(self.ppuFramePatternRangeModal) then
    modalHandleKey(self.ppuFramePatternRangeModal, k)
    return
  end
  if modalVisible(self.textFieldDemoModal) then
    modalHandleKey(self.textFieldDemoModal, k)
    return
  end
  if self.splash and self.splash.isVisible and self.splash:isVisible() then
    if self.splash.keypressed then
      self.splash:keypressed(k)
    end
    return
  end

  if ChrCanvasOnlyMode.isActive(self) and k == "escape" then
    self:clearChrCanvasOnlyMode()
    refreshCursor(self)
    return
  end

  -- Check for Ctrl key combinations
  local ctrlDown = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
  
  -- Ctrl+S: Save dialog (project, ROM, or both)
  if ctrlDown and k == "s" then
    self:showSaveOptionsModal()
    refreshCursor(self)
    return
  end
  
  -- Ctrl+N: New window dialog
  if ctrlDown and k == "n" then
    self:showNewWindowModal()
    refreshCursor(self)
    return
  end

  -- Ctrl+O: Open project (same as top toolbar Open button)
  if ctrlDown and k == "o" then
    if self.showOpenProjectModal then
      self:showOpenProjectModal()
    end
    refreshCursor(self)
    return
  end

  -- Pass appCore so input handlers can touch selection/etc later
  UserInput.keypressed(k, self)
  refreshCursor(self)
end

function AppCoreController:keyreleased(k)
  if modalVisible(self.quitConfirmModal)
      or modalVisible(self.saveOptionsModal)
      or modalVisible(self.genericActionsModal)
      or modalVisible(self.settingsModal)
      or modalVisible(self.newWindowTypeModal)
      or modalVisible(self.newWindowModal)
      or modalVisible(self.openProjectModal)
      or modalVisible(self.renameWindowModal)
      or modalVisible(self.romPaletteAddressModal)
      or modalVisible(self.ppuFrameSpriteLayerModeModal)
      or modalVisible(self.ppuFrameAddSpriteModal)
      or modalVisible(self.ppuFrameRangeModal)
      or modalVisible(self.ppuFramePatternRangeModal)
      or modalVisible(self.textFieldDemoModal)
      or (self.splash and self.splash.isVisible and self.splash:isVisible()) then
    refreshCursor(self)
    return
  end
  UserInput.keyreleased(k, self)
  refreshCursor(self)
end

function AppCoreController:mousepressed(x, y, b)
  local DebugController = require("controllers.dev.debug_controller")
  local mouse = ResolutionController:getScaledMouse(true, x, y)
  refreshCursor(self)
  
  DebugController.log("info", "INPUT", "AppCoreController:mousepressed - screen: (%d, %d), canvas: (%.1f, %.1f), button: %d", x, y, mouse.x, mouse.y, b)

  if self.quitConfirmModal:isVisible() then
    self.quitConfirmModal:mousepressed(mouse.x, mouse.y, b)
    refreshCursor(self)
    return
  end

  -- Splash consumes initial click
  if self.splash and self.splash:isVisible() then
    self.splash:mousepressed(mouse.x, mouse.y, b)
    refreshCursor(self)
    return
  end

  if self.saveOptionsModal and self.saveOptionsModal:isVisible() then
    self.saveOptionsModal:mousepressed(mouse.x, mouse.y, b)
    refreshCursor(self)
    return
  end

  if self.genericActionsModal:isVisible() then
    self.genericActionsModal:mousepressed(mouse.x, mouse.y, b)
    refreshCursor(self)
    return
  end

  if self.settingsModal and self.settingsModal:isVisible() then
    self.settingsModal:mousepressed(mouse.x, mouse.y, b)
    return
  end

  if self.newWindowTypeModal and self.newWindowTypeModal:isVisible() then
    self.newWindowTypeModal:mousepressed(mouse.x, mouse.y, b)
    return
  end
  if self.newWindowModal:isVisible() then
    self.newWindowModal:mousepressed(mouse.x, mouse.y, b)
    return
  end
  if self.openProjectModal and self.openProjectModal:isVisible() then
    self.openProjectModal:mousepressed(mouse.x, mouse.y, b)
    return
  end
  if self.renameWindowModal and self.renameWindowModal:isVisible() then
    self.renameWindowModal:mousepressed(mouse.x, mouse.y, b)
    return
  end
  if self.romPaletteAddressModal and self.romPaletteAddressModal:isVisible() then
    self.romPaletteAddressModal:mousepressed(mouse.x, mouse.y, b)
    return
  end
  if self.ppuFrameSpriteLayerModeModal and self.ppuFrameSpriteLayerModeModal:isVisible() then
    self.ppuFrameSpriteLayerModeModal:mousepressed(mouse.x, mouse.y, b)
    return
  end
  if self.ppuFrameAddSpriteModal and self.ppuFrameAddSpriteModal:isVisible() then
    self.ppuFrameAddSpriteModal:mousepressed(mouse.x, mouse.y, b)
    return
  end
  if self.ppuFrameRangeModal and self.ppuFrameRangeModal:isVisible() then
    self.ppuFrameRangeModal:mousepressed(mouse.x, mouse.y, b)
    return
  end
  if self.ppuFramePatternRangeModal and self.ppuFramePatternRangeModal:isVisible() then
    self.ppuFramePatternRangeModal:mousepressed(mouse.x, mouse.y, b)
    return
  end
  if self.textFieldDemoModal and self.textFieldDemoModal:isVisible() then
    self.textFieldDemoModal:mousepressed(mouse.x, mouse.y, b)
    return
  end

  if self.toastController and self.toastController:mousepressed(mouse.x, mouse.y, b) then
    return
  end

  if handleAppContextMenuMousePressed(self, mouse.x, mouse.y, b) then
    return
  end

  if ChrCanvasOnlyMode.isActive(self) then
    ChrCanvasOnlyMode.handleMousePressed(self, mouse.x, mouse.y, b, self.wm)
    refreshCursor(self)
    return
  end

  if AppTopToolbarController.mousepressed(self, mouse.x, mouse.y, b) then
    refreshCursor(self)
    return
  end

  local activeInteraction = hasActiveWindowInteraction(self)
  if b == 1 and self.taskbar and self.taskbar:contains(mouse.x, mouse.y) then
    self:hideAppContextMenus()
  end
  if (not activeInteraction) and self.taskbar and self.taskbar:mousepressed(mouse.x, mouse.y, b) then
    return
  end

  UserInput.mousepressed(mouse.x, mouse.y, b)
  refreshCursor(self)
end

function AppCoreController:mousereleased(x, y, b)
  local mouse = ResolutionController:getScaledMouse(true, x, y)
  refreshCursor(self)
  
  local DebugController = require("controllers.dev.debug_controller")
  DebugController.log("info", "INPUT", "AppCoreController:mousereleased - screen: (%d, %d), canvas: (%.1f, %.1f), button: %d", x, y, mouse.x, mouse.y, b)

  if self.quitConfirmModal:isVisible() then
    self.quitConfirmModal:mousereleased(mouse.x, mouse.y, b)
    refreshCursor(self)
    return
  end

  if self.splash and self.splash:isVisible() then
    self.splash:mousereleased(mouse.x, mouse.y, function()
      AppSettingsController.save({ skipSplash = true })
    end)
    refreshCursor(self)
    return
  end

  if self.saveOptionsModal and self.saveOptionsModal:isVisible() then
    self.saveOptionsModal:mousereleased(mouse.x, mouse.y, b)
    refreshCursor(self)
    return
  end

  if self.genericActionsModal:isVisible() then
    self.genericActionsModal:mousereleased(mouse.x, mouse.y, b)
    refreshCursor(self)
    return
  end

  if self.settingsModal and self.settingsModal:isVisible() then
    self.settingsModal:mousereleased(mouse.x, mouse.y, b)
    return
  end

  if self.newWindowTypeModal and self.newWindowTypeModal:isVisible() then
    self.newWindowTypeModal:mousereleased(mouse.x, mouse.y, b)
    return
  end
  if self.newWindowModal:isVisible() then
    self.newWindowModal:mousereleased(mouse.x, mouse.y, b)
    return
  end
  if self.openProjectModal and self.openProjectModal:isVisible() then
    self.openProjectModal:mousereleased(mouse.x, mouse.y, b)
    return
  end
  if self.renameWindowModal and self.renameWindowModal:isVisible() then
    self.renameWindowModal:mousereleased(mouse.x, mouse.y, b)
    return
  end
  if self.romPaletteAddressModal and self.romPaletteAddressModal:isVisible() then
    self.romPaletteAddressModal:mousereleased(mouse.x, mouse.y, b)
    return
  end
  if self.ppuFrameSpriteLayerModeModal and self.ppuFrameSpriteLayerModeModal:isVisible() then
    self.ppuFrameSpriteLayerModeModal:mousereleased(mouse.x, mouse.y, b)
    return
  end
  if self.ppuFrameAddSpriteModal and self.ppuFrameAddSpriteModal:isVisible() then
    self.ppuFrameAddSpriteModal:mousereleased(mouse.x, mouse.y, b)
    return
  end
  if self.ppuFrameRangeModal and self.ppuFrameRangeModal:isVisible() then
    self.ppuFrameRangeModal:mousereleased(mouse.x, mouse.y, b)
    return
  end
  if self.ppuFramePatternRangeModal and self.ppuFramePatternRangeModal:isVisible() then
    self.ppuFramePatternRangeModal:mousereleased(mouse.x, mouse.y, b)
    return
  end
  if self.textFieldDemoModal and self.textFieldDemoModal:isVisible() then
    self.textFieldDemoModal:mousereleased(mouse.x, mouse.y, b)
    return
  end

  if self.toastController and self.toastController:mousereleased(mouse.x, mouse.y, b) then
    return
  end

  if handleAppContextMenuMouseReleased(self, mouse.x, mouse.y, b) then
    return
  end

  if ChrCanvasOnlyMode.isActive(self) then
    ChrCanvasOnlyMode.handleMouseReleased(self, mouse.x, mouse.y, b, self.wm)
    refreshCursor(self)
    return
  end

  if AppTopToolbarController.mousereleasedQuickButtons(self, mouse.x, mouse.y, b) then
    refreshCursor(self)
    return
  end

  local activeInteraction = hasActiveWindowInteraction(self)
  -- Always finalize input interactions first so resize/drag end is never skipped.
  UserInput.mousereleased(mouse.x, mouse.y, b)
  AppTopToolbarController.mousereleasedDockedToolbar(self, mouse.x, mouse.y, b)

  if (not activeInteraction) and self.taskbar and self.taskbar:mousereleased(mouse.x, mouse.y, b) then
    refreshCursor(self)
    return
  end
  refreshCursor(self)
end

function AppCoreController:mousemoved(x, y, dx, dy)
  local mouse = ResolutionController:getScaledMouse(true, x, y)
  dx = dx or 0
  dy = dy or 0
  refreshCursor(self)

  if self.quitConfirmModal:isVisible() then
    self.quitConfirmModal:mousemoved(mouse.x, mouse.y)
    return
  end

  if self.splash and self.splash:isVisible() then
    local bx, by = nil, nil
    if self.splash.button then
      local sw, sh = self.canvas:getWidth(), self.canvas:getHeight()
      bx, by = (function()
        local iw, ih = self.splash.image:getWidth(), self.splash.image:getHeight()
        local sx = (sw - iw) / 2
        local sy = (sh - ih) / 2
        return sx + 8, sy + ih - self.splash.button.h - 8
      end)()
      self.splash.button.hovered = self.splash.button:contains(mouse.x, mouse.y)
    end
    return
  end

  if self.saveOptionsModal and self.saveOptionsModal:isVisible() then
    self.saveOptionsModal:mousemoved(mouse.x, mouse.y)
    return
  end

  if self.genericActionsModal:isVisible() then
    self.genericActionsModal:mousemoved(mouse.x, mouse.y)
    return
  end

  if self.settingsModal and self.settingsModal:isVisible() then
    self.settingsModal:mousemoved(mouse.x, mouse.y)
    return
  end

  if handleAppContextMenuMouseMoved(self, mouse.x, mouse.y) then
    return
  end

  if self.newWindowTypeModal and self.newWindowTypeModal:isVisible() then
    self.newWindowTypeModal:mousemoved(mouse.x, mouse.y)
    return
  end
  if self.newWindowModal:isVisible() then
    self.newWindowModal:mousemoved(mouse.x, mouse.y)
    return
  end
  if self.openProjectModal and self.openProjectModal:isVisible() then
    self.openProjectModal:mousemoved(mouse.x, mouse.y)
    return
  end
  if self.renameWindowModal and self.renameWindowModal:isVisible() then
    self.renameWindowModal:mousemoved(mouse.x, mouse.y)
    return
  end
  if self.romPaletteAddressModal and self.romPaletteAddressModal:isVisible() then
    self.romPaletteAddressModal:mousemoved(mouse.x, mouse.y)
    return
  end
  if self.ppuFrameSpriteLayerModeModal and self.ppuFrameSpriteLayerModeModal:isVisible() then
    self.ppuFrameSpriteLayerModeModal:mousemoved(mouse.x, mouse.y)
    return
  end
  if self.ppuFrameAddSpriteModal and self.ppuFrameAddSpriteModal:isVisible() then
    self.ppuFrameAddSpriteModal:mousemoved(mouse.x, mouse.y)
    return
  end
  if self.ppuFrameRangeModal and self.ppuFrameRangeModal:isVisible() then
    self.ppuFrameRangeModal:mousemoved(mouse.x, mouse.y)
    return
  end
  if self.ppuFramePatternRangeModal and self.ppuFramePatternRangeModal:isVisible() then
    self.ppuFramePatternRangeModal:mousemoved(mouse.x, mouse.y)
    return
  end
  if self.textFieldDemoModal and self.textFieldDemoModal:isVisible() then
    self.textFieldDemoModal:mousemoved(mouse.x, mouse.y)
    return
  end

  if ChrCanvasOnlyMode.isActive(self) then
    ChrCanvasOnlyMode.handleMouseMoved(
      self,
      mouse.x,
      mouse.y,
      dx / ResolutionController.canvasScaleX,
      dy / ResolutionController.canvasScaleY,
      self.wm
    )
    return
  end

  if self.toastController then
    self.toastController:mousemoved(mouse.x, mouse.y)
  end

  if self.taskbar and not hasActiveWindowInteraction(self) then
    self.taskbar:mousemoved(mouse.x, mouse.y)
  end

  AppTopToolbarController.mousemoved(self, mouse.x, mouse.y)

  UserInput.mousemoved(
    mouse.x,
    mouse.y,
    dx / ResolutionController.canvasScaleX,
    dy / ResolutionController.canvasScaleY
  )
end

function AppCoreController:wheelmoved(dx, dy)
  if self.quitConfirmModal:isVisible() then
    return
  end
  if self.splash and self.splash:isVisible() then
    return
  end
  if (self.saveOptionsModal and self.saveOptionsModal:isVisible())
      or self.genericActionsModal:isVisible()
      or (self.settingsModal and self.settingsModal:isVisible())
      or (self.newWindowTypeModal and self.newWindowTypeModal:isVisible())
      or self.newWindowModal:isVisible()
      or (self.openProjectModal and self.openProjectModal:isVisible())
      or (self.renameWindowModal and self.renameWindowModal:isVisible())
      or (self.romPaletteAddressModal and self.romPaletteAddressModal:isVisible())
      or (self.ppuFrameSpriteLayerModeModal and self.ppuFrameSpriteLayerModeModal:isVisible())
      or (self.ppuFrameAddSpriteModal and self.ppuFrameAddSpriteModal:isVisible())
      or (self.ppuFrameRangeModal and self.ppuFrameRangeModal:isVisible())
      or (self.ppuFramePatternRangeModal and self.ppuFramePatternRangeModal:isVisible())
      or (self.textFieldDemoModal and self.textFieldDemoModal:isVisible()) then
    if self.openProjectModal and self.openProjectModal:isVisible() and self.openProjectModal.wheelmoved then
      return self.openProjectModal:wheelmoved(dx, dy)
    end
    return
  end
  if ChrCanvasOnlyMode.isActive(self) then
    local mouse = ResolutionController:getScaledMouse(true)
    ChrCanvasOnlyMode.handleWheel(self, dx, dy, mouse.x, mouse.y)
    return
  end
  if self.taskbar and self.taskbar.wheelmoved and self.taskbar:wheelmoved(dx, dy) then
    return
  end
  UserInput.wheelmoved(dx, dy)
end

function AppCoreController:textinput(text)
  if self.newWindowTypeModal and self.newWindowTypeModal:isVisible() then
    return
  end
  if self.newWindowModal and self.newWindowModal:isVisible() then
    self.newWindowModal:textinput(text)
    return
  end
  if self.renameWindowModal and self.renameWindowModal:isVisible() then
    self.renameWindowModal:textinput(text)
    return
  end
  if self.romPaletteAddressModal and self.romPaletteAddressModal:isVisible() then
    self.romPaletteAddressModal:textinput(text)
    return
  end
  if self.ppuFrameSpriteLayerModeModal and self.ppuFrameSpriteLayerModeModal:isVisible() then
    return
  end
  if self.ppuFrameAddSpriteModal and self.ppuFrameAddSpriteModal:isVisible() then
    self.ppuFrameAddSpriteModal:textinput(text)
    return
  end
  if self.ppuFrameRangeModal and self.ppuFrameRangeModal:isVisible() then
    self.ppuFrameRangeModal:textinput(text)
    return
  end
  if self.ppuFramePatternRangeModal and self.ppuFramePatternRangeModal:isVisible() then
    self.ppuFramePatternRangeModal:textinput(text)
    return
  end
  if self.textFieldDemoModal and self.textFieldDemoModal:isVisible() then
    self.textFieldDemoModal:textinput(text)
    return
  end
end

------------------------------------------------------------

local function resolveClipboardActionFocus(app, ctx)
  if ctx and type(ctx.getFocus) == "function" then
    return ctx.getFocus()
  end
  if app and app.wm and app.wm.getFocus then
    return app.wm:getFocus() or app.winBank
  end
  return app and app.winBank or nil
end

function AppCoreController:getClipboardToolbarActionState(action)
  local ctx = _G.ctx or self:_buildCtx()
  local focus = resolveClipboardActionFocus(self, ctx)
  return KeyboardClipboardController.getActionAvailability(ctx, focus, action)
end

function AppCoreController:performClipboardToolbarAction(action, targetWin, targetLayerIndex, opts)
  local ctx = _G.ctx or self:_buildCtx()
  local focus = targetWin or resolveClipboardActionFocus(self, ctx)
  local actionOpts = opts or {}
  if type(targetLayerIndex) == "number" then
    actionOpts.layerIndex = targetLayerIndex
    if focus then
      if focus.setActiveLayerIndex then
        focus:setActiveLayerIndex(targetLayerIndex)
      else
        focus.activeLayer = targetLayerIndex
      end
    end
  end
  if targetWin and self.wm and self.wm.setFocus then
    self.wm:setFocus(targetWin)
  end
  return KeyboardClipboardController.performClipboardAction(ctx, focus, action, actionOpts)
end

------------------------------------------------------------

end
