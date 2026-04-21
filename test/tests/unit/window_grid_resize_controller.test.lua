local GridResize = require("controllers.window.window_grid_resize_controller")

describe("window_grid_resize_controller", function()
  it("remaps paletteNumbers when adding a column (0-based linear keys)", function()
    local win = {
      cols = 10,
      rows = 2,
      visibleCols = 10,
      layers = {
        {
          kind = "tile",
          items = {},
          paletteNumbers = { [15] = 3 }, -- (col 5, row 1): 1 * 10 + 5
        },
      },
      setScroll = function() end,
    }
    GridResize.addColumn(win)
    expect(win.cols).toBe(11)
    local L = win.layers[1]
    expect(L.paletteNumbers[15]).toBe(nil)
    expect(L.paletteNumbers[16]).toBe(3) -- 1 * 11 + 5
  end)

  it("remaps paletteNumbers when removing the last column", function()
    local win = {
      cols = 11,
      rows = 2,
      visibleCols = 11,
      layers = {
        {
          kind = "tile",
          items = {},
          paletteNumbers = { [16] = 2 }, -- (5, 1) on 11-wide grid
        },
      },
      setScroll = function() end,
    }
    local ok = GridResize.removeLastColumn(win)
    expect(ok).toBe(true)
    expect(win.cols).toBe(10)
    local L = win.layers[1]
    expect(L.paletteNumbers[16]).toBe(nil)
    expect(L.paletteNumbers[15]).toBe(2)
  end)
end)
