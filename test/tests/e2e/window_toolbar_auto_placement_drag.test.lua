-- E2E: moving a focused window updates attached specialized toolbar layout for windowToolbarPlacement = auto.
-- Uses real window drag (header press + move + release), then checks geometry against ToolbarBase rules.

local E2EHarness = require("test.e2e_harness")
local ToolbarAuto = require("test.e2e_visible.scenarios.toolbar_auto_placement_helpers")

describe("e2e - auto toolbar placement after window drag", function()
  it("keeps CHR specialized toolbar aligned with resolved placement across many moves", function()
    local harness = E2EHarness.new({
      settings = {
        skipSplash = true,
        separateToolbar = false,
        windowToolbarPlacement = "auto",
      },
    })

    local ok, err = pcall(function()
      local app = harness:boot()
      harness:loadROM()

      local win = assert(harness:findWindow({ kind = "chr" }), "expected CHR window after ROM load")
      app.wm:setFocus(win)
      assert(app.windowToolbarPlacement == "auto", "harness settings should pin window toolbar placement to auto")

      local positions = {
        { 48, 90 },
        { 520, 70 },
        { 720, 320 },
        { 120, 400 },
        { 340, 200 },
        { 10, 160 },
        { 840, 120 },
        { 180, 300 },
      }

      for _, pos in ipairs(positions) do
        ToolbarAuto.dragWindowContentToward(win, pos[1], pos[2])
        ToolbarAuto.assertSpecializedToolbarMatchesAutoLayout(win, app)
      end
    end)

    harness:destroy()
    if not ok then
      error(err)
    end
  end)
end)
