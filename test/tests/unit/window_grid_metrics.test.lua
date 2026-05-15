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

  it("keeps 8px layout metrics for CHR windows in odd-even order mode", function()
    local win = Window.new(0, 0, 8, 8, 16, 32, 1, { title = "chr-grid" })
    win.kind = "chr"
    win.orderMode = "oddEven"
    win.layers = {
      { kind = "tile" },
    }
    win.activeLayer = 1

    local metrics = win:getDisplayGridMetrics()

    expect(metrics.cellW).toBe(8)
    expect(metrics.cellH).toBe(8)
    expect(metrics.rowStride).toBe(1)

    win.visibleCols = 16
    win.visibleRows = 32
    local vw, vh = win:getVisibleSize()
    expect(vw).toBe(16 * 8)
    expect(vh).toBe(32 * 8)
  end)

  it("keeps 8px layout for pattern_table windows in tile 8x16 layout mode (CHR reorder, no stretch)", function()
    local win = Window.new(0, 0, 8, 8, 16, 16, 1, { title = "pattern-table" })
    win.kind = "pattern_table"
    win.layers = {
      { kind = "tile", mode = "8x16" },
    }
    win.activeLayer = 1
    win.visibleCols = 16
    win.visibleRows = 16

    local metrics = win:getDisplayGridMetrics()
    expect(metrics.cellW).toBe(8)
    expect(metrics.cellH).toBe(8)
    expect(metrics.rowStride).toBe(1)

    local vw, vh = win:getVisibleSize()
    expect(vw).toBe(16 * 8)
    expect(vh).toBe(16 * 8)
  end)

  it("sizes the viewport using 8x16 spacing for tile layers in 8x16 mode", function()
    local win = Window.new(0, 0, 8, 8, 16, 16, 1, { title = "pattern-like" })
    win.visibleCols = 16
    win.visibleRows = 16
    win.layers = {
      { kind = "tile", mode = "8x16" },
    }
    win.activeLayer = 1

    local vw, vh = win:getVisibleSize()
    expect(vw).toBe(16 * 8)
    expect(vh).toBe(16 * 16)
  end)
end)
