local TileInvalidationIndex = require("controllers.app.tile_invalidation_index")

describe("tile_invalidation_index.lua", function()
  local function makeRecordingPpuFrame(opts)
    opts = opts or {}
    local calls = {}
    local win = {
      kind = "ppu_frame",
      cols = opts.cols or 32,
      layers = opts.layers or {},
      invalidateNametableLayerCanvas = function(_, li, col, row)
        if col == nil or row == nil then
          calls[#calls + 1] = { scope = "nametable", li = li, full = true }
        else
          calls[#calls + 1] = { scope = "nametable", li = li, col = col, row = row }
        end
      end,
    }
    return win, calls
  end

  local function makeRecordingStaticArt(opts)
    opts = opts or {}
    local calls = {}
    local win = {
      kind = "static_art",
      cols = opts.cols or 16,
      layers = opts.layers or {},
      invalidateTileLayerCanvas = function(_, li, col, row)
        if col == nil or row == nil then
          calls[#calls + 1] = { scope = "tileLayer", li = li, full = true }
        else
          calls[#calls + 1] = { scope = "tileLayer", li = li, col = col, row = row }
        end
      end,
    }
    return win, calls
  end

  local function makeWm(windows)
    return {
      _structureGeneration = 1,
      getStructureGeneration = function(self)
        return self._structureGeneration
      end,
      getWindows = function()
        return windows
      end,
    }
  end

  local function clearCalls(calls)
    for i = #calls, 1, -1 do
      calls[i] = nil
    end
  end

  local function normalizeCalls(calls)
    local copy = {}
    for i, call in ipairs(calls) do
      copy[i] = {
        scope = call.scope,
        li = call.li,
        col = call.col,
        row = call.row,
        full = call.full,
      }
    end
    table.sort(copy, function(a, b)
      local ak = string.format("%s:%s:%s:%s:%s", a.scope, a.li, a.col or "", a.row or "", a.full and "1" or "0")
      local bk = string.format("%s:%s:%s:%s:%s", b.scope, b.li, b.col or "", b.row or "", b.full and "1" or "0")
      return ak < bk
    end)
    return copy
  end

  it("indexes nametable item cells and applies per-cell invalidation", function()
    local layer = {
      kind = "tile",
      items = {
        [6] = { index = 5, _bankIndex = 1 },
      },
    }
    local win, calls = makeRecordingPpuFrame({ layers = { layer } })
    local wm = makeWm({ win })
    local index = TileInvalidationIndex.rebuild(wm)

    local touched = TileInvalidationIndex.invalidateNametableFromIndex(index, 1, 5)
    expect(touched).toBeTruthy()
    expect(normalizeCalls(calls)).toEqual({
      { scope = "nametable", li = 1, col = 5, row = 0, full = nil },
    })
  end)

  it("indexes static art tile-layer cells", function()
    local layer = {
      kind = "tile",
      items = {
        [18] = { index = 12, _bankIndex = 2 },
      },
    }
    local win, calls = makeRecordingStaticArt({ cols = 16, layers = { layer } })
    local wm = makeWm({ win })
    local index = TileInvalidationIndex.rebuild(wm)

    local touched = TileInvalidationIndex.invalidateTileLayerFromIndex(index, 2, 12)
    expect(touched).toBeTruthy()
    expect(normalizeCalls(calls)).toEqual({
      { scope = "tileLayer", li = 1, col = 1, row = 1, full = nil },
    })
  end)

  it("uses full-layer fallback when pattern table references a tile with no item instance", function()
    local layer = {
      kind = "tile",
      items = {},
      patternTable = {
        ranges = {
          { bank = 1, from = 8, to = 8 },
        },
      },
    }
    local win, calls = makeRecordingPpuFrame({ layers = { layer } })
    local wm = makeWm({ win })
    local index = TileInvalidationIndex.rebuild(wm)

    local touched = TileInvalidationIndex.invalidateNametableFromIndex(index, 1, 8)
    expect(touched).toBeTruthy()
    expect(normalizeCalls(calls)).toEqual({
      { scope = "nametable", li = 1, col = nil, row = nil, full = true },
    })
  end)

  it("matches full-window scan results for nametable and tile-layer invalidation", function()
    local ppuLayer = {
      kind = "tile",
      items = {
        [1] = { index = 0, _bankIndex = 1 },
        [40] = { index = 7, _bankIndex = 1 },
      },
      patternTable = {
        ranges = {
          { bank = 1, from = 99, to = 99 },
        },
      },
    }
    local staticLayer = {
      kind = "tile",
      items = {
        [3] = { index = 2, _bankIndex = 1 },
      },
      patternTable = {
        ranges = {
          { bank = 1, from = 50, to = 50 },
        },
      },
    }

    local ppuWin, ppuCalls = makeRecordingPpuFrame({ layers = { ppuLayer } })
    local staticWin, staticCalls = makeRecordingStaticArt({ layers = { staticLayer } })
    local wm = makeWm({ ppuWin, staticWin })

    local bank, tile = 1, 7
    local index = TileInvalidationIndex.rebuild(wm)
    TileInvalidationIndex.invalidateNametableFromIndex(index, bank, tile)
    TileInvalidationIndex.invalidateTileLayerFromIndex(index, bank, tile)
    local indexCalls = normalizeCalls(ppuCalls)
    for _, call in ipairs(staticCalls) do
      indexCalls[#indexCalls + 1] = call
    end
    table.sort(indexCalls, function(a, b)
      local ak = string.format("%s:%s:%s:%s:%s", a.scope, a.li, a.col or "", a.row or "", a.full and "1" or "0")
      local bk = string.format("%s:%s:%s:%s:%s", b.scope, b.li, b.col or "", b.row or "", b.full and "1" or "0")
      return ak < bk
    end)

    clearCalls(ppuCalls)
    clearCalls(staticCalls)
    TileInvalidationIndex.scanInvalidateNametable(wm, bank, tile)
    TileInvalidationIndex.scanInvalidateTileLayer(wm, bank, tile)
    local scanCalls = normalizeCalls(ppuCalls)
    for _, call in ipairs(staticCalls) do
      scanCalls[#scanCalls + 1] = call
    end
    table.sort(scanCalls, function(a, b)
      local ak = string.format("%s:%s:%s:%s:%s", a.scope, a.li, a.col or "", a.row or "", a.full and "1" or "0")
      local bk = string.format("%s:%s:%s:%s:%s", b.scope, b.li, b.col or "", b.row or "", b.full and "1" or "0")
      return ak < bk
    end)

    expect(indexCalls).toEqual(scanCalls)
  end)

  it("reloads sprite refs indexed for a CHR tile", function()
    local reloads = 0
    local topRef = {
      _bankIndex = 1,
      index = 4,
      loadFromCHR = function(self, bankBytes, tileIndex)
        reloads = reloads + 1
        expect(bankBytes).toBeTruthy()
        expect(tileIndex).toBe(4)
      end,
    }
    local win = {
      kind = "ppu_frame",
      layers = {
        {
          kind = "sprite",
          items = {
            { removed = false, topRef = topRef, botRef = nil },
          },
        },
      },
    }
    local wm = makeWm({ win })
    local index = TileInvalidationIndex.rebuild(wm)
    local bankBytes = { 0x00 }

    local touched = TileInvalidationIndex.invalidateSpritesFromIndex(index, 1, 4, bankBytes)
    expect(touched).toBeTruthy()
    expect(reloads).toBe(1)
  end)

  it("rebuilds lazily when window structure generation changes", function()
    local AppCoreController = require("controllers.app.core_controller")
    local app = setmetatable({
      wm = makeWm({}),
      _tileInvalidationIndexDirty = false,
      _tileInvalidationIndex = { wmGeneration = 1, byKey = {} },
    }, AppCoreController)

    app.wm._structureGeneration = 2
    local index = app:ensureTileInvalidationIndex()
    expect(index.wmGeneration).toBe(2)
    expect(app._tileInvalidationIndexDirty).toBeFalsy()
  end)
end)
