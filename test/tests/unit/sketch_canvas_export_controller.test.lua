local chr = require("chr")
local SketchCanvasExportController = require("controllers.game_art.sketch_canvas_export_controller")
local SketchCanvasGalleryRomController = require("controllers.game_art.sketch_canvas_gallery_rom_controller")
local WM = require("controllers.window.window_controller")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")

describe("chr.encodeTile", function()
  it("round-trips with decodeTile", function()
    local pixels = {}
    for i = 1, 64 do
      pixels[i] = (i * 3) % 4
    end
    local bytes, err = chr.encodeTile(pixels)
    expect(err).toBeNil()
    expect(#bytes).toBe(16)

    local bank = {}
    for i = 1, 16 do
      bank[i] = bytes[i]
    end
    local decoded = chr.decodeTile(bank, 0)
    expect(decoded).toBeTruthy()
    for i = 1, 64 do
      expect(decoded[i]).toBe(pixels[i])
    end
  end)
end)

describe("sketch_canvas_export_controller.lua - scaffold", function()
  it("builds default paths beside the ROM", function()
    local app = {
      appEditState = {
        romOriginalPath = "/tmp/games/demo.nes",
      },
    }
    local win = { title = "My Sketch!" }
    expect(SketchCanvasExportController.defaultExportDir(app)).toBe("/tmp/games")
    expect(SketchCanvasExportController.defaultChrPath(app, win)).toBe("/tmp/games/My_Sketch.chr")
    expect(SketchCanvasExportController.defaultNametablePath(app, win)).toBe("/tmp/games/My_Sketch.nam")
  end)

  it("prefers the saved project folder over the ROM folder for exports", function()
    local app = {
      projectPath = "/home/g/art/gallery.lua",
      encodedProjectPath = "/home/g/art/gallery.ppux",
      appEditState = {
        romOriginalPath = "/tmp/games/demo.nes",
      },
    }
    expect(SketchCanvasExportController.defaultExportDir(app)).toBe("/home/g/art")
    expect(SketchCanvasGalleryRomController.defaultOutPath(app)).toBe("/home/g/art/gallery_gallery.nes")
  end)

  it("uses the encoded project folder when only .ppux is set", function()
    local app = {
      encodedProjectPath = "/tmp/sketches/my_slides.ppux",
    }
    expect(SketchCanvasExportController.defaultExportDir(app)).toBe("/tmp/sketches")
    expect(SketchCanvasGalleryRomController.defaultOutPath(app)).toBe("/tmp/sketches/my_slides_gallery.nes")
  end)

  it("pads a 4KB bank to 8KB", function()
    local four = string.rep("\1", 4096)
    local eight, err = SketchCanvasExportController.padChrBankTo8KiB(four)
    expect(err).toBeNil()
    expect(#eight).toBe(8192)
    expect(eight:sub(1, 4096)).toBe(four)
    expect(eight:sub(4097)).toBe(string.rep("\0", 4096))
  end)

  it("writes binary files", function()
    local path = os.tmpname()
    local ok, out = SketchCanvasExportController.writeBinaryFile(path, "ABC")
    expect(ok).toBe(true)
    expect(out).toBe(path)
    local fh = assert(io.open(path, "rb"))
    local data = fh:read("*a")
    fh:close()
    os.remove(path)
    expect(data).toBe("ABC")
  end)

  it("requires pack data before encode stubs", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Empty" })
    local data, err = SketchCanvasExportController.encodeChrBankFromSketch(win)
    expect(data).toBeNil()
    expect(err).toBe("Generate a pack before exporting")

    local nt, ntErr = SketchCanvasExportController.encodeNametableFromSketch(win)
    expect(nt).toBeNil()
    expect(ntErr).toBe("Generate a pack before exporting")
  end)

  it("encodes a 4KB CHR bank from pack data", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Packed" })
    local canvas = win:getActiveCanvas()
    -- Fill entire screen with color 1 so empty cells share one unique.
    for y = 0, 239 do
      for x = 0, 255 do
        canvas:edit(x, y, 1)
      end
    end
    -- Distinct second unique at (8,0)
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(8 + x, y, 2)
      end
    end
    local okGen = SketchCanvasPackController.generate(win)
    expect(okGen).toBe(true)
    expect(#win.tilesPool).toBe(2)

    win.paddingTileIndex = 0
    local data, err = SketchCanvasExportController.encodeChrBankFromSketch(win)
    expect(err).toBeNil()
    expect(data).toBeTruthy()
    expect(#data).toBe(4096)

    local tile0 = chr.decodeTile(data, 0)
    local tile1 = chr.decodeTile(data, 1)
    local tilePad = chr.decodeTile(data, 2)
    expect(tile0[1]).toBe(1)
    expect(tile1[1]).toBe(2)
    expect(tilePad[1]).toBe(1) -- padding uses index 0

    local path = os.tmpname() .. ".chr"
    local okWrite, outPath = SketchCanvasExportController.exportChrBankToFile({
      appEditState = { romOriginalPath = path },
    }, win, path)
    expect(okWrite).toBe(true)
    local fh = assert(io.open(path, "rb"))
    local written = fh:read("*a")
    fh:close()
    os.remove(path)
    expect(#written).toBe(4096)
    expect(written).toBe(data)
  end)

  it("encodes nametable bytes with optional attributes", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "NT" })
    local pt = wm:createPatternTableWindow({ title = "NT PT" })
    local canvas = win:getActiveCanvas()
    for y = 0, 239 do
      for x = 0, 255 do
        canvas:edit(x, y, 1)
      end
    end
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(8 + x, y, 2)
      end
    end
    expect(SketchCanvasPackController.linkSketchToPatternTable(win, pt, wm)).toBe(true)
    expect(SketchCanvasPackController.generate(win)).toBe(true)

    local tilesOnly, err = SketchCanvasExportController.encodeNametableFromSketch(win)
    expect(err).toBeNil()
    expect(#tilesOnly).toBe(960)
    -- Cell (0,0) and (1,0) should be different pool indices
    expect(string.byte(tilesOnly, 1)).toBe(0)
    expect(string.byte(tilesOnly, 2)).toBe(1)

    local withAttrs, err2 = SketchCanvasExportController.encodeNametableFromSketch(win, {
      includeAttributes = true,
    })
    expect(err2).toBeNil()
    expect(#withAttrs).toBe(1024)
    expect(withAttrs:sub(1, 960)).toBe(tilesOnly)
    expect(withAttrs:sub(961)).toBe(string.rep("\0", 64))

    -- Real attrs: set quadrant palette 2 (UI key 3 -> index 2) at tile 0,0
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
    local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
    local layer = win.layers[1]
    expect(NametableTilesController.setPaletteNumberForTile(win, layer, 0, 0, 3)).toBe(true)
    rawset(_G, "ctx", prev)
    local withRealAttrs = SketchCanvasExportController.encodeNametableFromSketch(win, {
      includeAttributes = true,
    })
    expect(#withRealAttrs).toBe(1024)
    expect(string.byte(withRealAttrs, 961)).toBe(0x02)

    local path = os.tmpname() .. ".nam"
    local okWrite = SketchCanvasExportController.exportNametableToFile({}, win, path, {
      includeAttributes = true,
    })
    expect(okWrite).toBe(true)
    local fh = assert(io.open(path, "rb"))
    local written = fh:read("*a")
    fh:close()
    os.remove(path)
    expect(written).toBe(withRealAttrs)
  end)

  it("encodes a 32-byte palette blob (fallback and linked sketch palette)", function()
    local fallback = SketchCanvasExportController.encodePaletteFromSketch(nil)
    expect(#fallback).toBe(32)
    expect(string.byte(fallback, 1)).toBe(0x07)
    expect(string.byte(fallback, 2)).toBe(0x17)
    expect(string.byte(fallback, 17)).toBe(0x07)
    expect(string.byte(fallback, 18)).toBe(0x0F)

    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "PalSketch" })
    local pal = wm:createRomPaletteWindow({ title = "Sketch palette", paletteRole = "sketch" })
    pal.codes2D[0][0] = "0A"
    local PaletteLinkController = require("controllers.palette.palette_link_controller")
    expect(PaletteLinkController.linkLayerToPalette(sketch, 1, pal)).toBe(true)
    local blob = SketchCanvasExportController.encodePaletteFromSketch(sketch, wm)
    expect(#blob).toBe(32)
    expect(string.byte(blob, 1)).toBe(0x0A)
    -- $3F10 mirrors $3F00: sprite color 0 must match BG0
    expect(string.byte(blob, 17)).toBe(0x0A)
    expect(string.byte(blob, 18)).toBe(0x0F)
    expect(#(sketch.nametableAttrBytes or {})).toBe(64)
    expect(sketch.nametableAttrBytes[1]).toBe(0)
  end)

  it("bakes non-backdrop color-0 into CHR for hardware / gallery export", function()
    -- NES BG index 0 always uses $3F00. Sketch shows per-attr color 0; gallery
    -- export remaps those pixels (and may pick a better backdrop) so regions keep
    -- their intended solid fills on hardware.
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "Color0Bake" })
    local pt = wm:createPatternTableWindow({ title = "Color0Bake PT" })
    local canvas = sketch:getActiveCanvas()
    for y = 0, 15 do
      for x = 0, 15 do
        canvas:edit(x, y, 0)
      end
    end
    for y = 0, 15 do
      for x = 16, 31 do
        canvas:edit(x, y, 0)
      end
    end
    -- Occupy colors 1-3 under palette 2 so black cannot be injected into that row.
    for y = 0, 7 do
      for x = 16, 23 do
        canvas:edit(x, y, 1 + (x + y) % 3)
      end
    end
    expect(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm)).toBe(true)
    expect(SketchCanvasPackController.generate(sketch)).toBe(true)

    local pal = wm:createRomPaletteWindow({ title = "BakePal", paletteRole = "sketch" })
    pal.codes2D[0][0], pal.codes2D[0][1], pal.codes2D[0][2], pal.codes2D[0][3] = "07", "17", "27", "36"
    pal.codes2D[1][0], pal.codes2D[1][1], pal.codes2D[1][2], pal.codes2D[1][3] = "0F", "15", "26", "36"
    local PaletteLinkController = require("controllers.palette.palette_link_controller")
    expect(PaletteLinkController.linkLayerToPalette(sketch, 1, pal)).toBe(true)

    local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
    local layer = sketch.layers[1]
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
    expect(NametableTilesController.setPaletteNumberForTile(sketch, layer, 2, 0, 2)).toBe(true)
    expect(NametableTilesController.setPaletteNumberForTile(sketch, layer, 3, 0, 2)).toBe(true)
    expect(NametableTilesController.setPaletteNumberForTile(sketch, layer, 2, 1, 2)).toBe(true)
    expect(NametableTilesController.setPaletteNumberForTile(sketch, layer, 3, 1, 2)).toBe(true)
    rawset(_G, "ctx", prev)

    local chr4k, nam, palBlob, err =
      SketchCanvasExportController.encodeHardwareSlideFromSketch(sketch, wm)
    expect(err).toBeNil()
    expect(#chr4k).toBe(4096)
    expect(#nam).toBe(1024)
    expect(#palBlob).toBe(32)

    -- Tiles (2-3,0-1) share the top-right attr quadrant → palette index 1 → 0x04.
    expect(string.byte(nam, 961)).toBe(0x04)

    -- Prefer backdrop 0F so the fully-used pink row keeps 15/26/36.
    expect(string.byte(palBlob, 1)).toBe(0x0F)
    -- Brown 07 must still be present on BG row 0 (promoted into a non-zero slot).
    local row0 = {
      string.byte(palBlob, 1),
      string.byte(palBlob, 2),
      string.byte(palBlob, 3),
      string.byte(palBlob, 4),
    }
    local hasBrown = false
    for i = 1, 4 do
      if row0[i] == 0x07 then
        hasBrown = true
      end
    end
    expect(hasBrown).toBe(true)

    -- Left solid (palette 0) was remapped off index 0 → CHR has non-zero pixels.
    local leftTile = string.byte(nam, 1)
    local bank = {}
    for i = 1, 16 do
      bank[i] = string.byte(chr4k, leftTile * 16 + i)
    end
    local pixels = chr.decodeTile(bank, 0)
    local sawNonZero = false
    for i = 1, 64 do
      if pixels[i] ~= 0 then
        sawNonZero = true
        break
      end
    end
    expect(sawNonZero).toBe(true)
  end)
end)

describe("sketch_canvas_gallery_rom_controller.lua", function()
  local function paintAndLinkGenerate(wm, win)
    local canvas = win:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 1)
      end
    end
    local pt = wm:createPatternTableWindow({ title = (win.title or "S") .. " PT" })
    expect(SketchCanvasPackController.linkSketchToPatternTable(win, pt, wm)).toBe(true)
    expect(SketchCanvasPackController.generateAndApply(win, wm)).toBe(true)
    return pt
  end

  it("collects only packed sketches that still have a linked pattern table", function()
    local wm = WM.new()
    local empty = wm:createSketchCanvasWindow({ title = "Empty" })
    local packedOnly = wm:createSketchCanvasWindow({ title = "PackedNoLink" })
    local canvas = packedOnly:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 1)
      end
    end
    expect(SketchCanvasPackController.generate(packedOnly)).toBe(true)
    expect(SketchCanvasGalleryRomController.canBuildGalleryRom(wm)).toBe(false)
    expect(#SketchCanvasGalleryRomController.collectPackedSketches(wm)).toBe(0)

    local packed = wm:createSketchCanvasWindow({ title = "Packed" })
    paintAndLinkGenerate(wm, packed)

    local list = SketchCanvasGalleryRomController.collectPackedSketches(wm)
    expect(#list).toBe(1)
    expect(list[1]).toBe(packed)
    expect(SketchCanvasGalleryRomController.canBuildGalleryRom(wm)).toBe(true)
    expect(empty).toBeTruthy()
    expect(packedOnly).toBeTruthy()
  end)

  it("writes slide assets and meta without make", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Slide0" })
    local canvas = win:getActiveCanvas()
    for y = 0, 239 do
      for x = 0, 255 do
        canvas:edit(x, y, 1)
      end
    end
    expect(SketchCanvasPackController.generate(win)).toBe(true)

    local tmp = os.tmpname()
    os.remove(tmp)
    local asmDir = tmp .. "_gallery_asm"
    local metaPath = asmDir .. "/s/slide_meta.s"
    assert(os.execute("mkdir -p '" .. asmDir .. "/s'") == true or os.execute("mkdir -p '" .. asmDir .. "/s'") == 0)

    local ok, count = SketchCanvasGalleryRomController.writeSlideAssets(asmDir, { win })
    expect(ok).toBe(true)
    expect(count).toBe(1)

    local chrFh = assert(io.open(asmDir .. "/data/chr/slide00.chr", "rb"))
    local chrData = chrFh:read("*a")
    chrFh:close()
    expect(#chrData).toBe(8192)

    local namFh = assert(io.open(asmDir .. "/data/nam/slide00.nam", "rb"))
    local namData = namFh:read("*a")
    namFh:close()
    expect(#namData).toBe(1024)

    local palFh = assert(io.open(asmDir .. "/data/pal/slide00/main.pal", "rb"))
    local palData = palFh:read("*a")
    palFh:close()
    expect(#palData).toBe(32)

    local okMeta = SketchCanvasGalleryRomController.writeSlideMeta(metaPath, 1)
    expect(okMeta).toBe(true)
    local metaFh = assert(io.open(metaPath, "rb"))
    local meta = metaFh:read("*a")
    metaFh:close()
    expect(meta:find("%.byte 1", 1, false)).toBeTruthy()

    os.execute("rm -rf '" .. asmDir .. "'")
  end)

  it("buildGalleryRom writes assets with skipMake", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "G" })
    paintAndLinkGenerate(wm, win)

    local asmDir = SketchCanvasGalleryRomController.resolveGalleryAsmDir()
    expect(asmDir).toBeTruthy()

    local ok, pathOrErr = SketchCanvasGalleryRomController.buildGalleryRom(
      { wm = wm },
      { win },
      { asmDir = asmDir, skipMake = true }
    )
    expect(ok).toBe(true)
    expect(pathOrErr).toBe(asmDir)

    local metaFh = assert(io.open(asmDir .. "/s/slide_meta.s", "rb"))
    local meta = metaFh:read("*a")
    metaFh:close()
    expect(meta:find("%.byte 1", 1, false)).toBeTruthy()
  end)

  it("buildGalleryRom runs assemble and copies gallery.nes", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "MakeMe" })
    local canvas = win:getActiveCanvas()
    for y = 0, 239 do
      for x = 0, 255 do
        canvas:edit(x, y, 1)
      end
    end
    local pt = wm:createPatternTableWindow({ title = "MakeMe PT" })
    expect(SketchCanvasPackController.linkSketchToPatternTable(win, pt, wm)).toBe(true)
    expect(SketchCanvasPackController.generateAndApply(win, wm)).toBe(true)

    local workDir = SketchCanvasGalleryRomController.prepareWritableGalleryDir({
      destDir = os.tmpname() .. "_gallery_work",
    })
    expect(workDir).toBeTruthy()
    local outPath = os.tmpname() .. "_out_gallery.nes"

    local ok, pathOrErr = SketchCanvasGalleryRomController.buildGalleryRom(
      {
        wm = wm,
        appEditState = { romOriginalPath = "/tmp/demo.nes" },
      },
      { win },
      { asmDir = workDir, outPath = outPath }
    )
    expect(ok).toBe(true)
    expect(pathOrErr).toBe(outPath)

    local fh = assert(io.open(outPath, "rb"))
    local data = fh:read("*a")
    fh:close()
    os.remove(outPath)
    expect(#data).toBe(163856)
    expect(data:sub(1, 4)).toBe("NES" .. string.char(0x1A))
    local chrRegion = data:sub(16 + 32768 + 1)
    local nonzero = 0
    for i = 1, #chrRegion do
      if chrRegion:byte(i) ~= 0 then
        nonzero = nonzero + 1
      end
    end
    expect(nonzero > 0).toBe(true)

    if package.config:sub(1, 1) == "\\" then
      os.execute('rmdir /s /q "' .. workDir:gsub("/", "\\") .. '" >NUL 2>NUL')
    else
      os.execute('rm -rf "' .. workDir .. '" >/dev/null 2>&1')
    end
  end)

  it("prepareWritableGalleryDir copies template into a writable cache", function()
    local dest = os.tmpname() .. "_gallery_prepare"
    local dir, err = SketchCanvasGalleryRomController.prepareWritableGalleryDir({ destDir = dest })
    expect(err).toBeNil()
    expect(dir).toBe(dest)
    local cfg = io.open(dest .. "/nes.cfg", "rb") or io.open(dest .. "\\nes.cfg", "rb")
    expect(cfg).toBeTruthy()
    if cfg then
      cfg:close()
    end
    local main = io.open(dest .. "/s/main.s", "rb") or io.open(dest .. "\\s\\main.s", "rb")
    expect(main).toBeTruthy()
    if main then
      main:close()
    end
    if package.config:sub(1, 1) == "\\" then
      os.execute('rmdir /s /q "' .. dest:gsub("/", "\\") .. '" >NUL 2>NUL')
    else
      os.execute('rm -rf "' .. dest .. '" >/dev/null 2>&1')
    end
  end)

  it("checkCc65Tools reports availability", function()
    local ok, a, b = SketchCanvasGalleryRomController.checkCc65Tools()
    if ok then
      expect(type(a) == "string" and a ~= "").toBe(true)
      expect(type(b) == "string" and b ~= "").toBe(true)
    else
      expect(type(a) == "string" and a:find("cc65", 1, true) ~= nil).toBe(true)
    end
  end)
end)
