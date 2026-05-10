local ChrDiffOverlay = require("controllers.chr.chr_diff_overlay")

describe("chr_diff_overlay.lua", function()
  describe("tileBytesChanged", function()
    it("detects any byte difference in a 16-byte tile", function()
      local orig = {}
      local cur = {}
      for i = 1, 16 do
        orig[i] = i
        cur[i] = i
      end
      expect(ChrDiffOverlay.tileBytesChanged(orig, cur, 0)).toBe(false)

      cur[16] = 99
      expect(ChrDiffOverlay.tileBytesChanged(orig, cur, 0)).toBe(true)
    end)

    it("uses byte offset tileIndex * 16 (1-based arrays)", function()
      local orig = {}
      local cur = {}
      for i = 1, 32 do
        orig[i] = 0
        cur[i] = 0
      end
      cur[18] = 1
      expect(ChrDiffOverlay.tileBytesChanged(orig, cur, 1)).toBe(true)
      expect(ChrDiffOverlay.tileBytesChanged(orig, cur, 0)).toBe(false)
    end)

    it("treats missing original bank as zeros", function()
      local cur = {}
      for i = 1, 16 do
        cur[i] = 0
      end
      expect(ChrDiffOverlay.tileBytesChanged(nil, cur, 0)).toBe(false)

      cur[1] = 1
      expect(ChrDiffOverlay.tileBytesChanged(nil, cur, 0)).toBe(true)
    end)
  end)

  describe("8x16 metatile (oddEven)", function()
    it("marks both grid rows when either half-tile differs", function()
      local orig = {}
      local cur = {}
      for i = 1, 512 * 16 do
        orig[i] = 0
        cur[i] = 0
      end

      local col = 3
      local pair = 2
      local posTop = pair * 32 + col
      local posBottom = posTop + 16
      local tTop = ChrDiffOverlay.mapIndexForOrder("oddEven", posTop)
      local tBot = ChrDiffOverlay.mapIndexForOrder("oddEven", posBottom)
      expect(tTop ~= tBot).toBeTruthy()

      cur[tBot * 16 + 1] = 1

      expect(ChrDiffOverlay.cellChanged(orig, cur, "oddEven", posTop)).toBe(true)
      expect(ChrDiffOverlay.cellChanged(orig, cur, "oddEven", posBottom)).toBe(true)

      cur[tBot * 16 + 1] = 0
      expect(ChrDiffOverlay.cellChanged(orig, cur, "oddEven", posTop)).toBe(false)
    end)
  end)

  describe("normal layout", function()
    it("marks only the grid tile whose CHR bytes differ", function()
      local orig = {}
      local cur = {}
      for i = 1, 512 * 16 do
        orig[i] = 3
        cur[i] = 3
      end
      local pos = 96
      local ti = ChrDiffOverlay.mapIndexForOrder("normal", pos)
      expect(ti).toBe(pos)

      cur[ti * 16 + 1] = 8

      expect(ChrDiffOverlay.cellChanged(orig, cur, "normal", pos)).toBe(true)
      expect(ChrDiffOverlay.cellChanged(orig, cur, "normal", pos + 1)).toBe(false)

      cur[ti * 16 + 1] = 3

      cur[(ti + 1) * 16 + 10] = 9
      expect(ChrDiffOverlay.cellChanged(orig, cur, "normal", pos)).toBe(false)
      expect(ChrDiffOverlay.cellChanged(orig, cur, "normal", ti + 1)).toBe(true)

      cur[(ti + 1) * 16 + 10] = 3
      expect(ChrDiffOverlay.cellChanged(orig, cur, "normal", ti + 1)).toBe(false)
    end)
  end)
end)
