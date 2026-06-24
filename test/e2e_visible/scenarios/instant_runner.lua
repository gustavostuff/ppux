-- Runs non-visual E2E scenario steps (call / click / key) for headless CI.

local Steps = require("test.e2e_visible.steps")
local resolvePoint = Steps.resolvePoint

local M = {}

function M.runSteps(harness, app, runner, steps)
  for _, step in ipairs(steps or {}) do
    if step.kind == "mouse_down" then
      local x, y = resolvePoint(step.pointResolver, harness, app, runner)
      assert(x and y, "mouse_down point could not be resolved: " .. tostring(step.label))
      harness:mouseDown(step.button or 1, x, y)
    elseif step.kind == "mouse_up" then
      local x, y = resolvePoint(step.pointResolver, harness, app, runner)
      assert(x and y, "mouse_up point could not be resolved: " .. tostring(step.label))
      harness:mouseUp(step.button or 1, x, y)
    elseif step.kind == "key_press" then
      harness:keyPress(step.key, { mods = step.mods })
    elseif step.kind == "text_input" then
      harness:textInput(step.text)
    elseif step.kind == "call" then
      assert(type(step.fn) == "function", "call step requires fn: " .. tostring(step.label))
      step.fn(harness, app, runner)
    elseif step.kind == "pause" or step.kind == "move" or step.kind == "assert_delay" then
      -- Visual timing only.
    else
      error("unsupported instant step kind: " .. tostring(step.kind))
    end
  end
end

return M
