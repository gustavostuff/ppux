local E2EHarness = require("test.e2e_harness")
local E2EVisualConfig = require("test.e2e_visual_config")
local E2EVisibleSteps = require("test.e2e_visible.steps")
local E2EVisibleScenarios = require("test.e2e_visible.scenarios")
local ContextualMenuController = require("controllers.ui.contextual_menu_controller")
local colors = require("app_colors")
local Flux = require("lib.flux")
local Text = require("utils.text_utils")

local normalizeSpeedMultiplier = E2EVisibleSteps.normalizeSpeedMultiplier
local applySpeedMultiplierToSteps = E2EVisibleSteps.applySpeedMultiplierToSteps
local resolvePoint = E2EVisibleSteps.resolvePoint
local SCENARIOS = E2EVisibleScenarios.scenarios
local SCENARIO_ALIASES = E2EVisibleScenarios.aliases

local VisibleE2ERunner = {}
VisibleE2ERunner.__index = VisibleE2ERunner
VisibleE2ERunner.ABORT_ALL_FLAG_PATH = "/tmp/ppux_e2e_abort_all.flag"

local cachedOverlayFont = nil

local function getOverlayFont()
  if cachedOverlayFont then
    return cachedOverlayFont
  end

  local paths = {
    "user_interface/fonts/proggy-tiny.ttf",
    "../user_interface/fonts/proggy-tiny.ttf",
  }

  for _, path in ipairs(paths) do
    local ok, font = pcall(love.graphics.newFont, path, 16)
    if ok and font then
      cachedOverlayFont = font
      return cachedOverlayFont
    end
  end

  cachedOverlayFont = love.graphics.newFont(16)
  return cachedOverlayFont
end

function VisibleE2ERunner.new(opts)
  opts = opts or {}
  local requestedScenarioName = opts.scenario or "modals"
  local scenarioName = SCENARIO_ALIASES[requestedScenarioName] or requestedScenarioName
  local scenario = assert(SCENARIOS[scenarioName], "Unknown E2E scenario: " .. tostring(requestedScenarioName))
  local speedMultiplier = normalizeSpeedMultiplier(
    opts.speedMultiplier
      or opts.speed
      or (E2EVisualConfig and E2EVisualConfig.speedMultiplier)
      or 1
  )

  local harness = E2EHarness.new({
    stepDelaySeconds = 0,
    settings = opts.settings,
    shimEventQuit = false,
  })
  local app = harness:boot()
  local self = setmetatable({
    harness = harness,
    app = app,
    scenarioName = scenarioName,
    requestedScenarioName = requestedScenarioName,
    scenario = scenario,
    speedMultiplier = speedMultiplier,
    steps = {},
    currentStepIndex = 0,
    currentStep = nil,
    currentLabel = "Booting",
    done = false,
    doneElapsed = 0,
    autoCloseDelay = (opts.autoCloseDelay or 0.5) / speedMultiplier,
    quitIssued = false,
    timelineSeconds = 0,
    recordedTimes = {},
    demoMenu = nil,
    abortModalVisible = false,
    abortModalFocusIndex = 3,
    abortButtons = {
      { label = "Current", action = "current" },
      { label = "All", action = "all" },
      { label = "Continue", action = "continue" },
    },
    abortButtonRects = {},
  }, VisibleE2ERunner)

  if scenarioName == "submenu_positions" then
    self.demoMenu = ContextualMenuController.new({
      getBounds = function()
        return {
          w = app.canvas:getWidth(),
          h = app.canvas:getHeight(),
        }
      end,
      cols = 8,
      cellW = 15,
      cellH = 15,
      padding = 0,
      colGap = 0,
      rowGap = 1,
      splitIconCell = true,
    })
    app.e2eOverlayMenu = self.demoMenu
  end

  self.steps = applySpeedMultiplierToSteps(scenario.build(harness, app, self) or {}, speedMultiplier)
  return self
end

function VisibleE2ERunner:getApp()
  return self.app
end

