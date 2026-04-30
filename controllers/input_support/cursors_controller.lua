local CursorsController = {}
local ResolutionController = require("controllers.app.resolution_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local CURSOR_ROOT = "img/cursors"
local DEFAULT_CURSOR_SET = "2x"
local IGNORED_CURSOR_SETS = { bkp = true }

local CURSOR_FILES = {
  arrow = "cursor_arrow_0_0.png",
  hand = "cursor_hand_8_1.png",
  pencil = "cursor_pencil_6_6.png",
  fill = "cursor_fill_2_21.png",
  pick = "cursor_pick_2_27.png",
  rect_fill = "cursor_rect_14_14.png",
}

local function cursorPathForName(name, setName)
  local fileName = CURSOR_FILES[name]
  if not fileName then return nil end
  return string.format("%s/%s/%s", CURSOR_ROOT, setName, fileName)
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

local function anyModalVisible(app)
  return (app and app.quitConfirmModal and app.quitConfirmModal.isVisible and app.quitConfirmModal:isVisible())
    or (app and app.saveOptionsModal and app.saveOptionsModal.isVisible and app.saveOptionsModal:isVisible())
    or (app and app.genericActionsModal and app.genericActionsModal.isVisible and app.genericActionsModal:isVisible())
    or (app and app.settingsModal and app.settingsModal.isVisible and app.settingsModal:isVisible())
    or (app and app.newWindowModal and app.newWindowModal.isVisible and app.newWindowModal:isVisible())
    or (app and app.renameWindowModal and app.renameWindowModal.isVisible and app.renameWindowModal:isVisible())
    or (app and app.romPaletteAddressModal and app.romPaletteAddressModal.isVisible and app.romPaletteAddressModal:isVisible())
    or (app and app.ppuFrameSpriteLayerModeModal and app.ppuFrameSpriteLayerModeModal.isVisible and app.ppuFrameSpriteLayerModeModal:isVisible())
    or (app and app.ppuFrameAddSpriteModal and app.ppuFrameAddSpriteModal.isVisible and app.ppuFrameAddSpriteModal:isVisible())
    or (app and app.ppuFrameRangeModal and app.ppuFrameRangeModal.isVisible and app.ppuFrameRangeModal:isVisible())
    or (app and app.textFieldDemoModal and app.textFieldDemoModal.isVisible and app.textFieldDemoModal:isVisible())
    or (app and app.splash and app.splash.isVisible and app.splash:isVisible())
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

local function isHoveringInteractiveUI(app)
  local mx, my = getMouseCanvasPosition()
  if type(mx) ~= "number" or type(my) ~= "number" then return false end

  local taskbar = app and app.taskbar
  if taskbar and taskbar.isInteractiveAt and taskbar:isInteractiveAt(mx, my) then
    return true
  end

  return false
end

local function resolveTargetCursorName(app, mode)
  local mx, my = getMouseCanvasPosition()
  if type(mx) == "number" and type(my) == "number" then
    if app and app.settingsModal and type(app.settingsModal.isHoveringColorPickerSwatchAt) == "function" then
      if app.settingsModal:isHoveringColorPickerSwatchAt(mx, my) then
        return "hand"
      end
    end
  end

  local resolvedMode = (mode == "edit") and "edit" or "tile"
  local grabDown = love.keyboard.isDown("g")
  local fillDown = love.keyboard.isDown("f")

  if anyModalVisible(app) then
    return "arrow"
  end

  if isHoveringInteractiveUI(app) then
    return "hand"
  end

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
  if not (love and love.mouse) then return end

  local cursors = app and app.hardwareCursors or {}
  local targetName = resolveTargetCursorName(app, mode)

  if app and targetName == "rect_fill" and not cursors.rect_fill then
    cursors.rect_fill = ensureNamedCursorLoaded(app, "rect_fill")
  end

  local useSoftwareCursor = shouldUseSoftwareCursor(app)
  if useSoftwareCursor then
    if app and targetName == "rect_fill" then
      ensureNamedSoftwareCursorLoaded(app, "rect_fill")
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

function CursorsController.init(app)
  if not app then return end
  local cursorSet = resolveCursorSetName(app.cursorSetName)
  app.cursorSetName = cursorSet

  app.hardwareCursors = {
    arrow = loadNamedCursor("arrow", cursorSet),
    hand = loadNamedCursor("hand", cursorSet),
    pencil = loadNamedCursor("pencil", cursorSet),
    fill = loadNamedCursor("fill", cursorSet),
    pick = loadNamedCursor("pick", cursorSet),
    rect_fill = loadNamedCursor("rect_fill", cursorSet),
  }
  app.softwareCursors = {
    arrow = ensureNamedSoftwareCursorLoaded(app, "arrow"),
    hand = ensureNamedSoftwareCursorLoaded(app, "hand"),
    pencil = ensureNamedSoftwareCursorLoaded(app, "pencil"),
    fill = ensureNamedSoftwareCursorLoaded(app, "fill"),
    pick = ensureNamedSoftwareCursorLoaded(app, "pick"),
    rect_fill = ensureNamedSoftwareCursorLoaded(app, "rect_fill"),
  }
  app._softwareCursorModeActive = false
  app._cursorVisible = nil

  setMouseVisibility(app, true)

  CursorsController.applyModeCursor(app, app.mode)
end

function CursorsController.update(app)
  -- Cursor application is event-driven; do not mutate hardware cursor in update().
  return
end

function CursorsController.isUsingSoftwareCursor(app)
  return app and app._softwareCursorModeActive == true
end

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
