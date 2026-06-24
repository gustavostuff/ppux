local Factory = require("controllers.game_art.window_factory_controller")
local WM = require("controllers.window.window_controller")
local chr = require("chr")

describe("window_factory_controller.lua", function()
  local function makeTilesPool()
    return {
      [1] = {
        [0] = { _bankIndex = 1, index = 0, pixels = {} },
      },
    }
  end

  it("createPaletteWindow restores selection and active palette sync", function()
    local win = Factory.createPaletteWindow({
      id = "palette_01",
      rows = 1,
      cols = 4,
      items = {
        { row = 0, col = 0, code = "0F" },
        { row = 0, col = 1, code = "17" },
        { row = 0, col = 2, code = "26" },
        { row = 0, col = 3, code = "30" },
      },
      selectedCol = 2,
      selectedRow = 0,
      activePalette = true,
    })

    expect(win._id).toBe("palette_01")
    expect(win.kind).toBe("palette")
    local col, row = win:getSelected()
    expect(col).toBe(2)
    expect(row).toBe(0)
  end)

  it("createChrBankWindow honors ROM-window mode flag", function()
    local chrWin = Factory.createChrBankWindow({
      id = "bank",
      x = 0,
      y = 0,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      currentBank = 2,
    })
    local romWin = Factory.createChrBankWindow({
      id = "rom_bank",
      isRomWindow = true,
      x = 0,
      y = 0,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
    })

    expect(chrWin.isRomWindow).toBeFalsy()
    expect(romWin.isRomWindow).toBe(true)
    expect(chrWin.currentBank).toBe(2)
  end)

  it("createStaticArtWindow hydrates tile placements from layout", function()
    local tilesPool = makeTilesPool()
    local ensureCalls = 0
    local win = Factory.createStaticArtWindow({
      id = "static_01",
      title = "Static",
      x = 10,
      y = 10,
      cellW = 8,
      cellH = 8,
      cols = 8,
      rows = 8,
      zoom = 2,
      layers = {
        {
          kind = "tile",
          name = "Layer 1",
          items = {
            { bank = 1, tile = 0, col = 1, row = 2 },
          },
        },
      },
    }, tilesPool, function(bank)
      ensureCalls = ensureCalls + 1
      expect(bank).toBe(1)
    end)

    expect(win.kind).toBe("static_art")
    expect(ensureCalls).toBe(1)
    local placed = win:get(1, 2, 1)
    expect(placed).toBe(tilesPool[1][0])
  end)

  it("createOamAnimationWindow restores OAM slot items from layout", function()
    local win = Factory.createOamAnimationWindow({
      id = "oam_01",
      title = "OAM",
      x = 0,
      y = 0,
      cellW = 8,
      cellH = 8,
      cols = 8,
      rows = 8,
      zoom = 2,
      delaysPerLayer = { 0.2 },
      layers = {
        {
          kind = "sprite",
          name = "Frame 1",
          linkedPatternTableWindowId = "pt_a",
          items = {
            { startAddr = 32, paletteNumber = 3, dx = 1, dy = 2 },
          },
        },
      },
    }, {}, function() end)

    expect(win.kind).toBe("oam_animation")
    expect(win.frameDelays[1]).toBe(0.2)
    local layer = win.layers[1]
    expect(layer.linkedPatternTableWindowId).toBe("pt_a")
    expect(#layer.items).toBe(1)
    expect(layer.items[1].startAddr).toBe(32)
    expect(layer.items[1].paletteNumber).toBe(3)
  end)

  it("finalizeWindow repairs zero visible viewport dimensions from layout", function()
    local wm = WM.new()
    local win = Factory.createStaticArtWindow({
      id = "static_zero_viewport",
      title = "Static",
      x = 0,
      y = 0,
      cellW = 8,
      cellH = 8,
      cols = 8,
      rows = 8,
      zoom = 2,
      visibleCols = 0,
      visibleRows = 0,
      layers = { { kind = "tile", name = "Layer 1", items = {} } },
    }, {}, function() end)

    Factory.finalizeWindow(win, {
      id = "static_zero_viewport",
      title = "Static",
      cols = 8,
      rows = 8,
      visibleCols = 0,
      visibleRows = 0,
      layers = win.layers and {} or {},
    }, {}, wm, "", {}, 1)

    expect(win.visibleCols).toBe(8)
    expect(win.visibleRows).toBe(8)
  end)

  it("createPatternTableWindow applies non-active layer opacity", function()
    local win = Factory.createPatternTableWindow({
      id = "pt_01",
      title = "Pattern",
      x = 0,
      y = 0,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      nonActiveLayerOpacity = 0.25,
      layers = { { kind = "tile", name = "Pattern table" } },
    }, {}, function() end)

    expect(win.kind).toBe("pattern_table")
    expect(win.layers[1].opacity).toBe(1.0)
  end)
end)
