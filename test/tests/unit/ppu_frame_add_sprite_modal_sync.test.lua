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
      -- Occupies 0x000..0x0EC; selection must use free starts beyond that.
      spriteLayer = makeLayer(60),
      tilesPool = { [1] = {} },
    })
    local starts = {}
    for i = 0, 8 do
      starts[#starts + 1] = 0x100 + i * 4
    end
    modal.hexGrid:_setStarts(starts, 0x120, { emit = true })
    -- 60 existing + 8 selected = 68 > 64, and also hit the 8-cap.
    expect(modal._limitWarning).toBe(Dialog.MSG_NES_LIMIT)
    expect(modal:_confirm()).toBe(false)
    expect(modal.visible).toBe(true)
    modal:hide()
  end)

  it("disables Add and clears preview when the grid has no selection", function()
    local modal = Dialog.new()
    modal:show({
      romRaw = string.rep("\0", 256),
      spriteLayer = makeLayer(0),
      tilesPool = { [1] = {} },
    })
    expect(modal.addButton.enabled).toBe(true)
    local reservedH = modal.preview:preferredHeight()

    modal.hexGrid:_setStarts({}, 0, { emit = true, allowEmpty = true })
    expect(#modal.hexGrid:getSelectedStarts()).toBe(0)
    expect(modal.addButton.enabled).toBe(false)
    expect(#(modal.preview.selectedStarts or {})).toBe(0)
    expect(#(modal.preview._slots or {})).toBe(0)
    expect(modal.preview:preferredHeight()).toBe(reservedH)
    expect(modal:_confirm()).toBe(false)
    expect(modal.visible).toBe(true)

    expect(modal.panel.cols).toBe(3)
    modal:hide()
  end)

  it("mirrors Add-mode selection onto the sprite layer and clears drafts on Cancel", function()
    local modal = Dialog.new()
    local layer = makeLayer(0)
    -- Seed one committed sprite so occupied filtering is covered.
    layer.items[1] = { startAddr = 0x10 }

    modal:show({
      romRaw = string.rep("\0", 512),
      spriteLayer = layer,
      tilesPool = { [1] = {} },
    })

    modal.hexGrid:_setStarts({ 0x20, 0x24 }, 0x24, { emit = true })
    local previewCount = 0
    local previewAddrs = {}
    for _, item in ipairs(layer.items) do
      if Dialog._isModalPreviewItem(item) then
        previewCount = previewCount + 1
        previewAddrs[#previewAddrs + 1] = item.startAddr
      end
    end
    expect(previewCount).toBe(2)
    expect(previewAddrs[1]).toBe(0x20)
    expect(previewAddrs[2]).toBe(0x24)
    -- Drafts must not count as occupied / block re-selection.
    local occupied = Dialog._collectOccupiedOamStarts(layer)
    expect(#occupied).toBe(1)
    expect(occupied[1]).toBe(0x10)

    modal:_cancel()
    expect(modal.visible).toBe(false)
    expect(#layer.items).toBe(1)
    expect(layer.items[1].startAddr).toBe(0x10)
    expect(Dialog._isModalPreviewItem(layer.items[1])).toBe(false)
  end)

  it("clears layer drafts before Confirm and restores them if Add is rejected", function()
    local modal = Dialog.new()
    local layer = makeLayer(0)
    local confirmedStarts = nil
    modal:show({
      romRaw = string.rep("\0", 512),
      spriteLayer = layer,
      tilesPool = { [1] = {} },
      onConfirm = function(_, _, opts)
        confirmedStarts = opts and opts.starts or nil
        -- Simulate reject after drafts were cleared for insertion.
        local draftCount = 0
        for _, item in ipairs(layer.items) do
          if Dialog._isModalPreviewItem(item) then
            draftCount = draftCount + 1
          end
        end
        expect(draftCount).toBe(0)
        return false
      end,
    })

    modal.hexGrid:_setStarts({ 0x40 }, 0x40, { emit = true })
    expect(#layer.items).toBe(1)
    expect(Dialog._isModalPreviewItem(layer.items[1])).toBe(true)

    expect(modal:_confirm()).toBe(false)
    expect(modal.visible).toBe(true)
    expect(confirmedStarts[1]).toBe(0x40)
    -- Rejected confirm restores the live layer preview.
    expect(#layer.items).toBe(1)
    expect(Dialog._isModalPreviewItem(layer.items[1])).toBe(true)
    expect(layer.items[1].startAddr).toBe(0x40)

    modal:hide()
    expect(#layer.items).toBe(0)
  end)

  it("does not place layer drafts while editing an existing sprite", function()
    local modal = Dialog.new()
    local layer = makeLayer(0)
    layer.items[1] = { startAddr = 0x08 }
    modal:show({
      romRaw = string.rep("\0", 512),
      spriteLayer = layer,
      tilesPool = { [1] = {} },
      isEdit = true,
      appearanceSprite = layer.items[1],
      initialOamStart = "0x000008",
    })
    modal:_onGridSelect(0x0C)
    local draftCount = 0
    for _, item in ipairs(layer.items) do
      if Dialog._isModalPreviewItem(item) then
        draftCount = draftCount + 1
      end
    end
    expect(draftCount).toBe(0)
    expect(#layer.items).toBe(1)
    modal:hide()
  end)
end)
