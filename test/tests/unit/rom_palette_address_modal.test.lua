local RomPaletteAddressModal = require("ui.modals.rom_palette_address_modal")
local AppCoreController = require("controllers.app.core_controller")

describe("rom_palette_address_modal.lua", function()
  it("confirms trimmed address text on enter", function()
    local confirmed = nil
    local targetWindow = { title = "ROM Palette" }
    local modal = RomPaletteAddressModal.new()

    modal:show({
      window = targetWindow,
      col = 2,
      row = 1,
      onConfirm = function(addressText, win, col, row)
        confirmed = {
          addressText = addressText,
          win = win,
          col = col,
          row = row,
        }
      end,
    })

    modal.textField:setText("  3F10  ")
    expect(modal:handleKey("return")).toBe(true)

    expect(modal:isVisible()).toBe(false)
    expect(confirmed).toBeTruthy()
    expect(confirmed.addressText).toBe("0x003F10")
    expect(confirmed.win).toBe(targetWindow)
    expect(confirmed.col).toBe(2)
    expect(confirmed.row).toBe(1)
  end)

  it("keeps the modal open when the confirm callback rejects the value", function()
    local modal = RomPaletteAddressModal.new()
    local confirmCalls = 0

    modal:show({
      onConfirm = function()
        confirmCalls = confirmCalls + 1
        return false
      end,
    })

    modal.textField:setText("ZZZZ")
    expect(modal:handleKey("return")).toBe(true)
    expect(confirmCalls).toBe(1)
    expect(modal:isVisible()).toBe(true)
  end)

  it("handles textinput only while visible", function()
    local modal = RomPaletteAddressModal.new()

    expect(modal:textinput("A")).toBe(false)

    modal:show({ initialAddress = "3F" })
    expect(modal:textinput("1")).toBe(true)
    expect(modal.textField:getText()).toBe("0x000031")
  end)

  it("treats $0D and $40+ as invalid NES palette bytes", function()
    expect(RomPaletteAddressModal.isValidNesPaletteByte(0x0C)).toBe(true)
    expect(RomPaletteAddressModal.isValidNesPaletteByte(0x0F)).toBe(true)
    expect(RomPaletteAddressModal.isValidNesPaletteByte(0x0D)).toBe(false)
    expect(RomPaletteAddressModal.isValidNesPaletteByte(0x1E)).toBe(false)
    expect(RomPaletteAddressModal.isValidNesPaletteByte(0x3F)).toBe(false)
    expect(RomPaletteAddressModal.isValidNesPaletteByte(0x40)).toBe(false)
    expect(RomPaletteAddressModal.isValidNesPaletteByte(0xFF)).toBe(false)
  end)

  it("semi-selects valid NES color bytes on the current hex page", function()
    local modal = RomPaletteAddressModal.new()
    -- Page 0 (16 cols x 8 rows): mix of valid and invalid.
    local bytes = {}
    for i = 0, 127 do
      bytes[i + 1] = string.char(i)
    end
    local rom = table.concat(bytes)
    modal:show({
      romRaw = rom,
      initialAddress = "0x00000F",
    })

    expect(modal.hexGrid:getCols()).toBe(16)
    expect(modal.hexGrid:bytesPerPage()).toBe(128)
    local semi = modal.hexGrid:getSemiSelectedStarts()
    local semiSet = {}
    for _, addr in ipairs(semi) do
      semiSet[addr] = true
    end
    expect(semiSet[0x0C]).toBe(true)
    expect(semiSet[0x0F]).toBe(true)
    expect(semiSet[0x0D]).toBeNil()
    expect(semiSet[0x1E]).toBeNil()
    expect(semiSet[0x40]).toBeNil()
    expect(modal.hexGrid:getGroupSize()).toBe(1)
    expect(modal.selectedPreview.code).toBe("0F")
    expect(modal.textField:getText()).toBe("0x00000F")
    modal:hide()
  end)

  it("shows Base ROM color + User override when editing an already-bound cell", function()
    local modal = RomPaletteAddressModal.new()
    local bytes = {}
    for i = 0, 127 do
      bytes[i + 1] = string.char(i)
    end
    local rom = table.concat(bytes)
    modal:show({
      romRaw = rom,
      initialAddress = "0x00000F",
      userOverrideCode = "2A",
    })

    expect(modal._showUserOverride).toBe(true)
    expect(modal.overridePreview.code).toBe("2A")
    expect(modal.selectedPreview.code).toBe("0F")

    local plain = RomPaletteAddressModal.new()
    plain:show({ romRaw = rom, initialAddress = "0x00000F" })
    expect(modal.panel.rows).toBe(plain.panel.rows + 1)
    plain:hide()
    modal:hide()
  end)

  it("keeps Selected label layout when no user override is provided", function()
    local modal = RomPaletteAddressModal.new()
    modal:show({
      romRaw = string.rep(string.char(0x0F), 128),
      initialAddress = "0x00000F",
    })
    expect(modal._showUserOverride).toBe(false)
    expect(modal.overridePreview.code).toBeNil()
    modal:hide()
  end)

  it("keeps the address field in sync when the grid selection changes", function()
    local modal = RomPaletteAddressModal.new()
    local rom = string.rep("\x30", 256)
    modal:show({
      romRaw = rom,
      initialAddress = "0x000000",
    })
    modal.hexGrid:setSelectedAddr(0x20, { emit = false })
    modal:_onGridSelect(0x20, { fromGrid = true })
    expect(modal.textField:getText()).toBe("0x000020")
    expect(modal.selectedPreview.code).toBe("30")
    modal:hide()
  end)

  it("rejects clicks on invalid NES color bytes and shows a warning", function()
    local modal = RomPaletteAddressModal.new()
    local bytes = {}
    for i = 0, 127 do
      bytes[i + 1] = string.char(i)
    end
    modal:show({
      romRaw = table.concat(bytes),
      initialAddress = "0x00000F",
    })
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 0x0F })
    -- Click $0D (forbidden) - PAD+gutter+header cell layout matches default 16-col grid.
    local hx = 2 + 38 + 0x0D * 15 + 2
    local hy = 2 + 12 + 0 * 10 + 2
    modal.hexGrid:setPosition(0, 0)
    modal.hexGrid:mousepressed(hx, hy, 1)
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 0x0F })
    expect(modal._invalidColorWarning).toBe("Not a valid color")
    expect(modal:cursorNameAt(hx, hy)).toBe("arrow")
    expect(modal:cursorNameAt(2 + 38 + 0x0F * 15 + 2, hy)).toBe("hand")
    modal:hide()
  end)
