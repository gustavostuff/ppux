local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")

describe("mouse_tile_drop_controller.lua - CHR grouped drag/drop", function()
  local function makeGroup(entries, extra)
    local minCol, maxCol = 0, 0
    local minRow, maxRow = 0, 0
    for i, entry in ipairs(entries) do
      local col = entry.offsetCol or 0
      local row = entry.offsetRow or 0
      if i == 1 then
        minCol, maxCol = col, col
        minRow, maxRow = row, row
      else
        if col < minCol then minCol = col end
        if col > maxCol then maxCol = col end
        if row < minRow then minRow = row end
        if row > maxRow then maxRow = row end
      end
    end
    local group = {
      entries = entries,
      minOffsetCol = minCol,
      maxOffsetCol = maxCol,
      minOffsetRow = minRow,
      maxOffsetRow = maxRow,
      spanCols = (maxCol - minCol) + 1,
      spanRows = (maxRow - minRow) + 1,
      sourceSelectionMode = "8x8",
    }
    if extra then
      for k, v in pairs(extra) do
        group[k] = v
      end
    end
    return group
  end

  local function makeTileWindow(cols, rows)
    local items = {}
    local selected = nil
    local win = {
      kind = "static_art",
      x = 0, y = 0, zoom = 1, cellW = 8, cellH = 8,
      cols = cols, rows = rows, scrollCol = 0, scrollRow = 0,
      layers = { { kind = "tile" } },
      getActiveLayerIndex = function() return 1 end,
      isInContentArea = function(_, x, y)
        return x >= 0 and y >= 0 and x < (cols * 8) and y < (rows * 8)
      end,
      toGridCoords = function(_, x, y)
        if x < 0 or y < 0 or x >= cols * 8 or y >= rows * 8 then
          return false
        end
        return true, math.floor(x / 8), math.floor(y / 8)
      end,
      set = function(_, col, row, item)
        items[(row * cols) + col + 1] = item
      end,
      get = function(_, col, row)
        return items[(row * cols) + col + 1]
      end,
      setSelected = function(_, col, row)
        selected = { col = col, row = row }
      end,
    }
    return win, items, function() return selected end
  end

  local function makeSpriteWindow(cols, rows, mode)
    local win = {
      kind = "static_art",
      x = 0, y = 0, zoom = 1, cellW = 8, cellH = 8,
      cols = cols, rows = rows, scrollCol = 0, scrollRow = 0,
      layers = { { kind = "sprite", mode = mode or "8x8", items = {}, originX = 0, originY = 0 } },
      getActiveLayerIndex = function() return 1 end,
      isInContentArea = function(_, x, y)
        return x >= 0 and y >= 0 and x < (cols * 8) and y < (rows * 8)
      end,
      toGridCoords = function(_, x, y)
        if x < 0 or y < 0 or x >= cols * 8 or y >= rows * 8 then
          return false
        end
        return true, math.floor(x / 8), math.floor(y / 8)
      end,
    }
    return win
  end

  it("reports not enough area when the grouped selection is larger than the destination", function()
    local group = makeGroup({
      { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = { index = 1, _bankIndex = 1 } },
      { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = { index = 2, _bankIndex = 1 } },
      { srcCol = 2, srcRow = 0, offsetCol = 2, offsetRow = 0, item = { index = 3, _bankIndex = 1 } },
    })
    local dst = makeTileWindow(2, 2)
    local wm = {
      windowAt = function() return dst end,
    }

    local candidate = MouseTileDropController.getHoverTooltipCandidate({
      drag = {
        active = true,
        item = group.entries[1].item,
        tileGroup = group,
        srcWin = { kind = "chr" },
      },
    }, 8, 8, wm)

    expect(candidate).toBeTruthy()
    expect(candidate.text).toBe("not enough area to drop")
  end)

  it("reports out of bounds when a hovered grouped drop would overflow the destination", function()
    local group = makeGroup({
      { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = { index = 1, _bankIndex = 1 } },
      { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = { index = 2, _bankIndex = 1 } },
    })
    local dst = makeTileWindow(4, 4)
    local wm = {
      windowAt = function() return dst end,
    }

    local candidate = MouseTileDropController.getHoverTooltipCandidate({
      drag = {
        active = true,
        item = group.entries[1].item,
        tileGroup = group,
        srcWin = { kind = "chr" },
      },
    }, 24, 0, wm)

    expect(candidate).toBeTruthy()
    expect(candidate.text).toBe("out of bounds")
  end)

  it("blocks CHR 8x8 multi-selection drops into 8x16 sprite layers", function()
    local group = makeGroup({
      { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = { index = 4, _bankIndex = 1 } },
      { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = { index = 5, _bankIndex = 1 } },
    })
    local dst = makeSpriteWindow(8, 8, "8x16")
    local wm = {
      windowAt = function() return dst end,
    }

    local candidate = MouseTileDropController.getHoverTooltipCandidate({
      drag = {
        active = true,
        item = group.entries[1].item,
        tileGroup = group,
        srcWin = { kind = "chr" },
      },
    }, 8, 8, wm)

    expect(candidate).toBeTruthy()
    expect(candidate.text).toBe("8x8 tile payload cannot drop into 8x16 sprite layer")
  end)

  it("blocks non-CHR inter-window tile drags", function()
    local item = { id = "a" }
    local srcWin = {
      kind = "static_art",
      layers = { { kind = "tile" } },
      getActiveLayerIndex = function() return 1 end,
    }
    local dst, items = makeTileWindow(4, 4)
    local wm = {
      windowAt = function() return dst end,
      setFocus = function() end,
    }
    local commit = nil
    local handled = MouseTileDropController.handleTileDrop({
      ctx = { app = {} },
      drag = {
        active = true,
        item = item,
        srcWin = srcWin,
        srcLayer = 1,
        srcCol = 0,
        srcRow = 0,
      },
      clearDragState = function(value)
        commit = value
      end,
    }, 8, 8, wm)

    expect(handled).toBe(true)
    expect(items[6]).toBeNil()
    expect(commit).toBe(false)
  end)

  it("copies a CHR grouped drag into tile windows without removing the source", function()
    local a = { id = "a", index = 4, _bankIndex = 1 }
    local b = { id = "b", index = 5, _bankIndex = 1 }
    local group = makeGroup({
      { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = a },
      { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = b },
    })
    local dst, items, getSelected = makeTileWindow(4, 4)
    local sourceRemoved = false
    local srcWin = {
      kind = "chr",
      removeAt = function()
        sourceRemoved = true
      end,
    }
    local focused = nil
    local wm = {
      windowAt = function() return dst end,
      setFocus = function(_, win) focused = win end,
    }

    local clearedCommit = nil
    local handled = MouseTileDropController.handleTileDrop({
      ctx = { app = {} },
      drag = {
        active = true,
        item = a,
        tileGroup = group,
        srcWin = srcWin,
        srcLayer = 1,
      },
      clearDragState = function(commit)
        clearedCommit = commit
      end,
    }, 8, 8, wm)

    expect(handled).toBe(true)
    expect(items[6]).toBe(a) -- (1,1)
    expect(items[7]).toBe(b) -- (2,1)
    expect(sourceRemoved).toBe(false)
    expect(focused).toBe(dst)
    expect(clearedCommit).toBe(true)
    expect(getSelected().col).toBe(1)
    expect(getSelected().row).toBe(1)
  end)

  it("drops CHR grouped drags onto sprite layers snapped to pixels", function()
    local a = { id = "a", index = 4, _bankIndex = 1 }
    local b = { id = "b", index = 5, _bankIndex = 1 }
    local group = makeGroup({
      { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = a },
      { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = b },
    })
    local dst = makeSpriteWindow(8, 8, "8x8")
    local focused = nil
    local wm = {
      windowAt = function() return dst end,
      setFocus = function(_, win) focused = win end,
    }

    local clearedCommit = nil
    local handled = MouseTileDropController.handleTileDrop({
      ctx = {
        app = {
          appEditState = {
            tilesPool = {
              [1] = {
                [4] = a,
                [5] = b,
                [6] = { id = "c", index = 6, _bankIndex = 1 },
              },
            },
          },
        },
      },
      drag = {
        active = true,
        item = a,
        tileGroup = group,
        srcWin = { kind = "chr" },
        srcLayer = 1,
      },
      clearDragState = function(commit)
        clearedCommit = commit
      end,
    }, 19, 11, wm)

    expect(handled).toBe(true)
    expect(#dst.layers[1].items).toBe(2)
    expect(dst.layers[1].items[1].worldX).toBe(19)
    expect(dst.layers[1].items[1].worldY).toBe(11)
    expect(dst.layers[1].items[2].worldX).toBe(27)
    expect(dst.layers[1].items[2].worldY).toBe(11)
    expect(focused).toBe(dst)
    expect(clearedCommit).toBe(true)
  end)

  it("drops only the top refs from CHR 8x16 groups into 8x16 sprite layers", function()
    local t4 = { index = 4, _bankIndex = 1 }
    local t5 = { index = 5, _bankIndex = 1 }
    local t6 = { index = 6, _bankIndex = 1 }
    local t7 = { index = 7, _bankIndex = 1 }
    local group = makeGroup({
      { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = t4 },
      { srcCol = 0, srcRow = 1, offsetCol = 0, offsetRow = 1, item = t5 },
      { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = t6 },
      { srcCol = 1, srcRow = 1, offsetCol = 1, offsetRow = 1, item = t7 },
    }, {
      sourceSelectionMode = "8x16",
      spriteEntries = {
        { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = t4, bottomItem = t5 },
        { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = t6, bottomItem = t7 },
      },
      spriteMinOffsetCol = 0,
      spriteMaxOffsetCol = 1,
      spriteMinOffsetRow = 0,
      spriteMaxOffsetRow = 0,
      spriteSpanCols = 2,
      spriteSpanRows = 1,
    })
    local dst = makeSpriteWindow(8, 8, "8x16")
    local wm = {
      windowAt = function() return dst end,
      setFocus = function() end,
    }

    MouseTileDropController.handleTileDrop({
      ctx = {
        app = {
          appEditState = {
            tilesPool = {
              [1] = {
                [4] = t4,
                [5] = t5,
                [6] = t6,
                [7] = t7,
              },
            },
          },
        },
      },
      drag = {
        active = true,
        item = t4,
        tileGroup = group,
        srcWin = { kind = "chr" },
        srcLayer = 1,
      },
      clearDragState = function() end,
    }, 3, 2, wm)

    local items = dst.layers[1].items
    expect(#items).toBe(2)
    expect(items[1].worldX).toBe(3)
    expect(items[1].worldY).toBe(2)
    expect(items[2].worldX).toBe(11)
    expect(items[2].worldY).toBe(2)
    expect(items[1].tile).toBe(4)
    expect(items[1].tileBelow).toBe(5)
    expect(items[2].tile).toBe(6)
    expect(items[2].tileBelow).toBe(7)
  end)

  it("drops both halves from CHR 8x16 groups into 8x8 sprite layers", function()
    local t4 = { index = 4, _bankIndex = 1 }
    local t5 = { index = 5, _bankIndex = 1 }
    local group = makeGroup({
      { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = t4 },
      { srcCol = 0, srcRow = 1, offsetCol = 0, offsetRow = 1, item = t5 },
    }, {
      sourceSelectionMode = "8x16",
      spriteEntries = {
        { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = t4, bottomItem = t5 },
      },
      spriteMinOffsetCol = 0,
      spriteMaxOffsetCol = 0,
      spriteMinOffsetRow = 0,
      spriteMaxOffsetRow = 0,
      spriteSpanCols = 1,
      spriteSpanRows = 1,
    })
    local dst = makeSpriteWindow(8, 8, "8x8")
    local wm = {
      windowAt = function() return dst end,
      setFocus = function() end,
    }

    MouseTileDropController.handleTileDrop({
      ctx = {
        app = {
          appEditState = {
            tilesPool = {
              [1] = {
                [4] = t4,
                [5] = t5,
              },
            },
          },
        },
      },
      drag = {
        active = true,
        item = t4,
        tileGroup = group,
        srcWin = { kind = "chr" },
        srcLayer = 1,
      },
      clearDragState = function() end,
    }, 6, 4, wm)

    local items = dst.layers[1].items
    expect(#items).toBe(2)
    expect(items[1].worldX).toBe(6)
    expect(items[1].worldY).toBe(4)
    expect(items[2].worldX).toBe(6)
    expect(items[2].worldY).toBe(12)
    expect(items[1].tile).toBe(4)
    expect(items[2].tile).toBe(5)
  end)

  it("routes CHR 8x16 internal drags to swapCells in the same CHR window", function()
    local function makeTile(index, seed)
      local pixels = {}
      for i = 1, 64 do
        pixels[i] = (i + seed) % 4
      end
      return { index = index, _bankIndex = 1, pixels = pixels }
    end

    local topTile = makeTile(10, 0)
    local bottomTile = makeTile(11, 1)
    local dstTopTile = makeTile(26, 2)
    local dstBottomTile = makeTile(27, 3)
    local swapCall = nil
    local selected = nil
    local undoCalls = {
      started = 0,
      recorded = 0,
      finished = 0,
      canceled = 0,
    }
    local unsavedCalls = 0
    local undoRedo = {
      activeEvent = nil,
      startPaintEvent = function(self)
        undoCalls.started = undoCalls.started + 1
        self.activeEvent = {}
      end,
      recordPixelChange = function()
        undoCalls.recorded = undoCalls.recorded + 1
      end,
      finishPaintEvent = function(self)
        undoCalls.finished = undoCalls.finished + 1
        self.activeEvent = nil
        return true
      end,
      cancelPaintEvent = function(self)
        undoCalls.canceled = undoCalls.canceled + 1
        self.activeEvent = nil
      end,
    }
    local grid = {
      ["0,2"] = topTile,
      ["0,3"] = bottomTile,
      ["1,2"] = dstTopTile,
      ["1,3"] = dstBottomTile,
    }
    local dst = {
      kind = "chr",
      currentBank = 3,
      x = 0, y = 0, zoom = 1, cellW = 8, cellH = 8,
      layers = { { kind = "tile" } },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 1, 3 end,
      get = function(_, col, row)
        return grid[string.format("%d,%d", col, row)]
      end,
      swapCells = function(_, c1, r1, c2, r2, edits, bankIdx, appEditState)
        swapCall = {
          c1 = c1, r1 = r1,
          c2 = c2, r2 = r2,
          edits = edits,
          bankIdx = bankIdx,
          appEditState = appEditState,
        }
        local tileA = grid[string.format("%d,%d", c1, r1)]
        local tileB = grid[string.format("%d,%d", c2, r2)]
        for i = 1, 64 do
          tileA.pixels[i], tileB.pixels[i] = tileB.pixels[i], tileA.pixels[i]
        end
      end,
      setSelected = function(_, col, row)
        selected = { col = col, row = row }
      end,
    }
    local wm = {
      windowAt = function() return dst end,
      setFocus = function() end,
    }
    local clearedCommit = nil

    local handled = MouseTileDropController.handleTileDrop({
      ctx = {
        app = {
          edits = {},
          undoRedo = undoRedo,
          appEditState = { sentinel = true },
        },
      },
      drag = {
        active = true,
        item = topTile,
        tileGroup = {
          entries = {
            { item = topTile, offsetCol = 0, offsetRow = 0 },
            { item = bottomTile, offsetCol = 0, offsetRow = 1 },
          },
          spriteEntries = {
            { item = topTile, offsetCol = 0, offsetRow = 0, bottomItem = bottomTile },
          },
          sourceSelectionMode = "8x16",
        },
        srcWin = dst,
        srcCol = 0,
        srcRow = 2,
        srcLayer = 1,
      },
      clearDragState = function(commit)
        clearedCommit = commit
      end,
      markUnsaved = function()
        unsavedCalls = unsavedCalls + 1
      end,
    }, 12, 28, wm)

    expect(handled).toBe(true)
    expect(swapCall).toBeTruthy()
    expect(swapCall.c1).toBe(0)
    expect(swapCall.r1).toBe(2)
    expect(swapCall.c2).toBe(1)
    expect(swapCall.r2).toBe(3)
    expect(swapCall.bankIdx).toBe(3)
    expect(selected.col).toBe(1)
    expect(selected.row).toBe(3)
    expect(undoCalls.started).toBe(1)
    expect(undoCalls.recorded).toBeGreaterThan(0)
    expect(undoCalls.finished).toBe(1)
    expect(undoCalls.canceled).toBe(0)
    expect(unsavedCalls).toBe(0)
    expect(clearedCommit).toBe(true)
  end)

  it("swaps all entries for CHR grouped internal drags in the same window", function()
    local function makeTile(index, seed)
      local pixels = {}
      for i = 1, 64 do
        pixels[i] = (i + seed) % 4
      end
      return { index = index, _bankIndex = 1, pixels = pixels }
    end

    local srcA = makeTile(40, 0)
    local srcB = makeTile(41, 1)
    local dstA = makeTile(50, 2)
    local dstB = makeTile(51, 3)
    local swapCalls = {}
    local undoCalls = {
      started = 0,
      recorded = 0,
      finished = 0,
      canceled = 0,
    }
    local grid = {
      ["0,0"] = srcA,
      ["1,0"] = srcB,
      ["2,0"] = dstA,
      ["3,0"] = dstB,
    }
    local dst = {
      kind = "chr",
      cols = 4,
      rows = 2,
      currentBank = 2,
      x = 0, y = 0, zoom = 1, cellW = 8, cellH = 8,
      layers = { { kind = "tile" } },
      getActiveLayerIndex = function() return 1 end,
      toGridCoords = function() return true, 2, 0 end,
      get = function(_, col, row)
        return grid[string.format("%d,%d", col, row)]
      end,
      swapCells = function(_, c1, r1, c2, r2)
        swapCalls[#swapCalls + 1] = { c1 = c1, r1 = r1, c2 = c2, r2 = r2 }
        local k1 = string.format("%d,%d", c1, r1)
        local k2 = string.format("%d,%d", c2, r2)
        grid[k1], grid[k2] = grid[k2], grid[k1]
      end,
      setSelected = function() end,
    }
    local undoRedo = {
      activeEvent = nil,
      startPaintEvent = function(self)
        undoCalls.started = undoCalls.started + 1
        self.activeEvent = {}
      end,
      recordPixelChange = function()
        undoCalls.recorded = undoCalls.recorded + 1
      end,
      finishPaintEvent = function(self)
        undoCalls.finished = undoCalls.finished + 1
        self.activeEvent = nil
        return true
      end,
      cancelPaintEvent = function(self)
        undoCalls.canceled = undoCalls.canceled + 1
        self.activeEvent = nil
      end,
    }
    local wm = {
      windowAt = function() return dst end,
      setFocus = function() end,
    }
    local clearedCommit = nil

    local handled = MouseTileDropController.handleTileDrop({
      ctx = {
        app = {
          edits = {},
          undoRedo = undoRedo,
          appEditState = {},
        },
      },
      drag = {
        active = true,
        item = srcA,
        tileGroup = {
          entries = {
            { srcCol = 0, srcRow = 0, offsetCol = 0, offsetRow = 0, item = srcA },
            { srcCol = 1, srcRow = 0, offsetCol = 1, offsetRow = 0, item = srcB },
          },
          sourceSelectionMode = "8x8",
        },
        srcWin = dst,
        srcCol = 0,
        srcRow = 0,
        srcLayer = 1,
      },
      clearDragState = function(commit)
        clearedCommit = commit
      end,
      markUnsaved = function() end,
    }, 20, 4, wm)

    expect(handled).toBe(true)
    expect(#swapCalls).toBe(2)
    expect(swapCalls[1].c1).toBe(0)
    expect(swapCalls[1].r1).toBe(0)
    expect(swapCalls[1].c2).toBe(2)
    expect(swapCalls[1].r2).toBe(0)
    expect(swapCalls[2].c1).toBe(1)
    expect(swapCalls[2].r1).toBe(0)
    expect(swapCalls[2].c2).toBe(3)
    expect(swapCalls[2].r2).toBe(0)

    expect(grid["0,0"]).toBe(dstA)
    expect(grid["1,0"]).toBe(dstB)
    expect(grid["2,0"]).toBe(srcA)
    expect(grid["3,0"]).toBe(srcB)

    expect(undoCalls.started).toBe(1)
    expect(undoCalls.recorded).toBeGreaterThan(0)
    expect(undoCalls.finished).toBe(1)
    expect(undoCalls.canceled).toBe(0)
    expect(clearedCommit).toBe(true)
  end)
end)
