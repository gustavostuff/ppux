local Dialog = require("ui.modals.ppu_frame_add_sprite_modal")
local RomHexGrid = require("ui.rom_hex_grid")

describe("ppu_frame_add_sprite_modal grid/field sync", function()
  local function makeLayer(itemCount)
    local items = {}
    for i = 1, (itemCount or 0) do
      items[i] = { startAddr = (i - 1) * 4 }
    end
    return {
      kind = "sprite",
      mode = "8x8",
      linkedPatternTableWindowId = "pt",
      patternTable = { ranges = { { from = 0, to = 255, bank = 1 } } },
      items = items,
    }
  end

  it("grid select updates OAM field and preview address", function()
    local modal = Dialog.new()
    local rom = string.rep("\0", 256)
    modal:show({
      romRaw = rom,
      initialOamStart = "0x000000",
      spriteLayer = makeLayer(0),
      tilesPool = { [1] = {} },
    })

    modal:_onGridSelect(0x34)
    expect(modal.oamStartField:getText()).toBe("0x000034")
    expect(modal.hexGrid:getSelectedAddr()).toBe(0x34)
    expect(modal.preview.selectedAddr).toBe(0x34)
    modal:hide()
  end)

  it("OAM field text sync updates grid selection", function()
    local modal = Dialog.new()
    modal:show({
      romRaw = string.rep("\0", 512),
      initialOamStart = "",
      spriteLayer = makeLayer(0),
      tilesPool = { [1] = {} },
    })

    modal.oamStartField:setText("0x000080")
    modal:_syncFromOamField()
    expect(modal.hexGrid:getSelectedAddr()).toBe(0x80)
    expect(modal.preview.selectedAddr).toBe(0x80)
    modal:hide()
  end)

  it("shows 8-item cap warning when selection hits MAX_SELECTED_STARTS", function()
    local modal = Dialog.new()
    modal:show({
      romRaw = string.rep("\0", 512),
      initialOamStart = "0x000000",
      spriteLayer = makeLayer(0),
      tilesPool = { [1] = {} },
    })
    local starts = {}
    for i = 0, 8 do
      starts[#starts + 1] = i * 4
    end
    modal.hexGrid:_setStarts(starts, 0x20, { emit = true })
    expect(#modal.hexGrid:getSelectedStarts()).toBe(RomHexGrid.MAX_SELECTED_STARTS)
    expect(modal._limitWarning).toBe(Dialog.MSG_MAX_PER_ADD)
    modal:hide()
  end)

  it("NES 64 warning takes priority over the 8-item message", function()
    local modal = Dialog.new()
    modal:show({
      romRaw = string.rep("\0", 512),
      initialOamStart = "0x000000",
      spriteLayer = makeLayer(60),
      tilesPool = { [1] = {} },
    })
    local starts = {}
    for i = 0, 8 do
      starts[#starts + 1] = i * 4
    end
    modal.hexGrid:_setStarts(starts, 0x20, { emit = true })
    -- 60 existing + 8 selected = 68 > 64, and also hit the 8-cap.
    expect(modal._limitWarning).toBe(Dialog.MSG_NES_LIMIT)
    expect(modal:_confirm()).toBe(false)
    expect(modal.visible).toBe(true)
    modal:hide()
  end)
end)
