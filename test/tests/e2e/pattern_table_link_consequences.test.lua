local E2EHarness = require("test.e2e_harness")
local E2EScenarios = require("test.e2e_visible.scenarios")
local InstantRunner = require("test.e2e_visible.scenarios.instant_runner")

describe("e2e - Pattern table link consequences", function()
  it("links PT consumers and remaps NT cells when retargeting", function()
    local scenario = assert(
      E2EScenarios.scenarios.pattern_table_link_consequences,
      "expected pattern_table_link_consequences scenario"
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
end)
