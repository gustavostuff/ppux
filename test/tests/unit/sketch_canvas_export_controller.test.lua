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

    local path = os.tmpname() .. ".nam"
    local okWrite = SketchCanvasExportController.exportNametableToFile({}, win, path, {
      includeAttributes = true,
    })
    expect(okWrite).toBe(true)
    local fh = assert(io.open(path, "rb"))
    local written = fh:read("*a")
    fh:close()
    os.remove(path)
    expect(written).toBe(withAttrs)
  end)
end)

describe("sketch_canvas_gallery_rom_controller.lua", function()
  it("collects only packed sketch canvases", function()
    local wm = WM.new()
    local empty = wm:createSketchCanvasWindow({ title = "Empty" })
    local packed = wm:createSketchCanvasWindow({ title = "Packed" })
    local canvas = packed:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 1)
      end
    end
    expect(SketchCanvasPackController.generate(packed)).toBe(true)

    local list = SketchCanvasGalleryRomController.collectPackedSketches(wm)
    expect(#list).toBe(1)
    expect(list[1]).toBe(packed)
    expect(empty).toBeTruthy()
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
    local canvas = win:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 2)
      end
    end
    expect(SketchCanvasPackController.generate(win)).toBe(true)

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

  it("buildGalleryRom runs make and copies gallery.nes", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "MakeMe" })
    local canvas = win:getActiveCanvas()
    for y = 0, 239 do
      for x = 0, 255 do
        canvas:edit(x, y, 1)
      end
    end
    expect(SketchCanvasPackController.generate(win)).toBe(true)

    local asmDir = SketchCanvasGalleryRomController.resolveGalleryAsmDir()
    expect(asmDir).toBeTruthy()
    local outPath = os.tmpname() .. "_out_gallery.nes"

    local ok, pathOrErr = SketchCanvasGalleryRomController.buildGalleryRom(
      {
        wm = wm,
        appEditState = { romOriginalPath = "/tmp/demo.nes" },
      },
      { win },
      { asmDir = asmDir, outPath = outPath }
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
  end)
end)
