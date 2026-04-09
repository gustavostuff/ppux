local AppCoreController = require("controllers.app.core_controller")
local AppSettingsController = require("controllers.app.settings_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local RomProjectController = require("controllers.rom.rom_project_controller")

local E2EHarness = {}
E2EHarness.__index = E2EHarness

local function deepcopy(value, seen)
  if type(value) ~= "table" then
    return value
  end

  seen = seen or {}
  if seen[value] then
    return seen[value]
  end

  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[deepcopy(k, seen)] = deepcopy(v, seen)
  end
  return copy
end

local function mergeSettings(base, overrides)
  local merged = deepcopy(base or {})
  for k, v in pairs(overrides or {}) do
    merged[k] = v
  end
  return merged
end

local function normalizeMods(mods)
  local normalized = {}
  for _, key in ipairs(mods or {}) do
    normalized[key] = true
  end
  return normalized
end

local function buttonCenter(button)
  assert(button, "button is required")
  return button.x + (button.w * 0.5), button.y + (button.h * 0.5)
end

local function firstReadablePath(candidates)
  for _, path in ipairs(candidates or {}) do
    local file = io.open(path, "rb")
    if file then
      file:close()
      return path
    end
  end
  return nil
end

function E2EHarness.new(opts)
  opts = opts or {}
  local defaults = (AppSettingsController.defaults and AppSettingsController.defaults()) or {}
  local instance = setmetatable({
    opts = opts,
    app = nil,
    quitRequested = false,
    settings = mergeSettings(defaults, mergeSettings({
      skipSplash = true,
    }, opts.settings or {})),
    _restore = {},
    _mouseX = 0,
    _mouseY = 0,
    _mouseCanvasX = 0,
    _mouseCanvasY = 0,
    _mouseButtons = {},
    _keysDown = {},
    _previousCtx = rawget(_G, "ctx"),
    _timerNow = 0,
    stepDelaySeconds = opts.stepDelaySeconds or 0.1,
    stepDt = opts.stepDt or (1 / 60),
    shimEventQuit = (opts.shimEventQuit ~= false),
    shimTimerTime = (opts.shimTimerTime ~= false),
  }, E2EHarness)

  return instance
end

function E2EHarness:_installInputShims()
  love.keyboard = love.keyboard or {}
  love.mouse = love.mouse or {}
  love.event = love.event or {}

  self._restore.keyboardIsDown = love.keyboard.isDown
  self._restore.mouseGetPosition = love.mouse.getPosition
  self._restore.mouseIsDown = love.mouse.isDown
  if self.shimEventQuit then
    self._restore.eventQuit = love.event.quit
  end
  self._restore.timerGetTime = love.timer and love.timer.getTime or nil

  love.keyboard.isDown = function(...)
    for i = 1, select("#", ...) do
      local key = select(i, ...)
      if self._keysDown[key] then
        return true
      end
    end
    return false
  end

  love.mouse.getPosition = function()
    return self._mouseX, self._mouseY
  end

  love.mouse.isDown = function(button)
    return self._mouseButtons[button] == true
  end

  if self.shimEventQuit then
    love.event.quit = function()
      self.quitRequested = true
      return true
    end
  end

  if self.shimTimerTime then
    love.timer = love.timer or {}
    love.timer.getTime = function()
      return self._timerNow or 0
    end
  end
end

function E2EHarness:_installSettingsShim()
  self._restore.settingsLoad = AppSettingsController.load
  self._restore.settingsLoadDisplay = AppSettingsController.loadDisplaySettings
  self._restore.settingsSave = AppSettingsController.save
  self._restore.settingsSaveDisplay = AppSettingsController.saveDisplaySettings

  AppSettingsController.load = function()
    return deepcopy(self.settings)
  end

  AppSettingsController.loadDisplaySettings = function()
    return deepcopy(self.settings)
  end

  AppSettingsController.save = function(opts)
    for k, v in pairs(opts or {}) do
      self.settings[k] = v
    end
    return true
  end

  AppSettingsController.saveDisplaySettings = function(opts)
    for k, v in pairs(opts or {}) do
      self.settings[k] = v
    end
    return true
  end
end

function E2EHarness:boot()
  if self.app then
    return self.app
  end

  _G.__PPUX_DISABLE_LOADING_SCREEN__ = true
  self:_installInputShims()
  self:_installSettingsShim()

  local app = AppCoreController.new()
  app:load()

  if app.splash then
    app.splash.visible = false
  end

  self.app = app
  return app
end

function E2EHarness:destroy()
  if self._restore.keyboardIsDown then
    love.keyboard.isDown = self._restore.keyboardIsDown
  end
  if self._restore.mouseGetPosition then
    love.mouse.getPosition = self._restore.mouseGetPosition
  end
  if self._restore.mouseIsDown then
    love.mouse.isDown = self._restore.mouseIsDown
  end
  if self.shimEventQuit and self._restore.eventQuit then
    love.event.quit = self._restore.eventQuit
  end
  if self._restore.timerGetTime then
    love.timer.getTime = self._restore.timerGetTime
  end
  if self._restore.settingsLoad then
    AppSettingsController.load = self._restore.settingsLoad
  end
  if self._restore.settingsLoadDisplay then
    AppSettingsController.loadDisplaySettings = self._restore.settingsLoadDisplay
  end
  if self._restore.settingsSave then
    AppSettingsController.save = self._restore.settingsSave
  end
  if self._restore.settingsSaveDisplay then
    AppSettingsController.saveDisplaySettings = self._restore.settingsSaveDisplay
  end

  _G.ctx = self._previousCtx
  self.app = nil
end

function E2EHarness:advanceTimer(dt)
  local delta = tonumber(dt) or 0
  if delta < 0 then
    delta = 0
  end
  self._timerNow = (self._timerNow or 0) + delta
  return self._timerNow
end

function E2EHarness:getApp()
  return self.app
end

function E2EHarness:getStatusText()
  return self.app and self.app.statusText or nil
end

function E2EHarness:getFocusedWindow()
  local wm = self.app and self.app.wm
  return wm and wm.getFocus and wm:getFocus() or nil
end

function E2EHarness:getWindows()
  local wm = self.app and self.app.wm
  return (wm and wm.getWindows and wm:getWindows()) or {}
end

function E2EHarness:getTaskbar()
  return self.app and self.app.taskbar or nil
end

function E2EHarness:resolveTestRomPath()
  return firstReadablePath({
    "test/test_rom.nes",
    "test_rom.nes",
  })
end

function E2EHarness:findWindow(query)
  query = query or {}
  for _, win in ipairs(self:getWindows()) do
    local matches = true
    if query.kind and win.kind ~= query.kind then
      matches = false
    end
    if query.title and win.title ~= query.title then
      matches = false
    end
    if query.id and win._id ~= query.id then
      matches = false
    end
    if matches then
      return win
    end
  end
  return nil
end

function E2EHarness:loadROM(path)
  local app = assert(self.app, "E2EHarness not booted")
  path = path or self:resolveTestRomPath()
  assert(path, "No readable test ROM path found")
  local ok = RomProjectController.loadROM(app, path)
  assert(ok, "Failed to load ROM: " .. tostring(path))
  return app.winBank
end

function E2EHarness:advanceFrames(count, dt, draw)
  local app = assert(self.app, "E2EHarness not booted")
  count = math.max(1, math.floor(count or 1))
  dt = dt or (1 / 60)

  for _ = 1, count do
    self:advanceTimer(dt)
    app:update(dt)
    if draw then
      app:draw()
    end
  end
end

function E2EHarness:_refreshTaskbarLayout()
  local app = self.app
  local taskbar = app and app.taskbar
  local canvas = app and app.canvas
  if not (taskbar and taskbar.updateLayout and canvas and canvas.getWidth and canvas.getHeight) then
    return taskbar
  end

  taskbar:updateLayout(canvas:getWidth(), canvas:getHeight())
  return taskbar
end

function E2EHarness:wait(seconds, dt, draw)
  seconds = seconds or self.stepDelaySeconds
  if seconds <= 0 then
    return
  end

  dt = dt or self.stepDt
  local frames = math.max(1, math.ceil(seconds / dt))
  self:advanceFrames(frames, dt, draw)
end

function E2EHarness:_settleAfterAction(opts, fallbackDt)
  opts = opts or {}
  if opts.wait == false then
    return
  end

  local dt = opts.dt or fallbackDt or self.stepDt
  if opts.frames then
    self:advanceFrames(opts.frames, dt, opts.draw)
    return
  end

  self:wait(opts.delaySeconds, dt, opts.draw)
end

function E2EHarness:findTaskbarButton(query)
  query = query or {}
  local taskbar = self:_refreshTaskbarLayout()
  if not taskbar then
    return nil
  end

  local kind = query.kind
  if kind == "menu" then
    return taskbar.menuButton
  end
  if kind == "sort_title" then
    return taskbar.sortAlphaButton
  end
  if kind == "sort_kind" then
    return taskbar.sortKindButton
  end
  if kind == "window" then
    if query.win and taskbar.minimizedButtonsByWindow then
      return taskbar.minimizedButtonsByWindow[query.win]
    end
    for win, button in pairs(taskbar.minimizedButtonsByWindow or {}) do
      local matches = true
      if query.title and win.title ~= query.title then
        matches = false
      end
      if query.id and win._id ~= query.id then
        matches = false
      end
      if matches then
        return button
      end
    end
    return nil
  end
  if kind == "mode_indicator" then
    local font = love.graphics.getFont()
    local mode = (self.app and self.app.mode == "edit") and "Edit" or "Tile"
    local textW = (font and font:getWidth(mode)) or 0
    local badgeW = math.max(24, textW + 12)
    local totalW = badgeW + taskbar.h
    local badgeX = math.floor((taskbar.x + taskbar.w) - 6 - totalW)
    return {
      x = badgeX,
      y = taskbar.y,
      w = totalW,
      h = taskbar.h,
    }
  end

  return nil
end

function E2EHarness:getTaskbarButtonCenter(query)
  local button = self:findTaskbarButton(query)
  if not button then
    return nil
  end
  return buttonCenter(button)
end

function E2EHarness:findTaskbarMenuItem(text)
  local taskbar = self:_refreshTaskbarLayout()
  local panel = taskbar and taskbar.menuController and taskbar.menuController.panel or nil
  if not (panel and panel.cells) then
    return nil
  end

  for row, rowCells in pairs(panel.cells) do
    for _, cell in pairs(rowCells or {}) do
      if cell and cell.text == text then
        cell._row = row
        return cell
      end
    end
  end
  return nil
end

function E2EHarness:getTaskbarMenuItemCenter(text)
  local cell = self:findTaskbarMenuItem(text)
  if not (cell and cell.button) then
    return nil
  end
  return buttonCenter(cell.button)
end

function E2EHarness:openTaskbarMenu(opts)
  local taskbar = self:_refreshTaskbarLayout()
  if not taskbar then
    return false
  end
  if taskbar.menuController and taskbar.menuController:isVisible() then
    return true
  end

  local x, y = self:getTaskbarButtonCenter({ kind = "menu" })
  assert(x and y, "taskbar menu button not found")
  self:click(x, y, opts)
  return taskbar.menuController and taskbar.menuController:isVisible() or false
end

function E2EHarness:clickTaskbarButton(query, opts)
  local x, y = self:getTaskbarButtonCenter(query)
  assert(x and y, "taskbar button not found")
  self:click(x, y, opts)
end

function E2EHarness:clickTaskbarMenuItem(text, opts)
  if not self:openTaskbarMenu({
    wait = false,
  }) then
    error("taskbar menu is not available")
  end

  local x, y = self:getTaskbarMenuItemCenter(text)
  assert(x and y, "taskbar menu item not found: " .. tostring(text))
  self:click(x, y, opts)
end

function E2EHarness:canvasToScreen(x, y)
  local scaleX = ResolutionController.canvasScaleX or 1
  local scaleY = ResolutionController.canvasScaleY or 1
  local canvasX = ResolutionController.canvasX or 0
  local canvasY = ResolutionController.canvasY or 0
  return canvasX + x * scaleX, canvasY + y * scaleY
end

function E2EHarness:_setMouseCanvasPosition(x, y)
  self._mouseCanvasX = x
  self._mouseCanvasY = y
  self._mouseX, self._mouseY = self:canvasToScreen(x, y)
  return self._mouseX, self._mouseY
end

-- Window geometry and mouse input both use full canvas coordinates (top toolbar included).
function E2EHarness:contentToCanvasPoint(x, y)
  return x, tonumber(y) or 0
end

function E2EHarness:getMouseCanvasPosition()
  return self._mouseCanvasX or 0, self._mouseCanvasY or 0
end

function E2EHarness:moveMouse(x, y)
  local app = assert(self.app, "E2EHarness not booted")
  local prevScreenX, prevScreenY = self._mouseX, self._mouseY
  local sx, sy = self:_setMouseCanvasPosition(x, y)
  app:mousemoved(sx, sy, sx - prevScreenX, sy - prevScreenY)
  return sx, sy
end

function E2EHarness:mouseDown(button, x, y)
  local app = assert(self.app, "E2EHarness not booted")
  button = button or 1
  local sx, sy
  if x ~= nil and y ~= nil then
    sx, sy = self:moveMouse(x, y)
  else
    sx, sy = self._mouseX, self._mouseY
  end
  self._mouseButtons[button] = true
  app:mousepressed(sx, sy, button)
  return sx, sy
end

function E2EHarness:mouseUp(button, x, y)
  local app = assert(self.app, "E2EHarness not booted")
  button = button or 1
  local sx, sy
  if x ~= nil and y ~= nil then
    sx, sy = self:moveMouse(x, y)
  else
    sx, sy = self._mouseX, self._mouseY
  end
  self._mouseButtons[button] = false
  app:mousereleased(sx, sy, button)
  return sx, sy
end

function E2EHarness:windowCellCenter(win, col, row)
  local zoom = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local cellW = win.cellW or 8
  local cellH = win.cellH or 8
  local scrollCol = win.scrollCol or 0
  local scrollRow = win.scrollRow or 0

  return self:contentToCanvasPoint(
    win.x + ((col - scrollCol) + 0.5) * cellW * zoom,
    win.y + ((row - scrollRow) + 0.5) * cellH * zoom
  )
end

function E2EHarness:windowPixelCenter(win, col, row, px, py)
  local zoom = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  local cellW = win.cellW or 8
  local cellH = win.cellH or 8
  local scrollCol = win.scrollCol or 0
  local scrollRow = win.scrollRow or 0
  local localPx = math.max(0, math.min(cellW - 1, math.floor(px or 0)))
  local localPy = math.max(0, math.min(cellH - 1, math.floor(py or 0)))

  return self:contentToCanvasPoint(
    win.x + ((col - scrollCol) * cellW + localPx + 0.5) * zoom,
    win.y + ((row - scrollRow) * cellH + localPy + 0.5) * zoom
  )
end

function E2EHarness:click(x, y, opts)
  opts = opts or {}
  local button = opts.button or 1

  self:mouseDown(button, x, y)
  self:mouseUp(button, x, y)
  self:_settleAfterAction(opts)
end

function E2EHarness:clickWindowCell(win, col, row, opts)
  local x, y = self:windowCellCenter(win, col, row)
  self:click(x, y, opts)
end

function E2EHarness:clickWindowPixel(win, col, row, px, py, opts)
  local x, y = self:windowPixelCenter(win, col, row, px, py)
  self:click(x, y, opts)
end

function E2EHarness:drag(fromX, fromY, toX, toY, opts)
  local app = assert(self.app, "E2EHarness not booted")
  opts = opts or {}
  local button = opts.button or 1
  local steps = math.max(1, math.floor(opts.steps or 6))
  local dt = opts.dt or self.stepDt

  self:mouseDown(button, fromX, fromY)

  local prevCanvasX, prevCanvasY = fromX, fromY
  for i = 1, steps do
    local t = i / steps
    local currentCanvasX = fromX + (toX - fromX) * t
    local currentCanvasY = fromY + (toY - fromY) * t
    self:moveMouse(currentCanvasX, currentCanvasY)
    self:advanceTimer(dt)
    app:update(dt)
    prevCanvasX, prevCanvasY = currentCanvasX, currentCanvasY
  end

  self:mouseUp(button, toX, toY)
  self:_settleAfterAction({
    wait = opts.wait,
    frames = opts.framesAfter,
    dt = dt,
    draw = opts.draw,
    delaySeconds = opts.delaySeconds,
  }, dt)
end

function E2EHarness:dragWindowCell(srcWin, srcCol, srcRow, dstWin, dstCol, dstRow, opts)
  local fromX, fromY = self:windowCellCenter(srcWin, srcCol, srcRow)
  local toX, toY = self:windowCellCenter(dstWin, dstCol, dstRow)
  self:drag(fromX, fromY, toX, toY, opts)
end

function E2EHarness:_setMods(mods, down)
  local normalized = normalizeMods(mods)
  self._keysDown.lctrl = down and (normalized.ctrl or normalized.lctrl) or false
  self._keysDown.rctrl = down and (normalized.ctrl or normalized.rctrl) or false
  self._keysDown.lshift = down and (normalized.shift or normalized.lshift) or false
  self._keysDown.rshift = down and (normalized.shift or normalized.rshift) or false
  self._keysDown.lalt = down and (normalized.alt or normalized.lalt) or false
  self._keysDown.ralt = down and (normalized.alt or normalized.ralt) or false
end

function E2EHarness:keyPress(key, opts)
  local app = assert(self.app, "E2EHarness not booted")
  opts = opts or {}
  self:keyDown(key, opts.mods)
  if opts.release ~= false then
    self:keyUp(key, opts.mods)
  end
  self:_settleAfterAction(opts)
end

function E2EHarness:keyChord(key, mods, opts)
  opts = opts or {}
  opts.mods = mods
  self:keyPress(key, opts)
end

function E2EHarness:keyDown(key, mods)
  local app = assert(self.app, "E2EHarness not booted")
  self:_setMods(mods, true)
  app:keypressed(key)
end

function E2EHarness:keyUp(key, mods)
  local app = assert(self.app, "E2EHarness not booted")
  app:keyreleased(key)
  self:_setMods(mods, false)
end

function E2EHarness:textInput(text, opts)
  local app = assert(self.app, "E2EHarness not booted")
  text = tostring(text or "")
  opts = opts or {}

  for i = 1, #text do
    app:textinput(text:sub(i, i))
  end

  self:_settleAfterAction(opts)
end

function E2EHarness:isModalVisible(name)
  local app = self.app
  if not app then
    return false
  end

  local modal = app[name]
  if modal and type(modal.isVisible) == "function" then
    return modal:isVisible()
  end

  if type(name) == "string" then
    local suffixed = app[name .. "Modal"]
    if suffixed and type(suffixed.isVisible) == "function" then
      return suffixed:isVisible()
    end
  end

  return false
end

function E2EHarness:createDroppedFile(filename, bytes)
  if bytes == nil and type(filename) == "string" then
    local file = io.open(filename, "rb")
    if file then
      bytes = file:read("*a")
      file:close()
    end
  end

  return {
    getFilename = function()
      return filename
    end,
    open = function()
      return true
    end,
    read = function()
      return bytes or ""
    end,
    close = function()
      return true
    end,
  }
end

function E2EHarness:dropFile(filename, bytes)
  local app = assert(self.app, "E2EHarness not booted")
  local file = type(filename) == "table" and filename or self:createDroppedFile(filename, bytes)
  app:filedropped(file)
  self:_settleAfterAction()
  return file
end

return E2EHarness
