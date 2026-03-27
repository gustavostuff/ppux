local Window = require("user_interface.windows_system.window")
local SpaceHighlightController = require("controllers.window.space_highlight_controller")

describe("space_highlight_controller.lua", function()
  local function makeWindow(kind)
    local win = Window.new(0, 0, 8, 8, 4, 4, 1, {
      title = "Space Highlight",
    })
    win.kind = kind or "static_art"
    return win
  end

  it("collects only tile refs from the current bank for tile layers", function()
    local layer = {
      kind = "tile",
      items = {
        [1] = { _bankIndex = 2, index = 5 },
        [2] = { _bankIndex = 1, index = 7 },
        [3] = { _bankIndex = 2, index = 9 },
      },
      removedCells = {
        [3] = true,
      },
    }

    local keys = SpaceHighlightController.collectLayerBankTileKeys(layer, 2)

    expect(keys["2:5"]).toBe(true)
    expect(keys["1:7"]).toBe(nil)
    expect(keys["2:9"]).toBe(nil)
  end)

  it("collects top and bottom refs from sprite layers for the current bank", function()
    local layer = {
      kind = "sprite",
      items = {
        {
          topRef = { _bankIndex = 3, index = 10 },
          botRef = { _bankIndex = 3, index = 11 },
        },
        {
          topRef = { _bankIndex = 4, index = 20 },
          botRef = { _bankIndex = 3, index = 21 },
        },
        {
          removed = true,
          topRef = { _bankIndex = 3, index = 30 },
        },
      },
    }

    local keys = SpaceHighlightController.collectLayerBankTileKeys(layer, 3)

    expect(keys["3:10"]).toBe(true)
    expect(keys["3:11"]).toBe(true)
    expect(keys["3:21"]).toBe(true)
    expect(keys["4:20"]).toBe(nil)
    expect(keys["3:30"]).toBe(nil)
  end)

  it("builds a space-highlight model from the focused non-chr window and current bank", function()
    local focus = makeWindow("static_art")
    focus.layers = {
      {
        kind = "tile",
        items = {
          [1] = { _bankIndex = 2, index = 3 },
          [2] = { _bankIndex = 1, index = 7 },
        },
      },
    }
    focus.activeLayer = 1

    local bankWindow = makeWindow("chr")
    bankWindow.currentBank = 2

    local ctx = {
      app = {
        winBank = bankWindow,
        appEditState = {
          currentBank = 2,
        },
      },
      wm = function()
        return {
          getFocus = function()
            return focus
          end,
        }
      end,
      getFocus = function()
        return focus
      end,
    }

    local model = SpaceHighlightController.buildModel(ctx, true)

    expect(model).toBeTruthy()
    expect(model.focusedWindow).toBe(focus)
    expect(model.bankWindow).toBe(bankWindow)
    expect(model.currentBank).toBe(2)
    expect(model.matchedTileKeys["2:3"]).toBe(true)
    expect(model.matchedTileKeys["1:7"]).toBe(nil)
  end)

  it("does not build a space-highlight model when the focused window is chr-like", function()
    local focus = makeWindow("chr")
    focus.layers = {
      {
        kind = "tile",
        items = {
          [1] = { _bankIndex = 2, index = 3 },
        },
      },
    }

    local ctx = {
      app = {
        winBank = focus,
        appEditState = {
          currentBank = 2,
        },
      },
      wm = function()
        return {
          getFocus = function()
            return focus
          end,
        }
      end,
      getFocus = function()
        return focus
      end,
    }

    expect(SpaceHighlightController.buildModel(ctx, true)).toBe(nil)
  end)

  it("builds a selection-highlight model from selected refs only", function()
    local focus = makeWindow("static_art")
    focus.layers = {
      {
        kind = "tile",
        items = {
          [1] = { _bankIndex = 2, index = 3 },
          [2] = { _bankIndex = 2, index = 4 },
          [3] = { _bankIndex = 1, index = 8 },
        },
      },
    }
    focus.activeLayer = 1
    focus:setSelected(1, 0, 1)

    local bankWindow = makeWindow("chr")
    bankWindow.currentBank = 2

    local ctx = {
      app = {
        winBank = bankWindow,
        appEditState = {
          currentBank = 2,
        },
      },
      wm = function()
        return {
          getFocus = function()
            return focus
          end,
        }
      end,
      getFocus = function()
        return focus
      end,
    }

    local model = SpaceHighlightController.buildSelectionModel(ctx)

    expect(model).toBeTruthy()
    expect(model.bankWindow).toBe(bankWindow)
    expect(model.matchedTileKeys["2:4"]).toBe(true)
    expect(model.matchedTileKeys["2:3"]).toBe(nil)
    expect(model.matchedTileKeys["1:8"]).toBe(nil)
  end)

  it("reports whether a model has any matched keys", function()
    expect(SpaceHighlightController.hasMatchedKeys({
      matchedTileKeys = {
        ["1:2"] = true,
      },
    })).toBe(true)
    expect(SpaceHighlightController.hasMatchedKeys({
      matchedTileKeys = {},
    })).toBe(false)
  end)
end)
