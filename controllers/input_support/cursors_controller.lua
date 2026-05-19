local CursorsController = {}
local ResolutionController = require("controllers.app.resolution_controller")
local Shared = require("controllers.app.core_controller_shared")
local WindowCaps = require("controllers.window.window_capabilities")
local AppTopToolbar = require("controllers.app.app_top_toolbar_controller")
local MouseWindowChrome = require("controllers.input.mouse_window_chrome_controller")

--- Specialized toolbars are laid out above the header (`ToolbarBase:updatePosition`), which is outside
--- `Window:contains` (that rect starts at the header top). Use the same surface hit-test as chrome input.
local function topSurfaceWindowAt(wm, mx, my)
  if not wm then
    return nil
  end
  if type(wm.getTopInteractiveSurfaceWindowAt) == "function" then
    return wm:getTopInteractiveSurfaceWindowAt(mx, my)
  end
  return MouseWindowChrome.getTopInteractiveSurfaceWindowAt(mx, my, wm)
end

local CURSOR_ROOT = "img/cursors"
local DEFAULT_CURSOR_SET = "2x"
local IGNORED_CURSOR_SETS = { bkp = true }

local CURSOR_FILES_BY_SET = {
  ["2x"] = {
    arrow = "cursor_arrow_0_0.png",
    hand = "cursor_hand_8_1.png",
    pencil = "cursor_pencil_6_6.png",
    fill = "cursor_fill_2_21.png",
    pick = "cursor_pick_2_27.png",
    rect_fill = "cursor_rect_14_14.png",
    unavailable = "cursor_unavailable_14_14.png",
    resize = "cursor_resize_14_14.png",
  },
  ["1x"] = {
    arrow = "cursor_arrow_0_0.png",
    hand = "cursor_hand_4_0.png",
    pencil = "cursor_pencil_3_3.png",
    fill = "cursor_fill_1_10.png",
    pick = "cursor_pick_1_13.png",
    rect_fill = "cursor_rect_7_7.png",
    unavailable = "cursor_unavailable_7_7.png",
    resize = "cursor_resize_7_7.png",
  },
}

local function cursorFilesForSet(setName)
  return CURSOR_FILES_BY_SET[setName] or CURSOR_FILES_BY_SET[DEFAULT_CURSOR_SET]
end

local function cursorPathForName(name, setName)
  local fileName = cursorFilesForSet(setName)[name]
  if not fileName then return nil end
  return string.format("%s/%s/%s", CURSOR_ROOT, setName, fileName)
end

local function desiredCursorSetName()
  if ResolutionController and ResolutionController.isCanvasCrtShaderEnabled then
    local ok, on = pcall(function()
      return ResolutionController:isCanvasCrtShaderEnabled()
    end)
    if ok and on == true then
      return "1x"
    end
  end
  return DEFAULT_CURSOR_SET
end

local function parseHotspot(path)
  local hx, hy = tostring(path or ""):match("_(%d+)_(%d+)%.png$")
  return tonumber(hx) or 0, tonumber(hy) or 0
end

local function loadCursorFromPath(path)
  if not (love and love.image and love.mouse and love.image.newImageData and love.mouse.newCursor) then
    return nil
  end

  local okData, imageData = pcall(love.image.newImageData, path)
  if not okData or not imageData then
    return nil
  end

  local hotX, hotY = parseHotspot(path)
  local okCursor, cursor = pcall(love.mouse.newCursor, imageData, hotX, hotY)
  if not okCursor then
    return nil
  end

  return cursor
end

local function resolveCursorSetName(requested)
  local setName = requested or DEFAULT_CURSOR_SET
  if IGNORED_CURSOR_SETS[setName] then
    return DEFAULT_CURSOR_SET
  end

  if love and love.filesystem and love.filesystem.getInfo then
    local info = love.filesystem.getInfo(CURSOR_ROOT .. "/" .. setName, "directory")
    if info then
      return setName
    end
  end

  return DEFAULT_CURSOR_SET
end

local function loadNamedCursor(name, setName)
  local path = cursorPathForName(name, setName)
  if not path then return nil end
  return loadCursorFromPath(path)
end

