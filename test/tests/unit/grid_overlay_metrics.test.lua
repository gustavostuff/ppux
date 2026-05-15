local GridOverlay = require("controllers.window.grid_overlay_metrics")
local Window = require("user_interface.windows_system.window")

describe("grid_overlay_metrics — chess band height", function()
  it("uses doubled vertical period on CHR banks in oddEven mode", function()
    local win = Window.new(0, 0, 8, 8, 16, 32, 1, { title = "chr" })
    win.kind = "chr"
    win.orderMode = "oddEven"
    win.layers = { { kind = "tile", name = "Bank" } }
    win.activeLayer = 1
    local grid = win:getDisplayGridMetrics()
    expect(GridOverlay.overlayVerticalPeriodNes(win, grid)).toBe(16)
    expect(GridOverlay.chessNominalRowSkip(win, grid)).toBe(2)
  end)

  it("uses doubled vertical period on pattern_table tile layer in 8x16 mode", function()
    local win = Window.new(0, 0, 8, 8, 16, 16, 1, { title = "pt" })
    win.kind = "pattern_table"
    win.layers = { { kind = "tile", mode = "8x16", name = "Pattern table" } }
    win.activeLayer = 1
    local grid = win:getDisplayGridMetrics()
    expect(GridOverlay.overlayVerticalPeriodNes(win, grid)).toBe(16)
    expect(GridOverlay.chessNominalRowSkip(win, grid)).toBe(2)
  end)

  it("keeps nominal row stride 1 when metrics already doubled (static_art tile 8x16)", function()
    local win = Window.new(0, 0, 8, 8, 16, 16, 1, { title = "sa" })
    win.kind = "static_art"
    win.layers = { { kind = "tile", mode = "8x16", name = "L1" } }
    win.activeLayer = 1
    local grid = win:getDisplayGridMetrics()
    expect(grid.cellH).toBe(16)
    expect(GridOverlay.overlayVerticalPeriodNes(win, grid)).toBe(16)
    expect(GridOverlay.chessNominalRowSkip(win, grid)).toBe(1)
  end)
end)
