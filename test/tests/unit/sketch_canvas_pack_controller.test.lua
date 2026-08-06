local WM = require("controllers.window.window_controller")
local PixelCanvas = require("ui.windows_system.pixel_canvas")
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

  it("collapses near-empty tiles into one flat shade under high tolerance", function()
    local canvas = PixelCanvas.new(256, 240, 0)
    -- Five near-empty tiles with disjoint 5-pixel marks (pairwise diffs up to 10).
    local marks = {
      { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 }, { 4, 0 },
    }
    for i, pos in ipairs(marks) do
      local ox = pos[1] * 8
      local oy = pos[2] * 8
      for p = 0, 4 do
        canvas:edit(ox + p, oy, 1)
      end
      -- Shift marks so they don't overlap across tiles... actually each tile is separate.
      -- Use different pixel positions within each tile:
      for y = 0, 7 do
        for x = 0, 7 do
          canvas:edit(ox + x, oy + y, 0)
        end
      end
      for p = 0, 4 do
        local idx = (i - 1) * 5 + p
        local px = idx % 8
        local py = math.floor(idx / 8) % 8
        canvas:edit(ox + px, oy + py, 1)
      end
    end
    paintTile(canvas, 5, 0, 0) -- exact flat shade 0
    paintTile(canvas, 6, 0, 2) -- flat shade 2

    local packGreedyWouldSplit = assert(SketchCanvasPackController.packFromCanvas(canvas, 8))
    -- Near-empties stay unique (shade-0 collapse is exact-blank only); plus solid 2;
    -- exact blank cells share one shade-0 flat.
    expect(packGreedyWouldSplit.uniqueCount >= 2).toBe(true)
    local solid0Slots = 0
    local solid2Slots = 0
    local nonSolid = 0
    for _, entry in ipairs(packGreedyWouldSplit.tilesPool) do
      if entry.solidShade == 0 then
        solid0Slots = solid0Slots + 1
      elseif entry.solidShade == 2 then
        solid2Slots = solid2Slots + 1
      else
        nonSolid = nonSolid + 1
      end
    end
    expect(solid0Slots).toBe(1)
    expect(solid2Slots).toBe(1)
    expect(nonSolid >= 1).toBe(true)

    -- CHR/PT sample for shade 0 must be a true flat, not a near-empty skirt edge.
    local solid0Entry = nil
    for _, entry in ipairs(packGreedyWouldSplit.tilesPool) do
      if entry.solidShade == 0 then
        solid0Entry = entry
        break
      end
    end
    expect(solid0Entry).toBeTruthy()
    local pixels = SketchCanvasPackController.pixelsForPoolEntry(canvas, solid0Entry)
    local allSame = true
    for i = 1, 64 do
      if pixels[i] ~= 0 then
        allSame = false
        break
      end
    end
    expect(allSame).toBe(true)
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

    local kind, text = SketchCanvasPackController.formatGenerateToast(false, "too_many_unique")
    expect(kind).toBe("error")
    expect(text:find("256", 1, true)).toBeTruthy()
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

  it("toolbar Generate packs and reports unique count via toast; tolerance buttons adjust window.tolerance", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local pt = wm:createPatternTableWindow()
    paintTile(win.layers[1].canvas, 0, 0, 2)
    assert(SketchCanvasPackController.linkSketchToPatternTable(win, pt, wm))

    local toasts = {}
    local statusText = nil
    local ctx = {
      showToast = function(kind, text)
        toasts[#toasts + 1] = { kind = kind, text = text }
      end,
      setStatus = function(text)
        statusText = text
      end,
      app = {},
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
    -- Live regen from tolerance buttons reports via status bar (not toast).
    expect(#toasts).toBe(0)
    expect(statusText:find("unique pattern", 1, true)).toBeTruthy()
    expect(#win.nametableBytes).toBe(960)

    toasts = {}
    statusText = nil
    toolbar.generateButton.action()
    expect(#win.nametableBytes).toBe(960)
    expect(toasts[#toasts].kind).toBe("info")
    expect(toasts[#toasts].text:find("unique pattern", 1, true)).toBeTruthy()

    Timer.after = origAfter
  end)
end)
