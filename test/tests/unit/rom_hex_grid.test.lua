local RomHexGrid = require("ui.rom_hex_grid")
local appColors = require("app_colors")

describe("RomHexGrid", function()
  local function makeRom(n)
    return string.rep("\0", n)
  end

  local function cellPixel(col, row)
    -- PAD + gutter/header + center of cell (GUTTER_W=38, CELL_W=15, CELL_H=12, HEADER_H=12)
    return 2 + 38 + col * 15 + 2, 2 + 12 + row * 12 + 2
  end

  local function oamGrid(opts)
    opts = opts or {}
    opts.groupSize = opts.groupSize or 4
    return RomHexGrid.new(opts)
  end

  it("click sets selected address from scroll + cell", function()
    local selected = nil
    local grid = oamGrid({
      onSelect = function(addr)
        selected = addr
      end,
    })
    grid:setRomRaw(makeRom(512))
    grid:setPosition(0, 0)
    grid.scrollOffset = 0x20

    local hx, hy = cellPixel(0, 0)
    local hit = grid:mousepressed(hx, hy, 1)
    expect(hit).toBe(true)
    expect(selected).toBe(0x20)
    expect(grid:getSelectedAddr()).toBe(0x20)
  end)

  it("selection visually spans groupSize bytes from the start address", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(256))
    grid:setSelectedAddr(0x10, { emit = false })
    local starts = grid:getSelectedStarts()
    expect(#starts).toBe(1)
    expect(starts[1]).toBe(0x10)

    local span = grid:getGroupSize()
    local function covered(addr)
      for _, start in ipairs(grid:getSelectedStarts()) do
        if addr >= start and addr < start + span then
          return true
        end
      end
      return false
    end
    expect(covered(0x10)).toBe(true)
    expect(covered(0x13)).toBe(true)
    expect(covered(0x14)).toBe(false)
  end)

  it("groupSize 1 selects a single byte", function()
    local grid = RomHexGrid.new({ groupSize = 1 })
    grid:setRomRaw(makeRom(256))
    grid:setSelectedAddr(0x11, { emit = false })
    expect(grid:getSelectedStarts()).toEqual({ 0x11 })
    expect(grid:getGroupSize()).toBe(1)
  end)

  it("click toggles additional non-overlapping groups without Ctrl", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    grid.scrollOffset = 0

    local x10, y10 = cellPixel(0, 1)
    grid:mousepressed(x10, y10, 1)
    expect(grid:getSelectedStarts()).toEqual({ 0x10 })

    -- Inside the 0x10..0x13 selection → toggles that group off.
    local x11, y11 = cellPixel(1, 1)
    grid:mousepressed(x11, y11, 1)
    expect(#grid:getSelectedStarts()).toBe(0)

    grid:mousepressed(x11, y11, 1)
    expect(grid:getSelectedStarts()).toEqual({ 0x11 })

    -- Overlapping candidate (0x0F..0x12 vs 0x11..0x14) toggles the conflict off.
    local x0F, y0F = cellPixel(0x0F, 0)
    grid:mousepressed(x0F, y0F, 1)
    expect(#grid:getSelectedStarts()).toBe(0)

    grid:mousepressed(x11, y11, 1)
    expect(grid:getSelectedStarts()).toEqual({ 0x11 })

    -- Non-overlapping 0x20..0x23 can be added alongside 0x11..0x14.
    local x20, y20 = cellPixel(0, 2)
    grid:mousepressed(x20, y20, 1)
    local starts = grid:getSelectedStarts()
    expect(#starts).toBe(2)
    expect(starts[1]).toBe(0x11)
    expect(starts[2]).toBe(0x20)
  end)

  it("addStartGroup rejects overlapping fixed-size groups", function()
    local starts, primary, added = RomHexGrid.addStartGroup({ 0x10 }, 0x11, 4)
    expect(added).toBe(false)
    expect(#starts).toBe(1)
    expect(starts[1]).toBe(0x10)
    expect(primary).toBe(0x10)
  end)

  it("clicking a selected group toggles it off", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    grid:setSelectedAddr(0x10, { emit = false })
    local x11, y11 = cellPixel(1, 1) -- 0x11 inside 0x10..0x13
    grid:mousepressed(x11, y11, 1)
    expect(#grid:getSelectedStarts()).toBe(0)
  end)

  it("toggling off a semi-selected group restores semi (caller list unchanged)", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    grid:setSemiSelectedStarts({ 0x10 })
    grid:setSelectedAddr(0x10, { emit = false })
    expect(grid:getSelectedStarts()).toEqual({ 0x10 })
    expect(grid:getSemiSelectedStarts()).toEqual({ 0x10 })
    local x10, y10 = cellPixel(0, 1)
    grid:mousepressed(x10, y10, 1)
    expect(#grid:getSelectedStarts()).toBe(0)
    expect(grid:getSemiSelectedStarts()).toEqual({ 0x10 })
  end)

  it("addStartGroup does not fill intermediate groups", function()
    local starts, primary, added = RomHexGrid.addStartGroup({ 0x10 }, 0x20, 4)
    expect(added).toBe(true)
    expect(#starts).toBe(2)
    expect(starts[1]).toBe(0x10)
    expect(starts[2]).toBe(0x20)
    expect(primary).toBe(0x20)
  end)

  it("uses red/green/blue/yellow/brown from app_colors and cycles", function()
    local list = RomHexGrid.getHighlightColors()
    expect(#list).toBe(5)
    expect(list[1][1]).toBe(appColors.red[1])
    expect(list[2][1]).toBe(appColors.green[1])
    expect(list[3][1]).toBe(appColors.blue[1])
    expect(list[4][1]).toBe(appColors.yellow[1])
    expect(list[5][1]).toBe(appColors.brown[1])
    local grid = oamGrid()
    local c6 = grid:highlightColorForStartIndex(6)
    expect(c6[1]).toBe(appColors.red[1])
    expect(grid:textColorForStartIndex(4)[1]).toBe(appColors.black[1])
    expect(grid:textColorForStartIndex(1)[1]).toBe(appColors.white[1])
  end)

  it("keeps first-selected group color when adding a lower address", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(512))
    grid:setSelectedAddr(0x08)
    expect(grid:highlightColorForStart(0x08)[1]).toBe(appColors.red[1])

    local starts = select(1, RomHexGrid.addStartGroup(grid:getSelectedStarts(), 0x00, 4))
    grid:_setStarts(starts, 0x00, { emit = false, resetColors = false })

    expect(#grid:getSelectedStarts()).toBe(2)
    expect(grid:highlightColorForStart(0x08)[1]).toBe(appColors.red[1])
    expect(grid:highlightColorForStart(0x00)[1]).toBe(appColors.green[1])
    expect(grid:highlightColorForStartIndex(1)[1]).toBe(appColors.red[1])
    expect(grid:highlightColorForStartIndex(2)[1]).toBe(appColors.green[1])
  end)

  it("nil maxSelectedStarts allows unlimited selection", function()
    local grid = oamGrid() -- no maxSelectedStarts
    grid:setRomRaw(makeRom(512))
    local starts = {}
    for i = 0, 10 do
      starts[#starts + 1] = i * 4
    end
    grid:_setStarts(starts, 0x28, { emit = false })
    expect(#grid:getSelectedStarts()).toBe(11)
  end)

  it("caps selection when maxSelectedStarts is set and reports selectionCapHit", function()
    local capHits = 0
    local grid = oamGrid({
      maxSelectedStarts = 8,
      onSelect = function(_, opts)
        if opts and opts.selectionCapHit then
          capHits = capHits + 1
        end
      end,
    })
    grid:setRomRaw(makeRom(512))
    local starts = {}
    for i = 0, 8 do
      starts[#starts + 1] = i * 4
    end
    grid:_setStarts(starts, 0x20, { emit = true })
    local selected = grid:getSelectedStarts()
    expect(#selected).toBe(8)
    expect(capHits).toBe(1)
    expect(selected[1]).toBe(0x00)
    expect(selected[8]).toBe(0x1C)
  end)

  it("maxSelectedStarts 1 replaces selection on a new click", function()
    local grid = RomHexGrid.new({ groupSize = 1, maxSelectedStarts = 1 })
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    local x0, y0 = cellPixel(0, 0)
    local x5, y5 = cellPixel(5, 0)
    grid:mousepressed(x0, y0, 1)
    expect(grid:getSelectedStarts()).toEqual({ 0 })
    grid:mousepressed(x5, y5, 1)
    expect(grid:getSelectedStarts()).toEqual({ 5 })
  end)

  it("supports 32-column layout and scrollbar drag scrolling", function()
    local scrolls = 0
    local grid = RomHexGrid.new({
      cols = 32,
      groupSize = 1,
      onScroll = function()
        scrolls = scrolls + 1
      end,
    })
    grid:setRomRaw(makeRom(4096))
    grid:setPosition(0, 0)
    expect(grid:getCols()).toBe(32)
    expect(grid:bytesPerPage()).toBe(256)
    expect(grid:getWidth()).toBe(RomHexGrid.contentWidth(32))

    -- Click in full-ROM overview track (right of byte grid).
    local trackX = 2 + 38 + 32 * 15 + 2 + 1
    local trackY = 2 + 12 + 40
    expect(grid:mousepressed(trackX, trackY, 1)).toBe(true)
    expect(grid:isScrollDragging()).toBe(true)
    local before = grid.scrollOffset
    grid:mousemoved(trackX, trackY + 20)
    expect(grid.scrollOffset).toBeGreaterThanOrEqual(before)
    expect(scrolls).toBeGreaterThanOrEqual(1)
    grid:mousereleased(trackX, trackY + 20, 1)
    expect(grid:isScrollDragging()).toBe(false)
  end)

  it("zoomed detail track is cols-wide (1px per byte) and not scrubbable", function()
    local grid = RomHexGrid.new({ cols = 16, groupSize = 1 })
    grid:setRomRaw(makeRom(8192))
    grid:setPosition(0, 0)
    grid.scrollOffset = 2048
    local trackH = RomHexGrid.ROWS * RomHexGrid.CELL_H
    local zoomStart, zoomLen = grid:_computeZoomWindow()
    -- Track height pixels == hex rows spanned (1:1); width == cols.
    expect(zoomLen / 16).toBe(trackH)
    expect(RomHexGrid.zoomTrackWidth(16)).toBe(16)
    local zx, _, zw, zh = grid:_zoomScrollbarTrackRect()
    expect(zw).toBe(16)
    expect(zh).toBe(trackH)
    expect(zoomStart <= 2048).toBe(true)
    expect(zoomStart + zoomLen > 2048).toBe(true)

    local zoomX = zx + 1
    local trackY = 2 + 12
    local before = grid.scrollOffset
    -- Zoom track clicks do not start a scroll drag.
    expect(grid:_scrollbarHitTest(zoomX, trackY + 10)).toBe(false)
    expect(grid:mousepressed(zoomX, trackY + 10, 1)).toBe(true)
    expect(grid:isScrollDragging()).toBe(false)
    expect(grid.scrollOffset).toBe(before)
  end)

  it("contentWidth accounts for cols-wide zoom track", function()
    expect(RomHexGrid.contentWidth(16)).toBeGreaterThan(RomHexGrid.contentWidth(8))
    -- Wider col count grows both the byte grid and the zoom miniature.
    local w16 = RomHexGrid.contentWidth(16)
    local w32 = RomHexGrid.contentWidth(32)
    expect(w32 - w16).toBe((32 - 16) * RomHexGrid.CELL_W + (32 - 16))
  end)

  it("wheel steps 8 rows; Shift+wheel steps 64 rows", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(4096))
    grid:setPosition(0, 0)
    grid.scrollOffset = 0

    grid:wheelmovedAt(0, -1, 10, 10, { shift = false })
    expect(grid.scrollOffset).toBe(8 * 16)

    grid.scrollOffset = 0
    grid:wheelmovedAt(0, -1, 10, 10, { shift = true })
    expect(grid.scrollOffset).toBe(64 * 16)
  end)

  it("clamps scroll at ROM ends", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(200))
    grid.scrollOffset = 9999
    grid:clampScroll()
    expect(grid.scrollOffset).toBe(grid:maxScroll())
    expect(grid.scrollOffset % 16).toBe(0)

    grid.scrollOffset = -50
    grid:clampScroll()
    expect(grid.scrollOffset).toBe(0)
  end)

  it("scrollOnSelect false keeps scroll offset when clicking groups", function()
    local grid = RomHexGrid.new({
      cols = 16,
      groupSize = 4,
      maxSelectedStarts = 8,
      scrollOnSelect = false,
    })
    grid:setRomRaw(makeRom(0x400))
    grid:setPosition(0, 0)
    grid.scrollOffset = 0x100
    grid:_setStarts({}, 0, {
      emit = false,
      allowEmpty = true,
      resetColors = true,
      scrollToReveal = false,
    })
    local hx, hy = cellPixel(0, 0) -- addr 0x100 on this page
    grid:mousepressed(hx, hy, 1)
    expect(grid.scrollOffset).toBe(0x100)
    expect(grid:getSelectedStarts()).toEqual({ 0x100 })
    -- Toggle off same group — still no scroll.
    grid:mousepressed(hx, hy, 1)
    expect(grid.scrollOffset).toBe(0x100)
    expect(grid:getSelectedStarts()).toEqual({})
  end)

  it("scrollToReveal brings off-screen selection into view", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(2048))
    grid.scrollOffset = 0
    grid:scrollToReveal(0x200)
    expect(grid.scrollOffset <= 0x200).toBe(true)
    expect(grid.scrollOffset + RomHexGrid.BYTES_PER_PAGE - 1).toBeGreaterThanOrEqual(0x200)
  end)

  it("pixelCenterForAddr scrolls into view and returns the cell center", function()
    local grid = RomHexGrid.new({ cols = 16, groupSize = 1 })
    grid:setRomRaw(makeRom(0x400))
    grid:setPosition(10, 20)
    grid.scrollOffset = 0
    local x, y = grid:pixelCenterForAddr(0x200)
    expect(type(x) == "number" and type(y) == "number").toBe(true)
    expect(grid:addrAtPixel(x, y)).toBe(0x200)
  end)

  it("cursorNameAt returns unavailable over disabled and hand over ninja cells", function()
    local grid = RomHexGrid.new({
      cols = 16,
      groupSize = 4,
      defaultCellStyle = "ninja",
    })
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    grid:setDisabledStarts({ 0x10 })
    local hx, hy = cellPixel(0, 1) -- 0x10
    expect(grid:cursorNameAt(hx, hy)).toBe("unavailable")
    local fx, fy = cellPixel(4, 1) -- 0x14 free
    expect(grid:cursorNameAt(fx, fy)).toBe("hand")
  end)

  it("setSelectedAddr does not scroll when the start is already on the page", function()
    local grid = RomHexGrid.new({ cols = 16, groupSize = 1, maxSelectedStarts = 1 })
    grid:setRomRaw(makeRom(0x400))
    grid.scrollOffset = 0x100
    grid:setSelectedAddr(0x110, { emit = false, scrollToReveal = true })
    expect(grid.scrollOffset).toBe(0x100)
  end)

  it("setSelectedAddr scrolls only until an off-page start becomes visible", function()
    local grid = RomHexGrid.new({ cols = 16, groupSize = 1, maxSelectedStarts = 1 })
    grid:setRomRaw(makeRom(0x400))
    grid.scrollOffset = 0
    grid:setSelectedAddr(0x200, { emit = false, scrollToReveal = true })
    expect(grid.scrollOffset <= 0x200).toBe(true)
    expect(grid.scrollOffset + RomHexGrid.BYTES_PER_PAGE - 1).toBeGreaterThanOrEqual(0x200)
  end)

  it("snaps a click 2 bytes before a disabled group to the preceding start", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    grid:setDisabledStarts({ 0x2A })
    expect(grid:resolveSelectableStart(0x28)).toBe(0x26)
    grid:setSelectedAddr(0x28, { emit = false })
    expect(grid:getSelectedStarts()).toEqual({ 0x26 })
  end)

  it("does not select when clicking inside a disabled gray span", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(256))
    grid:setSelectedAddr(0x10, { emit = false })
    grid:setOccupiedStarts({ 0x2A })
    expect(grid:resolveSelectableStart(0x2B)).toBeNil()
    grid:setSelectedAddr(0x2B, { emit = false })
    expect(grid:getSelectedStarts()).toEqual({ 0x10 })
  end)

  it("setMinimapMarkers keeps valid color keys and offsets only", function()
    local grid = oamGrid()
    grid:setMinimapMarkers({
      { offset = 0x100, color = "red" },
      { offset = -1, color = "green" },
      { offset = 0x200, color = "purple" },
      { offset = 0x300, color = "blue" },
      { offset = 0x400, color = "gray" },
      { offset = 0x500, color = { 0.1, 0.2, 0.3, 0.9 } },
      "nope",
    })
    local markers = grid:getMinimapMarkers()
    expect(#markers).toBe(4)
    expect(markers[1].offset).toBe(0x100)
    expect(markers[1].color).toBe("red")
    expect(markers[1].groupCount).toBe(1)
    expect(markers[1].groupSize).toBe(1)
    expect(markers[2].offset).toBe(0x300)
    expect(markers[2].color).toBe("blue")
    expect(markers[3].offset).toBe(0x400)
    expect(markers[3].color).toBe("gray")
    expect(markers[4].offset).toBe(0x500)
    expect(markers[4].color[1]).toBe(0.1)
    expect(markers[4].color[2]).toBe(0.2)
    expect(markers[4].color[3]).toBe(0.3)
  end)

  it("setMinimapMarkers stores groupCount × groupSize ranges", function()
    local grid = oamGrid()
    grid:setMinimapMarkers({
      { offset = 0x1000, color = "red", groupCount = 16, groupSize = 16 },
      { offset = 0x2000, color = "gray", groupCount = 1, groupSize = 4 },
    })
    local markers = grid:getMinimapMarkers()
    expect(#markers).toBe(2)
    expect(markers[1].groupCount).toBe(16)
    expect(markers[1].groupSize).toBe(16)
    expect(RomHexGrid.minimapMarkerByteLength(markers[1])).toBe(256)
    expect(RomHexGrid.minimapMarkerByteLength(markers[2])).toBe(4)
  end)

  it("combined minimap markers append live selection colors after static marks", function()
    local grid = oamGrid()
    grid:setRomRaw(makeRom(512))
    grid:setMinimapMarkers({
      { offset = 0x100, color = "gray", groupCount = 1, groupSize = 4 },
    })
    grid:setSelectedAddr(0x20, { emit = false })
    local combined = grid:_combinedMinimapMarkers()
    expect(#combined).toBe(2)
    expect(combined[1].offset).toBe(0x100)
    expect(combined[1].color).toBe("gray")
    expect(combined[2].offset).toBe(0x20)
    expect(combined[2].groupSize).toBe(4)
    expect(type(combined[2].color)).toBe("table")
    expect(RomHexGrid.minimapMarkerByteLength(combined[2])).toBe(4)
    -- Static list stays occupied-only; selection is live at draw time.
    expect(#grid:getMinimapMarkers()).toBe(1)

    grid:_setStarts({ 0x20, 0x40 }, 0x40, { emit = false })
    combined = grid:_combinedMinimapMarkers()
    expect(#combined).toBe(3)
    expect(combined[2].offset).toBe(0x20)
    expect(combined[3].offset).toBe(0x40)
  end)

  it("combined minimap markers use selectedColorForAddr when provided", function()
    local grid = RomHexGrid.new({
      cols = 16,
      groupSize = 1,
      selectedColorForAddr = function()
        return { 0.1, 0.2, 0.3, 0.9 }
      end,
    })
    grid:setRomRaw(makeRom(256))
    grid:setSelectedAddr(0x11, { emit = false })
    local combined = grid:_combinedMinimapMarkers()
    expect(#combined).toBe(1)
    expect(combined[1].offset).toBe(0x11)
    expect(combined[1].color[1]).toBe(0.1)
    expect(combined[1].color[2]).toBe(0.2)
    expect(combined[1].color[3]).toBe(0.3)
  end)

  it("selectionCrosshairCell maps on-page selection to row/col", function()
    local grid = RomHexGrid.new({ cols = 16, groupSize = 1, selectionCrosshair = true })
    grid:setRomRaw(makeRom(512))
    grid.scrollOffset = 0x20
    grid:setSelectedAddr(0x2B, { emit = false })
    local row, col = grid:_selectionCrosshairCell()
    expect(row).toBe(0)
    expect(col).toBe(0xB)
    grid.scrollOffset = 0x100
    expect(grid:_selectionCrosshairCell()).toBeNil()
  end)

  it("semi-selected starts keep per-start groupSize after selection groupSize changes", function()
    local grid = RomHexGrid.new({ cols = 16, groupSize = 1, maxSelectedStarts = 1 })
    grid:setRomRaw(makeRom(512))
    grid:setSemiSelectedStarts({ 0x10, 0x40 }, {
      groupSizeByStart = { [0x10] = 8, [0x40] = 16 },
      resetColors = true,
    })
    expect(grid:getSemiGroupSize(0x10)).toBe(8)
    expect(grid:getSemiGroupSize(0x40)).toBe(16)
    expect(grid:highlightColorForStart(0x10)[1]).toBe(appColors.red[1])
    expect(grid:highlightColorForStart(0x40)[1]).toBe(appColors.green[1])

    grid:setSelectedAddr(0x10, { emit = false, resetColors = true })
    grid:setSelectedGroupSizes({ [0x10] = 8 })
    expect(grid:getGroupSize()).toBe(1)
    expect(grid:getSelectedGroupSize(0x10)).toBe(8)
    expect(#grid:getSemiSelectedStarts()).toBe(2)
    expect(grid:getSemiGroupSize(0x10)).toBe(8)
    expect(grid:getSemiGroupSize(0x40)).toBe(16)
    expect(grid:highlightColorForStart(0x10)[1]).toBe(appColors.red[1])
    expect(grid:highlightColorForStart(0x40)[1]).toBe(appColors.green[1])
  end)

  it("highlightKeyForIndex cycles red/green/blue/yellow/brown", function()
    expect(RomHexGrid.highlightKeyForIndex(1)).toBe("red")
    expect(RomHexGrid.highlightKeyForIndex(5)).toBe("brown")
    expect(RomHexGrid.highlightKeyForIndex(6)).toBe("red")
  end)
end)
