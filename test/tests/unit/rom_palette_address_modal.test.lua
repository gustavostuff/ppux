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
end)

describe("showRomPaletteAddressModal initial address", function()
  local function makeApp(capture)
    return setmetatable({
      romPaletteAddressModal = {
        show = function(_, opts)
          capture.opts = opts
        end,
      },
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
  end)

  it("keeps the cell's own address when already set", function()
    local capture = {}
    local app = makeApp(capture)
    local win = {
      paletteData = {
        romColors = {
          { 0x3F00, 0x3F10, nil, nil },
        },
      },
    }

    app:showRomPaletteAddressModal(win, 1, 0)

    expect(capture.opts.initialAddress).toBe("0x003F10")
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
