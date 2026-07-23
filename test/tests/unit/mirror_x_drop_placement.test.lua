local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")

local F = assert(loadfile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "mirror_x_drop_fixtures.lua"))()

describe("mirror X drop - placement results", function()
  local function dropOnto(dst, group, srcWin, screenX, screenY, extraItems)
    local items = {}
    for _, e in ipairs(group.entries) do
      items[#items + 1] = e.item
    end
    if group.spriteEntries then
      for _, e in ipairs(group.spriteEntries) do
        items[#items + 1] = e.item
        if e.bottomItem then
          items[#items + 1] = e.bottomItem
        end
      end
    end
    if extraItems then
      for _, it in ipairs(extraItems) do
        items[#items + 1] = it
      end
    end

    local wm = {
      windowAt = function()
        return dst
      end,
      setFocus = function() end,
    }
    local cleared = nil
    local handled = MouseTileDropController.handleTileDrop({
      ctx = {
        app = {
          appEditState = {
            tilesPool = F.poolForItems(items),
          },
        },
      },
      drag = {
        active = true,
        item = group.entries[1].item,
        tileGroup = group,
        srcWin = srcWin,
        srcLayer = 1,
      },
      clearDragState = function(commit)
        cleared = commit
      end,
    }, screenX, screenY, wm)
    return handled, cleared
  end

  describe("8x8 sprite layer placement", function()
    it("places a single tile at the remapped point when destination is mirrored", function()
      F.withUnfocusedCtx(function()
        local a = F.item(4)
        local group = F.makeGroup({
          { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = a },
        })
        local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = true, useRealMirrorRemap = true })
        local handled = dropOnto(dst, group, { kind = "chr" }, 10, 20)
        expect(handled).toBe(true)
        expect(#dst.layers[1].items).toBe(1)
        expect(dst.layers[1].items[1].worldX).toBe(54)
        expect(dst.layers[1].items[1].worldY).toBe(20)
        expect(dst.layers[1].items[1].mirrorX).toBe(false)
      end)
    end)

    it("places contiguous multi with remapped anchor and unflipped offsets for destination-only mirror", function()
      F.withUnfocusedCtx(function()
        local group = F.contiguousRow(3, 4)
        local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = true, useRealMirrorRemap = true })
        -- Visual x=24 -> data 40; offsets stay 0,+8,+16 => 40,48,56 (56 is max for 8px sprite in 64).
        local handled = dropOnto(dst, group, { kind = "chr" }, 24, 8)
        expect(handled).toBe(true)
        expect(#dst.layers[1].items).toBe(3)
        local xs = {}
        for _, s in ipairs(dst.layers[1].items) do
          xs[#xs + 1] = s.worldX
          expect(s.mirrorX).toBe(false)
        end
        table.sort(xs)
        expect(xs).toEqual({ 40, 48, 56 })
      end)
    end)

    it("places gapped multi with source-relative offsets and no individual mirrorX", function()
      F.withUnfocusedCtx(function()
        local group = F.gappedRowTwo()
        group.entries[1].item = F.item(4)
        group.entries[2].item = F.item(5)
        local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = true, useRealMirrorRemap = true })
        -- Visual x=24 -> data 40; offsets 0 and +16 => 40 and 56.
        local handled = dropOnto(dst, group, { kind = "chr" }, 24, 8)
        expect(handled).toBe(true)
        expect(#dst.layers[1].items).toBe(2)
        local xs = {}
        for _, s in ipairs(dst.layers[1].items) do
          xs[#xs + 1] = s.worldX
          expect(s.mirrorX == true).toBe(false)
        end
        table.sort(xs)
        expect(xs).toEqual({ 40, 56 })
      end)
    end)

    it("places contiguous multi with source-only mirror using leftward offsets", function()
      local group = F.contiguousRow(3, 4)
      local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = false })
      local handled = dropOnto(dst, group, { kind = "chr", _mirrorXPreview = true }, 24, 8)
      expect(handled).toBe(true)
      local xs = {}
      for _, s in ipairs(dst.layers[1].items) do
        xs[#xs + 1] = s.worldX
      end
      table.sort(xs)
      expect(xs).toEqual({ 8, 16, 24 })
    end)

    it("places with unflipped offsets when both windows are mirrored", function()
      F.withUnfocusedCtx(function()
        local group = F.contiguousRow(2, 4)
        local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = true, useRealMirrorRemap = true })
        local handled = dropOnto(dst, group, { kind = "chr", _mirrorXPreview = true }, 24, 8)
        expect(handled).toBe(true)
        local xs = {}
        for _, s in ipairs(dst.layers[1].items) do
          xs[#xs + 1] = s.worldX
        end
        table.sort(xs)
        expect(xs).toEqual({ 40, 48 })
      end)
    end)

    it("places with unflipped offsets when neither window is mirrored", function()
      local group = F.contiguousRow(2, 4)
      local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = false })
      local handled = dropOnto(dst, group, { kind = "chr" }, 16, 8)
      expect(handled).toBe(true)
      local xs = {}
      for _, s in ipairs(dst.layers[1].items) do
        xs[#xs + 1] = s.worldX
      end
      table.sort(xs)
      expect(xs).toEqual({ 16, 24 })
    end)
  end)

  describe("8x16 sprite layer placement", function()
    it("places 8x16 pair tops with remapped anchor and unflipped offsets for destination-only mirror", function()
      F.withUnfocusedCtx(function()
        local group, topA, botA, topB, botB = F.make8x16Group()
        local dst = F.makeSpriteWindow(8, 8, "8x16", { mirror = true, useRealMirrorRemap = true })
        local handled = dropOnto(
          dst,
          group,
          { kind = "chr", orderMode = "oddEven" },
          24,
          8,
          { topA, botA, topB, botB }
        )
        expect(handled).toBe(true)
        expect(#dst.layers[1].items).toBe(2)
        local xs = {}
        for _, s in ipairs(dst.layers[1].items) do
          xs[#xs + 1] = s.worldX
          expect(s.mirrorX == true).toBe(false)
        end
        table.sort(xs)
        expect(xs).toEqual({ 40, 48 })
      end)
    end)

    it("places gapped 8x16 pairs with source-relative hole under destination mirror", function()
      F.withUnfocusedCtx(function()
        local group, topA, botA, topC, botC = F.make8x16GappedGroup()
        local dst = F.makeSpriteWindow(8, 8, "8x16", { mirror = true, useRealMirrorRemap = true })
        local handled = dropOnto(
          dst,
          group,
          { kind = "chr", orderMode = "oddEven" },
          24,
          8,
          { topA, botA, topC, botC }
        )
        expect(handled).toBe(true)
        expect(#dst.layers[1].items).toBe(2)
        local xs = {}
        for _, s in ipairs(dst.layers[1].items) do
          xs[#xs + 1] = s.worldX
        end
        table.sort(xs)
        expect(xs).toEqual({ 40, 56 })
      end)
    end)
  end)

  describe("tile layer placement", function()
    it("writes contiguous tiles with remapped anchor and unflipped offsets for destination-only mirror", function()
      F.withUnfocusedCtx(function()
        local group = F.contiguousRow(2, 4)
        local dst = F.makeTileWindow(8, 8, { mirror = true, useRealMirrorRemap = true })
        -- Visual x=24 -> data 40 -> col 5; unflipped 5 and 6.
        local handled = dropOnto(dst, group, { kind = "chr" }, 24, 8)
        expect(handled).toBe(true)
        expect(dst:get(5, 1) and dst:get(5, 1).index).toBe(4)
        expect(dst:get(6, 1) and dst:get(6, 1).index).toBe(5)
      end)
    end)

    it("writes gapped tiles preserving source-relative offsets under destination mirror", function()
      F.withUnfocusedCtx(function()
        local group = F.gappedRowTwo()
        group.entries[1].item = F.item(4)
        group.entries[2].item = F.item(5)
        local dst = F.makeTileWindow(8, 8, { mirror = true, useRealMirrorRemap = true })
        -- Visual x=24 -> data 40 -> col 5; offsets 0 and +2 => cols 5 and 7.
        local handled = dropOnto(dst, group, { kind = "chr" }, 24, 8)
        expect(handled).toBe(true)
        expect(dst:get(5, 1) and dst:get(5, 1).index).toBe(4)
        expect(dst:get(7, 1) and dst:get(7, 1).index).toBe(5)
        expect(dst:get(6, 1)).toBeNil()
      end)
    end)

    it("writes unflipped columns when both sides are mirrored", function()
      F.withUnfocusedCtx(function()
        local group = F.contiguousRow(2, 4)
        local dst = F.makeTileWindow(8, 8, { mirror = true, useRealMirrorRemap = true })
        local handled = dropOnto(dst, group, { kind = "chr", _mirrorXPreview = true }, 24, 8)
        expect(handled).toBe(true)
        -- x=24 -> remap 40 -> col 5; unflipped 5 and 6.
        expect(dst:get(5, 1) and dst:get(5, 1).index).toBe(4)
        expect(dst:get(6, 1) and dst:get(6, 1).index).toBe(5)
      end)
    end)

    it("writes flipped columns when source alone is mirrored into an unmirrored tile window", function()
      local group = F.contiguousRow(2, 4)
      local dst = F.makeTileWindow(8, 8, { mirror = false })
      local handled = dropOnto(dst, group, { kind = "chr", _mirrorXPreview = true }, 24, 8)
      expect(handled).toBe(true)
      -- Anchor col 3 (x=24); flipped offsets 0 and -1 => cols 3 and 2.
      expect(dst:get(3, 1) and dst:get(3, 1).index).toBe(4)
      expect(dst:get(2, 1) and dst:get(2, 1).index).toBe(5)
    end)
  end)
end)
