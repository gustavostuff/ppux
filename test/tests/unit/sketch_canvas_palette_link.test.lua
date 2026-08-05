local WM = require("controllers.window.window_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local SketchCanvasGalleryRomController = require("controllers.game_art.sketch_canvas_gallery_rom_controller")
local KeyboardArtActions = require("controllers.input.keyboard_art_actions_controller")
local WindowCaps = require("controllers.window.window_capabilities")

describe("sketch_canvas_palette_link (B5)", function()
  it("creates sketch-mode palettes with free editable cells", function()
    local wm = WM.new()
    local pal = wm:createRomPaletteWindow({
      title = "Sketch palette",
      paletteRole = "sketch",
    })
    expect(pal.paletteRole).toBe("sketch")
    expect(pal:isSketchPalette()).toBe(true)
    expect(pal:isCellEditable(0, 0)).toBe(true)
    expect(pal:isCellEditable(3, 3)).toBe(true)
    expect(pal.codes2D[0][0]).toBe("07")
  end)

  it("creates sketch-mode palettes even when a ROM is loaded (no address read)", function()
    local wm = WM.new()
    local pal = wm:createRomPaletteWindow({
      title = "Sketch palette",
      paletteRole = "sketch",
      -- Non-empty romRaw used to crash initializeFromROMOrUserCodes on "sketch" markers.
      romRaw = string.rep("\0", 64),
    })
    expect(pal:isSketchPalette()).toBe(true)
    expect(pal.codes2D[0][0]).toBe("07")
    expect(pal.codes2D[0][1]).toBe("17")
    expect(pal:isCellEditable(0, 0)).toBe(true)
  end)

  it("allows adjusting sketch-mode palette colors without ROM addresses", function()
    local wm = WM.new()
    local pal = wm:createRomPaletteWindow({
      title = "Sketch palette",
      paletteRole = "sketch",
      romRaw = string.rep("\0", 64),
    })
    pal:setSelected(0, 0)
    local before = pal.codes2D[0][0]
    expect(before).toBe("07")
    pal:adjustSelectedByArrows(1, 0)
    expect(pal.codes2D[0][0]).toBe("08")
    -- Universal backdrop: all rows' color 0 stay in sync.
    for row = 0, 3 do
      expect(pal.codes2D[row][0]).toBe("08")
    end
    pal:adjustSelectedByArrows(0, 1)
    expect(pal.codes2D[0][0]).toBe("18")
    for row = 0, 3 do
      expect(pal.codes2D[row][0]).toBe("18")
    end
  end)

  it("syncs sketch palette color 0 across rows and sketch palette windows", function()
    local wm = WM.new()
    local palA = wm:createRomPaletteWindow({ title = "Sketch A", paletteRole = "sketch" })
    local palB = wm:createRomPaletteWindow({ title = "Sketch B", paletteRole = "sketch" })
    local previousCtx = rawget(_G, "ctx")
    rawset(_G, "ctx", { app = { wm = wm } })

    for row = 0, 3 do
      palA.codes2D[row][0] = "07"
      palA:set(0, row, "07")
      palB.codes2D[row][0] = "0F"
      palB:set(0, row, "0F")
    end
    palA:setSelected(0, 0)
    palA:adjustSelectedByArrows(1, 0) -- 07 -> 08
    for row = 0, 3 do
      expect(palA.codes2D[row][0]).toBe("08")
      expect(palB.codes2D[row][0]).toBe("08")
    end

    local col1BeforeB = palB.codes2D[0][1]
    palA:setSelected(1, 0)
    local col1BeforeA = palA.codes2D[0][1]
    palA:adjustSelectedByArrows(1, 0)
    expect(palA.codes2D[0][1]).toNotBe(col1BeforeA)
    expect(palB.codes2D[0][1]).toBe(col1BeforeB)
    rawset(_G, "ctx", previousCtx)
  end)

  it("normalizes divergent sketch color-0 values on load", function()
    local RomPaletteWindow = require("user_interface.windows_system.rom_palette_window")
    local pal = RomPaletteWindow.new(0, 0, 1, "smooth_fbx", 4, 4, {
      title = "Sketch palette",
      paletteRole = "sketch",
      paletteData = {
        romColors = {
          { "sketch", "sketch", "sketch", "sketch" },
          { "sketch", "sketch", "sketch", "sketch" },
          { "sketch", "sketch", "sketch", "sketch" },
          { "sketch", "sketch", "sketch", "sketch" },
        },
        userDefinedCode = {
          { row = 0, col = 0, code = "0F" },
          { row = 1, col = 0, code = "07" },
          { row = 2, col = 0, code = "09" },
          { row = 0, col = 1, code = "15" },
        },
      },
    })
    for row = 0, 3 do
      expect(pal.codes2D[row][0]).toBe("0F")
    end
    expect(pal.codes2D[0][1]).toBe("15")
  end)

  it("links sketch canvas to sketch palette and defaults attrs to row 0", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "S" })
    local romPal = wm:createRomPaletteWindow({ title = "ROM", paletteRole = "rom" })
    local sketchPal = wm:createRomPaletteWindow({ title = "Sketch pal", paletteRole = "sketch" })

    local okRom, errRom = PaletteLinkController.linkLayerToPalette(sketch, 1, romPal)
    expect(okRom).toBe(false)
    expect(type(errRom) == "string" and errRom:find("sketch-mode", 1, true) ~= nil).toBe(true)

    expect(PaletteLinkController.linkLayerToPalette(sketch, 1, sketchPal)).toBe(true)
    local layer = sketch.layers[1]
    expect(layer.paletteData.winId).toBe(sketchPal._id)
    expect(#sketch.nametableAttrBytes).toBe(64)
    for i = 1, 64 do
      expect(sketch.nametableAttrBytes[i]).toBe(0)
    end
    expect(SketchPalette.getLinkedSketchPalette(sketch, wm)).toBe(sketchPal)
  end)

  it("rejects linking sketch-mode palette to non-sketch windows", function()
    local sketchPal = {
      _id = "pal_sketch_1",
      kind = "rom_palette",
      paletteRole = "sketch",
      title = "Sketch pal",
      _closed = false,
    }
    local static = {
      kind = "static_art",
      title = "Art",
      activeLayer = 1,
      layers = {
        { kind = "tile", name = "Tiles" },
      },
      getActiveLayerIndex = function(self)
        return self.activeLayer or 1
      end,
    }
    local ok, err = PaletteLinkController.linkLayerToPalette(static, 1, sketchPal)
    expect(ok).toBe(false)
    expect(type(err) == "string" and err:find("sketch canvases", 1, true) ~= nil).toBe(true)
  end)

  it("tile mode keys 1-4 write attribute quadrants", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "Reflect" })
    local canvas = sketch:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 1)
      end
    end
    expect(SketchCanvasPackController.generate(sketch)).toBe(true)
    SketchPalette.ensureAttrBytes(sketch)

    local prev = rawget(_G, "ctx")
    rawset(_G, "ctx", { getMode = function() return "tile" end })

    local layer = sketch.layers[1]
    sketch:setSelected(0, 0, 1)
    expect(WindowCaps.isSketchReflectNametable(sketch)).toBe(true)
    expect(NametableTilesController.setPaletteNumberForTile(sketch, layer, 0, 0, 2)).toBe(true)
    expect(sketch.nametableAttrBytes[1]).toBe(0x01)

    local ctx = {
      getMode = function()
        return "tile"
      end,
      app = { undoRedo = nil },
      setStatus = function() end,
    }
    expect(KeyboardArtActions.handlePaletteNumberAssignment(ctx, "4", sketch, {})).toBe(true)
    expect(sketch.nametableAttrBytes[1]).toBe(0x03)
    rawset(_G, "ctx", prev)
  end)

  it("gallery writeSlideAssets writes main.pal per slide", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "G" })
    local canvas = sketch:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 2)
      end
    end
    expect(SketchCanvasPackController.generate(sketch)).toBe(true)
    local pal = wm:createRomPaletteWindow({ title = "P", paletteRole = "sketch" })
    pal.codes2D[0][1] = "22"
    expect(PaletteLinkController.linkLayerToPalette(sketch, 1, pal)).toBe(true)

    local tmp = os.tmpname()
    os.remove(tmp)
    local asmDir = tmp .. "_gallery"
    os.execute("mkdir -p '" .. asmDir .. "'")
    -- Minimal Makefile so resolve paths aren't needed; writeSlideAssets only needs dirs.
    local ok, n = SketchCanvasGalleryRomController.writeSlideAssets(asmDir, { sketch }, wm)
    expect(ok).toBe(true)
    expect(n).toBe(1)

    local palPath = asmDir .. "/data/pal/slide00/main.pal"
    local fh = assert(io.open(palPath, "rb"))
    local blob = fh:read("*a")
    fh:close()
    expect(#blob).toBe(32)
    expect(string.byte(blob, 2)).toBe(0x22)

    -- Cleanup
    os.execute("rm -rf '" .. asmDir .. "'")
  end)
end)
