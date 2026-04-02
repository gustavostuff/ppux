local M = {}

local function normalizeSpeedMultiplier(value)
  local n = tonumber(value)
  if not n or n <= 0 then
    return 1
  end
  return n
end

local function applySpeedMultiplierToSteps(steps, speedMultiplier)
  local multiplier = normalizeSpeedMultiplier(speedMultiplier)
  if multiplier == 1 then
    return steps or {}
  end

  local scaled = {}
  for i, step in ipairs(steps or {}) do
    local nextStep = {}
    for k, v in pairs(step) do
      nextStep[k] = v
    end

    if (nextStep.kind == "pause" or nextStep.kind == "move") and type(nextStep.duration) == "number" then
      nextStep.duration = nextStep.duration / multiplier
    end

    if nextStep.kind == "assert_delay" then
      if type(nextStep.expected) == "number" then
        nextStep.expected = nextStep.expected / multiplier
      end
      if type(nextStep.tolerance) == "number" then
        nextStep.tolerance = math.max(0.0005, nextStep.tolerance / multiplier)
      end
    end

    scaled[i] = nextStep
  end

  return scaled
end

local function pause(label, duration)
  return {
    kind = "pause",
    label = label,
    duration = duration or 0.1,
  }
end

local function moveTo(label, pointResolver, duration)
  return {
    kind = "move",
    label = label,
    duration = duration or 0.1,
    pointResolver = pointResolver,
  }
end

local function mouseDown(label, pointResolver, button)
  return {
    kind = "mouse_down",
    label = label,
    pointResolver = pointResolver,
    button = button or 1,
    recordKey = nil,
  }
end

local function mouseUp(label, pointResolver, button)
  return {
    kind = "mouse_up",
    label = label,
    pointResolver = pointResolver,
    button = button or 1,
    recordKey = nil,
  }
end

local function keyPress(label, key, mods)
  return {
    kind = "key_press",
    label = label,
    key = key,
    mods = mods,
    recordKey = nil,
  }
end

local function textInput(label, text)
  return {
    kind = "text_input",
    label = label,
    text = text,
    recordKey = nil,
  }
end

local function call(label, fn)
  return {
    kind = "call",
    label = label,
    fn = fn,
  }
end

local function assertDelay(label, fromKey, toKey, expected, tolerance)
  return {
    kind = "assert_delay",
    label = label,
    fromKey = fromKey,
    toKey = toKey,
    expected = expected,
    tolerance = tolerance or 0.02,
  }
end

local function resolvePoint(resolver, harness, app, runner)
  if type(resolver) == "function" then
    return resolver(harness, app, runner)
  end
  if type(resolver) == "table" then
    return resolver.x, resolver.y
  end
  return nil, nil
end

local function appendClick(steps, label, pointResolver, opts)
  opts = opts or {}
  steps[#steps + 1] = moveTo(label, pointResolver, opts.moveDuration or 0.12)
  steps[#steps + 1] = pause(label, opts.prePressPause or 0.08)
  steps[#steps + 1] = mouseDown(label, pointResolver, opts.button or 1)
  steps[#steps + 1] = pause(label, opts.holdDuration or 0.08)
  steps[#steps + 1] = mouseUp(label, pointResolver, opts.button or 1)
  steps[#steps + 1] = pause(label, opts.postPause or 0.12)
end

local function appendDrag(steps, label, fromResolver, toResolver, opts)
  opts = opts or {}
  steps[#steps + 1] = moveTo(label, fromResolver, opts.moveDuration or 0.12)
  steps[#steps + 1] = pause(label, opts.prePressPause or 0.08)
  steps[#steps + 1] = mouseDown(label, fromResolver, opts.button or 1)
  steps[#steps + 1] = pause(label, opts.holdDuration or 0.08)
  steps[#steps + 1] = moveTo(label, toResolver, opts.dragDuration or 0.4)
  steps[#steps + 1] = pause(label, opts.preReleasePause or 0.06)
  steps[#steps + 1] = mouseUp(label, toResolver, opts.button or 1)
  steps[#steps + 1] = pause(label, opts.postPause or 0.12)
end

M.normalizeSpeedMultiplier = normalizeSpeedMultiplier
M.applySpeedMultiplierToSteps = applySpeedMultiplierToSteps
M.pause = pause
M.moveTo = moveTo
M.mouseDown = mouseDown
M.mouseUp = mouseUp
M.keyPress = keyPress
M.textInput = textInput
M.call = call
M.assertDelay = assertDelay
M.resolvePoint = resolvePoint
M.appendClick = appendClick
M.appendDrag = appendDrag

return M
