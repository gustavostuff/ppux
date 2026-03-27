local ChrBankWindow = require("user_interface.windows_system.chr_bank_window")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")

local function makeTile(index, fill)
  local tile = {
    index = index,
    pixels = {},
  }

  for i = 1, 64 do
    tile.pixels[i] = fill
  end

  function tile:swapPixelsWith(other)
    for i = 1, 64 do
      self.pixels[i], other.pixels[i] = other.pixels[i], self.pixels[i]
    end
    return true
  end

  return tile
end

local function makeFakeWindow(opts)
  opts = opts or {}
  local fakeWin = setmetatable({
    activeLayer = opts.activeLayer or 1,
    currentBank = opts.currentBank or 1,
    orderMode = opts.orderMode or "normal",
    _tiles = opts.tiles or {},
    _layerKind = opts.layerKind or "tile",
  }, ChrBankWindow)

  function fakeWin:getLayer()
    return { kind = self._layerKind }
  end

  function fakeWin:get(col, row)
    return self._tiles[tostring(col) .. "," .. tostring(row)]
  end

  return fakeWin
end

describe("chr_bank_window.lua - swapCells persistence", function()
  it("records swapped CHR pixel data into global edits even without prior edits", function()
    local tileA = makeTile(10, 1)
    local tileB = makeTile(11, 2)

    -- Make a couple pixels distinct so we can prove snapshots were recorded.
    tileA.pixels[1] = 3 -- (0,0)
    tileB.pixels[64] = 0 -- (7,7)

    local fakeWin = makeFakeWindow({
      currentBank = 4,
      tiles = {
        ["0,0"] = tileA,
        ["1,0"] = tileB,
      },
    })

    local edits = { banks = {} }

    ChrBankWindow.swapCells(fakeWin, 0, 0, 1, 0, edits, 4, nil)

    expect(edits.banks[4]).toBeTruthy()
    expect(edits.banks[4][10]).toBeTruthy()
    expect(edits.banks[4][11]).toBeTruthy()

    -- Tile 10 should now contain tileB's pixels after swap.
    expect(edits.banks[4][10]["0_0"]).toBe(2)
    expect(edits.banks[4][10]["7_7"]).toBe(0)

    -- Tile 11 should now contain tileA's pixels after swap.
    expect(edits.banks[4][11]["0_0"]).toBe(3)
    expect(edits.banks[4][11]["7_7"]).toBe(1)
  end)

  it("uses currentBank when bankIdx is omitted", function()
    local tileA = makeTile(21, 1)
    local tileB = makeTile(22, 2)
    local fakeWin = makeFakeWindow({
      currentBank = 7,
      tiles = {
        ["0,0"] = tileA,
        ["1,0"] = tileB,
      },
    })
    local edits = { banks = {} }

    ChrBankWindow.swapCells(fakeWin, 0, 0, 1, 0, edits, nil, nil)

    expect(edits.banks[7]).toBeTruthy()
    expect(edits.banks[7][21]).toBeTruthy()
    expect(edits.banks[7][22]).toBeTruthy()
  end)

  it("is a no-op when swapping the same cell", function()
    local tileA = makeTile(30, 1)
    tileA.pixels[1] = 3
    local fakeWin = makeFakeWindow({
      currentBank = 2,
      tiles = {
        ["0,0"] = tileA,
      },
    })
    local edits = { banks = {} }

    ChrBankWindow.swapCells(fakeWin, 0, 0, 0, 0, edits, 2, nil)

    expect(tileA.pixels[1]).toBe(3)
    expect(edits.banks[2]).toBeNil()
  end)

  it("does not swap when a tile is missing or invalid", function()
    local tileA = makeTile(40, 1)
    local invalidTile = { index = 41, pixels = { 1, 2, 3 } }

    local missingWin = makeFakeWindow({
      currentBank = 3,
      tiles = {
        ["0,0"] = tileA,
      },
    })
    local invalidWin = makeFakeWindow({
      currentBank = 3,
      tiles = {
        ["0,0"] = tileA,
        ["1,0"] = invalidTile,
      },
    })

    local edits = { banks = {} }
    ChrBankWindow.swapCells(missingWin, 0, 0, 1, 0, edits, 3, nil)
    expect(edits.banks[3]).toBeNil()

    ChrBankWindow.swapCells(invalidWin, 0, 0, 1, 0, edits, 3, nil)
    expect(edits.banks[3]).toBeNil()
    expect(tileA.pixels[1]).toBe(1)
  end)

  it("swaps existing edit table references before writing post-swap snapshots", function()
    local tileA = makeTile(50, 1)
    local tileB = makeTile(51, 2)
    local edits = {
      banks = {
        [6] = {
          [50] = { marker = "A" },
          [51] = { marker = "B" },
        },
      },
    }
    local fakeWin = makeFakeWindow({
      currentBank = 6,
      tiles = {
        ["0,0"] = tileA,
        ["1,0"] = tileB,
      },
    })

    ChrBankWindow.swapCells(fakeWin, 0, 0, 1, 0, edits, 6, nil)

    expect(edits.banks[6][50].marker).toBe("B")
    expect(edits.banks[6][51].marker).toBe("A")
    expect(edits.banks[6][50]["0_0"]).toBe(2)
    expect(edits.banks[6][51]["0_0"]).toBe(1)
  end)

  it("updates duplicate-sync indexes for both swapped tiles", function()
    local tileA = makeTile(60, 1)
    local tileB = makeTile(61, 2)
    local fakeWin = makeFakeWindow({
      currentBank = 9,
      tiles = {
        ["0,0"] = tileA,
        ["1,0"] = tileB,
      },
    })

    local appEditState = {}
    local calledState = nil
    local calledTargets = nil
    local originalUpdateTiles = ChrDuplicateSync.updateTiles
    ChrDuplicateSync.updateTiles = function(state, targets)
      calledState = state
      calledTargets = targets
    end

    local ok, err = pcall(function()
      ChrBankWindow.swapCells(fakeWin, 0, 0, 1, 0, { banks = {} }, 9, appEditState)
    end)
    ChrDuplicateSync.updateTiles = originalUpdateTiles
    if not ok then error(err) end

    expect(calledState).toBe(appEditState)
    expect(calledTargets).toBeTruthy()
    expect(calledTargets[1].bank).toBe(9)
    expect(calledTargets[1].tileIndex).toBe(60)
    expect(calledTargets[2].bank).toBe(9)
    expect(calledTargets[2].tileIndex).toBe(61)
  end)

  it("swaps tile pixels even when edits is nil", function()
    local tileA = makeTile(70, 1)
    local tileB = makeTile(71, 2)
    tileA.pixels[5] = 3
    tileB.pixels[5] = 0
    local fakeWin = makeFakeWindow({
      currentBank = 1,
      tiles = {
        ["0,0"] = tileA,
        ["1,0"] = tileB,
      },
    })

    ChrBankWindow.swapCells(fakeWin, 0, 0, 1, 0, nil, nil, nil)

    expect(tileA.pixels[1]).toBe(2)
    expect(tileA.pixels[5]).toBe(0)
    expect(tileB.pixels[1]).toBe(1)
    expect(tileB.pixels[5]).toBe(3)
  end)

  it("swaps both halves when CHR window is in 8x16 mode", function()
    local topA = makeTile(80, 1)
    local botA = makeTile(81, 2)
    local topB = makeTile(82, 3)
    local botB = makeTile(83, 0)

    topA.pixels[1] = 2
    botA.pixels[64] = 1
    topB.pixels[1] = 0
    botB.pixels[64] = 3

    local fakeWin = makeFakeWindow({
      currentBank = 8,
      orderMode = "oddEven",
      tiles = {
        ["0,0"] = topA,
        ["0,1"] = botA,
        ["1,0"] = topB,
        ["1,1"] = botB,
      },
    })
    local edits = { banks = {} }

    ChrBankWindow.swapCells(fakeWin, 0, 1, 1, 1, edits, 8, nil)

    expect(topA.pixels[1]).toBe(0)
    expect(topB.pixels[1]).toBe(2)
    expect(botA.pixels[64]).toBe(3)
    expect(botB.pixels[64]).toBe(1)
    expect(edits.banks[8][80]["0_0"]).toBe(0)
    expect(edits.banks[8][82]["0_0"]).toBe(2)
    expect(edits.banks[8][81]["7_7"]).toBe(3)
    expect(edits.banks[8][83]["7_7"]).toBe(1)
  end)

  it("treats top and bottom halves of the same 8x16 item as the same logical swap target", function()
    local topA = makeTile(84, 1)
    local botA = makeTile(85, 2)
    local topB = makeTile(86, 3)
    local botB = makeTile(87, 0)

    local fakeWin = makeFakeWindow({
      currentBank = 8,
      orderMode = "oddEven",
      tiles = {
        ["0,0"] = topA,
        ["0,1"] = botA,
        ["1,0"] = topB,
        ["1,1"] = botB,
      },
    })

    ChrBankWindow.swapCells(fakeWin, 0, 0, 0, 1, { banks = {} }, 8, nil)

    expect(topA.pixels[1]).toBe(1)
    expect(botA.pixels[1]).toBe(2)
    expect(topB.pixels[1]).toBe(3)
    expect(botB.pixels[1]).toBe(0)
  end)

  it("creates edits storage when edits table has no banks key", function()
    local tileA = makeTile(72, 1)
    local tileB = makeTile(73, 2)
    local fakeWin = makeFakeWindow({
      currentBank = 5,
      tiles = {
        ["0,0"] = tileA,
        ["1,0"] = tileB,
      },
    })
    local edits = {}

    ChrBankWindow.swapCells(fakeWin, 0, 0, 1, 0, edits, 5, nil)

    expect(edits.banks).toBeTruthy()
    expect(edits.banks[5]).toBeTruthy()
    expect(edits.banks[5][72]["0_0"]).toBe(2)
    expect(edits.banks[5][73]["0_0"]).toBe(1)
  end)

  it("returns early when active layer is not tile", function()
    local tileA = makeTile(74, 1)
    local tileB = makeTile(75, 2)
    local fakeWin = makeFakeWindow({
      currentBank = 4,
      layerKind = "sprite",
      tiles = {
        ["0,0"] = tileA,
        ["1,0"] = tileB,
      },
    })
    local edits = { banks = {} }
    local called = false
    local originalUpdateTiles = ChrDuplicateSync.updateTiles
    ChrDuplicateSync.updateTiles = function()
      called = true
    end

    local ok, err = pcall(function()
      ChrBankWindow.swapCells(fakeWin, 0, 0, 1, 0, edits, 4, {})
    end)
    ChrDuplicateSync.updateTiles = originalUpdateTiles
    if not ok then error(err) end

    expect(tileA.pixels[1]).toBe(1)
    expect(tileB.pixels[1]).toBe(2)
    expect(edits.banks[4]).toBeNil()
    expect(called).toBe(false)
  end)

  it("updates duplicate-sync only for swapped tiles that still have numeric indexes", function()
    local tileA = makeTile(76, 1)
    tileA.index = "not-a-number"
    local tileB = makeTile(77, 2)
    local fakeWin = makeFakeWindow({
      currentBank = 6,
      tiles = {
        ["0,0"] = tileA,
        ["1,0"] = tileB,
      },
    })
    local edits = { banks = {} }
    local calledTargets = nil
    local originalUpdateTiles = ChrDuplicateSync.updateTiles
    ChrDuplicateSync.updateTiles = function(_, targets)
      calledTargets = targets
    end

    local ok, err = pcall(function()
      ChrBankWindow.swapCells(fakeWin, 0, 0, 1, 0, edits, 6, {})
    end)
    ChrDuplicateSync.updateTiles = originalUpdateTiles
    if not ok then error(err) end

    expect(calledTargets).toBeTruthy()
    expect(#calledTargets).toBe(1)
    expect(calledTargets[1].bank).toBe(6)
    expect(calledTargets[1].tileIndex).toBe(77)
    expect(edits.banks[6]["not-a-number"]).toBeNil()
    expect(edits.banks[6][77]).toBeTruthy()
  end)
end)

describe("chr_bank_window.lua - constructor", function()
  it("initializes CHR-specific defaults and flags", function()
    local win = ChrBankWindow.new(12, 18, 8, 8, 16, 32, 2, {
      title = "CHR Bank",
      currentBank = 3,
      orderMode = "reverse",
      visibleCols = 10,
      visibleRows = 12,
      resizable = false,
    })

    expect(win.kind).toBe("chr")
    expect(win.currentBank).toBe(3)
    expect(win.orderMode).toBe("reverse")
    expect(win.resizable).toBe(true)
    expect(win.visibleCols).toBe(10)
    expect(win.visibleRows).toBe(12)
    expect(win.activeLayer).toBe(1)
    expect(#win.layers).toBe(1)
    expect(win.layers[1].name).toBe("Bank")
    expect(win.layers[1].kind).toBe("tile")
    expect(win.drawOnlyActiveLayer).toBe(true)
    expect(win.flags.allowInternalDrag).toBe(false)
    expect(win.flags.allowExternalDrag).toBe(true)
    expect(win.flags.allowExternalDrop).toBe(true)
  end)

  it("keeps currentBank and activeLayer in sync when bank layers are reset", function()
    local win = ChrBankWindow.new(0, 0, 8, 8, 16, 32, 2, {
      currentBank = 3,
    })

    win:resetBankLayers(5)

    expect(#win.layers).toBe(5)
    expect(win.currentBank).toBe(3)
    expect(win.activeLayer).toBe(3)

    win:shiftBank(1)
    expect(win.currentBank).toBe(4)
    expect(win.activeLayer).toBe(4)

    win:setActiveLayerIndex(2)
    expect(win.currentBank).toBe(2)
    expect(win.activeLayer).toBe(2)
  end)
end)