function VisibleE2ERunner:_startNextStep()
  self.currentStepIndex = self.currentStepIndex + 1
  local step = self.steps[self.currentStepIndex]
  self.currentStep = step
  if not step then
    self.done = true
    self.currentLabel = "Done"
    return
  end

  step.elapsed = 0
  self.currentLabel = step.label or step.kind or ("Step " .. tostring(self.currentStepIndex))

  if step.kind == "move" then
    local fromX, fromY = self.harness:getMouseCanvasPosition()
    local toX, toY = resolvePoint(step.pointResolver, self.harness, self.app, self)
    step.fromX = fromX
    step.fromY = fromY
    step.toX = assert(toX, "move step x could not be resolved")
    step.toY = assert(toY, "move step y could not be resolved")
    step.duration = math.max(0.001, tonumber(step.duration) or 0.1)
    step.cursor = {
      x = fromX,
      y = fromY,
    }
    step.tweenGroup = Flux.group()
    step.tweenGroup:to(step.cursor, step.duration, {
      x = step.toX,
      y = step.toY,
    }):ease("linear")
    self.harness:moveMouse(fromX, fromY)
  elseif step.kind == "pause" then
    step.duration = math.max(0.001, tonumber(step.duration) or 0.1)
  end
end

function VisibleE2ERunner:_recordEvent(key)
  if not key then
    return
  end
  self.recordedTimes[key] = self.timelineSeconds
end

function VisibleE2ERunner:_setAbortModalVisible(visible)
  self.abortModalVisible = (visible == true)
  if self.abortModalVisible then
    self.abortModalFocusIndex = self.abortModalFocusIndex or 3
  end
end

function VisibleE2ERunner:_quitNow(exitCode)
  if self.app and self.app.clearUnsavedChanges then
    self.app:clearUnsavedChanges()
  end
  if self.app then
    self.app._allowImmediateQuit = true
  end
  self.quitIssued = true
  love.event.quit(exitCode or 0)
end

function VisibleE2ERunner:_requestAbortAll()
  local path = self.ABORT_ALL_FLAG_PATH
  local file = io.open(path, "wb")
  if file then
    file:write("abort_all\n")
    file:close()
  end
end

function VisibleE2ERunner:_activateAbortChoice(action)
  if action == "continue" then
    self:_setAbortModalVisible(false)
    return true
  end

  if action == "all" then
    self:_requestAbortAll()
    self:_quitNow(0)
    return true
  end

  if action == "current" then
    self:_quitNow(0)
    return true
  end

  return false
end

