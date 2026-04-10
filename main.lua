local app
local e2eRunner
local lastPolledMouseX
local lastPolledMouseY
local highSpeedPaintMode = true
local highSpeedToggleLatched = false
local crtModeToggleLatched = false
local AppCoreController
local RomProjectController
local LoveRunLoop = require("controllers.app.love_run_loop")
local applyHighSpeedPaintMode

local function parseCommandLineArgs(argv)
  local out = {
    e2eScenario = nil,
    e2eSpeedMultiplier = nil,
    romPath = nil,
  }

  local i = 1
  while argv and i <= #argv do
    local value = argv[i]
    if value == "--e2e" then
      out.e2eScenario = argv[i + 1] or "modals"
      i = i + 2
    elseif value == "--e2e-speed" then
      out.e2eSpeedMultiplier = tonumber(argv[i + 1]) or 1
      i = i + 2
    elseif value and not value:match("^%-") and not out.romPath then
      out.romPath = value
      i = i + 1
    else
      i = i + 1
    end
  end

  return out
end

function love.load(arg)
  local cli = parseCommandLineArgs(arg)

  if cli.e2eScenario then
    local VisibleE2ERunner = require("test.e2e_visible_runner")
    e2eRunner = VisibleE2ERunner.new({
      scenario = cli.e2eScenario,
      speedMultiplier = cli.e2eSpeedMultiplier,
    })
    app = e2eRunner:getApp()
    return
  end

  local SimpleLoadingScreen = require("controllers.app.simple_loading_screen")
  SimpleLoadingScreen.present("Starting PPUX...")

  AppCoreController = require("controllers.app.core_controller")
  RomProjectController = require("controllers.rom.rom_project_controller")

  SimpleLoadingScreen.present("Initializing app...")
  app = AppCoreController.new()
  SimpleLoadingScreen.present("Preparing workspace...")
  app:load()

  -- Check for command-line arguments (ROM file path)
  -- In LÖVE, command-line arguments are passed as a parameter to love.load()
  -- arg[0] is typically the game directory, actual args start at arg[1]
  if cli.romPath then
    RomProjectController.loadROM(app, cli.romPath)
  end

  if love.mouse and love.mouse.getPosition then
    lastPolledMouseX, lastPolledMouseY = love.mouse.getPosition()
  end

  -- Re-assert startup mode in case initialization touched window flags and
  -- silently restored vsync defaults.
  applyHighSpeedPaintMode(highSpeedPaintMode)
end

local function ctrlDown()
  return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
end

local function digitFiveDown()
  return love.keyboard.isDown("5") or love.keyboard.isDown("kp5")
end

local function digitSixDown()
  return love.keyboard.isDown("6") or love.keyboard.isDown("kp6")
end

local function digitSevenDown()
  return love.keyboard.isDown("7") or love.keyboard.isDown("kp7")
end

local function digitEightDown()
  return love.keyboard.isDown("8") or love.keyboard.isDown("kp8")
end

function applyHighSpeedPaintMode(enabled)
  highSpeedPaintMode = not not enabled

  local targetVsync = highSpeedPaintMode and 0 or 1

  if love.window and love.window.setVSync then
    pcall(love.window.setVSync, targetVsync)
  end

  -- Some systems/drivers ignore setVSync changes until window mode flags are
  -- re-applied. Keep all existing window flags and only force vsync.
  if love.window and love.window.getMode and love.window.updateMode then
    local w, h, flags = love.window.getMode()
    if type(flags) == "table" and flags.vsync ~= targetVsync then
      local nextFlags = {}
      for k, v in pairs(flags) do
        nextFlags[k] = v
      end
      nextFlags.vsync = targetVsync
      nextFlags.x = nil
      nextFlags.y = nil
      pcall(love.window.updateMode, w, h, nextFlags)
    end
  end
end

local function shouldToggleHighSpeedMode(key, isrepeat)
  if isrepeat or not ctrlDown() then
    return false
  end

  local keyIsFive = (key == "5" or key == "kp5")
  local keyIsSix = (key == "6" or key == "kp6")
  if not (keyIsFive or keyIsSix) then
    return false
  end

  return digitFiveDown() and digitSixDown()
end

local function shouldToggleCrtMode(key, isrepeat)
  if isrepeat or not ctrlDown() then
    return false
  end

  local keyIsSeven = (key == "7" or key == "kp7")
  local keyIsEight = (key == "8" or key == "kp8")
  if not (keyIsSeven or keyIsEight) then
    return false
  end

  return digitSevenDown() and digitEightDown()
end