local function ensureNamedCursorLoaded(app, name)
  if not app then return nil end
  app.hardwareCursors = app.hardwareCursors or {}
  if app.hardwareCursors[name] then
    return app.hardwareCursors[name]
  end

  local cursorSet = resolveCursorSetName(app.cursorSetName)
  app.cursorSetName = cursorSet
  local cursor = loadNamedCursor(name, cursorSet)
  if cursor then
    app.hardwareCursors[name] = cursor
  end
  return cursor
end

local function loadSoftwareCursorFromPath(path)
  if not (love and love.graphics and love.graphics.newImage) then
    return nil, 0, 0
  end

  local okImage, image = pcall(love.graphics.newImage, path)
  if not okImage or not image then
    return nil, 0, 0
  end

  image:setFilter("nearest", "nearest")
  local hotX, hotY = parseHotspot(path)
  return image, hotX, hotY
end

local function ensureNamedSoftwareCursorLoaded(app, name)
  if not app then return nil end
  app.softwareCursors = app.softwareCursors or {}
  if app.softwareCursors[name] then
    return app.softwareCursors[name]
  end

  local cursorSet = resolveCursorSetName(app.cursorSetName)
  app.cursorSetName = cursorSet
  local path = cursorPathForName(name, cursorSet)
  if not path then return nil end

  local image, hotX, hotY = loadSoftwareCursorFromPath(path)
  if not image then
    return nil
  end

  local entry = {
    image = image,
    hotX = hotX or 0,
    hotY = hotY or 0,
  }
  app.softwareCursors[name] = entry
  return entry
end

local function getMouseCanvasPosition(asInteger)
  local useInteger = (asInteger ~= false)
  if ResolutionController and ResolutionController.getScaledMouse then
    local ok, mouse = pcall(function()
      return ResolutionController:getScaledMouse(useInteger)
    end)
    if ok and mouse and type(mouse.x) == "number" and type(mouse.y) == "number" then
      return mouse.x, mouse.y
    end
  end

  if love and love.mouse and love.mouse.getPosition then
    local x, y = love.mouse.getPosition()
    if type(x) == "number" and type(y) == "number" then
      return x, y
    end
  end

  return nil, nil
end

local function shouldUseSoftwareCursor(app)
  if not app then
    return false
  end
  if not (ResolutionController and ResolutionController.isCanvasCrtShaderEnabled) then
    return false
  end
  local ok, enabled = pcall(function()
    return ResolutionController:isCanvasCrtShaderEnabled()
  end)
  return ok and enabled == true
end

local function setMouseVisibility(app, visible)
  if not (love and love.mouse and love.mouse.setVisible) then
    return
  end
  if app and app._cursorVisible == visible then
    return
  end
  love.mouse.setVisible(visible)
  if app then
    app._cursorVisible = visible
  end
end

--- True when (mx, my) is over window content while reference tracing view is active.
local function isReferenceTracingViewAtPointer(app, mx, my)
  if type(mx) ~= "number" or type(my) ~= "number" then
    return false
  end
  local wm = app and app.wm
  if not (wm and wm.windowAt) then
    return false
  end
  local win = wm:windowAt(mx, my)
  if not win then
    return false
  end
  local ReferenceBackgroundController = require("controllers.window.reference_background_controller")
  if not ReferenceBackgroundController.isReferenceTracingViewActive(win) then
    return false
  end
  if win.isInContentArea and win:isInContentArea(mx, my) then
    return true
  end
  return false
end

