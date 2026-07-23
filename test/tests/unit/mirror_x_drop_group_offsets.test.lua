local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")

local F = assert(loadfile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "mirror_x_drop_fixtures.lua"))()

describe("mirror X drop - group offset resolution", function()
  local function expectUnchanged(group, srcMirror, dstMirror)
    local src = F.winFlags(srcMirror)
    local dst = F.dstFlags(dstMirror)
    local resolved = MouseTileDropController.resolveDropTileGroup(group, src, dst)
    expect(resolved).toBe(group)
  end

  local function expectNegatedOffsets(group, srcMirror, dstMirror)
    local src = F.winFlags(srcMirror)
    local dst = F.dstFlags(dstMirror)
    local resolved = MouseTileDropController.resolveDropTileGroup(group, src, dst)
    expect(resolved).toNotBe(group)
    for i, entry in ipairs(group.entries) do
      expect(resolved.entries[i].offsetCol).toBe(-(entry.offsetCol or 0))
      expect(resolved.entries[i].offsetRow).toBe(entry.offsetRow or 0)
      expect(resolved.entries[i].item).toBe(entry.item)
    end
    expect(resolved.minOffsetCol).toBe(-(group.maxOffsetCol or 0))
    expect(resolved.maxOffsetCol).toBe(-(group.minOffsetCol or 0))
  end

  describe("mirror combination matrix (8x8 contiguous multi)", function()
    local group = F.contiguousRow(3)

    it("no mirror on either side leaves offsets unchanged", function()
      expectUnchanged(group, false, false)
    end)

    it("both mirrored leaves offsets unchanged", function()
      expectUnchanged(group, true, true)
    end)

    it("source only mirrored negates offsetCols around anchor", function()
      expectNegatedOffsets(group, true, false)
    end)

    it("destination only mirrored leaves offsets unchanged (window transform handles it)", function()
      expectUnchanged(group, false, true)
    end)
  end)

  describe("single selection", function()
    local group = F.makeGroup({ F.singleEntry(0, 0, 9) })

    it("stays at offset 0 for every mirror combination", function()
      for _, srcM in ipairs({ false, true }) do
        for _, dstM in ipairs({ false, true }) do
          local resolved = MouseTileDropController.resolveDropTileGroup(group, F.winFlags(srcM), F.dstFlags(dstM))
          expect(resolved.entries[1].offsetCol).toBe(0)
        end
      end
    end)
  end)

  describe("contiguous multi-selection", function()
    it("leaves a 2-wide row unchanged when destination alone is mirrored", function()
      local group = F.contiguousRow(2)
      local resolved = MouseTileDropController.resolveDropTileGroup(group, F.winFlags(false), F.dstFlags(true))
      expect(resolved).toBe(group)
      expect(F.sortedOffsetCols(resolved.entries)).toEqual({ 0, 1 })
    end)

    it("flips a 4-wide row when source alone is mirrored", function()
      local group = F.contiguousRow(4, 10)
      local resolved = MouseTileDropController.resolveDropTileGroup(group, F.winFlags(true), F.dstFlags(false))
      expect(resolved.minOffsetCol).toBe(-3)
      expect(resolved.maxOffsetCol).toBe(0)
      expect(F.offsetsByItemIndex(resolved.entries)[10]).toBe(0)
      expect(F.offsetsByItemIndex(resolved.entries)[13]).toBe(-3)
    end)
  end)

  describe("non-contiguous multi-selection", function()
    it("keeps gapped row offsets when destination alone is mirrored", function()
      local group = F.gappedRowTwo()
      local resolved = MouseTileDropController.resolveDropTileGroup(group, F.winFlags(false), F.dstFlags(true))
      expect(resolved).toBe(group)
      expect(F.offsetsByItemIndex(resolved.entries)[1]).toBe(0)
      expect(F.offsetsByItemIndex(resolved.entries)[2]).toBe(2)
    end)

    it("flips only X for a gapped 2D shape when source alone is mirrored", function()
      local group = F.gappedShape()
      local resolved = MouseTileDropController.resolveDropTileGroup(group, F.winFlags(true), F.dstFlags(false))
      local byIdx = F.offsetsByItemIndex(resolved.entries)
      expect(byIdx[1]).toBe(0)
      expect(byIdx[2]).toBe(-2)
      expect(byIdx[3]).toBe(-2)
      expect(resolved.entries[3].offsetRow).toBe(1)
    end)

    it("both mirrored keeps gapped shape offsets identical", function()
      local group = F.gappedShape()
      expectUnchanged(group, true, true)
    end)
  end)

  describe("8x16 spriteEntries", function()
    it("leaves spriteEntries unchanged for destination-only mirror", function()
      local group = F.make8x16Group()
      local resolved = MouseTileDropController.resolveDropTileGroup(group, F.winFlags(false), F.dstFlags(true))
      expect(resolved).toBe(group)
      expect(resolved.spriteEntries[2].offsetCol).toBe(1)
    end)

    it("mirrors gapped 8x16 spriteEntries when source alone is mirrored", function()
      local group = select(1, F.make8x16GappedGroup())
      local resolved = MouseTileDropController.resolveDropTileGroup(group, F.winFlags(true), F.dstFlags(false))
      expect(resolved.spriteEntries[1].offsetCol).toBe(0)
      expect(resolved.spriteEntries[2].offsetCol).toBe(-2)
      expect(resolved.spriteMinOffsetCol).toBe(-2)
      expect(resolved.spriteMaxOffsetCol).toBe(0)
    end)

    it("leaves 8x16 spriteEntries unchanged when both windows are mirrored", function()
      local group = F.make8x16Group()
      local resolved = MouseTileDropController.resolveDropTileGroup(group, F.winFlags(true), F.dstFlags(true))
      expect(resolved).toBe(group)
      expect(resolved.spriteEntries[2].offsetCol).toBe(1)
    end)
  end)

  it("returns nil for a nil group", function()
    expect(MouseTileDropController.resolveDropTileGroup(nil, F.winFlags(true), F.dstFlags(false))).toBeNil()
  end)

  it("ignores palette windows as mirror sources for offset flipping", function()
    local group = F.contiguousRow(2)
    local src = { kind = "rom_palette", _mirrorXPreview = true, isPalette = true }
    local WindowCaps = require("controllers.window.window_capabilities")
    if WindowCaps.isAnyPaletteWindow(src) then
      local resolved = MouseTileDropController.resolveDropTileGroup(group, src, F.dstFlags(false))
      expect(resolved).toBe(group)
    end
  end)
end)
