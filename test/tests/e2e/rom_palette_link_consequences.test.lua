local E2EHarness = require("test.e2e_harness")
local E2EScenarios = require("test.e2e_visible.scenarios")
local InstantRunner = require("test.e2e_visible.scenarios.instant_runner")
local Steps = require("test.e2e_visible.steps")

local resolvePoint = Steps.resolvePoint

local function nextActionKind(steps, index)
  for i = index + 1, #(steps or {}) do
    local kind = steps[i] and steps[i].kind
    if kind ~= "pause" and kind ~= "assert_delay" then
      return kind
    end
  end
  return nil
end

local function interpolateMouse(harness, toX, toY, samples)
  local fromX, fromY = harness:getMouseCanvasPosition()
  samples = math.max(2, math.floor(tonumber(samples) or 12))
  for s = 1, samples do
    local t = s / samples
    harness:moveMouse(fromX + (toX - fromX) * t, fromY + (toY - fromY) * t)
  end
end

describe("e2e - ROM palette link consequences", function()
  it("links palette consumers and resolves codes after retarget/mutation", function()
    local scenario = assert(
      E2EScenarios.scenarios.rom_palette_link_consequences,
      "expected rom_palette_link_consequences scenario"
    )
    local harness = E2EHarness.new({
      settings = { skipSplash = true },
    })
    local ok, err = pcall(function()
      local app = harness:boot()
      local runner = { harness = harness, app = app }
      local steps = scenario.build(harness, app, runner)
      InstantRunner.runSteps(harness, app, runner, steps)
    end)
    harness:destroy()
    if not ok then
      error(err)
    end
  end)

  it("retargets static dest onto palette B along an interpolated drag", function()
    local scenario = assert(
      E2EScenarios.scenarios.rom_palette_link_consequences,
      "expected rom_palette_link_consequences scenario"
    )
    local harness = E2EHarness.new({
      settings = { skipSplash = true },
    })
    local ok, err = pcall(function()
      local app = harness:boot()
      local runner = { harness = harness, app = app }
      local steps = scenario.build(harness, app, runner)
      local interpolateNextMove = false
      for i, step in ipairs(steps) do
        if step.label == "Retarget static art badge onto palette B" and step.kind == "mouse_down" then
          interpolateNextMove = true
        end
        if step.kind == "mouse_down" then
          local x, y = resolvePoint(step.pointResolver, harness, app, runner)
          harness:mouseDown(step.button or 1, x, y)
        elseif step.kind == "mouse_up" then
          local x, y = resolvePoint(step.pointResolver, harness, app, runner)
          harness:mouseUp(step.button or 1, x, y)
        elseif step.kind == "key_press" then
          harness:keyPress(step.key, { mods = step.mods })
        elseif step.kind == "text_input" then
          harness:textInput(step.text)
        elseif step.kind == "call" then
          step.fn(harness, app, runner)
        elseif step.kind == "move" then
          if nextActionKind(steps, i) == "mouse_down" then
            goto continue
          end
          local x, y = resolvePoint(step.pointResolver, harness, app, runner)
          if x and y then
            if interpolateNextMove then
              interpolateNextMove = false
              interpolateMouse(harness, x, y, 24)
            else
              harness:moveMouse(x, y)
            end
          end
        end
        ::continue::
        if step.label == "Assert static art retarget follows palette B colors" then
          assert(
            runner.staticArtWin.layers[1].paletteData.winId == runner.romPaletteBWin._id,
            "expected static linked to palette B"
          )
          return
        end
      end
      error("expected dest→B retarget assert step")
    end)
    harness:destroy()
    if not ok then
      error(err)
    end
  end)
end)
