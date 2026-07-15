local AppCoreController = require("controllers.app.core_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")

describe("applyPpuFrameRangeState peer sync", function()
  local oldSyncPeers

  beforeEach(function()
    oldSyncPeers = NametableTilesController.syncPeerPpuFrameNametableWindows
  end)

  afterEach(function()
    NametableTilesController.syncPeerPpuFrameNametableWindows = oldSyncPeers
  end)

  local function makeAttrBytes(fill)
    local attrs = {}
    for i = 1, 64 do
      attrs[i] = fill
    end
    return attrs
  end

  local function makeLayer(startAddr, endAddr)
    return {
      kind = "tile",
      mode = "8x8",
      codec = "konami",
      nametableStartAddr = startAddr,
      nametableEndAddr = endAddr,
      userDefinedAttrs = string.rep("ff", 64),
      patternTable = {
        ranges = {
          { bank = 1, from = 0, to = 255 },
        },
      },
      items = {},
    }
  end

  it("calls syncPeerPpuFrameNametableWindows from applyPpuFrameRangeState", function()
    local syncCalls = 0
    NametableTilesController.syncPeerPpuFrameNametableWindows = function(sourceWin, sourceLayer, opts)
      syncCalls = syncCalls + 1
      expect(sourceWin).toBeTruthy()
      expect(sourceLayer).toBeTruthy()
      expect(opts.wm).toBeTruthy()
      return 0
    end

    local layer = makeLayer(0x2000, 0x2100)
    local win = {
      kind = "ppu_frame",
      cols = 32,
      rows = 30,
      layers = { layer },
      activeLayer = 1,
      nametableBytes = {},
      nametableAttrBytes = makeAttrBytes(0x11),
    }
    function win:syncNametableLayerMetadata() end

    local app = setmetatable({
      appEditState = { romRaw = "" },
      wm = { getWindows = function() return { win } end },
    }, AppCoreController)

    local ok = app:applyPpuFrameRangeState({
      win = win,
      layerIndex = 1,
      cols = 32,
      rows = 30,
      nametableBytes = {},
      nametableAttrBytes = makeAttrBytes(0x22),
      originalNametableBytes = {},
      originalNametableAttrBytes = {},
      originalCompressedBytes = {},
      tileSwapsMap = {},
      layerState = {
        kind = "tile",
        mode = "8x8",
        codec = "konami",
        nametableStartAddr = 0x2000,
        nametableEndAddr = 0x2100,
        patternTable = layer.patternTable,
        tileSwaps = {},
      },
    })

    expect(ok).toBe(true)
    expect(syncCalls).toBe(1)
    expect(win.nametableAttrBytes[1]).toBe(0x22)
    expect(layer.userDefinedAttrs:sub(1, 2)).toBe("22")
  end)

  it("propagates restored attribute bytes to peer windows sharing the nametable range", function()
    local layerA = makeLayer(0x1000, 0x1100)
    local layerB = makeLayer(0x1000, 0x1100)
    local winA = {
      kind = "ppu_frame",
      title = "A",
      cols = 32,
      rows = 30,
      layers = { layerA },
      activeLayer = 1,
      nametableBytes = {},
      nametableAttrBytes = makeAttrBytes(0xFF),
      _closed = false,
    }
    local winB = {
      kind = "ppu_frame",
      title = "B",
      cols = 32,
      rows = 30,
      layers = { layerB },
      activeLayer = 1,
      nametableBytes = {},
      nametableAttrBytes = makeAttrBytes(0xFF),
      _originalNametableBytes = {},
      _tileSwaps = {},
      _closed = false,
      romRaw = "peer-rom",
    }
    for i = 1, 960 do
      winA.nametableBytes[i] = 0
      winB.nametableBytes[i] = 0
      winB._originalNametableBytes[i] = 0
    end

    local refreshed = false
    function winB:refreshNametableVisuals()
      refreshed = true
    end
    function winB:syncNametableLayerMetadata() end
    function winA:syncNametableLayerMetadata() end

    local restoredAttrs = makeAttrBytes(0x00)
    restoredAttrs[1] = 0x55

    local app = setmetatable({
      appEditState = {
        romRaw = "",
        tilesPool = {},
      },
      wm = {
        getWindows = function()
          return { winA, winB }
        end,
      },
    }, AppCoreController)

    local ok = app:applyPpuFrameRangeState({
      win = winA,
      layerIndex = 1,
      cols = 32,
      rows = 30,
      nametableBytes = winA.nametableBytes,
      nametableAttrBytes = restoredAttrs,
      originalNametableBytes = {},
      originalNametableAttrBytes = {},
      originalCompressedBytes = {},
      tileSwapsMap = {},
      layerState = {
        kind = "tile",
        mode = "8x8",
        codec = "konami",
        nametableStartAddr = 0x1000,
        nametableEndAddr = 0x1100,
        patternTable = layerA.patternTable,
        tileSwaps = {},
      },
    })

    expect(ok).toBe(true)
    expect(winA.nametableAttrBytes[1]).toBe(0x55)
    expect(layerA.userDefinedAttrs:sub(1, 2)).toBe("55")
    expect(winB.nametableAttrBytes[1]).toBe(0x55)
    expect(layerB.userDefinedAttrs:sub(1, 2)).toBe("55")
    expect(refreshed).toBe(true)
  end)
end)