function VisibleE2ERunner:keypressed(key)
  if not self.abortModalVisible then
    if key == "escape" then
      self:_setAbortModalVisible(true)
      return true
    end
    return false
  end

  if key == "escape" then
    self:_activateAbortChoice("continue")
    return true
  end

  if key == "left" then
    self.abortModalFocusIndex = math.max(1, (self.abortModalFocusIndex or 1) - 1)
    return true
  end
  if key == "right" or key == "tab" then
    self.abortModalFocusIndex = math.min(#self.abortButtons, (self.abortModalFocusIndex or 1) + 1)
    return true
  end
  if key == "return" or key == "kpenter" or key == "space" then
    local button = self.abortButtons[self.abortModalFocusIndex or 1]
    return button and self:_activateAbortChoice(button.action) or true
  end
  if key == "1" or key == "kp1" then
    return self:_activateAbortChoice("current")
  end
  if key == "2" or key == "kp2" then
    return self:_activateAbortChoice("all")
  end
  if key == "3" or key == "kp3" then
    return self:_activateAbortChoice("continue")
  end

  return true
end

function VisibleE2ERunner:mousepressed(x, y, button)
  if not self.abortModalVisible or button ~= 1 then
    return false
  end

  for index, rect in ipairs(self.abortButtonRects or {}) do
    if x >= rect.x and x <= (rect.x + rect.w) and y >= rect.y and y <= (rect.y + rect.h) then
      self.abortModalFocusIndex = index
      local buttonDef = self.abortButtons[index]
      if buttonDef then
        self:_activateAbortChoice(buttonDef.action)
      end
      return true
    end
  end

  return true
end

function VisibleE2ERunner:_runInstantStep(step)
  if step.kind == "mouse_down" or step.kind == "mouse_up" then
    local x, y = resolvePoint(step.pointResolver, self.harness, self.app, self)
    assert(x and y, step.kind .. " point could not be resolved")
    if step.kind == "mouse_down" then
      self.harness:mouseDown(step.button or 1, x, y)
    else
      self.harness:mouseUp(step.button or 1, x, y)
    end
    self:_recordEvent(step.recordKey)
    self.currentStep = nil
    return
  end

  if step.kind == "key_press" then
    self.harness:keyPress(step.key, {
      mods = step.mods,
      wait = false,
    })
    self:_recordEvent(step.recordKey)
    self.currentStep = nil
    return
  end

  if step.kind == "text_input" then
    self.harness:textInput(step.text, {
      wait = false,
    })
    self:_recordEvent(step.recordKey)
    self.currentStep = nil
    return
  end

  if step.kind == "call" then
    assert(type(step.fn) == "function", "call step requires fn")
    step.fn(self.harness, self.app, self)
    self:_recordEvent(step.recordKey)
    self.currentStep = nil
    return
  end

  if step.kind == "assert_delay" then
    local fromTime = assert(self.recordedTimes[step.fromKey], "missing recorded time: " .. tostring(step.fromKey))
    local toTime = assert(self.recordedTimes[step.toKey], "missing recorded time: " .. tostring(step.toKey))
    local actual = toTime - fromTime
    local expected = tonumber(step.expected) or 0.1
    local tolerance = tonumber(step.tolerance) or 0.02
    local delta = math.abs(actual - expected)
    if delta > tolerance then
      error(string.format(
        "Visible E2E delay assertion failed: expected %.3fs between %s and %s, got %.3fs",
        expected,
        tostring(step.fromKey),
        tostring(step.toKey),
        actual
      ))
    end
    self.app:setStatus(string.format("Delay OK: %.3fs", actual))
    self.currentStep = nil
    return
  end
end

function VisibleE2ERunner:_currentStepSummary()
  local total = #self.steps
  local index = tonumber(self.currentStepIndex) or 0
  if total > 0 then
    index = math.max(1, math.min(index, total))
  else
    index = 0
  end

  local step = self.currentStep
  local label = self.currentLabel
  if (not label or label == "") and step then
    label = step.label or step.kind
  end
  label = label or "unknown"

  local kind = (step and step.kind) or "n/a"
  local scenario = tostring(self.scenarioName or "unknown")
  return string.format(
    "scenario=%s step=%d/%d kind=%s label=%s",
    scenario,
    index,
    total,
    tostring(kind),
    tostring(label)
  )
end

function VisibleE2ERunner:_raiseWithStepContext(err)
  error(string.format(
    "Visible E2E failed (%s): %s",
    self:_currentStepSummary(),
    tostring(err)
  ), 0)
end

function VisibleE2ERunner:update(dt)
  if self.abortModalVisible then
    return
  end

  local ok, err = xpcall(function()
    if self.harness and self.harness.advanceTimer then
      self.harness:advanceTimer(dt)
    end
    local remaining = dt

    while remaining > 0 do
      if not self.currentStep and not self.done then
        self:_startNextStep()
      end

      local step = self.currentStep
      if not step then
        self.timelineSeconds = self.timelineSeconds + remaining
        remaining = 0
        break
      end

      if step.kind == "pause" then
        local needed = math.max(0, step.duration - step.elapsed)
        local consume = math.min(remaining, needed)
        step.elapsed = step.elapsed + consume
        self.timelineSeconds = self.timelineSeconds + consume
        remaining = remaining - consume
        if step.elapsed >= step.duration then
          self.currentStep = nil
        end
      elseif step.kind == "move" then
        local needed = math.max(0, step.duration - step.elapsed)
        local consume = math.min(remaining, needed)
        step.elapsed = step.elapsed + consume
        self.timelineSeconds = self.timelineSeconds + consume
        remaining = remaining - consume

        if step.tweenGroup then
          step.tweenGroup:update(consume)
        end
        self.harness:moveMouse(
          step.cursor and step.cursor.x or step.toX,
          step.cursor and step.cursor.y or step.toY
        )
        if step.elapsed >= step.duration then
          self.harness:moveMouse(step.toX, step.toY)
          step.tweenGroup = nil
          step.cursor = nil
          self.currentStep = nil
        end
      else
        self:_runInstantStep(step)
        if self.currentStep == step then
          break
        end
      end
    end

    self.app:update(dt)

    if self.done and not self.quitIssued then
      self.doneElapsed = self.doneElapsed + dt
      if self.doneElapsed >= self.autoCloseDelay then
        if self.app.clearUnsavedChanges then
          self.app:clearUnsavedChanges()
        end
        self.app._allowImmediateQuit = true
        self.quitIssued = true
        love.event.quit()
      end
    end
  end, function(message)
    return debug.traceback(tostring(message), 2)
  end)

  if not ok then
    self:_raiseWithStepContext(err)
  end
end

function VisibleE2ERunner:drawOverlay()
  local title = string.format("E2E: %s (%0.2fx)", self.scenario.title or self.scenarioName, self.speedMultiplier or 1)
  local stepText = string.format("Step %d/%d: %s", math.min(self.currentStepIndex, #self.steps), #self.steps, self.currentLabel or "")
  local escHint = "Esc to pause/abort"

  local previousFont = love.graphics.getFont()
  local font = getOverlayFont()
  love.graphics.setFont(font)

  local w1 = font:getWidth(title)
  local w2 = font:getWidth(stepText)
  local w3 = font:getWidth(escHint)
  local boxW = math.max(w1, w2, w3) + 16
  local boxH = font:getHeight() * 3 + 18

  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", 8, 8, boxW, boxH)
  Text.print(title, 14, 12, { color = colors.white, font = font })
  Text.print(stepText, 14, 12 + font:getHeight() + 2, { color = colors.white, font = font })
  Text.print(escHint, 14, 12 + (font:getHeight() + 2) * 2, { color = { 1, 0.95, 0.2, 1 }, font = font })

  local cursorCanvasX, cursorCanvasY = self.harness:getMouseCanvasPosition()
  local cursorScreenX, cursorScreenY = self.harness:canvasToScreen(cursorCanvasX, cursorCanvasY)
  love.graphics.setColor(1, 0.95, 0.2, 0.95)
  love.graphics.circle("fill", cursorScreenX, cursorScreenY, 6)
  love.graphics.setColor(0, 0, 0, 0.9)
  love.graphics.circle("line", cursorScreenX, cursorScreenY, 6)

  if self.abortModalVisible then
    local titleText = "Abort:"
    local buttonGap = 6
    local padding = 12
    local buttonH = font:getHeight() + 12
    local widestButton = 0
    for _, button in ipairs(self.abortButtons) do
      widestButton = math.max(widestButton, font:getWidth(button.label))
    end
    local buttonW = widestButton + 20
    local titleW = font:getWidth(titleText)
    local innerW = (buttonW * 3) + (buttonGap * 2)
    local boxW = math.max(titleW, innerW) + (padding * 2)
    local boxH = padding * 2 + font:getHeight() + 6 + buttonH
    local boxX = math.floor((love.graphics.getWidth() - boxW) * 0.5)
    local boxY = math.floor((love.graphics.getHeight() - boxH) * 0.5)
    local buttonsY = boxY + padding + font:getHeight() + 6
    local buttonsX = boxX + padding

    love.graphics.setColor(0, 0, 0, 0.78)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH)
    Text.print(titleText, boxX + padding, boxY + padding, { color = colors.white, font = font })

    self.abortButtonRects = {}
    for index, button in ipairs(self.abortButtons) do
      local bx = buttonsX + (index - 1) * (buttonW + buttonGap)
      local by = buttonsY
      self.abortButtonRects[index] = { x = bx, y = by, w = buttonW, h = buttonH }
      if index == (self.abortModalFocusIndex or 1) then
        love.graphics.setColor(0.2, 0.65, 0.2, 1)
      else
        love.graphics.setColor(0.22, 0.22, 0.22, 1)
      end
      love.graphics.rectangle("fill", bx, by, buttonW, buttonH)
      love.graphics.setColor(colors.white)
      local labelW = font:getWidth(button.label)
      local labelX = bx + math.floor((buttonW - labelW) * 0.5)
      local labelY = by + math.floor((buttonH - font:getHeight()) * 0.5)
      Text.print(button.label, labelX, labelY, { color = colors.white, font = font })
    end
  else
    self.abortButtonRects = {}
  end

  love.graphics.setColor(colors.white)
  if previousFont and previousFont ~= font then
    love.graphics.setFont(previousFont)
  end
end

function VisibleE2ERunner:destroy()
  if self.demoMenu and self.demoMenu.hide then
    self.demoMenu:hide()
  end
  if self.app and self.app.e2eOverlayMenu == self.demoMenu then
    self.app.e2eOverlayMenu = nil
  end
  if self.harness then
    self.harness:destroy()
  end
end

VisibleE2ERunner._normalizeSpeedMultiplier = normalizeSpeedMultiplier
VisibleE2ERunner._applySpeedMultiplierToSteps = applySpeedMultiplierToSteps

return VisibleE2ERunner
