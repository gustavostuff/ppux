local WM = require("controllers.window.window_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local SketchDisplay = require("controllers.game_art.sketch_canvas_display_controller")
local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")

local function withWm(wm, fn)
  local prev = rawget(_G, "ctx")
  rawset(_G, "ctx", {
    app = { wm = wm },
    wm = function()
      return wm
    end,
  })
  local ok, err = pcall(fn)
  rawset(_G, "ctx", prev)
  if not ok then
    error(err)
  end
end

describe("sketch_canvas_display_controller.lua", function()
  it("rebuilds palettized cache only when source, attrs, or palette codes change", function()
    local wm = WM.new()
    withWm(wm, function()
      local sketch = wm:createSketchCanvasWindow({ title = "BG" })
      local pal = wm:createRomPaletteWindow({ title = "Sketch pal", paletteRole = "sketch" })
      assert(PaletteLinkController.linkLayerToPalette(sketch, 1, pal))
      SketchPalette.ensureAttrBytes(sketch)
      local canvas = sketch:getActiveCanvas()
      canvas:edit(0, 0, 2)
      local layer = sketch.layers[1]
      local app = { wm = wm }

      love.graphics.push("all")
      love.graphics.origin()
      expect(SketchDisplay.drawAttrPalettized(app, sketch, canvas, layer, 1, nil)).toBe(true)
      expect(sketch._sketchPalettized.rebuilds).toBe(1)
      expect(SketchDisplay.drawAttrPalettized(app, sketch, canvas, layer, 1, nil)).toBe(true)
      expect(sketch._sketchPalettized.rebuilds).toBe(1)

      pal.codes2D[0][1] = "22"
      expect(SketchDisplay.drawAttrPalettized(app, sketch, canvas, layer, 1, nil)).toBe(true)
      expect(sketch._sketchPalettized.rebuilds).toBe(2)

      sketch.nametableAttrBytes[1] = 0x01
      expect(SketchDisplay.drawAttrPalettized(app, sketch, canvas, layer, 1, nil)).toBe(true)
      expect(sketch._sketchPalettized.rebuilds).toBe(3)

      canvas:edit(1, 0, 3)
      expect(SketchDisplay.drawAttrPalettized(app, sketch, canvas, layer, 1, nil)).toBe(true)
      expect(sketch._sketchPalettized.rebuilds).toBe(4)
      love.graphics.pop()
    end)
  end)

  it("changes fingerprint when attribute or source revision changes", function()
    local wm = WM.new()
    withWm(wm, function()
      local sketch = wm:createSketchCanvasWindow({ title = "BG" })
      local pal = wm:createRomPaletteWindow({ title = "Sketch pal", paletteRole = "sketch" })
      assert(PaletteLinkController.linkLayerToPalette(sketch, 1, pal))
      SketchPalette.ensureAttrBytes(sketch)
      local canvas = sketch:getActiveCanvas()
      local layer = sketch.layers[1]
      local a = SketchDisplay.sourceFingerprint(sketch, canvas, layer, nil)
      canvas:edit(2, 2, 1)
      local b = SketchDisplay.sourceFingerprint(sketch, canvas, layer, nil)
      expect(a == b).toBe(false)
      sketch.nametableAttrBytes[2] = 0x02
      local c = SketchDisplay.sourceFingerprint(sketch, canvas, layer, nil)
      expect(b == c).toBe(false)
    end)
  end)
end)
