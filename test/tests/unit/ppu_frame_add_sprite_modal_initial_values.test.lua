local AppCoreController = require("controllers.app.core_controller")

local function validSpriteLayer(extra)
  local layer = {
    kind = "sprite",
    linkedPatternTableWindowId = "pt_win",
    patternTable = {
      ranges = {
        { from = 0, to = 255, bank = 1 },
      },
    },
    items = {},
  }
  if extra then
    for k, v in pairs(extra) do
      layer[k] = v
    end
  end
  return layer
end

describe("showPpuFrameAddSpriteModal initial OAM address", function()
  local function makeApp(capture)
    return setmetatable({
      ppuFrameAddSpriteModal = {
        show = function(_, opts)
          capture.opts = opts
        end,
      },
      appEditState = {},
      setStatus = function() end,
      showToast = function() end,
    }, AppCoreController)
  end

  it("prefills OAM start from the last added sprite in an OAM animation window", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      kind = "oam_animation",
      activeLayer = 2,
      getActiveLayerIndex = function() return 2 end,
      layers = {
        validSpriteLayer({
          items = {
            { startAddr = 0x100 },
            { startAddr = 0x104 },
          },
        }),
        validSpriteLayer({
          items = {
            { startAddr = 0x200 },
          },
        }),
      },
    }

    app:showPpuFrameAddSpriteModal(win)

    expect(capture.opts.initialOamStart).toBe("0x000200")
  end)

  it("leaves OAM start empty when the OAM animation window has no sprites yet", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      kind = "oam_animation",
      activeLayer = 1,
      getActiveLayerIndex = function() return 1 end,
      layers = {
        validSpriteLayer({ items = {} }),
      },
    }

    app:showPpuFrameAddSpriteModal(win)

    expect(capture.opts.initialOamStart).toBe("")
  end)

  it("ignores removed sprites when choosing the last OAM address", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      kind = "oam_animation",
      activeLayer = 1,
      getActiveLayerIndex = function() return 1 end,
      layers = {
        validSpriteLayer({
          items = {
            { startAddr = 0x100, removed = true },
            { startAddr = 0x108 },
          },
        }),
      },
    }

    app:showPpuFrameAddSpriteModal(win)

    expect(capture.opts.initialOamStart).toBe("0x000108")
  end)

  it("does not prefill OAM start for PPU frame windows", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      kind = "ppu_frame",
      layers = {
        validSpriteLayer({
          items = {
            { startAddr = 0x300 },
          },
        }),
      },
      getSpriteLayers = function(self)
        return { { layer = self.layers[1], index = 1 } }
      end,
    }

    app:showPpuFrameAddSpriteModal(win)

    expect(capture.opts.initialOamStart).toBe("")
  end)
end)

describe("showPpuFrameAddSpriteModal pattern table gate", function()
  local function makeApp(capture)
    return setmetatable({
      ppuFrameAddSpriteModal = {
        show = function(_, opts)
          capture.opts = opts
          capture.showCalls = (capture.showCalls or 0) + 1
        end,
      },
      appEditState = { romRaw = string.rep("\0", 256) },
      status = nil,
      toast = nil,
      setStatus = function(self, text)
        self.status = text
      end,
      showToast = function(self, kind, text)
        self.toast = { kind = kind, text = text }
      end,
    }, AppCoreController)
  end

  it("rejects open when sprite layer has no linked pattern table", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      kind = "oam_animation",
      activeLayer = 1,
      getActiveLayerIndex = function() return 1 end,
      layers = {
        {
          kind = "sprite",
          patternTable = {
            ranges = { { from = 0, to = 255, bank = 1 } },
          },
          items = {},
        },
      },
    }

    local ok = app:showPpuFrameAddSpriteModal(win)

    expect(ok).toBe(false)
    expect(capture.showCalls or 0).toBe(0)
    expect(app.status).toBe("Link a sprite pattern table before adding sprites")
  end)

  it("rejects open when pattern table mapping is invalid", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      kind = "ppu_frame",
      layers = {
        {
          kind = "sprite",
          linkedPatternTableWindowId = "pt",
          patternTable = { ranges = {} },
          items = {},
        },
      },
      getSpriteLayers = function(self)
        return { { layer = self.layers[1], index = 1 } }
      end,
    }

    local ok = app:showPpuFrameAddSpriteModal(win)

    expect(ok).toBe(false)
    expect(capture.showCalls or 0).toBe(0)
  end)

  it("opens when sprite layer has linked valid pattern table", function()
    local capture = {}
    local app = makeApp(capture)
    local layer = validSpriteLayer()
    local win = {
      kind = "oam_animation",
      activeLayer = 1,
      getActiveLayerIndex = function() return 1 end,
      layers = { layer },
    }

    local ok = app:showPpuFrameAddSpriteModal(win)

    expect(ok).toNotBe(false)
    expect(capture.showCalls).toBe(1)
    expect(capture.opts.spriteLayer).toBe(layer)
    expect(capture.opts.romRaw).toBe(app.appEditState.romRaw)
  end)
end)

describe("showPpuFrameAddSpriteModal multi-select confirm", function()
  it("adds every selected OAM start address", function()
    local capture = {}
    local app = setmetatable({
      ppuFrameAddSpriteModal = {
        show = function(_, opts)
          capture.opts = opts
        end,
      },
      appEditState = {
        romRaw = string.rep("\0", 512),
        tilesPool = { [1] = {} },
      },
      markUnsaved = function() end,
      setStatus = function() end,
      showToast = function() end,
    }, AppCoreController)

    local layer = validSpriteLayer({ items = {} })
    local win = {
      kind = "ppu_frame",
      layers = { layer },
      getSpriteLayers = function(self)
        return { { layer = self.layers[1], index = 1 } }
      end,
      setActiveLayerIndex = function() end,
    }

    app:showPpuFrameAddSpriteModal(win)
    local ok = capture.opts.onConfirm("0x000000", win, {
      starts = { 0x00, 0x04, 0x10 },
    })
    expect(ok).toBe(true)
    expect(#layer.items).toBe(3)
    expect(layer.items[1].startAddr).toBe(0x00)
    expect(layer.items[2].startAddr).toBe(0x04)
    expect(layer.items[3].startAddr).toBe(0x10)
    expect(layer.multiSpriteSelection[1]).toBe(true)
    expect(layer.multiSpriteSelection[2]).toBe(true)
    expect(layer.multiSpriteSelection[3]).toBe(true)
  end)
end)
