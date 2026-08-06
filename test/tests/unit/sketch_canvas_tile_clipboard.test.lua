local WM = require("controllers.window.window_controller")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local function paintTile(canvas, tileCol, tileRow, value)
  local ox = tileCol * 8
  local oy = tileRow * 8
  for y = 0, 7 do
    for x = 0, 7 do
      canvas:edit(ox + x, oy + y, value)
    end
  end
end

local function withMode(mode, fn, wm)
  local prev = rawget(_G, "ctx")
  rawset(_G, "ctx", {
    getMode = function()
      return mode
    end,
    app = wm and { wm = wm } or nil,
    wm = wm and function()
      return wm
    end or nil,
  })
  local ok, err = pcall(fn)
  rawset(_G, "ctx", prev)
  if not ok then
    error(err)
  end
end

describe("sketch canvas - tile mode clipboard", function()
  beforeEach(function()
    KeyboardClipboardController.reset()
  end)

  it("copies and pastes nametable tiles within the same sketch", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    paintTile(sketch.layers[1].canvas, 1, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generate(sketch))

    local srcByte = sketch.nametableBytes[1]
    local dstBefore = sketch.nametableBytes[3] -- col 2, row 0
    expect(srcByte).toBeTruthy()
    expect(dstBefore).toBeTruthy()
    expect(srcByte).toNotBe(dstBefore)

    withMode("tile", function()
      expect(WindowCaps.isSketchReflectNametable(sketch)).toBe(true)

      sketch:setSelected(0, 0, 1)
      local status = nil
      local ctx = {
        getMode = function()
          return "tile"
        end,
        setStatus = function(text)
          status = text
        end,
        app = { wm = wm },
        wm = function()
          return wm
        end,
      }

      local copyAvail = KeyboardClipboardController.getActionAvailability(ctx, sketch, "copy")
      expect(copyAvail.allowed).toBe(true)
      expect(copyAvail.sketchPixels).toBeNil()

      expect(KeyboardClipboardController.performClipboardAction(ctx, sketch, "copy")).toBe(true)
      expect(status).toBe("Copied 1 tile")

      sketch:setSelected(2, 0, 1)
      local pasteAvail = KeyboardClipboardController.getActionAvailability(ctx, sketch, "paste")
      expect(pasteAvail.allowed).toBe(true)

      expect(KeyboardClipboardController.performClipboardAction(ctx, sketch, "paste")).toBe(true)
      expect(status).toBe("Pasted 1 tile")
      expect(sketch.nametableBytes[3]).toBe(srcByte)
      expect(sketch.nametableBytes[1]).toBe(srcByte)
    end, wm)
  end)

  it("does not treat tile-mode sketch as pixel clipboard", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(sketch.layers[1].canvas, 0, 0, 1)
    assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm))
    assert(SketchCanvasPackController.generate(sketch))

    withMode("tile", function()
      sketch:setSelected(0, 0, 1)
      local ctx = {
        getMode = function()
          return "tile"
        end,
        setStatus = function() end,
        app = { wm = wm },
        wm = function()
          return wm
        end,
      }
      local avail = KeyboardClipboardController.getActionAvailability(ctx, sketch, "copy")
      expect(avail.allowed).toBe(true)
      expect(avail.sketchPixels).toBeNil()
    end, wm)
  end)
end)
