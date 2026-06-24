local E2EHarness = require("test.e2e_harness")
local E2EScenarios = require("test.e2e_visible.scenarios")
local InstantRunner = require("test.e2e_visible.scenarios.instant_runner")

describe("e2e - OAM animation workflow", function()
  it("navigates frames, plays back, and add/removes a sprite", function()
    local scenario = assert(E2EScenarios.scenarios.oam_animation_workflow)
    local harness = E2EHarness.new({
      settings = { skipSplash = true },
    })

    local ok, err = pcall(function()
      local app = harness:boot()
      local runner = { harness = harness, app = app, speedMultiplier = 8 }
      local steps = scenario.build(harness, app, runner)
      InstantRunner.runSteps(harness, app, runner, steps)
    end)

    harness:destroy()
    if not ok then
      error(err)
    end
  end)
end)
