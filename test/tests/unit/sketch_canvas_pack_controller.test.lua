local WM = require("controllers.window.window_controller")
local PixelCanvas = require("user_interface.windows_system.pixel_canvas")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local ToolbarController = require("controllers.window.toolbar_controller")

local function paintTile(canvas, tileCol, tileRow, value)
  local ox = tileCol * 8
  local oy = tileRow * 8
  for y = 0, 7 do
    for x = 0, 7 do
      canvas:edit(ox + x, oy + y, value)
    end
  end
end

local function paintTileDiffPixels(canvas, tileCol, tileRow, baseValue, flipCount)
  paintTile(canvas, tileCol, tileRow, baseValue)
  local ox = tileCol * 8
  local oy = tileRow * 8
  local flipped = 0
  for y = 0, 7 do
    for x = 0, 7 do
      if flipped >= flipCount then
        return
      end
      canvas:edit(ox + x, oy + y, (baseValue + 1) % 4)
      flipped = flipped + 1
    end
  end
end

local function uniquePattern(id)
  local p = {}
  for i = 1, 64 do
    p[i] = 0
  end
  local n = math.floor(tonumber(id) or 0)
  p[1] = n % 4
  p[2] = math.floor(n / 4) % 4
  p[3] = math.floor(n / 16) % 4
  p[4] = math.floor(n / 64) % 4
  p[5] = math.floor(n / 256) % 4
  p[6] = math.floor(n / 1024) % 4
  return p
end

describe("sketch canvas - pack controller", function()
  it("packs a blank canvas to one unique pattern and 960 nametable bytes", function()
    local canvas = PixelCanvas.new(256, 240, 0)
    local pack, err = SketchCanvasPackController.packFromCanvas(canvas, 0)
    expect(err).toBeNil()
    expect(pack.uniqueCount).toBe(1)
    expect(#pack.tilesPool).toBe(1)
    expect(pack.tilesPool[1].x).toBe(0)
    expect(pack.tilesPool[1].y).toBe(0)
    expect(#pack.nametableBytes).toBe(960)
    for i = 1, 960 do
      expect(pack.nametableBytes[i]).toBe(0)
    end
  end)

  it("merges identical 8x8 cells at tolerance 0", function()
    local canvas = PixelCanvas.new(256, 240, 0)
    paintTile(canvas, 0, 0, 2)
    paintTile(canvas, 3, 2, 2)
    local pack = assert(SketchCanvasPackController.packFromCanvas(canvas, 0))
    -- First-seen painted solid is pool 0; blank cells become pool 1.
    expect(pack.uniqueCount).toBe(2)
    expect(pack.nametableBytes[1]).toBe(0) -- col0 row0
    local idx = (2 * 32) + 3 + 1 -- row2 col3, 1-based
    expect(pack.nametableBytes[idx]).toBe(0)
    expect(pack.nametableBytes[2]).toBe(1) -- blank neighbor
  end)

  it("keeps near-matches separate at tolerance 0 and merges when tolerance covers diffs", function()
    local canvas = PixelCanvas.new(256, 240, 0)
    paintTile(canvas, 0, 0, 1)
    paintTileDiffPixels(canvas, 1, 0, 1, 3) -- 3 pixels differ from solid 1

    local pack0 = assert(SketchCanvasPackController.packFromCanvas(canvas, 0))
    expect(pack0.uniqueCount).toBe(3) -- blank + solid + near

    local pack3 = assert(SketchCanvasPackController.packFromCanvas(canvas, 3))
    expect(pack3.uniqueCount).toBe(2) -- blank + merged painted pair
    expect(pack3.nametableBytes[1]).toBe(pack3.nametableBytes[2])
  end)

  it("errors when unique patterns would exceed 256", function()
    local fake = {
      width = 256,
      height = 240,
      extractTilePixels = function(_self, ox, oy)
        local col = math.floor(ox / 8)
        local row = math.floor(oy / 8)
        local id = row * 32 + col
        return uniquePattern(id)
      end,
    }
    local pack, err = SketchCanvasPackController.packFromCanvas(fake, 0)
    expect(pack).toBeNil()
    expect(err).toBe("too_many_unique")
  end)

  it("generate writes pool/nt on the window and leaves paddingTileIndex unused", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    win.paddingTileIndex = 7
    paintTile(win.layers[1].canvas, 0, 0, 3)
    paintTile(win.layers[1].canvas, 2, 0, 3)

    local ok, pack = SketchCanvasPackController.generate(win)
    expect(ok).toBe(true)
    expect(pack.uniqueCount).toBe(2)
    expect(#win.tilesPool).toBe(2)
    expect(#win.nametableBytes).toBe(960)
    expect(win.paddingTileIndex).toBe(7)
    expect(win.linkedPatternTableWindowId).toBeNil()
  end)

  it("toolbar Generate packs and reports unique count; tolerance buttons adjust window.tolerance", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(win.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(win, pt, wm))

    local statuses = {}
    local ctx = {
      app = {
        setStatus = function(_app, text)
          statuses[#statuses + 1] = text
        end,
      },
    }
    local toolbar = ToolbarController.createSpecializedToolbar(win, ctx, wm)
    expect(toolbar.generateButton.enabled).toBe(true)

    -- Linked sketches debounce tolerance via Timer; run the callback immediately.
    local Timer = require("utils.timer_utils")
    local origAfter = Timer.after
    Timer.after = function(_delay, fn)
      fn()
      return 1
    end

    toolbar.toleranceUpButton.action()
    expect(win.tolerance).toBe(1)
    -- Live regen (not the unlinked "Sketch tolerance: N" status).
    expect(statuses[#statuses]:find("unique pattern", 1, true)).toBeTruthy()
    expect(#win.nametableBytes).toBe(960)

    statuses = {}
    toolbar.generateButton.action()
    expect(#win.nametableBytes).toBe(960)
    expect(statuses[#statuses]:find("unique pattern", 1, true)).toBeTruthy()

    Timer.after = origAfter
  end)
end)
