local Window = require("user_interface.windows_system.window")

describe("window.lua - display grid metrics", function()
  it("uses 8x16 grid spacing for sprite layers in 8x16 mode", function()
    local win = Window.new(0, 0, 8, 8, 4, 4, 1, { title = "sprite-grid" })
    win.layers = {
      { kind = "sprite", mode = "8x16" },
    }
    win.activeLayer = 1

    local metrics = win:getDisplayGridMetrics()

    expect(metrics.cellW).toBe(8)
    expect(metrics.cellH).toBe(16)
    expect(metrics.rowStride).toBe(2)
  end)

  it("uses 8x16 grid spacing for chr windows in odd-even order mode", function()
    local win = Window.new(0, 0, 8, 8, 16, 32, 1, { title = "chr-grid" })
    win.kind = "chr"
    win.orderMode = "oddEven"
    win.layers = {
      { kind = "tile" },
    }
    win.activeLayer = 1

    local metrics = win:getDisplayGridMetrics()

    expect(metrics.cellW).toBe(8)
    expect(metrics.cellH).toBe(16)
    expect(metrics.rowStride).toBe(2)
  end)
end)
