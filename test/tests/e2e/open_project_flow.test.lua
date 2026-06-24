local E2EHarness = require("test.e2e_harness")
local E2EScenarios = require("test.e2e_visible.scenarios")
local InstantRunner = require("test.e2e_visible.scenarios.instant_runner")

describe("e2e - open project flow", function()
  local function runScenario(scenarioKey)
    local scenario = assert(E2EScenarios.scenarios[scenarioKey], "expected scenario: " .. scenarioKey)
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
  end

  it("opens fixture project through toolbar modal navigation", function()
    runScenario("open_project_happy_path")
  end)

  it("shows error and keeps ROM unloaded for invalid project file", function()
    runScenario("open_project_invalid_file")
  end)
end)
