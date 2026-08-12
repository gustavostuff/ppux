local E2EHarness = require("test.e2e_harness")
local E2EScenarios = require("test.e2e_visible.scenarios")
local InstantRunner = require("test.e2e_visible.scenarios.instant_runner")

describe("e2e - RomHexGrid modal flows", function()
  local function runScenario(scenarioKey)
    local scenario = assert(E2EScenarios.scenarios[scenarioKey], "expected scenario: " .. scenarioKey)
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
  end

  it("ROM palette address modal: invalid reject, select, replace, scroll semis, Set/Cancel", function()
    runScenario("rom_palette_hex_grid_flow")
  end)

  it("OAM add-sprite modal: multi-select, toggle, overlap conflict, cap, Add", function()
    runScenario("oam_sprite_hex_grid_flow")
  end)

  it("Nametable range modal: two-click range, inside/outside, Scan semis, overlap, Set", function()
    runScenario("nametable_hex_grid_flow")
  end)
end)
