local NametableHelpers = require("user_interface.windows_system.ppu_frame_nametable_helpers")
local PPUFrameWindow = require("user_interface.windows_system.ppu_frame_window")

describe("ppu_frame_nametable_helpers.lua", function()
  it("maps grid coordinates to linear indices", function()
    expect(NametableHelpers.lin(32, 0, 0)).toBe(1)
    expect(NametableHelpers.lin(32, 1, 0)).toBe(2)
    expect(NametableHelpers.lin(32, 0, 1)).toBe(33)
  end)

  it("finds the active nametable layer", function()
    local win = {
      activeLayer = 2,
      layers = {
        { kind = "sprite", items = {} },
        { kind = "tile", items = {} },
      },
    }
    local layer, idx = NametableHelpers.getNametableLayer(win)
    expect(layer.kind).toBe("tile")
    expect(idx).toBe(2)
  end)

  it("decodes palette numbers from attribute bytes", function()
    local win = {
      cols = 32,
      nametableAttrBytes = { 0x00 },
    }
    expect(NametableHelpers.decodePaletteNumberFromAttributes(win, 0, 0)).toBe(1)
  end)
end)

describe("ppu_frame_nametable_canvas.lua", function()
  it("installs canvas invalidation methods on PPU frame windows", function()
    local win = PPUFrameWindow.new(0, 0, 1, { title = "PPU" })
    expect(type(win.invalidateNametableLayerCanvas)).toBe("function")
    expect(type(win.drawNametableLayerCanvas)).toBe("function")
    expect(win:invalidateNametableLayerCanvas(1, 0, 0)).toBe(true)
  end)
end)
