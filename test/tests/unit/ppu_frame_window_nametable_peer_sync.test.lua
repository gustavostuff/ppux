local PPUFrameWindow = require("user_interface.windows_system.ppu_frame_window")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local NametableUtils = require("utils.nametable_utils")
local chr = require("chr")

describe("ppu_frame_window.lua - nametable peer sync on ROM update", function()
  local oldEncode
  local oldDecode
  local oldWriteStart
  local oldSyncPeers
  local peerSyncCalls

  beforeEach(function()
    oldEncode = NametableTilesController.encodeWindowNametableBytes
    oldDecode = NametableUtils.decode_compressed_nametable
    oldWriteStart = chr.writeBytesStartingAt
    oldSyncPeers = NametableTilesController.syncPeerPpuFrameNametableWindows
    peerSyncCalls = 0

    NametableTilesController.syncPeerPpuFrameNametableWindows = function()
      peerSyncCalls = peerSyncCalls + 1
      return 1
    end
  end)

  afterEach(function()
    NametableTilesController.encodeWindowNametableBytes = oldEncode
    NametableUtils.decode_compressed_nametable = oldDecode
    chr.writeBytesStartingAt = oldWriteStart
    NametableTilesController.syncPeerPpuFrameNametableWindows = oldSyncPeers
  end)

  local function makeWin(layerOverrides)
    local layer = {
      kind = "tile",
      nametableStartAddr = 0x100,
      nametableEndAddr = 0x102, -- 3-byte budget
      codec = "konami",
      noOverflowSupported = true,
    }
    for k, v in pairs(layerOverrides or {}) do
      layer[k] = v
    end

    local win = setmetatable({
      kind = "ppu_frame",
      title = "src",
      cols = 32,
      rows = 30,
      layers = { layer },
      activeLayer = 1,
      romRaw = string.rep("\0", 0x400),
      nametableBytes = {},
      nametableAttrBytes = { 0x00 },
      originalTotalByteNumber = 3,
    }, PPUFrameWindow)

    for i = 1, 960 do
      win.nametableBytes[i] = 0
    end

    function win:getLayer(i)
      return self.layers[i]
    end
    function win:syncNametableLayerMetadata() end

    return win, layer
  end

  it("peer-syncs even when over-budget skips the ROM write", function()
    NametableTilesController.encodeWindowNametableBytes = function()
      return { 0x01, 0x02, 0x03, 0x04, 0x05 } -- 5 > budget 3
    end
    NametableUtils.decode_compressed_nametable = function()
      return {}, {}
    end
    local wrote = false
    chr.writeBytesStartingAt = function()
      wrote = true
      return string.rep("\0", 0x400)
    end

    local win = makeWin({ noOverflowSupported = true })
    local ok, err = win:updateCompressedBytesInROM()
    expect(ok).toBe(true)
    expect(err).toBeNil()
    expect(wrote).toBe(false)
    expect(peerSyncCalls).toBe(1)
  end)

  it("still skips over-budget ROM writes when noOverflowSupported is false (UI sync only)", function()
    -- Live edits must not spill past the declared budget; that corruption path
    -- froze Contra cutscenes. Peers still sync in-memory nametable bytes.
    NametableTilesController.encodeWindowNametableBytes = function()
      return { 0x01, 0x02, 0x03, 0x04, 0x05 }
    end
    NametableUtils.decode_compressed_nametable = function()
      return {}, {}
    end
    local wrote = false
    chr.writeBytesStartingAt = function()
      wrote = true
      return string.rep("\0", 0x400)
    end

    local win = makeWin({ noOverflowSupported = false })
    local ok, err = win:updateCompressedBytesInROM()
    expect(ok).toBe(true)
    expect(err).toBeNil()
    expect(wrote).toBe(false)
    expect(peerSyncCalls).toBe(1)
  end)
end)
