local PPUFrameWindow = require("user_interface.windows_system.ppu_frame_window")

describe("ppu_frame_window.lua - pattern layer toggle navigation", function()
  it("keeps runtime pattern layer out of normal next/prev navigation", function()
    local win = PPUFrameWindow.new(0, 0, 1, { title = "PPU" })
    win.layers = {
      { kind = "tile", items = {} },
      { kind = "sprite", items = {} },
      { kind = "tile", items = {}, _runtimePatternTableRefLayer = true },
    }
    win.activeLayer = 1
    win.patternLayerSoloMode = false

    win:nextLayer()
    expect(win:getActiveLayerIndex()).toBe(2)
    win:nextLayer()
    expect(win:getActiveLayerIndex()).toBe(1)
    win:prevLayer()
    expect(win:getActiveLayerIndex()).toBe(2)

    win:setActiveLayerIndex(3)
    expect(win:getActiveLayerIndex()).toBe(1)
  end)

  it("isolates navigation to runtime pattern layer when solo mode is enabled", function()
    local win = PPUFrameWindow.new(0, 0, 1, { title = "PPU" })
    win.layers = {
      { kind = "tile", items = {} },
      { kind = "sprite", items = {} },
      { kind = "tile", items = {}, _runtimePatternTableRefLayer = true },
    }
    win.activeLayer = 1
    win.patternLayerSoloMode = false

    local ok, reason = win:setPatternLayerSoloMode(true)
    expect(ok).toBe(true)
    expect(reason).toBeNil()
    expect(win.patternLayerSoloMode).toBe(true)
    expect(win.drawOnlyActiveLayer).toBe(true)
    expect(win:getActiveLayerIndex()).toBe(3)

    win:nextLayer()
    expect(win:getActiveLayerIndex()).toBe(3)
    win:prevLayer()
    expect(win:getActiveLayerIndex()).toBe(3)
    win:setActiveLayerIndex(1)
    expect(win:getActiveLayerIndex()).toBe(3)

    local offOk = win:setPatternLayerSoloMode(false)
    expect(offOk).toBe(true)
    expect(win.patternLayerSoloMode).toBe(false)
    expect(win.drawOnlyActiveLayer).toBe(false)
    expect(win:getActiveLayerIndex()).toBe(1)
  end)

  it("refuses to enable solo mode when runtime pattern layer is missing", function()
    local win = PPUFrameWindow.new(0, 0, 1, { title = "PPU" })
    win.layers = {
      { kind = "tile", items = {} },
      { kind = "sprite", items = {} },
    }
    win.activeLayer = 1
    win.patternLayerSoloMode = false

    local ok, reason = win:setPatternLayerSoloMode(true)
    expect(ok).toBe(false)
    expect(reason).toBe("Pattern table layer is not available")
    expect(win.patternLayerSoloMode).toBe(false)
    expect(win:getActiveLayerIndex()).toBe(1)
  end)
end)
