-- E2E: moving a focused window keeps the attached specialized toolbar on top,
-- clamping Y to (app top bar height + TOOLBAR_OUTSIDE_GAP) and X inside the canvas (±gap) when needed.

local E2EHarness = require("test.e2e_harness")
local ToolbarAuto = require("test.e2e_visible.scenarios.toolbar_auto_placement_helpers")

describe("e2e - window toolbar viewport clamp after window drag", function()
  it("keeps CHR specialized toolbar visible with top and horizontal clamps", function()
    local harness = E2EHarness.new({
      settings = {
        skipSplash = true,
        separateToolbar = false,
      },
    })

    local ok, err = pcall(function()
      local app = harness:boot()
      harness:loadROM()

      local win = assert(harness:findWindow({ kind = "chr" }), "expected CHR window after ROM load")
      app.wm:setFocus(win)

      local positions = {
        { 48, 90 },
        { 520, 70 },
        { 720, 320 },
        { 120, 400 },
        { 340, 200 },
        { 10, 160 },
        { 840, 120 },
        { 180, 300 },
        -- Force Y clamp: push content so the natural toolbar strip would sit above the app bar.
        { 200, -40 },
        { 100, -120 },
        -- Force horizontal clamp: shove window toward left/right canvas edges.
        { -80, 200 },
        { 1200, 220 },
      }

      local sawYClamp = false
      local sawXClamp = false
      for _, pos in ipairs(positions) do
        ToolbarAuto.dragWindowContentToward(win, pos[1], pos[2])
        ToolbarAuto.assertSpecializedToolbarMatchesTopClamp(win, app)

        local tb = win.specializedToolbar
        local hx, hy, hw = win:getHeaderRect()
        local preferredY = math.floor(hy - tb.h - 1)
        local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
        local minY = AppTopToolbarController.getContentOffsetY(app) + 1
        if preferredY < minY then
          sawYClamp = true
        end

        local preferredLeft = hx + math.floor((hw - tb.w) / 2)
        local drawLeft = tb.x - 1
        if preferredLeft ~= drawLeft then
          sawXClamp = true
        end
      end

      assert(sawYClamp, "expected at least one drag position to exercise the top-bar Y clamp")
      assert(sawXClamp, "expected at least one drag position to exercise the horizontal X clamp")
    end)

    harness:destroy()
    if not ok then
      error(err)
    end
  end)
end)