local function isInteractiveFrame()
  -- The low-latency loop is only worth using while the dedicated high-speed
  -- paint mode is enabled. In normal mode we let LÖVE pace itself more calmly.
  if not highSpeedPaintMode then
    return false
  end
  if e2eRunner then
    return false
  end
  if not love.mouse then
    return false
  end
  return love.mouse.isDown(1) or love.mouse.isDown(2) or love.mouse.isDown(3)
end

local function pollMouseMovement()
  -- In high-speed paint mode we poll mouse motion every frame in addition to
  -- OS mousemove callbacks. That keeps fast drag painting responsive even when
  -- the platform delivers sparse mouse motion events.
  if not highSpeedPaintMode then
    return
  end
  if e2eRunner or not app or not love.mouse or not love.mouse.getPosition then
    return
  end

  local x, y = love.mouse.getPosition()
  if lastPolledMouseX == nil or lastPolledMouseY == nil then
    lastPolledMouseX, lastPolledMouseY = x, y
    return
  end

  if x ~= lastPolledMouseX or y ~= lastPolledMouseY then
    app:mousemoved(x, y, x - lastPolledMouseX, y - lastPolledMouseY)
    lastPolledMouseX, lastPolledMouseY = x, y
  end
end

function love.update(dt)
  if e2eRunner then
    e2eRunner:update(dt)
    return
  end
  pollMouseMovement()
  app:update(dt)
end

function love.draw()
  app:draw()
  if e2eRunner then
    e2eRunner:drawOverlay()
  end
end

function love.filedropped(file)
  if e2eRunner then return end
  app:filedropped(file)
end

function love.keypressed(k, scancode, isrepeat)
  if e2eRunner then
    if e2eRunner.keypressed then
      e2eRunner:keypressed(k, scancode, isrepeat)
    end
    return
  end
  if shouldToggleHighSpeedMode(k, isrepeat) and not highSpeedToggleLatched then
    applyHighSpeedPaintMode(not highSpeedPaintMode)
    highSpeedToggleLatched = true
    return
  end
  if shouldToggleCrtMode(k, isrepeat) and not crtModeToggleLatched then
    if app and app.toggleCrtMode then
      app:toggleCrtMode()
    end
    crtModeToggleLatched = true
    return
  end
  app:keypressed(k)
end

function love.keyreleased(k)
  if e2eRunner then return end
  if k == "lctrl" or k == "rctrl" or k == "5" or k == "6" or k == "kp5" or k == "kp6" then
    if not (ctrlDown() and digitFiveDown() and digitSixDown()) then
      highSpeedToggleLatched = false
    end
  end
  if k == "lctrl" or k == "rctrl" or k == "7" or k == "8" or k == "kp7" or k == "kp8" then
    if not (ctrlDown() and digitSevenDown() and digitEightDown()) then
      crtModeToggleLatched = false
    end
  end
  app:keyreleased(k)
end

function love.mousepressed(x, y, b)
  if e2eRunner then
    if e2eRunner.mousepressed then
      e2eRunner:mousepressed(x, y, b)
    end
    return
  end
  app:mousepressed(x, y, b)
end

function love.mousereleased(x, y, b)
  if e2eRunner then return end
  app:mousereleased(x, y, b)
end

function love.mousemoved(x, y, dx, dy)
  if e2eRunner then return end
  lastPolledMouseX, lastPolledMouseY = x, y
  app:mousemoved(x, y, dx, dy)
end

function love.wheelmoved(dx, dy)
  if e2eRunner then return end
  app:wheelmoved(dx, dy)
end

function love.textinput(text)
  if e2eRunner then return end
  if app and app.textinput then
    app:textinput(text)
  end
end

function love.resize(w, h)
  app:resize(w, h)
end

function love.focus(focused)
  if focused then
    applyHighSpeedPaintMode(highSpeedPaintMode)
  end
end

function love.quit()
  if e2eRunner and e2eRunner.destroy then
    e2eRunner:destroy()
  end
  if app and app.handleQuitRequest then
    return app:handleQuitRequest()
  end
  return false
end

-- We override LÖVE's default main loop so painting can run in a lower-latency
-- mode when needed. The key differences are:
-- 1. we can poll mouse movement every frame for smoother drag painting
-- 2. we can choose a more aggressive sleep strategy while interacting
-- 3. we can toggle that behavior at runtime instead of committing globally
--
-- When high-speed paint mode is disabled, this loop still runs, but it falls
-- back to calmer pacing and vsync so the app behaves more like normal LÖVE.
love.run = LoveRunLoop.create({
  isHighSpeedMode = function()
    return highSpeedPaintMode
  end,
  isInteractiveFrame = isInteractiveFrame,
  backgroundSleepSeconds = 0.01,
  focusedSleepSeconds = 0.001,
  normalSleepSeconds = 0.001,
})
