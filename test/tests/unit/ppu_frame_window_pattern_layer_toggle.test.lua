local PPUFrameWindow = require("user_interface.windows_system.ppu_frame_window")

local FULL_PATTERN_TABLE = {
  ranges = {
    {
      bank = 1,
      page = 1,
      tileRange = { from = 0, to = 255 },
    },
  },
}

--- PatternLayerGate locks navigation unless nametable ranges + grid + patterns are sane.
local function hydrateForLayerNavigation(win)
  local cols = win.cols or 32
  local rows = win.rows or 30
  local need = math.max(1, cols * rows)
  for i = 1, need do
    if win.nametableBytes[i] == nil then
      win.nametableBytes[i] = 0
    end
  end
  for _, layer in ipairs(win.layers or {}) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      if type(layer.nametableStartAddr) ~= "number" then
        layer.nametableStartAddr = 0x2000
      end
      if type(layer.nametableEndAddr) ~= "number" then
        layer.nametableEndAddr = layer.nametableStartAddr + need - 1
      end
      if type(layer.patternTable) ~= "table" then
        layer.patternTable = FULL_PATTERN_TABLE
      end
    elseif layer and layer.kind == "sprite" then
      if type(layer.patternTable) ~= "table" then
        layer.patternTable = FULL_PATTERN_TABLE
      end
    end
  end
end

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
    hydrateForLayerNavigation(win)

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
    hydrateForLayerNavigation(win)

    local ok, reason = win:setPatternLayerSoloMode(true)
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