--- True when (mx,my) is over artwork that can be painted with the pencil (sprite hit, tile cell with
--- content, or canvas layer). Uses the same rules as edit-mode pencil cursor eligibility.
function CursorsController.isHoveringEditableContentAt(app, mx, my)
  local wm = app and app.wm
  if not (wm and wm.windowAt) then return false end

  if type(mx) ~= "number" or type(my) ~= "number" then return false end

  local win = wm:windowAt(mx, my)
  if not win or win._closed or win.isPalette then return false end
  if not (win.layers and win.getActiveLayerIndex) then return false end

  local layerIndex = win:getActiveLayerIndex() or 1
  local layer = win.layers[layerIndex]
  if not layer then return false end

  if layer.kind == "sprite" then
    local SpriteController = require("controllers.sprite.sprite_controller")
    if not (SpriteController and SpriteController.pickSpriteAt) then return false end
    local pickedLayer, itemIndex = SpriteController.pickSpriteAt(win, mx, my, layerIndex)
    return pickedLayer ~= nil and itemIndex ~= nil
  end

  if layer.kind == "tile" then
    if not (win.toGridCoords and win.get) then return false end
    local ok, col, row = win:toGridCoords(mx, my)
    if not ok or type(col) ~= "number" or type(row) ~= "number" then return false end

    local cols = win.cols or 0
    if cols <= 0 then return false end
    local idx = (row * cols + col) + 1
    if (not WindowCaps.isPpuFrame(win)) and layer.removedCells and layer.removedCells[idx] then return false end

    if win.getVirtualTileHandle then
      return win:getVirtualTileHandle(col, row, layerIndex) ~= nil
    end
    return win:get(col, row, layerIndex) ~= nil
  end

  if layer.kind == "canvas" and layer.canvas then
    if not win.toGridCoords then return false end
    local ok = win:toGridCoords(mx, my)
    return ok == true
  end

  return false
end

local function isHoveringEditableContent(app)
  local mx, my = getMouseCanvasPosition()
  return CursorsController.isHoveringEditableContentAt(app, mx, my)
end

local function eachAppContextMenu(app, fn)
  if not app or not fn then
    return
  end
  local menus = {
    app.windowHeaderContextMenu,
    app.emptySpaceContextMenu,
    app.ppuTileContextMenu,
    app.paletteLinkContextMenu,
    app.e2eOverlayMenu,
  }
  for _, menu in ipairs(menus) do
    if menu then
      fn(menu)
    end
  end
end

local function modalPanelDisabledAt(modal, mx, my)
  if not (modal and modal.isVisible and modal:isVisible()) then
    return false
  end
  local inside = false
  if type(modal.contains) == "function" then
    inside = modal:contains(mx, my)
  elseif type(modal._containsBox) == "function" then
    inside = modal:_containsBox(mx, my)
  end
  if not inside then
    return false
  end
  local p = modal.panel
  return p and type(p.isHoveringDisabledButtonAt) == "function" and p:isHoveringDisabledButtonAt(mx, my)
end

local function modalPanelHandAt(modal, mx, my)
  if not (modal and modal.isVisible and modal:isVisible()) then
    return false
  end
  local inside = false
  if type(modal.contains) == "function" then
    inside = modal:contains(mx, my)
  elseif type(modal._containsBox) == "function" then
    inside = modal:_containsBox(mx, my)
  end
  if not inside then
    return false
  end
  local p = modal.panel
  if not p then
    return false
  end
  if type(p.getButtonAt) == "function" and p:getButtonAt(mx, my) then
    return true
  end
  if type(p.getComponentAt) == "function" and p:getComponentAt(mx, my) then
    return true
  end
  return false
end

local function toolbarDisabledAt(toolbar, mx, my)
  if not (toolbar and toolbar.contains and toolbar.getButtonAt) then
    return false
  end
  if not toolbar:contains(mx, my) then
    return false
  end
  local b = toolbar:getButtonAt(mx, my)
  return b and b.enabled == false
end

local function appQuickButtonsDisabledAt(app, mx, my)
  local buttons = app and app._appTopQuickButtons
  if not buttons then
    return false
  end
  local disabled = false
  AppTopToolbar.forEachQuickButtonKeyInLayoutOrder(app, function(key)
    if disabled then
      return
    end
    local b = buttons[key]
    if b and b.enabled == false and b.contains and b:contains(mx, my) then
      disabled = true
    end
  end)
  return disabled
end

