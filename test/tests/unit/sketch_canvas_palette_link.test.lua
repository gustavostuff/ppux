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

  it("syncs sketch palette color 0 across rows within the same window only", function()
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
      -- Other sketch palettes keep their own column 0.
      expect(palB.codes2D[row][0]).toBe("0F")
    end

    local col1BeforeB = palB.codes2D[0][1]
    palA:setSelected(1, 0)
    local col1BeforeA = palA.codes2D[0][1]
    palA:adjustSelectedByArrows(1, 0)
    expect(palA.codes2D[0][1]).toNotBe(col1BeforeA)
    expect(palB.codes2D[0][1]).toBe(col1BeforeB)
    rawset(_G, "ctx", previousCtx)
  end)

  it("undo of sketch palette color does not wipe the palette to black", function()
    local UndoRedoController = require("controllers.input_support.undo_redo_controller")
    local wm = WM.new()
    local ur = UndoRedoController.new(20)
    local pal = wm:createRomPaletteWindow({ title = "Sketch palette", paletteRole = "sketch" })
    local previousCtx = rawget(_G, "ctx")
    local app = { wm = wm, undoRedo = ur }
    rawset(_G, "ctx", { app = app })

    -- Customize several cells so undo must restore more than defaults.
    pal:setSelected(1, 0)
    pal:adjustSelectedByArrows(1, 0) -- 17 -> 18
    expect(pal.codes2D[0][1]).toBe("18")
    pal:setSelected(2, 1)
    pal:adjustSelectedByArrows(0, 1) -- 27 -> 37
    expect(pal.codes2D[1][2]).toBe("37")
    pal:setSelected(0, 0)
    pal:adjustSelectedByArrows(1, 0) -- color0 07 -> 08 (synced)

    local snapshot = {}
    for row = 0, 3 do
      snapshot[row] = {}
      for col = 0, 3 do
        snapshot[row][col] = pal.codes2D[row][col]
      end
    end

    -- Undo color0 change: must restore previous palette, not all 0F.
    expect(ur:undo(app)).toBe(true)
    expect(pal.codes2D[0][0]).toBe("07")
    for row = 0, 3 do
      expect(pal.codes2D[row][0]).toBe("07")
    end
    expect(pal.codes2D[0][1]).toBe("18")
    expect(pal.codes2D[1][2]).toBe("37")
    -- Default sketch colors must still be present (not wiped to black).
    expect(pal.codes2D[0][2]).toBe("27")
    expect(pal.codes2D[0][3]).toBe("36")
    expect(pal.codes2D[2][1]).toBe("17")

    expect(ur:redo(app)).toBe(true)
    for row = 0, 3 do
      for col = 0, 3 do
        expect(pal.codes2D[row][col]).toBe(snapshot[row][col])
      end
    end

    rawset(_G, "ctx", previousCtx)
  end)

  it("normalizes divergent sketch color-0 values on load", function()
    local RomPaletteWindow = require("ui.windows_system.rom_palette_window")
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
    local pt = wm:createPatternTableWindow()
    local canvas = sketch:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 1)
      end
    end
    expect(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm)).toBe(true)
    expect(SketchCanvasPackController.generate(sketch)).toBe(true)
    SketchPalette.ensureAttrBytes(sketch)

    local prev = rawget(_G, "ctx")
    rawset(_G, "ctx", {
      getMode = function()
        return "tile"
      end,
      app = { wm = wm },
      wm = function()
        return wm
      end,
    })

    local layer = sketch.layers[1]
    sketch:setSelected(0, 0, 1)
    expect(WindowCaps.isSketchReflectNametable(sketch)).toBe(true)
    expect(NametableTilesController.setPaletteNumberForTile(sketch, layer, 0, 0, 2)).toBe(true)
    expect(sketch.nametableAttrBytes[1]).toBe(0x01)

    local ctx = {
      getMode = function()
        return "tile"
      end,
      app = { undoRedo = nil, wm = wm },
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

    local fadePath = asmDir .. "/data/pal/slide00/fade_out.pal"
    local ff = assert(io.open(fadePath, "rb"))
    local fadeBlob = ff:read("*a")
    ff:close()
    expect(#fadeBlob).toBe(128)
    for i = 97, 128 do
      expect(string.byte(fadeBlob, i)).toBe(0x0F)
    end

    -- Cleanup
    os.execute("rm -rf '" .. asmDir .. "'")
  end)

  it("unlinking sketch palette keeps attrs and treats palette as gone (brown draw path)", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "S" })
    local pal = wm:createRomPaletteWindow({ title = "Sketch pal", paletteRole = "sketch" })
    local prev = rawget(_G, "ctx")
    rawset(_G, "ctx", { app = { wm = wm } })

    expect(PaletteLinkController.linkLayerToPalette(sketch, 1, pal)).toBe(true)
    sketch.nametableAttrBytes[1] = 0x03
    expect(SketchPalette.getLinkedSketchPalette(sketch, wm)).toBe(pal)

    expect(PaletteLinkController.removeLinkForLayer(sketch, 1)).toBe(true)
    expect(SketchPalette.getLinkedSketchPalette(sketch, wm)).toBeNil()
    expect(sketch.nametableAttrBytes[1]).toBe(0x03)
    expect(SketchPalette.DEFAULT_BROWN_CODES[1]).toBe("07")
    expect(SketchPalette.DEFAULT_BROWN_CODES[2]).toBe("17")
    expect(SketchPalette.DEFAULT_BROWN_CODES[3]).toBe("27")
    expect(SketchPalette.DEFAULT_BROWN_CODES[4]).toBe("36")

    rawset(_G, "ctx", prev)
  end)

  it("closing linked sketch palette keeps winId but getLinkedSketchPalette returns nil", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "S" })
    local pal = wm:createRomPaletteWindow({ title = "Sketch pal", paletteRole = "sketch" })
    expect(PaletteLinkController.linkLayerToPalette(sketch, 1, pal)).toBe(true)
    SketchPalette.ensureAttrBytes(sketch)
    sketch.nametableAttrBytes[2] = 0x02

    assert(wm:closeWindow(pal))
    expect(sketch.layers[1].paletteData.winId).toBe(pal._id)
    expect(SketchPalette.getLinkedSketchPalette(sketch, wm)).toBeNil()
    expect(sketch.nametableAttrBytes[2]).toBe(0x02)

    assert(wm:reopenWindow(pal))
    expect(SketchPalette.getLinkedSketchPalette(sketch, wm)).toBe(pal)
  end)

  it("encodePaletteBlob32 falls back to brown when palette is missing", function()
    local blob = SketchPalette.encodePaletteBlob32(nil)
    expect(#blob).toBe(32)
    expect(blob[1]).toBe(0x07)
    expect(blob[2]).toBe(0x17)
    expect(blob[3]).toBe(0x27)
    expect(blob[4]).toBe(0x36)
  end)

  it("darkenNesColor steps brightness and handles special columns", function()
    expect(SketchPalette.darkenNesColor(0x30)).toBe(0x20)
    expect(SketchPalette.darkenNesColor(0x22)).toBe(0x12)
    expect(SketchPalette.darkenNesColor(0x0A)).toBe(0x0F)
    expect(SketchPalette.darkenNesColor(0x3D)).toBe(0x2D)
    expect(SketchPalette.darkenNesColor(0x2D)).toBe(0x0F)
    expect(SketchPalette.darkenNesColor(0x0D)).toBe(0x0F)
    expect(SketchPalette.darkenNesColor(0x0E)).toBe(0x0F)
    expect(SketchPalette.darkenNesColor(0x0F)).toBe(0x0F)
    expect(SketchPalette.darkenNesColor(0x1E)).toBe(0x0F)
  end)

  it("buildFadeOutPaletteBlob is 128 bytes ending in all 0F with sprite BG0 mirror", function()
    local main = SketchPalette.encodePaletteBlob32(nil)
    local fade = SketchPalette.buildFadeOutPaletteBlob(main)
    expect(#fade).toBe(SketchPalette.FADE_OUT_BYTES)
    expect(SketchPalette.FADE_OUT_BYTES).toBe(128)

    -- First step: brown ramp darkened once.
    expect(fade[1]).toBe(0x0F) -- 07 -> 0F
    expect(fade[2]).toBe(0x07) -- 17 -> 07
    expect(fade[3]).toBe(0x17) -- 27 -> 17
    expect(fade[4]).toBe(0x26) -- 36 -> 26
    expect(fade[17]).toBe(fade[1]) -- sprite color-0 mirrors BG0

    -- Last step: all black.
    for i = 97, 128 do
      expect(fade[i]).toBe(0x0F)
    end
  end)
end)
