local RomHexGrid = require("ui.rom_hex_grid")
local appColors = require("app_colors")

describe("RomHexGrid", function()
  local function makeRom(n)
    return string.rep("\0", n)
  end

  local function cellPixel(col, row)
    -- PAD + gutter/header + center of cell (GUTTER_W=38, CELL_W=15, CELL_H=10, HEADER_H=12)
    return 2 + 38 + col * 15 + 2, 2 + 12 + row * 10 + 2
  end

  it("click sets selected address from scroll + cell", function()
    local selected = nil
    local grid = RomHexGrid.new({
      onSelect = function(addr)
        selected = addr
      end,
    })
    grid:setRomRaw(makeRom(512))
    grid:setPosition(0, 0)
    grid.scrollOffset = 0x20

    local hx, hy = cellPixel(0, 0)
    local hit = grid:mousepressed(hx, hy, 1, { ctrl = false })
    expect(hit).toBe(true)
    expect(selected).toBe(0x20)
    expect(grid:getSelectedAddr()).toBe(0x20)
  end)

  it("selection visually spans 4 bytes from the start address", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(256))
    grid:setSelectedAddr(0x10, { emit = false })
    local starts = grid:getSelectedStarts()
    expect(#starts).toBe(1)
    expect(starts[1]).toBe(0x10)

    local function covered(addr)
      for _, start in ipairs(grid:getSelectedStarts()) do
        if addr >= start and addr < start + RomHexGrid.OAM_SPAN then
          return true
        end
      end
      return false
    end
    expect(covered(0x10)).toBe(true)
    expect(covered(0x13)).toBe(true)
    expect(covered(0x14)).toBe(false)
  end)

  it("Ctrl+click adds one on-phase 4-byte group without filling a range", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    grid.scrollOffset = 0

    -- Select 0x10..0x13 (row 1, col 0)
    local x10, y10 = cellPixel(0, 1)
    grid:mousepressed(x10, y10, 1, { ctrl = false })
    grid:mousereleased(x10, y10, 1)

    -- 1 byte before (0x0F) → previous group 0x0C only
    local x0F, y0F = cellPixel(0x0F, 0)
    grid:mousepressed(x0F, y0F, 1, { ctrl = true })
    grid:mousereleased(x0F, y0F, 1)
    local starts = grid:getSelectedStarts()
    expect(#starts).toBe(2)
    expect(starts[1]).toBe(0x10)
    expect(starts[2]).toBe(0x0C)

    -- Farther byte (0x20) → add that group only (no intermediate fill)
    local x20, y20 = cellPixel(0, 2)
    grid:mousepressed(x20, y20, 1, { ctrl = true })
    grid:mousereleased(x20, y20, 1)
    starts = grid:getSelectedStarts()
    expect(#starts).toBe(3)
    expect(starts[1]).toBe(0x10)
    expect(starts[2]).toBe(0x0C)
    expect(starts[3]).toBe(0x20)
  end)

  it("addStartGroup does not fill intermediate groups", function()
    local starts, primary = RomHexGrid.addStartGroup({ 0x10 }, 0x20)
    expect(#starts).toBe(2)
    expect(starts[1]).toBe(0x10)
    expect(starts[2]).toBe(0x20)
    expect(primary).toBe(0x20)
  end)

  it("plain drag fills intermediate OAM groups", function()
    local starts, primary = RomHexGrid.extendStartsContiguous({ 0x10 }, 0x20)
    expect(#starts).toBe(5)
    expect(starts[1]).toBe(0x10)
    expect(starts[2]).toBe(0x14)
    expect(starts[3]).toBe(0x18)
    expect(starts[4]).toBe(0x1C)
    expect(starts[5]).toBe(0x20)
    expect(primary).toBe(0x20)
  end)

  it("Ctrl+click ignores bytes already covered by a selected span", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    grid.scrollOffset = 0

    local x0, y0 = cellPixel(0, 0)
    grid:mousepressed(x0, y0, 1, { ctrl = false })
    grid:mousereleased(x0, y0, 1)

    local x1, y1 = cellPixel(1, 0)
    grid:mousepressed(x1, y1, 1, { ctrl = true })
    grid:mousereleased(x1, y1, 1)
    local starts = grid:getSelectedStarts()
    expect(#starts).toBe(1)
    expect(starts[1]).toBe(0x00)
  end)

  it("drag multi-selects contiguous OAM groups within the current page", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(512))
    grid:setPosition(0, 0)
    grid.scrollOffset = 0

    local x0, y0 = cellPixel(0, 0)
    local x8, y8 = cellPixel(8, 0)
    grid:mousepressed(x0, y0, 1, { ctrl = false })
    expect(grid:isDragSelecting()).toBe(true)
    grid:mousemoved(x8, y8)
    grid:mousereleased(x8, y8, 1)
    expect(grid:isDragSelecting()).toBe(false)

    local starts = grid:getSelectedStarts()
    expect(#starts).toBe(3)
    expect(starts[1]).toBe(0x00)
    expect(starts[2]).toBe(0x04)
    expect(starts[3]).toBe(0x08)
  end)

  it("endDragSelect clears a stuck drag without requiring panel pressedComponent", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    local x0, y0 = cellPixel(0, 0)
    grid:mousepressed(x0, y0, 1, { ctrl = false })
    expect(grid:isDragSelecting()).toBe(true)
    expect(grid:endDragSelect()).toBe(true)
    expect(grid:isDragSelecting()).toBe(false)
    expect(grid:endDragSelect()).toBe(false)
  end)

  it("uses red/green/blue/yellow/brown from app_colors and cycles", function()
    local list = RomHexGrid.getHighlightColors()
    expect(#list).toBe(5)
    expect(list[1][1]).toBe(appColors.red[1])
    expect(list[2][1]).toBe(appColors.green[1])
    expect(list[3][1]).toBe(appColors.blue[1])
    expect(list[4][1]).toBe(appColors.yellow[1])
    expect(list[5][1]).toBe(appColors.brown[1])
    local grid = RomHexGrid.new()
    local c6 = grid:highlightColorForStartIndex(6)
    expect(c6[1]).toBe(appColors.red[1])
    -- Yellow groups use black glyphs for contrast.
    expect(grid:textColorForStartIndex(4)[1]).toBe(appColors.black[1])
    expect(grid:textColorForStartIndex(1)[1]).toBe(appColors.white[1])
  end)

  it("keeps first-selected group color when Ctrl+adding a lower address", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(512))
    grid:setSelectedAddr(0x08)
    expect(grid:highlightColorForStart(0x08)[1]).toBe(appColors.red[1])

    local starts = select(1, RomHexGrid.addStartGroup(grid:getSelectedStarts(), 0x00))
    grid:_setStarts(starts, 0x00, { emit = false, resetColors = false })

    expect(#grid:getSelectedStarts()).toBe(2)
    expect(grid:highlightColorForStart(0x08)[1]).toBe(appColors.red[1])
    expect(grid:highlightColorForStart(0x00)[1]).toBe(appColors.green[1])
    -- List order is selection order: first-selected 0x08 stays red at index 1.
    expect(grid:highlightColorForStartIndex(1)[1]).toBe(appColors.red[1])
    expect(grid:highlightColorForStartIndex(2)[1]).toBe(appColors.green[1])
  end)

  it("plain click resets the color sequence", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    local x8, y8 = cellPixel(8, 0)
    local x0, y0 = cellPixel(0, 0)
    grid:mousepressed(x8, y8, 1, { ctrl = false })
    grid:mousereleased(x8, y8, 1)
    grid:mousepressed(x0, y0, 1, { ctrl = true })
    grid:mousereleased(x0, y0, 1)
    expect(grid:highlightColorForStart(0x08)[1]).toBe(appColors.red[1])

    grid:mousepressed(x0, y0, 1, { ctrl = false })
    grid:mousereleased(x0, y0, 1)
    expect(grid:getSelectedStarts()[1]).toBe(0x00)
    expect(grid:highlightColorForStart(0x00)[1]).toBe(appColors.red[1])
  end)

  it("caps selection at 8 groups and reports selectionCapHit", function()
    local capHits = 0
    local grid = RomHexGrid.new({
      onSelect = function(_, opts)
        if opts and opts.selectionCapHit then
          capHits = capHits + 1
        end
      end,
    })
    grid:setRomRaw(makeRom(512))
    -- 9 contiguous groups: 0x00 .. 0x20
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

  it("wheel steps 8 rows; Shift+wheel steps 64 rows", function()
    local grid = RomHexGrid.new()
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
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(200))
    grid.scrollOffset = 9999
    grid:clampScroll()
    expect(grid.scrollOffset).toBe(grid:maxScroll())
    expect(grid.scrollOffset % 16).toBe(0)

    grid.scrollOffset = -50
    grid:clampScroll()
    expect(grid.scrollOffset).toBe(0)
  end)

  it("scrollToReveal brings off-screen selection into view", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(2048))
    grid.scrollOffset = 0
    grid:scrollToReveal(0x200)
    expect(grid.scrollOffset <= 0x200).toBe(true)
    expect(grid.scrollOffset + RomHexGrid.BYTES_PER_PAGE - 1).toBeGreaterThanOrEqual(0x200)
  end)

  it("snaps a click 2 bytes before an occupied group to the preceding 4-byte start", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(256))
    grid:setPosition(0, 0)
    grid:setOccupiedStarts({ 0x2A })
    -- Click two bytes before gray start 0x2A → select 0x26..0x29.
    expect(grid:resolveSelectableStart(0x28)).toBe(0x26)
    grid:setSelectedAddr(0x28, { emit = false })
    expect(grid:getSelectedStarts()).toEqual({ 0x26 })
  end)

  it("does not select when clicking inside an occupied gray span", function()
    local grid = RomHexGrid.new()
    grid:setRomRaw(makeRom(256))
    grid:setSelectedAddr(0x10, { emit = false })
    grid:setOccupiedStarts({ 0x2A })
    expect(grid:resolveSelectableStart(0x2B)).toBeNil()
    grid:setSelectedAddr(0x2B, { emit = false })
    expect(grid:getSelectedStarts()).toEqual({ 0x10 })
  end)
end)