local function isHoveringHandTargetAt(app, mx, my)
  if type(mx) ~= "number" or type(my) ~= "number" then
    return false
  end

  if AppTopToolbar.isPointerOverInteractiveTopChrome(app, mx, my) then
    return true
  end

  local function toolbarInteractiveHit(toolbar)
    if not (toolbar and toolbar.contains and toolbar.getButtonAt) then
      return false
    end
    if not toolbar:contains(mx, my) then
      return false
    end
    return toolbar:getButtonAt(mx, my) ~= nil
  end

  local wm = app and app.wm
  local win = topSurfaceWindowAt(wm, mx, my)
  if win then
    if toolbarInteractiveHit(win.headerToolbar) then
      return true
    end
    if toolbarInteractiveHit(win.specializedToolbar) then
      return true
    end
  end

  local menuHand = false
  eachAppContextMenu(app, function(menu)
    if menuHand then
      return
    end
    if menu.isVisible and menu:isVisible() and menu.contains and menu:contains(mx, my) then
      menuHand = true
    end
  end)
  if menuHand then
    return true
  end

  local taskbar = app and app.taskbar
  if taskbar and taskbar.isInteractiveAt and taskbar:isInteractiveAt(mx, my) then
    return true
  end
  if taskbar and taskbar.menuController and taskbar.menuController.isVisible and taskbar.menuController:isVisible() then
    local m = taskbar.menuController
    if m.contains and m:contains(mx, my) then
      return true
    end
  end

  local modals = {
    app and app.quitConfirmModal,
    app and app.pressEscAgainExitModal,
    app and app.saveOptionsModal,
    app and app.genericActionsModal,
    app and app.settingsModal,
    app and app.newWindowModal,
    app and app.newWindowTypeModal,
    app and app.renameWindowModal,
    app and app.romPaletteAddressModal,
    app and app.ppuFrameSpriteLayerModeModal,
    app and app.ppuFrameAddSpriteModal,
    app and app.ppuFrameRangeModal,
    app and app.ppuFramePatternRangeModal,
    app and app.textFieldDemoModal,
    app and app.openProjectModal,
    app and app.openReferencePngModal,
  }
  for _, modal in ipairs(modals) do
    if modalPanelHandAt(modal, mx, my) then
      return true
    end
  end

  if app and app.splash and app.splash.isPointOverButton and app.canvas and app.splash:isVisible() then
    if app.splash:isPointOverButton(mx, my, app.canvas) then
      return true
    end
  end

  return false
end

local function isHoveringDisabledUiAt(app, mx, my)
  if type(mx) ~= "number" or type(my) ~= "number" then
    return false
  end

  if appQuickButtonsDisabledAt(app, mx, my) then
    return true
  end

  local wm = app and app.wm
  local win = topSurfaceWindowAt(wm, mx, my)
  if win then
    if toolbarDisabledAt(win.headerToolbar, mx, my) then
      return true
    end
    if toolbarDisabledAt(win.specializedToolbar, mx, my) then
      return true
    end
  end

  local disabledMenu = false
  eachAppContextMenu(app, function(menu)
    if disabledMenu then
      return
    end
    if menu.isVisible and menu:isVisible() and menu.contains and menu:contains(mx, my) then
      if menu.isHoveringDisabledAt and menu:isHoveringDisabledAt(mx, my) then
        disabledMenu = true
      end
    end
  end)
  if disabledMenu then
    return true
  end

  local taskbar = app and app.taskbar
  if taskbar and taskbar.menuController and taskbar.menuController.isVisible and taskbar.menuController:isVisible() then
    local m = taskbar.menuController
    if m:contains(mx, my) and m.isHoveringDisabledAt and m:isHoveringDisabledAt(mx, my) then
      return true
    end
  end
  if taskbar and taskbar.buttons then
    for _, b in ipairs(taskbar.buttons) do
      if b and b.enabled == false and b.contains and b:contains(mx, my) then
        return true
      end
    end
  end

  local modals = {
    app and app.quitConfirmModal,
    app and app.pressEscAgainExitModal,
    app and app.saveOptionsModal,
    app and app.genericActionsModal,
    app and app.settingsModal,
    app and app.newWindowModal,
    app and app.newWindowTypeModal,
    app and app.renameWindowModal,
    app and app.romPaletteAddressModal,
    app and app.ppuFrameSpriteLayerModeModal,
    app and app.ppuFrameAddSpriteModal,
    app and app.ppuFrameRangeModal,
    app and app.ppuFramePatternRangeModal,
    app and app.textFieldDemoModal,
    app and app.openProjectModal,
    app and app.openReferencePngModal,
  }
  for _, modal in ipairs(modals) do
    if modalPanelDisabledAt(modal, mx, my) then
      return true
    end
  end

  if app and app.settingsModal and app.settingsModal.isVisible and app.settingsModal:isVisible() then
    if type(app.settingsModal.isHoveringDisabledAppearancePickerAt) == "function"
      and app.settingsModal:isHoveringDisabledAppearancePickerAt(mx, my) then
      return true
    end
  end

  return false