end)

describe("showRomPaletteAddressModal initial address", function()
  local function makeApp(capture)
    return setmetatable({
      romPaletteAddressModal = {
        show = function(_, opts)
          capture.opts = opts
        end,
      },
      appEditState = { romRaw = string.rep("\0", 64) },
      setStatus = function() end,
      showToast = function() end,
    }, AppCoreController)
  end

  it("prefills left-neighbor address + 1 when the cell is empty", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      paletteData = {
        romColors = {
          { 0x3F00, nil, nil, nil },
        },
      },
    }

    app:showRomPaletteAddressModal(win, 1, 0)

    expect(capture.opts.initialAddress).toBe("0x003F01")
    expect(capture.opts.romRaw).toBe(app.appEditState.romRaw)
  end)

  it("keeps the cell's own address when already set", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      paletteData = {
        romColors = {
          { 0x3F00, 0x3F10, nil, nil },
        },
        userDefinedCode = {
          { row = 0, col = 1, code = "2A" },
        },
      },
      codes2D = {
        [0] = { [0] = "07", [1] = "2A" },
      },
    }

    app:showRomPaletteAddressModal(win, 1, 0)

    expect(capture.opts.initialAddress).toBe("0x003F10")
    expect(capture.opts.userOverrideCode).toBe("2A")
  end)

  it("omits userOverrideCode when the cell matches ROM base (no userDefinedCode entry)", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      paletteData = {
        romColors = {
          { 0x3F00, 0x3F10, nil, nil },
        },
        userDefinedCode = {},
      },
      codes2D = {
        [0] = { [0] = "07", [1] = "07" },
      },
    }

    app:showRomPaletteAddressModal(win, 1, 0)

    expect(capture.opts.initialAddress).toBe("0x003F10")
    expect(capture.opts.userOverrideCode).toBeNil()
  end)

  it("omits userOverrideCode when the cell has no ROM address yet", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      paletteData = {
        romColors = {
          { 0x3F00, nil, nil, nil },
        },
        userDefinedCode = {
          { row = 0, col = 1, code = "2A" },
        },
      },
      codes2D = {
        [0] = { [0] = "07", [1] = "2A" },
      },
    }

    app:showRomPaletteAddressModal(win, 1, 0)

    expect(capture.opts.initialAddress).toBe("0x003F01")
    expect(capture.opts.userOverrideCode).toBeNil()
  end)

  it("leaves the field empty when there is no left neighbor address", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      paletteData = {
        romColors = {
          { nil, nil, nil, nil },
        },
      },
    }

    app:showRomPaletteAddressModal(win, 0, 0)

    expect(capture.opts.initialAddress).toBe("")
  end)
end)
