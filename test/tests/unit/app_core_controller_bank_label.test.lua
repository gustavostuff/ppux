local AppCoreController = require("controllers.app.core_controller")
local Window = require("user_interface.windows_system.window")

describe("app_core_controller.lua - bank tile label mirroring", function()
  it("shows the current-bank tile label for a selected non-chr tile", function()
    local shownTileIndex = nil

    local focus = Window.new(0, 0, 8, 8, 4, 4, 1, {
      title = "Static Art",
    })
    focus.kind = "static_art"
    focus.layers = {
      {
        kind = "tile",
        items = {
          [1] = { _bankIndex = 2, index = 37 },
          [2] = { _bankIndex = 1, index = 99 },
        },
      },
    }
    focus.activeLayer = 1
    focus:setSelected(0, 0, 1)

    local app = setmetatable({
      mode = "tile",
      isPainting = false,
      wm = {
        getFocus = function() return focus end,
      },
      winBank = {
        currentBank = 2,
        specializedToolbar = {
          showTileLabel = function(_, tileIndex)
            shownTileIndex = tileIndex
          end,
        },
      },
      appEditState = {
        currentBank = 2,
      },
      syncDuplicateTiles = false,
      spaceHighlightActive = false,
      setStatus = function() end,
    }, AppCoreController)

    local ctx = app:_buildCtx()
    local shown = ctx.showBankTileLabelForWindowSelection(focus)

    expect(shown).toBe(true)
    expect(shownTileIndex).toBe(37)
  end)
end)
