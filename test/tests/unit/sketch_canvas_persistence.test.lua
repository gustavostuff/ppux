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
    expect(win.showGrid).toBe("chess")
  end)

  it("persists showGrid attr mode through layout snapshot/restore", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Sketch grid" })
    win._id = "sketch_grid_01"
    win.showGrid = "attr"

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    expect(snapshot.windows[1].showGrid).toBe("attr")

    local built = GameArtWindowBuilderController.buildWindowsFromLayout(snapshot, {
      wm = WM.new(),
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
      decodePatternCanvasSnapshot = GameArtLayoutIOController.decodePatternCanvasSnapshot,
    })
    local restored = built.windowsById["sketch_grid_01"]
    expect(restored).toBeTruthy()
    expect(restored.kind).toBe("sketch_canvas")
    expect(restored.showGrid).toBe("attr")
  end)

  it("persists layer attrMode through layout snapshot/restore", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Sketch attrMode" })
    win._id = "sketch_attr_01"
    win.layers[1].attrMode = true

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    expect(snapshot.windows[1].layers[1].attrMode).toBe(true)

    local built = GameArtWindowBuilderController.buildWindowsFromLayout(snapshot, {
      wm = WM.new(),
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
      decodePatternCanvasSnapshot = GameArtLayoutIOController.decodePatternCanvasSnapshot,
    })
    local restored = built.windowsById["sketch_attr_01"]
    expect(restored).toBeTruthy()
    expect(restored.layers[1].attrMode).toBe(true)
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
    win.nametableAttrBytes = {}
    for i = 1, 64 do
      win.nametableAttrBytes[i] = (i == 1) and 85 or 0
    end
    win.tolerance = 2
    win.reflectPatternTable = true
    win.linkedPatternTableWindowId = "pt_01"
    win.paddingTileIndex = 0

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    local entry = snapshot.windows[1]
    expect(entry.kind).toBe("sketch_canvas")
    expect(entry.layers[1].edits.kind).toBe("canvas_snapshot")
    expect(type(entry.tilesPool)).toBe("table")
    expect(#entry.tilesPool).toBe(1)
    expect(entry.tilesPool[1]).toBe("0,0|8,8")
    expect(entry.nametableBytes.kind).toBe("byte_blob")
    expect(entry.nametableBytes.count).toBe(960)
    local ntData = entry.nametableBytes.data
    if type(ntData) == "table" then
      expect(#ntData >= 1).toBe(true)
      for _, chunk in ipairs(ntData) do
        expect(type(chunk)).toBe("string")
        expect(#chunk > 0).toBe(true)
        expect(#chunk <= 100).toBe(true)
      end
    else
      expect(type(ntData)).toBe("string")
      expect(#ntData > 0).toBe(true)
      expect(#ntData <= 100).toBe(true)
    end
    expect(entry.nametableAttrBytes.kind).toBe("byte_blob")
    expect(entry.nametableAttrBytes.count).toBe(64)
    local attrData = entry.nametableAttrBytes.data
    if type(attrData) == "table" then
      for _, chunk in ipairs(attrData) do
        expect(#chunk <= 100).toBe(true)
      end
    else
      expect(type(attrData)).toBe("string")
      expect(#attrData > 0).toBe(true)
      expect(#attrData <= 100).toBe(true)
    end
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
    expect(restored.nametableBytes[1]).toBe(1)
    expect(restored.nametableBytes[2]).toBe(0)
    expect(#restored.nametableAttrBytes).toBe(64)
    expect(restored.nametableAttrBytes[1]).toBe(85)
    expect(restored.tolerance).toBe(2)
    expect(restored.reflectPatternTable).toBe(true)
    expect(restored.linkedPatternTableWindowId).toBe("pt_01")
    expect(restored.paddingTileIndex).toBe(0)
  end)

  it("loads legacy integer-array nametableBytes from older projects", function()
    local legacyNt = {}
    for i = 1, 960 do
      legacyNt[i] = (i == 5) and 42 or 0
    end
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({
      nametableBytes = legacyNt,
      nametableAttrBytes = { 1, 2, 3 },
    })
    expect(#win.nametableBytes).toBe(960)
    expect(win.nametableBytes[5]).toBe(42)
    expect(#win.nametableAttrBytes).toBe(64)
    expect(win.nametableAttrBytes[1]).toBe(1)
    expect(win.nametableAttrBytes[2]).toBe(2)
    expect(win.nametableAttrBytes[3]).toBe(3)
    expect(win.nametableAttrBytes[4]).toBe(0)
  end)

  it("loads legacy table-form tilesPool from older projects", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({
      tilesPool = {
        { x = 16, y = 24, solidShade = 1, exactSolid = true },
        { x = 32, y = 40 },
      },
    })
    expect(#win.tilesPool).toBe(2)
    expect(win.tilesPool[1].x).toBe(16)
    expect(win.tilesPool[1].y).toBe(24)
    expect(win.tilesPool[1].solidShade).toBe(1)
    expect(win.tilesPool[1].exactSolid).toBe(true)
    expect(win.tilesPool[2].x).toBe(32)
    expect(win.tilesPool[2].y).toBe(40)
  end)

  it("encodeByteBlob / decodeByteBlob round-trip values", function()
    local src = {}
    for i = 1, 960 do
      src[i] = (i * 7) % 256
    end
    local blob, err = GameArtLayoutIOController.encodeByteBlob(src, 960)
    expect(blob).toBeTruthy()
    expect(err).toBeNil()
    expect(blob.kind).toBe("byte_blob")
    expect(type(blob.data)).toBe("table")
    expect(#blob.data > 1).toBe(true)
    for _, chunk in ipairs(blob.data) do
      expect(#chunk <= 100).toBe(true)
    end
    local decoded = assert(GameArtLayoutIOController.decodeByteBlob(blob))
    expect(#decoded).toBe(960)
    expect(decoded[1]).toBe(src[1])
    expect(decoded[100]).toBe(src[100])
    expect(decoded[960]).toBe(src[960])

    -- Legacy single-string data still decodes.
    local joined = table.concat(blob.data, "")
    local legacy = {
      kind = blob.kind,
      compression = blob.compression,
      textEncoding = blob.textEncoding,
      count = blob.count,
      data = joined,
    }
    local decodedLegacy = assert(GameArtLayoutIOController.decodeByteBlob(legacy))
    expect(decodedLegacy[100]).toBe(src[100])
  end)

  it("encodeTilesPool / decodeTilesPool round-trip solid and sample entries", function()
    local Pack = require("controllers.game_art.sketch_canvas_pack_controller")
    local src = {
      { x = 0, y = 0, solidShade = 0, exactSolid = true },
      { x = 128, y = 48 },
      { x = 8, y = 8, solidShade = 2 },
    }
    local encoded = Pack.encodeTilesPool(src)
    expect(type(encoded)).toBe("table")
    expect(#encoded).toBe(1)
    expect(encoded[1]).toBe("0,0,0e|128,48|8,8,2")
    local decoded = Pack.decodeTilesPool(encoded)
    expect(#decoded).toBe(3)
    expect(decoded[1].solidShade).toBe(0)
    expect(decoded[1].exactSolid).toBe(true)
    expect(decoded[2].x).toBe(128)
    expect(decoded[2].y).toBe(48)
    expect(decoded[2].solidShade).toBeNil()
    expect(decoded[3].solidShade).toBe(2)
    expect(decoded[3].exactSolid).toBeNil()
  end)

  it("encodeTilesPool chunks long pools on pipe boundaries under ~100 chars", function()
    local Pack = require("controllers.game_art.sketch_canvas_pack_controller")
    local src = {}
    for i = 0, 39 do
      src[#src + 1] = { x = i * 8, y = (i % 5) * 8 }
    end
    local encoded = Pack.encodeTilesPool(src)
    expect(type(encoded)).toBe("table")
    expect(#encoded > 1).toBe(true)
    for _, chunk in ipairs(encoded) do
      expect(type(chunk)).toBe("string")
      expect(#chunk <= 100).toBe(true)
      expect(chunk:sub(1, 1) ~= "|").toBe(true)
      expect(chunk:sub(-1) ~= "|").toBe(true)
    end
    local decoded = Pack.decodeTilesPool(encoded)
    expect(#decoded).toBe(40)
    expect(decoded[1].x).toBe(0)
    expect(decoded[40].x).toBe(39 * 8)
    -- Single-string form from older saves still loads.
    local joined = table.concat(encoded, "|")
    local fromString = Pack.decodeTilesPool(joined)
    expect(#fromString).toBe(40)
  end)

  it("round-trips solidShade and generateDirty through layout snapshot", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Sketch Solid" })
    win._id = "sketch_solid"
    win.layers[1].canvas:edit(1, 1, 3)
    win.tilesPool = {
      { x = 0, y = 0, solidShade = 0, exactSolid = true },
      { x = 8, y = 8, solidShade = 2 },
    }
    win.nametableBytes = {}
    for i = 1, 960 do
      win.nametableBytes[i] = (i % 2)
    end
    win._generateDirty = true

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    local entry = snapshot.windows[1]
    expect(entry.tilesPool).toEqual({ "0,0,0e|8,8,2" })
    expect(entry.generateDirty).toBe(true)

    local built = GameArtWindowBuilderController.buildWindowsFromLayout(snapshot, {
      wm = WM.new(),
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
      decodePatternCanvasSnapshot = GameArtLayoutIOController.decodePatternCanvasSnapshot,
    })
    local restored = built.windowsById["sketch_solid"]
    expect(restored.tilesPool[1].solidShade).toBe(0)
    expect(restored.tilesPool[1].exactSolid).toBe(true)
    expect(restored.tilesPool[2].solidShade).toBe(2)
    -- Saved generateDirty is recomputed on load; solidShade cells are skipped so pack agrees.
    expect(restored._generateDirty).toBeFalsy()
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
    expect(entry.tilesPool).toEqual({})
    expect(entry.nametableBytes).toBeNil()
    expect(entry.linkedPatternTableWindowId).toBeNil()
    expect(entry.tolerance).toBe(0)
    expect(entry.reflectPatternTable).toBe(false)
    expect(entry.paddingTileIndex).toBe(0)
  end)

  it("persists sketch canvas paletteData.winId links through layout snapshot/restore", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "Sketch Linked" })
    sketch._id = "sketch_pal_link"
    local pal = wm:createRomPaletteWindow({
      title = "Sketch palette",
      paletteRole = "sketch",
    })
    pal._id = "pal_sketch_01"
    sketch.layers[1].paletteData = { winId = pal._id }

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    local entry = nil
    for _, w in ipairs(snapshot.windows) do
      if w.id == "sketch_pal_link" then
        entry = w
        break
      end
    end
    expect(entry).toBeTruthy()
    expect(entry.layers).toBeTruthy()
    expect(entry.layers[1]).toBeTruthy()
    expect(entry.layers[1].paletteData).toBeTruthy()
    expect(entry.layers[1].paletteData.winId).toBe("pal_sketch_01")

    local Factory = require("controllers.game_art.window_factory_controller")
    local restored = Factory.createSketchCanvasWindow(entry, function() return true end)
    expect(restored.layers[1].paletteData).toBeTruthy()
    expect(restored.layers[1].paletteData.winId).toBe("pal_sketch_01")
  end)
end)