end

local function shouldUseResizeCursor(app, mx, my)
  local wm = app and app.wm
  if not wm then
    return false
  end
  if type(mx) ~= "number" or type(my) ~= "number" then
    return false
  end
  if type(wm.focusedResizeHandleAt) == "function" and wm:focusedResizeHandleAt(mx, my) then
    return true
  end
  local win = wm.getFocus and wm:getFocus() or nil
  return win and win.resizing == true
end

local function resolveTargetCursorName(app, mode)
  local mx, my = getMouseCanvasPosition()
  if type(mx) == "number" and type(my) == "number" then
    local _, topModal = Shared.getTopModal(app)
    if topModal then
      if app.settingsModal == topModal and type(app.settingsModal.isHoveringColorPickerSwatchAt) == "function" then
        if app.settingsModal:isHoveringColorPickerSwatchAt(mx, my) then
          return "hand"
        end
      end
      if app.settingsModal == topModal then
        if type(app.settingsModal.isHoveringDisabledAppearancePickerAt) == "function"
            and app.settingsModal:isHoveringDisabledAppearancePickerAt(mx, my) then
          return "unavailable"
        end
      end
      if modalPanelDisabledAt(topModal, mx, my) then
        return "unavailable"
      end
      if modalPanelHandAt(topModal, mx, my) then
        return "hand"
      end
      return "arrow"
    end

    if isReferenceTracingViewAtPointer(app, mx, my) then
      return "arrow"
    end

    if app and app.settingsModal and type(app.settingsModal.isHoveringColorPickerSwatchAt) == "function" then
      if app.settingsModal:isHoveringColorPickerSwatchAt(mx, my) then
        return "hand"
      end
    end
    if isHoveringDisabledUiAt(app, mx, my) then
      return "unavailable"
    end
    if shouldUseResizeCursor(app, mx, my) then
      return "resize"
    end
    if isHoveringHandTargetAt(app, mx, my) then
      return "hand"
    end
  end

  local resolvedMode = (mode == "edit") and "edit" or "tile"
  local grabDown = love.keyboard.isDown("g")
  local fillDown = love.keyboard.isDown("f")

  if resolvedMode == "edit" then
    local hoveringEditable = isHoveringEditableContent(app)
    if grabDown then
      return hoveringEditable and "pick" or "arrow"
    end
    if fillDown then
      return hoveringEditable and "fill" or "arrow"
    end
    if app and app.editTool == "rect_fill" then
      return "rect_fill"
    end
    return hoveringEditable and "pencil" or "arrow"
  end

  if isHoveringEditableContent(app) then
    return "hand"
  end
  return "arrow"
end

function CursorsController.applyModeCursor(app, mode)
  if not (love and love.mouse) then
    return
  end

  local cursors = app and app.hardwareCursors or {}
  local targetName = resolveTargetCursorName(app, mode)

  if app and targetName == "rect_fill" and not cursors.rect_fill then
    cursors.rect_fill = ensureNamedCursorLoaded(app, "rect_fill")
  end
  if app and targetName == "unavailable" and not cursors.unavailable then
    cursors.unavailable = ensureNamedCursorLoaded(app, "unavailable")
  end
  if app and targetName == "resize" and not cursors.resize then
    cursors.resize = ensureNamedCursorLoaded(app, "resize")
  end

  local useSoftwareCursor = shouldUseSoftwareCursor(app)
  if useSoftwareCursor then
    if app and targetName == "rect_fill" then
      ensureNamedSoftwareCursorLoaded(app, "rect_fill")
    end
    if app and targetName == "unavailable" then
      ensureNamedSoftwareCursorLoaded(app, "unavailable")
    end
    if app and targetName == "resize" then
      ensureNamedSoftwareCursorLoaded(app, "resize")
    end
    setMouseVisibility(app, false)
    if love.mouse.setCursor then
      love.mouse.setCursor()
    end
    if app then
      app._softwareCursorModeActive = true
      app.activeCursorName = targetName
      app.activeHardwareCursor = nil
    end
    return
  end

  if app then
    app._softwareCursorModeActive = false
  end
  setMouseVisibility(app, true)

  local target = cursors[targetName]
  if not target and targetName ~= "arrow" then
    target = cursors.arrow
    targetName = "arrow"
  end

  if app and app.activeHardwareCursor == target and app.activeCursorName == targetName then
    return
  end

  if target then
    if love.mouse.setCursor then
      love.mouse.setCursor(target)
    end
    if app then
      app.activeHardwareCursor = target
      app.activeCursorName = targetName
    end
  else
    -- Fallback to OS default cursor.
    if love.mouse.setCursor then
      love.mouse.setCursor()
    end
    if app then
      app.activeHardwareCursor = nil
      app.activeCursorName = nil
    end
  end
