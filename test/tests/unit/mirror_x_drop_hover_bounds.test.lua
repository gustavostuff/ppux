local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")

local F = assert(loadfile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "mirror_x_drop_fixtures.lua"))()

describe("mirror X drop - hover bounds and validity", function()
  local function hoverSprite(env, x, y, dst)
    local wm = {
      windowAt = function()
        return dst
      end,
    }
    return MouseTileDropController.getHoverDropState(env, x, y, wm)
  end

  local function tooltip(env, x, y, dst)
    local wm = {
      windowAt = function()
        return dst
      end,
    }
    return MouseTileDropController.getHoverTooltipCandidate(env, x, y, wm)
  end

  describe("8x8 sprite destination, destination mirrored", function()
    it("rejects contiguous multi near visual left when offsets stay source-relative", function()
      F.withUnfocusedCtx(function()
        local group = F.contiguousRow(3, 4)
        local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = true, useRealMirrorRemap = true })
        -- Visual x=10 -> data x=54. Unflipped 0..16 => 54,62,70 overflows.
        local state = hoverSprite({
          drag = {
            active = true,
            item = group.entries[1].item,
            tileGroup = group,
            srcWin = { kind = "chr" },
          },
        }, 10, 8, dst)
        expect(state.valid).toBe(false)
        expect(state.reason).toBe("out_of_bounds")
        expect(state.anchorPixelX).toBe(54)
      end)
    end)

    it("rejects contiguous multi near visual left when neither side is mirrored", function()
      local group = F.contiguousRow(3, 4)
      local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = false })
      local candidate = tooltip({
        drag = {
          active = true,
          item = group.entries[1].item,
          tileGroup = group,
          srcWin = { kind = "chr" },
        },
      }, 56, 8, dst)
      expect(candidate).toBeTruthy()
      expect(candidate.text).toBe("out of bounds")
    end)

    it("accepts gapped multi with remapped anchor and source-relative offsets", function()
      F.withUnfocusedCtx(function()
        local group = F.gappedRowTwo()
        group.entries[1].item = F.item(4)
        group.entries[2].item = F.item(5)
        local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = true, useRealMirrorRemap = true })
        -- Visual x=24 -> data 40; offsets 0 and +16 => 40 and 56.
        local state = hoverSprite({
          drag = {
            active = true,
            item = group.entries[1].item,
            tileGroup = group,
            srcWin = { kind = "chr" },
          },
        }, 24, 8, dst)
        expect(state.valid).toBe(true)
        local byItem = {}
        for _, p in ipairs(state.placements) do
          byItem[p.item.index] = p.pixelX
        end
        expect(byItem[4]).toBe(40)
        expect(byItem[5]).toBe(56)
      end)
    end)

    it("single selection stays valid at remapped anchor", function()
      F.withUnfocusedCtx(function()
        local a = F.item(4)
        local group = F.makeGroup({ F.singleEntry(0, 0, 4) })
        group.entries[1].item = a
        local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = true, useRealMirrorRemap = true })
        local state = hoverSprite({
          drag = {
            active = true,
            item = a,
            tileGroup = group,
            srcWin = { kind = "chr" },
          },
        }, 12, 20, dst)
        expect(state.valid).toBe(true)
        expect(state.placements[1].pixelX).toBe(52)
        expect(state.placements[1].pixelY).toBe(20)
      end)
    end)
  end)

  describe("8x8 sprite destination, source mirrored only", function()
    it("flips group layout for bounds using source-only mirror", function()
      local group = F.contiguousRow(3, 4)
      local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = false })
      -- Anchor at x=8; flipped offsets extend left into negative -> OOB.
      local state = hoverSprite({
        drag = {
          active = true,
          item = group.entries[1].item,
          tileGroup = group,
          srcWin = { kind = "chr", _mirrorXPreview = true },
        },
      }, 8, 8, dst)
      expect(state.valid).toBe(false)
      expect(state.reason).toBe("out_of_bounds")
    end)

    it("accepts source-mirrored group when anchor has room on the left", function()
      local group = F.contiguousRow(3, 4)
      local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = false })
      local state = hoverSprite({
        drag = {
          active = true,
          item = group.entries[1].item,
          tileGroup = group,
          srcWin = { kind = "chr", _mirrorXPreview = true },
        },
      }, 24, 8, dst)
      expect(state.valid).toBe(true)
      local xs = {}
      for _, p in ipairs(state.placements) do
        xs[#xs + 1] = p.pixelX
      end
      table.sort(xs)
      expect(xs).toEqual({ 8, 16, 24 })
    end)
  end)

  describe("both mirrored", function()
    it("does not flip offsets; remapped anchor alone drives placement", function()
      F.withUnfocusedCtx(function()
        local group = F.contiguousRow(2, 4)
        local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = true, useRealMirrorRemap = true })
        local state = hoverSprite({
          drag = {
            active = true,
            item = group.entries[1].item,
            tileGroup = group,
            srcWin = { kind = "chr", _mirrorXPreview = true },
          },
        }, 10, 8, dst)
        -- Remap 10->54, unflipped offsets 0 and +8 => 54 and 62, but maxWorldX=56 => OOB.
        expect(state.valid).toBe(false)
        expect(state.reason).toBe("out_of_bounds")
      end)
    end)

    it("accepts both-mirrored contiguous pair with room after remap", function()
      F.withUnfocusedCtx(function()
        local group = F.contiguousRow(2, 4)
        local dst = F.makeSpriteWindow(8, 8, "8x8", { mirror = true, useRealMirrorRemap = true })
        -- Visual x=24 -> data 40; 40 and 48 fit under max 56.
        local state = hoverSprite({
          drag = {
            active = true,
            item = group.entries[1].item,
            tileGroup = group,
            srcWin = { kind = "chr", _mirrorXPreview = true },
          },
        }, 24, 8, dst)
        expect(state.valid).toBe(true)
        expect(state.placements[1].pixelX).toBe(40)
        expect(state.placements[2].pixelX).toBe(48)
      end)
    end)
  end)

  describe("8x16 sprite destination", function()
    it("uses source-relative spriteEntries with remapped anchor for destination-only mirror", function()
      F.withUnfocusedCtx(function()
        local group = F.make8x16Group()
        local dst = F.makeSpriteWindow(8, 8, "8x16", { mirror = true, useRealMirrorRemap = true })
        local state = hoverSprite({
          drag = {
            active = true,
            item = group.spriteEntries[1].item,
            tileGroup = group,
            srcWin = { kind = "chr", orderMode = "oddEven" },
          },
        }, 24, 8, dst)
        expect(state.valid).toBe(true)
        expect(#state.placements).toBe(2)
        local xs = {}
        for _, p in ipairs(state.placements) do
          xs[#xs + 1] = p.pixelX
        end
        table.sort(xs)
        expect(xs).toEqual({ 40, 48 })
      end)
    end)

    it("blocks 8x8 multi into 8x16 regardless of mirror flags", function()
      local group = F.contiguousRow(2, 4)
      local dst = F.makeSpriteWindow(8, 8, "8x16", { mirror = true })
      local candidate = tooltip({
        drag = {
          active = true,
          item = group.entries[1].item,
          tileGroup = group,
          srcWin = { kind = "chr" },
        },
      }, 8, 8, dst)
      expect(candidate.text).toBe("8x8 tile payload cannot drop into 8x16 sprite layer")
    end)
  end)

  describe("tile-layer destination hover", function()
    it("reports out of bounds for contiguous multi overflowing an unmirrored tile window", function()
      local group = F.contiguousRow(2, 1)
      local dst = F.makeTileWindow(4, 4, { mirror = false })
      local candidate = tooltip({
        drag = {
          active = true,
          item = group.entries[1].item,
          tileGroup = group,
          srcWin = { kind = "chr" },
        },
      }, 24, 0, dst)
      expect(candidate.text).toBe("out of bounds")
    end)

    it("accepts destination-mirrored contiguous multi near visual left via remapped grid", function()
      F.withUnfocusedCtx(function()
        local group = F.contiguousRow(2, 1)
        local dst = F.makeTileWindow(8, 8, { mirror = true, useRealMirrorRemap = true })
        local state = hoverSprite({
          drag = {
            active = true,
            item = group.entries[1].item,
            tileGroup = group,
            srcWin = { kind = "chr" },
          },
        }, 16, 8, dst)
        -- Tile layer: remapped col from x=16 is col 6 (48/8); offsets stay 0 and +1 => cols 6 and 7.
        expect(state.valid).toBe(true)
        expect(state.anchorCol).toBe(6)
        expect(state.placements[1].col).toBe(6)
        expect(state.placements[2].col).toBe(7)
      end)
    end)
  end)
end)
