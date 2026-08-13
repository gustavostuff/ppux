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
      romRaw = string.rep("\x30", 0x4000),
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
    modal:_syncFromAddressField()
    expect(modal.setButton.enabled).toBe(true)
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
      romRaw = string.rep("\x30", 0x4000),
      initialAddress = "0x003F10",
      onConfirm = function()
        confirmCalls = confirmCalls + 1
        return false
      end,
    })

    expect(modal.setButton.enabled).toBe(true)
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

  it("uses ninja for valid colors, hides invalid, and user-selects the pick", function()
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
    expect(modal.hexGrid.defaultCellStyle).toBe("ninja")
    expect(modal.hexGrid.rejectedCellStyle).toBe("hidden")
    expect(modal.hexGrid:getSemiSelectedStarts()).toEqual({})
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 0x0F })
    expect(modal.hexGrid:getUserSelectedStarts()).toEqual({ 0x0F })
    expect(modal:_isValidColorAddr(0x0C)).toBe(true)
    expect(modal:_isValidColorAddr(0x0F)).toBe(true)
    expect(modal:_isValidColorAddr(0x0D)).toBe(false)
    expect(modal:_isValidColorAddr(0x1E)).toBe(false)
    expect(modal:_isValidColorAddr(0x40)).toBe(false)
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
      boundAddr = 0x0F,
      baseRomCode = "0F",
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

  it("restores captured base at the bound address when live romRaw holds the override", function()
    local modal = RomPaletteAddressModal.new()
    -- Live ROM already has the user override ($2A) written through at the bound address.
    local rom = string.rep("\x07", 0x10) .. string.char(0x2A) .. string.rep("\x07", 0x6F)
    modal:show({
      romRaw = rom,
      initialAddress = "0x000010",
      boundAddr = 0x10,
      baseRomCode = "07",
      userOverrideCode = "2A",
    })

    expect(modal._showUserOverride).toBe(true)
    expect(modal.overridePreview.code).toBe("2A")
    expect(modal.selectedPreview.code).toBe("07")
    expect(string.byte(modal.romRaw, 0x10 + 1)).toBe(0x07)
    expect(modal:_displayCodeAt(0x10)).toBe("07")
    expect(modal:_nesFillColorForAddr(0x10, 1)[1]).toBeTruthy()
    modal:hide()
  end)

  it("marks bound ROM palette addresses on the hex minimap with each cell's own color", function()
    local modal = RomPaletteAddressModal.new()
    local rom = string.rep(string.char(0x07), 256)
    -- Same hex dump row (0x10..0x1F): each bound addr keeps its UI cell tint.
    local win = {
      rows = 4,
      cols = 4,
      codes2D = {
        [0] = { [0] = "0F", [1] = "0C", [2] = "2A", [3] = "07" },
      },
      paletteData = {
        romColors = {
          { false, 0x11, 0x15, false },
          { false, false, false, false },
          { false, false, false, false },
          { false, false, false, false },
        },
      },
    }

    local markers = RomPaletteAddressModal.collectBoundRomColorMinimapMarkers(win, rom, {
      romPaletteWindows = { win },
    })
    expect(#markers).toBe(2)
    expect(markers[1].offset).toBe(0x11)
    expect(markers[2].offset).toBe(0x15)

    local rgb0C = require("palettes").smooth_fbx["0C"]
    local rgb2A = require("palettes").smooth_fbx["2A"]
    expect(markers[1].color[1]).toBe(rgb0C[1])
    expect(markers[1].color[2]).toBe(rgb0C[2])
    expect(markers[1].color[3]).toBe(rgb0C[3])
    expect(markers[2].color[1]).toBe(rgb2A[1])
    expect(markers[2].color[2]).toBe(rgb2A[2])
    expect(markers[2].color[3]).toBe(rgb2A[3])

    modal:show({
      window = win,
      romRaw = rom,
      initialAddress = "0x000011",
      romPaletteWindows = { win },
    })
    local gridMarkers = modal.hexGrid:getMinimapMarkers()
    expect(#gridMarkers).toBe(2)
    expect(gridMarkers[1].offset).toBe(0x11)
    expect(gridMarkers[2].offset).toBe(0x15)
    modal.searchField:setText("07")
    modal:_applyByteSearch()
    modal:_focusSearchField()
    expect(#modal.hexGrid:getMinimapMarkers() > 0).toBe(true)
    expect(modal.hexGrid:getMinimapMarkers()[1].boundPaint).toBe(false)
    modal.searchField:setFocused(false)
    modal:_refreshMinimapMarkers()
    gridMarkers = modal.hexGrid:getMinimapMarkers()
    expect(#gridMarkers).toBe(2)
    expect(gridMarkers[1].offset).toBe(0x11)
    expect(gridMarkers[2].offset).toBe(0x15)
    modal:hide()
  end)

  it("can mark bound addresses from all ROM palettes when the flag is on", function()
    local previous = RomPaletteAddressModal.MINIMAP_MARK_ALL_ROM_PALETTES
    RomPaletteAddressModal.MINIMAP_MARK_ALL_ROM_PALETTES = true
    local winA = {
      rows = 1,
      cols = 4,
      codes2D = { [0] = { [1] = "0C" } },
      paletteData = { romColors = { { false, 0x11, false, false } } },
    }
    local winB = {
      rows = 1,
      cols = 4,
      codes2D = { [0] = { [1] = "2A" } },
      paletteData = { romColors = { { false, 0x40, false, false } } },
    }
    local markers = RomPaletteAddressModal.collectBoundRomColorMinimapMarkers(winA, "", {
      romPaletteWindows = { winA, winB },
    })
    RomPaletteAddressModal.MINIMAP_MARK_ALL_ROM_PALETTES = previous
    expect(#markers).toBe(2)
    expect(markers[1].offset).toBe(0x11)
    expect(markers[2].offset).toBe(0x40)
  end)

  it("marks only the edited palette when MINIMAP_MARK_ALL_ROM_PALETTES is false", function()
    local previous = RomPaletteAddressModal.MINIMAP_MARK_ALL_ROM_PALETTES
    RomPaletteAddressModal.MINIMAP_MARK_ALL_ROM_PALETTES = false
    local winA = {
      rows = 1,
      cols = 4,
      codes2D = { [0] = { [1] = "0C" } },
      paletteData = { romColors = { { false, 0x11, false, false } } },
    }
    local winB = {
      rows = 1,
      cols = 4,
      codes2D = { [0] = { [1] = "2A" } },
      paletteData = { romColors = { { false, 0x40, false, false } } },
    }
    local markers = RomPaletteAddressModal.collectBoundRomColorMinimapMarkers(winA, "", {
      romPaletteWindows = { winA, winB },
    })
    RomPaletteAddressModal.MINIMAP_MARK_ALL_ROM_PALETTES = previous
    expect(#markers).toBe(1)
    expect(markers[1].offset).toBe(0x11)
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

  it("rejects clicks on invalid NES color bytes and clears the pick", function()
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
    local hy = 2 + 12 + 0 * 12 + 2
    modal.hexGrid:setPosition(0, 0)
    modal.hexGrid:mousepressed(hx, hy, 1)
    expect(modal.hexGrid:getSelectedStarts()).toEqual({})
    expect(modal.hexGrid:getUserSelectedStarts()).toEqual({})
    -- Hidden invalid: clear selection without the warning label.
    expect(modal._invalidColorWarning).toBe(nil)
    -- Masked "0x000000" field cannot be truly empty; clear resets to the mask skeleton.
    expect(modal.textField:getText()).toBe("0x000000")
    expect(modal.hexGrid.rejectedCellStyle).toBe("hidden")
    expect(modal:cursorNameAt(hx, hy)).toBe("arrow")
    expect(modal.setButton.enabled).toBe(false)
    modal:hide()
  end)

  it("parses spaced and packed hex-byte searches", function()
    expect(RomPaletteAddressModal.parseSearchBytes("A0 B2 23 0A")).toEqual({
      0xA0, 0xB2, 0x23, 0x0A,
    })
    expect(RomPaletteAddressModal.parseSearchBytes("a0b234567")).toEqual({
      0xA0, 0xB2, 0x34, 0x56,
    })
    expect(RomPaletteAddressModal.parseSearchBytes("")).toEqual({})
    expect(RomPaletteAddressModal.parseSearchBytes("G0")).toEqual({})
  end)

  it("underlines search hits and ignores non-hex search input", function()
    local modal = RomPaletteAddressModal.new()
    local rom = string.char(0x11, 0xA0, 0xB2, 0x23, 0x0A, 0x99, 0xA0, 0xB2, 0x23, 0x0A)
    modal:show({
      romRaw = rom,
      initialAddress = "",
    })
    modal.searchField:setText("A0 B2 23 0A")
    modal:_applyByteSearch()
    expect(modal.hexGrid:getUnderlinedStarts()).toEqual({ 1, 6 })
    expect(modal.hexGrid:getUnderlinedGroupSize(1)).toBe(4)
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 1 })
    expect(modal.hexGrid:getSelectedGroupSize(1)).toBe(4)
    expect(modal:_searchStatusText()).toBe("1/2")
    expect(#modal.hexGrid:getMinimapMarkers()).toBe(0)
    modal:_focusSearchField()
    local marks = modal.hexGrid:getMinimapMarkers()
    expect(#marks).toBe(2)
    expect(marks[1].offset).toBe(1)
    expect(marks[1].groupSize).toBe(4)
    expect(marks[1].boundPaint).toBe(false)
    expect(marks[1].color).toBe("red")
    expect(marks[2].offset).toBe(6)
    expect(marks[2].color).toBe("green")
    modal.searchField:setFocused(false)
    modal:_refreshMinimapMarkers()
    expect(#modal.hexGrid:getMinimapMarkers()).toBe(0)
    modal.searchField:setText("zz")
    expect(modal.searchField:getText()).toBe("")
    modal:_applyByteSearch()
    expect(modal.hexGrid:getUnderlinedStarts()).toEqual({})
    expect(modal.hexGrid:getSelectedStarts()).toEqual({})
    expect(modal:_searchStatusText()).toBe("")
    modal:hide()
  end)

  it("cycles search hits with Enter while the search field is focused", function()
    local modal = RomPaletteAddressModal.new()
    local rom = string.char(0x11, 0xA0, 0xB2, 0x23, 0x0A, 0x99, 0xA0, 0xB2, 0x23, 0x0A)
    modal:show({
      romRaw = rom,
      initialAddress = "",
    })
    modal.searchField:setText("A0B2230A")
    modal:_applyByteSearch()
    expect(modal:_searchStatusText()).toBe("1/2")
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 1 })
    modal:_focusSearchField()
    expect(modal:handleKey("return")).toBe(true)
    expect(modal._searchHitIndex).toBe(2)
    expect(modal:_searchStatusText()).toBe("2/2")
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 6 })
    expect(modal.hexGrid:getSelectedGroupSize(6)).toBe(4)
    expect(modal:handleKey("return")).toBe(true)
    expect(modal._searchHitIndex).toBe(1)
    expect(modal:_searchStatusText()).toBe("1/2")
    expect(modal:isVisible()).toBe(true)
    modal.searchField:setText("FF")
    modal:_applyByteSearch()
    expect(modal:_searchStatusText()).toBe("0")
    expect(modal.hexGrid:getSelectedStarts()).toEqual({})
    modal:hide()
  end)

  it("lays out Search bytes in one column with occurrence status and no hide-invalid checkbox", function()
    local modal = RomPaletteAddressModal.new()
    modal:show({
      romRaw = string.rep("\x30", 256),
      initialAddress = "",
    })
    expect(modal.hideInvalidCheckbox).toBeNil()
    expect(modal.searchField).toBeTruthy()
    expect(modal.searchField.accept).toBe("hex_bytes")
    expect(modal.hexGrid.boundAsSelected).toBe(true)
    expect(modal.hexGrid.minimapIncludeSelection).toBe(false)
    local row = modal._searchStatusRow
    expect(type(row)).toBe("number")
    local fieldCell = modal.panel:getCell(2, row)
    expect(fieldCell.component).toBe(modal.searchField)
    expect(fieldCell.colspan).toBe(1)
    local statusCell = modal.panel:getCell(3, row)
    expect(statusCell.text).toBe("")
    modal.searchField:setText("30")
    modal:_applyByteSearch()
    expect(modal:_searchStatusText()).toBe("1/256")
    expect(modal.panel:getCell(3, row).text).toBe("1/256")
    modal:hide()
  end)

  it("paints the active search hit Selected and inactive hits Underlined with the OAM color cycle", function()
    local modal = RomPaletteAddressModal.new()
    local rom = string.char(0x11, 0xA0, 0xB2, 0x23, 0x0A, 0x99, 0xA0, 0xB2, 0x23, 0x0A)
    modal:show({
      romRaw = rom,
      initialAddress = "",
    })
    modal.searchField:setText("A0B2230A")
    modal:_applyByteSearch()
    local red = modal:_searchHighlightColor(1)
    local green = modal:_searchHighlightColor(2)
    expect(modal:_searchColorForAddr(1)[1]).toBe(red[1])
    expect(modal:_searchColorForAddr(1)[2]).toBe(red[2])
    expect(modal:_searchColorForAddr(1)[3]).toBe(red[3])
    expect(modal:_searchColorForAddr(6)[1]).toBe(green[1])
    expect(modal:_selectedFillForAddr(1)[1]).toBe(red[1])
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 1 })
    expect(modal.hexGrid:getUnderlinedStarts()).toEqual({ 1, 6 })
    expect(modal.hexGrid:getSelectedGroupSize(1)).toBe(4)
    expect(modal.hexGrid:getUnderlinedGroupSize(6)).toBe(4)
    local underline = modal.hexGrid:_underlineColorForStart(6)
    expect(underline[1]).toBe(green[1])
    expect(underline[2]).toBe(green[2])
    expect(underline[3]).toBe(green[3])
    modal:_focusSearchField()
    expect(modal:handleKey("return")).toBe(true)
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ 6 })
    expect(modal:_selectedFillForAddr(6)[1]).toBe(green[1])
    expect(modal:isVisible()).toBe(true)
    modal:hide()
  end)

  it("restores mapped ROM palette minimap markers after unfocusing Search bytes", function()
    local modal = RomPaletteAddressModal.new()
    local rom = string.rep(string.char(0x07), 256)
    local win = {
      rows = 4,
      cols = 4,
      codes2D = {
        [0] = { [0] = "0F", [1] = "0C", [2] = "2A", [3] = "07" },
      },
      paletteData = {
        romColors = {
          { false, 0x11, 0x15, false },
          { false, false, false, false },
          { false, false, false, false },
          { false, false, false, false },
        },
      },
    }
    modal:show({
      window = win,
      romRaw = rom,
      initialAddress = "0x000011",
      romPaletteWindows = { win },
    })
    expect(#modal.hexGrid:getMinimapMarkers()).toBe(2)
    modal.searchField:setText("07")
    modal:_applyByteSearch()
    modal:_focusSearchField()
    expect(modal.searchField.focused).toBe(true)
    expect(modal.hexGrid:getMinimapMarkers()[1].boundPaint).toBe(false)
    modal.searchField.x, modal.searchField.y = 400, 400
    modal.textField.x, modal.textField.y = 400, 420
    modal.hexGrid:setPosition(0, 0)
    expect(modal:mousepressed(8, 20, 1)).toBe(true)
    expect(modal.searchField.focused).toBe(false)
    local restored = modal.hexGrid:getMinimapMarkers()
    expect(#restored).toBe(2)
    expect(restored[1].offset).toBe(0x11)
    expect(restored[2].offset).toBe(0x15)
    expect(restored[1].boundPaint).toBeNil()
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
      getCapturedBaseCode = function()
        return "07"
      end,
    }

    app:showRomPaletteAddressModal(win, 1, 0)

    expect(capture.opts.initialAddress).toBe("0x003F10")
    expect(capture.opts.boundAddr).toBe(0x3F10)
    expect(capture.opts.userOverrideCode).toBe("2A")
    expect(capture.opts.baseRomCode).toBe("07")
  end)

  it("prefers codes2D for override and captured base over live romRaw", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      paletteData = {
        romColors = {
          { 0x3F00, 0x3F10, nil, nil },
        },
        userDefinedCode = {
          { row = 0, col = 1, code = "29" },
        },
      },
      codes2D = {
        [0] = { [0] = "07", [1] = "1A" },
      },
      getCapturedBaseCode = function(_, col, row)
        expect(col).toBe(1)
        expect(row).toBe(0)
        return "29"
      end,
    }

    app:showRomPaletteAddressModal(win, 1, 0)

    expect(capture.opts.userOverrideCode).toBe("1A")
    expect(capture.opts.baseRomCode).toBe("29")
    expect(capture.opts.boundAddr).toBe(0x3F10)
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

describe("rom_palette_address_modal Set enabled", function()
  it("disables Set when opened with no valid color selection", function()
    local modal = RomPaletteAddressModal.new()
    modal:show({
      romRaw = string.rep("\x0F", 256),
      initialAddress = "",
    })
    expect(#modal.hexGrid:getSelectedStarts()).toBe(0)
    expect(modal.setButton.enabled).toBe(false)
    modal:hide()
  end)

  it("enables Set when a valid color is selected", function()
    local modal = RomPaletteAddressModal.new()
    modal:show({
      romRaw = string.rep("\x30", 256),
      initialAddress = "0x000010",
    })
    expect(#modal.hexGrid:getSelectedStarts()).toBe(1)
    expect(modal.setButton.enabled).toBe(true)
    modal:_clearPick()
    expect(modal.setButton.enabled).toBe(false)
    modal:hide()
  end)
end)
