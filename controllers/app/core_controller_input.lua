local Shared = require("controllers.app.core_controller_shared")
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
  for _, key in ipairs(Shared.APP_CONTEXT_MENU_KEYS) do
    local menu = app[key]
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

local function dispatchModalMousePressed(app, mouse, b)
  if Shared.modalVisible(app.quitConfirmModal) then
    app.quitConfirmModal:mousepressed(mouse.x, mouse.y, b)
    refreshCursor(app)
    return true
  end
  if app.splash and app.splash:isVisible() then
    app.splash:mousepressed(mouse.x, mouse.y, b)
    refreshCursor(app)
    return true
  end
  for _, modalKey in ipairs(Shared.APP_MODAL_KEYS_IN_ORDER) do
    if modalKey ~= "quitConfirmModal" then
      local modal = app[modalKey]
      if Shared.modalVisible(modal) then
        modal:mousepressed(mouse.x, mouse.y, b)
        if Shared.MODAL_MOUSE_REFRESH_CURSOR_KEYS[modalKey] then
          refreshCursor(app)
        end
        return true
      end
    end
  end
  return false
end

local function dispatchModalMouseReleased(app, mouse, b)
  if Shared.modalVisible(app.quitConfirmModal) then
    app.quitConfirmModal:mousereleased(mouse.x, mouse.y, b)
    refreshCursor(app)
    return true
  end
  if app.splash and app.splash:isVisible() then
    app.splash:mousereleased(mouse.x, mouse.y, function()
      AppSettingsController.save({ skipSplash = true })
    end)
    refreshCursor(app)
    return true
  end
  for _, modalKey in ipairs(Shared.APP_MODAL_KEYS_IN_ORDER) do
    if modalKey ~= "quitConfirmModal" then
      local modal = app[modalKey]
      if Shared.modalVisible(modal) then
        modal:mousereleased(mouse.x, mouse.y, b)
        if Shared.MODAL_MOUSE_REFRESH_CURSOR_KEYS[modalKey] then
          refreshCursor(app)
        end
        return true
      end
    end
  end
  return false
end

local function dispatchModalMouseMovedAfterSplash(app, mouse)
  for _, modalKey in ipairs(Shared.APP_MODAL_KEYS_IN_ORDER) do
    if modalKey ~= "quitConfirmModal" then
      local modal = app[modalKey]
      if Shared.modalVisible(modal) then
        modal:mousemoved(mouse.x, mouse.y)
        return true
      end
      if modalKey == "settingsModal" then
        if handleAppContextMenuMouseMoved(app, mouse.x, mouse.y) then
          return true
        end
      end
    end
  end
  return false
end

--- Subset of modals that participate in textinput (same precedence order as before).
local TEXTINPUT_ROUTES = {
  { key = "newWindowTypeModal", consumeOnly = true },
  { key = "newWindowModal", method = "textinput" },
  { key = "renameWindowModal", method = "textinput" },
  { key = "romPaletteAddressModal", method = "textinput" },
  { key = "ppuFrameSpriteLayerModeModal", consumeOnly = true },
  { key = "ppuFrameAddSpriteModal", method = "textinput" },
  { key = "ppuFrameRangeModal", method = "textinput" },
  { key = "ppuFramePatternRangeModal", method = "textinput" },
  { key = "textFieldDemoModal", method = "textinput" },
}

local function handleAlwaysAvailableWindowShortcuts(app, key, keyRepeat)
  if keyRepeat then
    return false
  end
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

function AppCoreController:keypressed(k, scancode, isrepeat)
  local keyRepeat = isrepeat == true

  if k == "f1" then
    if not keyRepeat then
      self.showDebugInfo = not (self.showDebugInfo == true)
    end
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
  if not keyRepeat and KeyboardDebugController.handleDebugKeys(debugCtx, debugUtils, k) then
    return
  end

  if handleAlwaysAvailableWindowShortcuts(self, k, keyRepeat) then
    return
  end

  -- Handle dialog input (first visible modal in stack order)
  for _, modalKey in ipairs(Shared.APP_MODAL_KEYS_IN_ORDER) do
    local modal = self[modalKey]
    if Shared.modalVisible(modal) then
      modalHandleKey(modal, k)
      if Shared.MODAL_KEY_REFRESH_CURSOR_KEYS[modalKey] then
        refreshCursor(self)
      end
      return
    end
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
  if ctrlDown and k == "s" and not keyRepeat then
    self:showSaveOptionsModal()
    refreshCursor(self)
    return
  end
  
  -- Ctrl+N: New window dialog
  if ctrlDown and k == "n" and not keyRepeat then
    self:showNewWindowModal()
    refreshCursor(self)
    return
  end

  -- Ctrl+O: Open project (same as top toolbar Open button)
  if ctrlDown and k == "o" and not keyRepeat then
    if self.showOpenProjectModal then
      self:showOpenProjectModal()
    end
    refreshCursor(self)
    return
  end

  -- Pass appCore so input handlers can touch selection/etc later
  UserInput.keypressed(k, self, keyRepeat)
  refreshCursor(self)
end

function AppCoreController:keyreleased(k)
  if Shared.anyModalVisible(self)
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

  if dispatchModalMousePressed(self, mouse, b) then
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
  if b == 1 and self.wm and self.wm.clearFocusOnWorkspaceMiss then
    self.wm:clearFocusOnWorkspaceMiss(mouse.x, mouse.y)
  end
  refreshCursor(self)
end

function AppCoreController:mousereleased(x, y, b)
  local mouse = ResolutionController:getScaledMouse(true, x, y)
  refreshCursor(self)
  
  local DebugController = require("controllers.dev.debug_controller")
  DebugController.log("info", "INPUT", "AppCoreController:mousereleased - screen: (%d, %d), canvas: (%.1f, %.1f), button: %d", x, y, mouse.x, mouse.y, b)

  if dispatchModalMouseReleased(self, mouse, b) then
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

  if Shared.modalVisible(self.quitConfirmModal) then
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

  if dispatchModalMouseMovedAfterSplash(self, mouse) then
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
  refreshCursor(self)
end

function AppCoreController:wheelmoved(dx, dy)
  if Shared.modalVisible(self.quitConfirmModal) then
    return
  end
  if self.splash and self.splash:isVisible() then
    return
  end
  if Shared.anyModalVisible(self) then
    local ref = self.openReferencePngModal
    if Shared.modalVisible(ref) and ref.wheelmoved then
      return ref:wheelmoved(dx, dy)
    end
    local proj = self.openProjectModal
    if Shared.modalVisible(proj) and proj.wheelmoved then
      return proj:wheelmoved(dx, dy)
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
  for _, route in ipairs(TEXTINPUT_ROUTES) do
    local modal = self[route.key]
    if Shared.modalVisible(modal) then
      if route.consumeOnly then
        return
      end
      local method = route.method
      if method and modal[method] then
        modal[method](modal, text)
      end
      return
    end
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
