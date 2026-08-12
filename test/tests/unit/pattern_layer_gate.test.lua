-- pattern_layer_gate.test.lua

local PatternLayerGate = require("controllers.window.pattern_layer_gate")
local NametableShapePreview = require("ui.nametable_shape_preview")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local NametableUtils = require("utils.nametable_utils")

local FULL_PATTERN_TABLE = {
  ranges = {
    { bank = 1, from = 0, to = 255 },
  },
}

local function buildFullPage(seed)
  local nt = {}
  for i = 1, 960 do
    nt[i] = (seed + i - 1) % 256
  end
  local at = {}
  for i = 1, 64 do
    at[i] = (seed + i) % 4
  end
  return nt, at
end

local function bytesToRomString(bytes)
  local parts = {}
  for i = 1, #bytes do
    parts[i] = string.char(bytes[i] % 256)
  end
  return table.concat(parts)
end

describe("pattern_layer_gate.lua nametable shadow", function()
  it("locks interaction without pattern table but allows shadow draw when bytes exist", function()
    local win = {
      kind = "ppu_frame",
      cols = 32,
      rows = 30,
      nametableBytes = {},
      layers = {
        {
          kind = "tile",
          nametableStartAddr = 0x1000,
          nametableEndAddr = 0x10FF,
          patternTable = {},
        },
      },
    }
    for i = 1, 960 do
      win.nametableBytes[i] = 0
    end

    local locked, reason = PatternLayerGate.isLayerInteractionLocked(win, 1)
    expect(locked).toBe(true)
    expect(type(reason) == "string").toBe(true)
    expect(PatternLayerGate.canDrawNametableShadow(win, 1)).toBe(true)
  end)

  it("unlocks interaction when pattern table is complete", function()
    local win = {
      kind = "ppu_frame",
      cols = 32,
      rows = 30,
      nametableBytes = {},
      layers = {
        {
          kind = "tile",
          nametableStartAddr = 0x1000,
          nametableEndAddr = 0x10FF,
          patternTable = FULL_PATTERN_TABLE,
        },
      },
    }
    for i = 1, 960 do
      win.nametableBytes[i] = 0
    end

    local locked = PatternLayerGate.isLayerInteractionLocked(win, 1)
    expect(locked).toBe(false)
    expect(PatternLayerGate.canDrawNametableShadow(win, 1)).toBe(true)
  end)

  it("does not allow shadow without nametable range or bytes", function()
    local win = {
      kind = "ppu_frame",
      cols = 32,
      rows = 30,
      nametableBytes = {},
      layers = {
        { kind = "tile", patternTable = {} },
      },
    }
    expect(PatternLayerGate.canDrawNametableShadow(win, 1)).toBe(false)
  end)

  it("forces shadow when linked pattern table window is missing even if ranges look complete", function()
    local win = {
      kind = "ppu_frame",
      cols = 32,
      rows = 30,
      nametableBytes = {},
      layers = {
        {
          kind = "tile",
          nametableStartAddr = 0x1000,
          nametableEndAddr = 0x10FF,
          linkedPatternTableWindowId = "gone-pt-id",
          patternTable = FULL_PATTERN_TABLE,
        },
      },
    }
    for i = 1, 960 do
      win.nametableBytes[i] = 0
    end

    -- No live wm windows → linked id is treated as missing.
    local prevCtx = rawget(_G, "ctx")
    rawset(_G, "ctx", {
      app = {
        wm = {
          getWindows = function()
            return {}
          end,
        },
      },
    })
    expect(PatternLayerGate.shouldDrawNametableShadow(win, 1)).toBe(true)
    expect(select(1, PatternLayerGate.isLayerInteractionLocked(win, 1))).toBe(true)
    rawset(_G, "ctx", prevCtx)
  end)
end)

describe("ppu_frame nametable visibility without pattern table", function()
  it("keeps nametable layer visible for shadow after pattern table unlink", function()
    local PPUFrameWindow = require("ui.windows_system.ppu_frame_window")
    local win = PPUFrameWindow.new(0, 0, 1, { title = "PPU" })
    local layer = win.layers[1]
    layer.kind = "tile"
    layer.nametableStartAddr = 0x1000
    layer.nametableEndAddr = 0x10FF
    layer.patternTable = { ranges = {} }
    layer.linkedPatternTableWindowId = nil
    win.nametableBytes = {}
    for i = 1, 960 do
      win.nametableBytes[i] = (i % 16)
    end

    expect(select(1, win:isPatternTableInteractionLocked(1))).toBe(true)
    expect(PatternLayerGate.canDrawNametableShadow(win, 1)).toBe(true)
    expect(win:isLayerVisibleInMode(1)).toBe(true)
    -- Navigation still excludes locked layers (no tile editing without PT).
    expect(win:isLayerAllowedInCurrentMode(1)).toBe(false)
  end)
end)

describe("nametable decode-only hydrate + shadow luminance", function()
  it("hydrates nametable bytes without a valid pattern table", function()
    local nt, at = buildFullPage(3)
    local compressed = NametableUtils.encode_decompressed_nametable(nt, at, "konami")
    local rom = bytesToRomString(compressed)
    local win = {
      kind = "ppu_frame",
      cols = 32,
      rows = 30,
      layers = { { kind = "tile", name = "Nametable" } },
      invalidateNametableLayerCanvas = function() end,
    }
    local layer = win.layers[1]

    local ok, err = NametableTilesController.hydrateWindowNametable(win, layer, {
      romRaw = rom,
      nametableStartAddr = 0,
      nametableEndAddr = #compressed - 1,
      codec = "konami",
      reportErrors = false,
    })

    expect(ok).toBe(true)
    expect(err).toBeNil()
    expect(#win.nametableBytes).toBe(960)
    expect(PatternLayerGate.canDrawNametableShadow(win, 1)).toBe(true)
    expect(select(1, PatternLayerGate.isLayerInteractionLocked(win, 1))).toBe(true)
  end)

  it("makes most-common luminance transparent for chess BG", function()
    local r, g, b, a = NametableShapePreview.rgbaForLuminance(0, true)
    expect(a).toBe(0)
    expect(r).toBe(0)
    local r2, g2, b2, a2 = NametableShapePreview.rgbaForLuminance(0.5, true)
    expect(a2).toBe(1)
    expect(r2).toBe(0.5)
    local r3, _, _, a3 = NametableShapePreview.rgbaForLuminance(0, false)
    expect(a3).toBe(1)
    expect(r3).toBe(0)
  end)
end)
