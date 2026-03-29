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
}

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
  local fileName = CURSOR_FILES[name]
  if not fileName then return nil end
  local path = string.format("%s/%s/%s", CURSOR_ROOT, setName, fileName)
  return loadCursorFromPath(path)
end

local function getMouseCanvasPosition()
  if ResolutionController and ResolutionController.getScaledMouse then
    local ok, mouse = pcall(function()
      return ResolutionController:getScaledMouse(true)
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

local function anyModalVisible(app)
  return (app and app.quitConfirmModal and app.quitConfirmModal.isVisible and app.quitConfirmModal:isVisible())
    or (app and app.saveOptionsModal and app.saveOptionsModal.isVisible and app.saveOptionsModal:isVisible())
    or (app and app.genericActionsModal and app.genericActionsModal.isVisible and app.genericActionsModal:isVisible())
    or (app and app.settingsModal and app.settingsModal.isVisible and app.settingsModal:isVisible())
    or (app and app.newWindowModal and app.newWindowModal.isVisible and app.newWindowModal:isVisible())
    or (app and app.renameWindowModal and app.renameWindowModal.isVisible and app.renameWindowModal:isVisible())
end

local function isHoveringTileOrSprite(app)
  local wm = app and app.wm
  if not (wm and wm.windowAt) then return false end

  local mx, my = getMouseCanvasPosition()
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
    if layer.removedCells and layer.removedCells[idx] then return false end

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

local function isHoveringInteractiveUI(app)
  local mx, my = getMouseCanvasPosition()
  if type(mx) ~= "number" or type(my) ~= "number" then return false end

  local taskbar = app and app.taskbar
  if taskbar and taskbar.isInteractiveAt and taskbar:isInteractiveAt(mx, my) then
    return true
  end

  return false
end

function CursorsController.applyModeCursor(app, mode)
  if not (love and love.mouse and love.mouse.setCursor) then return end

  local cursors = app and app.hardwareCursors or {}
  local resolvedMode = (mode == "edit") and "edit" or "tile"
  local grabDown = love.keyboard.isDown("g")
  local fillDown = love.keyboard.isDown("f")

  local target
  if anyModalVisible(app) then
    target = cursors.arrow
  elseif isHoveringInteractiveUI(app) then
    target = cursors.hand or cursors.arrow
  elseif resolvedMode == "edit" then
    if isHoveringTileOrSprite(app) then
      -- Grab has precedence when multiple tool keys are held.
      if grabDown then
        target = cursors.pick or cursors.pencil or cursors.arrow
      elseif fillDown then
        target = cursors.fill or cursors.pencil or cursors.arrow
      else
        target = cursors.pencil or cursors.arrow
      end
    else
      target = cursors.arrow or cursors.pencil
    end
  else
    if isHoveringTileOrSprite(app) then
      target = cursors.hand or cursors.arrow
    else
      target = cursors.arrow or cursors.hand
    end
  end

  if app and app.activeHardwareCursor == target then
    return
  end

  if target then
    love.mouse.setCursor(target)
    if app then app.activeHardwareCursor = target end
  else
    -- Fallback to OS default cursor.
    love.mouse.setCursor()
    if app then app.activeHardwareCursor = nil end
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
  }

  if love and love.mouse and love.mouse.setVisible then
    love.mouse.setVisible(true)
  end

  CursorsController.applyModeCursor(app, app.mode)
end

function CursorsController.update(app)
  if not app then return end
  CursorsController.applyModeCursor(app, app.mode)
end

return CursorsController
