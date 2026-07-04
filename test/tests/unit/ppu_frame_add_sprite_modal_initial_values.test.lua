local AppCoreController = require("controllers.app.core_controller")

describe("showPpuFrameAddSpriteModal initial OAM address", function()
  local function makeApp(capture)
    return setmetatable({
      ppuFrameAddSpriteModal = {
        show = function(_, opts)
          capture.opts = opts
        end,
      },
      appEditState = {},
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
        {
          kind = "sprite",
          items = {
            { startAddr = 0x100 },
            { startAddr = 0x104 },
          },
        },
        {
          kind = "sprite",
          items = {
            { startAddr = 0x200 },
          },
        },
      },
    }

    app:showPpuFrameAddSpriteModal(win)

    expect(capture.opts.initialOamStart).toBe("0x000200")
    expect(capture.opts.chrFieldsHidden).toBe(true)
  end)

  it("leaves OAM start empty when the OAM animation window has no sprites yet", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      kind = "oam_animation",
      activeLayer = 1,
      getActiveLayerIndex = function() return 1 end,
      layers = {
        { kind = "sprite", items = {} },
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
        {
          kind = "sprite",
          items = {
            { startAddr = 0x100, removed = true },
            { startAddr = 0x108 },
          },
        },
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
        {
          kind = "sprite",
          items = {
            { startAddr = 0x300 },
          },
        },
      },
    }

    app:showPpuFrameAddSpriteModal(win)

    expect(capture.opts.initialOamStart).toBe("")
  end)
end)
