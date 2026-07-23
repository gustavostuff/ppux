local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")

local F = assert(loadfile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "mirror_x_drop_fixtures.lua"))()

describe("mirror X clipboard paste - group layout only", function()
  beforeEach(function()
    KeyboardClipboardController.reset()
  end)

  local function makeStaticTileWin(cols, rows, opts)
    opts = opts or {}
    local grid = {}
    for r = 0, rows - 1 do
      grid[r] = {}
      for c = 0, cols - 1 do
        grid[r][c] = nil
      end
    end
    local multi = opts.multi or {}
    local win = {
      kind = "static_art",
      _mirrorXPreview = opts.mirror == true,
      cols = cols,
      rows = rows,
      cellW = 8,
      cellH = 8,
      layers = {
        {
          kind = "tile",
          multiTileSelection = multi,
          removedCells = {},
        },
      },
      getActiveLayerIndex = function()
        return 1
      end,
      getSelected = function()
        return opts.selCol or 0, opts.selRow or 0, 1
      end,
      get = function(_, col, row)
        return grid[row] and grid[row][col]
      end,
      set = function(_, col, row, item)
        grid[row] = grid[row] or {}
        grid[row][col] = item
      end,
      setSelected = function(_, col, row)
        opts.selCol, opts.selRow = col, row
      end,
      clearSelected = function() end,
    }
    win._grid = grid
    return win
  end

  local function makeSpriteWin(cols, rows, mode, opts)
    opts = opts or {}
    local layer = {
      kind = "sprite",
      mode = mode or "8x8",
      items = opts.items or {},
      selectedSpriteIndex = opts.selectedSpriteIndex,
      originX = 0,
      originY = 0,
    }
    if opts.selectedIndices then
      local SpriteController = require("controllers.sprite.sprite_controller")
      -- Selection is usually stored on layer; tests set selectedSpriteIndex / items directly.
      layer._testSelected = opts.selectedIndices
    end
    return {
      kind = "static_art",
      _mirrorXPreview = opts.mirror == true,
      cols = cols,
      rows = rows,
      cellW = 8,
      cellH = 8,
      layers = { layer },
      getActiveLayerIndex = function()
        return 1
      end,
    }, layer
  end

  local function ctxWithStatus()
    local status = nil
    return {
      setStatus = function(text)
        status = text
      end,
      app = {
        appEditState = { tilesPool = {} },
        markUnsaved = function() end,
      },
      _status = function()
        return status
      end,
    }, function()
      return status
    end
  end

  describe("tile clipboard", function()
    it("pastes contiguous multi unflipped when neither side is mirrored", function()
      local a, b = F.item(1), F.item(2)
      local source = makeStaticTileWin(8, 4, {
        mirror = false,
        multi = { [1] = true, [2] = true }, -- cols 0 and 1 on row 0
        selCol = 0,
        selRow = 0,
      })
      source:set(0, 0, a)
      source:set(1, 0, b)
      -- multiTileSelection keys are linear indices: row*cols+col+1
      source.layers[1].multiTileSelection = { [1] = true, [2] = true }

      local dest = makeStaticTileWin(8, 4, { mirror = false, selCol = 3, selRow = 1 })
      local ctx = select(1, ctxWithStatus())

      expect(KeyboardClipboardController.performClipboardAction(ctx, source, "copy")).toBe(true)
      expect(KeyboardClipboardController.performClipboardAction(ctx, dest, "paste")).toBe(true)
      expect(dest:get(3, 1) and dest:get(3, 1).index).toBe(1)
      expect(dest:get(4, 1) and dest:get(4, 1).index).toBe(2)
    end)

    it("keeps contiguous multi layout when pasting into a mirrored tile destination", function()
      local a, b, c = F.item(1), F.item(2), F.item(3)
      local source = makeStaticTileWin(8, 4, { mirror = false, selCol = 0, selRow = 0 })
      source:set(0, 0, a)
      source:set(1, 0, b)
      source:set(2, 0, c)
      source.layers[1].multiTileSelection = { [1] = true, [2] = true, [3] = true }

      local dest = makeStaticTileWin(8, 4, { mirror = true, selCol = 4, selRow = 2 })
      local ctx = select(1, ctxWithStatus())

      expect(KeyboardClipboardController.performClipboardAction(ctx, source, "copy")).toBe(true)
      expect(KeyboardClipboardController.performClipboardAction(ctx, dest, "paste")).toBe(true)
      -- Tile dest Mirror X does not reorder the group; paste at selection anchor.
      expect(dest:get(4, 2) and dest:get(4, 2).index).toBe(1)
      expect(dest:get(5, 2) and dest:get(5, 2).index).toBe(2)
      expect(dest:get(6, 2) and dest:get(6, 2).index).toBe(3)
    end)

    it("keeps gapped multi layout when pasting into a mirrored tile destination", function()
      local a, b = F.item(1), F.item(2)
      local source = makeStaticTileWin(8, 4, { mirror = false, selCol = 0, selRow = 0 })
      source:set(0, 0, a)
      source:set(2, 0, b)
      source.layers[1].multiTileSelection = { [1] = true, [3] = true }

      local dest = makeStaticTileWin(8, 4, { mirror = true, selCol = 3, selRow = 1 })
      local ctx = select(1, ctxWithStatus())

      expect(KeyboardClipboardController.performClipboardAction(ctx, source, "copy")).toBe(true)
      expect(KeyboardClipboardController.performClipboardAction(ctx, dest, "paste")).toBe(true)
      expect(dest:get(3, 1) and dest:get(3, 1).index).toBe(1)
      expect(dest:get(5, 1) and dest:get(5, 1).index).toBe(2)
      expect(dest:get(4, 1)).toBeNil()
    end)

    it("does not re-mirror when copying from a mirrored window into a mirrored window", function()
      local a, b = F.item(1), F.item(2)
      local source = makeStaticTileWin(8, 4, { mirror = true, selCol = 0, selRow = 0 })
      source:set(0, 0, a)
      source:set(1, 0, b)
      source.layers[1].multiTileSelection = { [1] = true, [2] = true }

      local dest = makeStaticTileWin(8, 4, { mirror = true, selCol = 2, selRow = 0 })
      local ctx = select(1, ctxWithStatus())

      expect(KeyboardClipboardController.performClipboardAction(ctx, source, "copy")).toBe(true)
      expect(KeyboardClipboardController.performClipboardAction(ctx, dest, "paste")).toBe(true)
      expect(dest:get(2, 0) and dest:get(2, 0).index).toBe(1)
      expect(dest:get(3, 0) and dest:get(3, 0).index).toBe(2)
    end)

    it("mirrors when copying from a mirrored source into an unmirrored destination", function()
      local a, b = F.item(1), F.item(2)
      local source = makeStaticTileWin(8, 4, { mirror = true, selCol = 0, selRow = 0 })
      source:set(0, 0, a)
      source:set(1, 0, b)
      source.layers[1].multiTileSelection = { [1] = true, [2] = true }

      local dest = makeStaticTileWin(8, 4, { mirror = false, selCol = 2, selRow = 1 })
      local ctx = select(1, ctxWithStatus())

      expect(KeyboardClipboardController.performClipboardAction(ctx, source, "copy")).toBe(true)
      expect(KeyboardClipboardController.performClipboardAction(ctx, dest, "paste")).toBe(true)
      expect(dest:get(2, 1) and dest:get(2, 1).index).toBe(2)
      expect(dest:get(3, 1) and dest:get(3, 1).index).toBe(1)
    end)

    it("pastes a single tile at the anchor for every mirror combination", function()
      for _, srcM in ipairs({ false, true }) do
        for _, dstM in ipairs({ false, true }) do
          KeyboardClipboardController.reset()
          local a = F.item(9)
          local source = makeStaticTileWin(4, 4, { mirror = srcM, selCol = 1, selRow = 1 })
          source:set(1, 1, a)
          source.layers[1].multiTileSelection = { [1 + 1 * 4 + 1] = true } -- row1 col1 -> index 6
          -- Fix: linear index = row * cols + col + 1 = 1*4+1+1 = 6
          source.layers[1].multiTileSelection = { [6] = true }

          local dest = makeStaticTileWin(4, 4, { mirror = dstM, selCol = 2, selRow = 2 })
          local ctx = select(1, ctxWithStatus())
          expect(KeyboardClipboardController.performClipboardAction(ctx, source, "copy")).toBe(true)
          expect(KeyboardClipboardController.performClipboardAction(ctx, dest, "paste")).toBe(true)
          expect(dest:get(2, 2) and dest:get(2, 2).index).toBe(9)
        end
      end
    end)
  end)

  describe("sprite clipboard", function()
    it("keeps sprite group positions when pasting into a mirrored destination without toggling mirrorX", function()
      local SpriteController = require("controllers.sprite.sprite_controller")
      local s1 = { worldX = 0, worldY = 0, x = 0, y = 0, mirrorX = false, removed = false }
      local s2 = { worldX = 16, worldY = 0, x = 16, y = 0, mirrorX = false, removed = false }
      local source, sourceLayer = makeSpriteWin(8, 4, "8x8", {
        mirror = false,
        items = { s1, s2 },
      })
      SpriteController.setSpriteSelection(sourceLayer, { 1, 2 })

      local dest, destLayer = makeSpriteWin(8, 4, "8x8", { mirror = true, items = {} })
      destLayer.selectedSpriteIndex = nil
      local ctx = select(1, ctxWithStatus())

      expect(KeyboardClipboardController.performClipboardAction(ctx, source, "copy")).toBe(true)
      expect(KeyboardClipboardController.performClipboardAction(ctx, dest, "paste")).toBe(true)
      expect(#destLayer.items).toBe(2)
      local xs = {}
      for _, s in ipairs(destLayer.items) do
        xs[#xs + 1] = s.worldX
        expect(s.mirrorX == true).toBe(false)
      end
      table.sort(xs)
      -- Dest Mirror X does not reorder; window transform handles visual mirror.
      expect(xs).toEqual({ 0, 16 })
    end)

    it("keeps sprite mirrorX flags from the clipboard payload without dest group reorder", function()
      local SpriteController = require("controllers.sprite.sprite_controller")
      local s1 = {
        worldX = 0,
        worldY = 0,
        x = 0,
        y = 0,
        mirrorX = true,
        _mirrorXOverrideSet = true,
        removed = false,
      }
      local s2 = {
        worldX = 8,
        worldY = 0,
        x = 8,
        y = 0,
        mirrorX = false,
        removed = false,
      }
      local source, sourceLayer = makeSpriteWin(8, 4, "8x8", {
        mirror = false,
        items = { s1, s2 },
      })
      SpriteController.setSpriteSelection(sourceLayer, { 1, 2 })

      local dest, destLayer = makeSpriteWin(8, 4, "8x8", { mirror = true, items = {} })
      local ctx = select(1, ctxWithStatus())

      expect(KeyboardClipboardController.performClipboardAction(ctx, source, "copy")).toBe(true)
      expect(KeyboardClipboardController.performClipboardAction(ctx, dest, "paste")).toBe(true)
      local flags = {}
      for _, s in ipairs(destLayer.items) do
        flags[s.worldX] = s.mirrorX == true
      end
      expect(flags[0]).toBe(true)
      expect(flags[8]).toBe(false)
    end)
  end)
end)
