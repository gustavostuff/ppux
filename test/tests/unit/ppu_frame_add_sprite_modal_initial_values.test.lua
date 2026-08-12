local AppCoreController = require("controllers.app.core_controller")
local Dialog = require("ui.modals.ppu_frame_add_sprite_modal")
local RomHexGrid = require("ui.rom_hex_grid")

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

  it("does not prefill initialOamStart for Add on OAM animation (modal derives it)", function()
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

    expect(capture.opts.initialOamStart).toBe("")
    expect(capture.opts.spriteLayer).toBe(win.layers[2])
  end)

  it("leaves initialOamStart empty when the OAM animation window has no sprites yet", function()
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

describe("Add sprite modal default selection and disabled layer scope", function()
  it("defaults to 0x00 when the target layer has no sprites", function()
    expect(Dialog._defaultAddOamStart({}, 4)).toBe(0)
  end)

  it("defaults to the group after the last disabled start", function()
    expect(Dialog._defaultAddOamStart({ 0x100, 0x108, 0x200 }, 4)).toBe(0x204)
  end)

  it("disables only current-layer starts; other OAM-anim layer starts stay free", function()
    local modal = Dialog.new()
    local activeLayer = validSpriteLayer({
      items = {
        { startAddr = 0x200 },
        { startAddr = 0x204 },
      },
    })
    local otherLayer = validSpriteLayer({
      items = {
        { startAddr = 0x100 },
        { startAddr = 0x104 },
      },
    })
    modal:show({
      romRaw = string.rep("\0", 1024),
      spriteLayer = activeLayer,
      tilesPool = { [1] = {} },
    })

    local occupied = modal.hexGrid:getOccupiedStarts()
    expect(occupied).toEqual({ 0x200, 0x204 })
    expect(modal.hexGrid:startOverlapsOccupied(0x100)).toBe(false)
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 0x208 })
    expect(modal.oamStartField:getText()).toBe("0x000208")
    -- otherLayer exists only to document cross-layer intent in this test.
    expect(#otherLayer.items).toBe(2)
    modal:hide()
  end)

  it("selects 0x00 and leaves disabled empty when adding to an empty layer", function()
    local modal = Dialog.new()
    modal:show({
      romRaw = string.rep("\0", 256),
      spriteLayer = validSpriteLayer({ items = {} }),
      tilesPool = { [1] = {} },
    })
    expect(modal.hexGrid:getOccupiedStarts()).toEqual({})
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 0 })
    expect(modal.oamStartField:getText()).toBe("0x000000")
    expect(modal.hexGrid:getMinimapMarkers()).toEqual({})
    modal:hide()
  end)

  it("injects gray minimap markers for in-layer occupied starts", function()
    local modal = Dialog.new()
    modal:show({
      romRaw = string.rep("\0", 1024),
      spriteLayer = validSpriteLayer({
        items = {
          { startAddr = 0x100 },
          { startAddr = 0x200 },
        },
      }),
      tilesPool = { [1] = {} },
    })
    expect(modal.hexGrid:getMinimapMarkers()).toEqual({
      { offset = 0x100, color = "gray", groupCount = 1, groupSize = 4 },
      { offset = 0x200, color = "gray", groupCount = 1, groupSize = 4 },
    })
    modal:hide()
    expect(modal.hexGrid:getMinimapMarkers()).toEqual({})
  end)

  it("Edit mode keeps the sprite address selected even when it is in-layer", function()
    local modal = Dialog.new()
    local layer = validSpriteLayer({
      items = {
        { startAddr = 0x2A0 },
        { startAddr = 0x2A4 },
      },
    })
    modal:show({
      title = "Edit sprite",
      primaryButtonText = "Save",
      isEdit = true,
      romRaw = string.rep("\0", 2048),
      spriteLayer = layer,
      initialOamStart = "0x0002A0",
      appearanceSprite = layer.items[1],
      tilesPool = { [1] = {} },
    })
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 0x2A0 })
    expect(modal.oamStartField:getText()).toBe("0x0002A0")
    -- Editing sprite's start is excluded from disabled so the group is selectable.
    expect(modal.hexGrid:getOccupiedStarts()).toEqual({ 0x2A4 })
    expect(modal.hexGrid.maxSelectedStarts).toBe(1)
    expect(modal.addButton.enabled).toBe(true)
    -- Toggle off the only selection → Save disabled.
    modal.hexGrid:setPosition(0, 0)
    modal.hexGrid:scrollToReveal(0x2A0)
    local cols = modal.hexGrid:getCols()
    local rel = 0x2A0 - (modal.hexGrid.scrollOffset or 0)
    local col = rel % cols
    local row = math.floor(rel / cols)
    local hx = 2 + 38 + col * 15 + 2
    local hy = 2 + 12 + row * 11 + 2
    modal.hexGrid:mousepressed(hx, hy, 1)
    expect(modal.hexGrid:getSelectedStarts()).toEqual({})
    expect(modal.addButton.enabled).toBe(false)
    modal:hide()
  end)

  it("Add mode allows multi-select and disables Add with an empty selection", function()
    local modal = Dialog.new()
    modal:show({
      romRaw = string.rep("\0", 256),
      spriteLayer = validSpriteLayer({ items = {} }),
      tilesPool = { [1] = {} },
    })
    expect(modal.hexGrid.maxSelectedStarts).toBe(RomHexGrid.MAX_SELECTED_STARTS)
    expect(modal.addButton.enabled).toBe(true)
    modal.hexGrid:_setStarts({}, 0, {
      emit = false,
      allowEmpty = true,
      resetColors = true,
      scrollToReveal = false,
    })
    modal:_syncPreviewFromGrid()
    expect(modal.addButton.enabled).toBe(false)
    modal:hide()
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