end

local function loadAllCursorAssets(app)
  local cursorSet = resolveCursorSetName(desiredCursorSetName())
  app.cursorSetName = cursorSet

  app.hardwareCursors = {
    arrow = loadNamedCursor("arrow", cursorSet),
    hand = loadNamedCursor("hand", cursorSet),
    pencil = loadNamedCursor("pencil", cursorSet),
    fill = loadNamedCursor("fill", cursorSet),
    pick = loadNamedCursor("pick", cursorSet),
    rect_fill = loadNamedCursor("rect_fill", cursorSet),
    unavailable = loadNamedCursor("unavailable", cursorSet),
    resize = loadNamedCursor("resize", cursorSet),
  }
  -- Clear before repopulating so CRT toggles do not reuse stale Image objects.
  app.softwareCursors = {}
  app.softwareCursors.arrow = ensureNamedSoftwareCursorLoaded(app, "arrow")
  app.softwareCursors.hand = ensureNamedSoftwareCursorLoaded(app, "hand")
  app.softwareCursors.pencil = ensureNamedSoftwareCursorLoaded(app, "pencil")
  app.softwareCursors.fill = ensureNamedSoftwareCursorLoaded(app, "fill")
  app.softwareCursors.pick = ensureNamedSoftwareCursorLoaded(app, "pick")
  app.softwareCursors.rect_fill = ensureNamedSoftwareCursorLoaded(app, "rect_fill")
  app.softwareCursors.unavailable = ensureNamedSoftwareCursorLoaded(app, "unavailable")
  app.softwareCursors.resize = ensureNamedSoftwareCursorLoaded(app, "resize")
  app._softwareCursorModeActive = false
  app._cursorVisible = nil

  setMouseVisibility(app, true)

  CursorsController.applyModeCursor(app, app.mode)
end

function CursorsController.init(app)
  if not app then return end
  loadAllCursorAssets(app)
end

--- Reload cursor PNGs when CRT mode changes (1x assets for software-drawn cursor under CRT).
function CursorsController.reloadForCrtMode(app)
  if not app then return end
  loadAllCursorAssets(app)
end

function CursorsController.update(app)
  -- Cursor application is event-driven; do not mutate hardware cursor in update().
  return
end

function CursorsController.isUsingSoftwareCursor(app)
  return app and app._softwareCursorModeActive == true
end

CursorsController.isHoveringDisabledUiAt = isHoveringDisabledUiAt

function CursorsController.draw(app)
  if not (app and CursorsController.isUsingSoftwareCursor(app)) then
    return
  end

  local name = app.activeCursorName or "arrow"
  local entry = app.softwareCursors and app.softwareCursors[name] or nil
  if not entry then
    entry = app.softwareCursors and app.softwareCursors.arrow or nil
  end
  if not (entry and entry.image) then
    return
  end

  local mx, my = getMouseCanvasPosition(false)
  if type(mx) ~= "number" or type(my) ~= "number" then
    return
  end

  local drawX = math.floor(mx - (entry.hotX or 0))
  local drawY = math.floor(my - (entry.hotY or 0))
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(entry.image, drawX, drawY)
end

return CursorsController
