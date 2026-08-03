local WM = require("controllers.window.window_controller")
local GameArtLayoutIOController = require("controllers.game_art.layout_io_controller")
local GameArtWindowBuilderController = require("controllers.game_art.window_builder_controller")

describe("sketch canvas - data model + persistence", function()
  it("defaults pack/link fields on a new sketch canvas window", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    expect(win.kind).toBe("sketch_canvas")
    expect(type(win.tilesPool)).toBe("table")
    expect(#win.tilesPool).toBe(0)
    expect(win.nametableBytes).toBeNil()
    expect(win.tolerance).toBe(0)
    expect(win.reflectPatternTable).toBe(false)
    expect(win.linkedPatternTableWindowId).toBeNil()
    expect(win.paddingTileIndex).toBe(0)
  end)

  it("accepts pack/link fields through createSketchCanvasWindow opts", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({
      tilesPool = {
        { x = 8, y = 16 },
        { x = 24, y = 0 },
      },
      nametableBytes = { 0, 1, 0, 1 },
      tolerance = 3,
      reflectPatternTable = true,
      linkedPatternTableWindowId = "pt_sketch_01",
      paddingTileIndex = 1,
    })
    expect(#win.tilesPool).toBe(2)
    expect(win.tilesPool[1].x).toBe(8)
    expect(win.tilesPool[1].y).toBe(16)
    expect(win.tilesPool[2].x).toBe(24)
    expect(win.tilesPool[2].y).toBe(0)
    expect(#win.nametableBytes).toBe(4)
    expect(win.nametableBytes[2]).toBe(1)
    expect(win.tolerance).toBe(3)
    expect(win.reflectPatternTable).toBe(true)
    expect(win.linkedPatternTableWindowId).toBe("pt_sketch_01")
    expect(win.paddingTileIndex).toBe(1)
  end)

  it("round-trips sketch pack fields through layout snapshot without storing pool pixels", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Sketch A" })
    win._id = "sketch_a"
    win.layers[1].canvas:edit(0, 0, 2)
    win.tilesPool = {
      { x = 0, y = 0 },
      { x = 8, y = 8 },
    }
    win.nametableBytes = {}
    for i = 1, 960 do
      win.nametableBytes[i] = (i % 2)
    end
    win.tolerance = 2
    win.reflectPatternTable = true
    win.linkedPatternTableWindowId = "pt_01"
    win.paddingTileIndex = 0

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    local entry = snapshot.windows[1]
    expect(entry.kind).toBe("sketch_canvas")
    expect(entry.layers[1].edits.kind).toBe("canvas_snapshot")
    expect(#entry.tilesPool).toBe(2)
    expect(entry.tilesPool[1].x).toBe(0)
    expect(entry.tilesPool[1].y).toBe(0)
    expect(entry.tilesPool[1].pixels).toBeNil()
    expect(#entry.nametableBytes).toBe(960)
    expect(entry.nametableBytes[1]).toBe(1)
    expect(entry.tolerance).toBe(2)
    expect(entry.reflectPatternTable).toBe(true)
    expect(entry.linkedPatternTableWindowId).toBe("pt_01")
    expect(entry.paddingTileIndex).toBe(0)

    local built = GameArtWindowBuilderController.buildWindowsFromLayout(snapshot, {
      wm = WM.new(),
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
      decodePatternCanvasSnapshot = GameArtLayoutIOController.decodePatternCanvasSnapshot,
    })
    local restored = built.windowsById["sketch_a"]
    expect(restored).toBeTruthy()
    expect(restored.layers[1].canvas:getPixel(0, 0)).toBe(2)
    expect(#restored.tilesPool).toBe(2)
    expect(restored.tilesPool[2].x).toBe(8)
    expect(restored.tilesPool[2].y).toBe(8)
    expect(#restored.nametableBytes).toBe(960)
    expect(restored.nametableBytes[2]).toBe(0)
    expect(restored.tolerance).toBe(2)
    expect(restored.reflectPatternTable).toBe(true)
    expect(restored.linkedPatternTableWindowId).toBe("pt_01")
    expect(restored.paddingTileIndex).toBe(0)
  end)

  it("omits empty nametableBytes and blank link id from the snapshot", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Sketch B" })
    win._id = "sketch_b"
    win.tilesPool = {}
    win.nametableBytes = nil
    win.linkedPatternTableWindowId = nil

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    local entry = snapshot.windows[1]
    expect(entry.tilesPool).toBeTruthy()
    expect(#entry.tilesPool).toBe(0)
    expect(entry.nametableBytes).toBeNil()
    expect(entry.linkedPatternTableWindowId).toBeNil()
    expect(entry.tolerance).toBe(0)
    expect(entry.reflectPatternTable).toBe(false)
    expect(entry.paddingTileIndex).toBe(0)
  end)
end)
