local ChrBankUiHelpers = require("controllers.chr.chr_bank_ui_helpers")
local KeyboardNavigationController = require("controllers.input.keyboard_navigation_controller")

describe("chr_bank_ui_helpers.lua", function()
  it("formats 16 CHR bytes as uppercase hex pairs", function()
    local bank = {}
    for i = 1, 16 do
      bank[i] = i - 1
    end
    expect(ChrBankUiHelpers.formatTileChrBytesHexSpaceSeparated(bank, 0)).toBe(
      "00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F"
    )

    for i = 1, 32 do
      bank[i] = 0
    end
    bank[17] = 0xAB
    expect(ChrBankUiHelpers.formatTileChrBytesHexSpaceSeparated(bank, 1)).toBe(
      "AB 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
    )
  end)

  it("copySelectedTileHexToClipboard reports when nothing is selected", function()
    local focus = {
      kind = "chr",
      getSelected = function()
        return nil, nil
      end,
      getTileIndexAt = function()
        return 0
      end,
    }
    local ctx = {
      app = {
        appEditState = { chrBanksBytes = { {} } },
      },
    }
    local ok, msg = ChrBankUiHelpers.copySelectedTileHexToClipboard(ctx, focus)
    expect(ok).toBe(false)
    expect(msg).toBe("Select a CHR tile first")
  end)

  it("copyChrTileHexToClipboard rejects invalid app or missing CHR bank entry", function()
    local ok, msg = ChrBankUiHelpers.copyChrTileHexToClipboard(nil, 1, 0)
    expect(ok).toBe(false)
    expect(msg).toBe("Invalid app")

    ok, msg = ChrBankUiHelpers.copyChrTileHexToClipboard({}, 1, 0)
    expect(ok).toBe(false)
    expect(msg).toBe("No CHR bank loaded")

    ok, msg = ChrBankUiHelpers.copyChrTileHexToClipboard({ appEditState = {} }, 1, 0)
    expect(ok).toBe(false)
    expect(msg).toBe("No CHR bank loaded")

    ok, msg = ChrBankUiHelpers.copyChrTileHexToClipboard(
      { appEditState = { chrBanksBytes = { {} } } },
      1,
      -1
    )
    expect(ok).toBe(false)
    expect(msg).toBe("Tile index out of range")
  end)

  it("copyChrTileHexToClipboard puts formatted hex on the system clipboard", function()
    local bank = {}
    for i = 1, 16 do
      bank[i] = i - 1
    end
    local app = {
      appEditState = { chrBanksBytes = { bank } },
    }
    local oldLove = rawget(_G, "love")
    local captured = nil
    rawset(_G, "love", {
      system = {
        setClipboardText = function(t)
          captured = t
        end,
      },
    })

    local ok, msg = ChrBankUiHelpers.copyChrTileHexToClipboard(app, 1, 0)
    expect(ok).toBe(true)
    expect(captured).toBe("00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F")
    expect(type(msg)).toBe("string")
    rawset(_G, "love", oldLove)
  end)
end)

describe("keyboard_navigation_controller.lua - CHR shortcuts", function()
  local function makeCtx(focus, utils)
    return {
      wm = function()
        return {
          getFocus = function()
            return focus
          end,
        }
      end,
      app = {
        appEditState = {
          currentBank = 1,
          chrBanksBytes = { {} },
        },
        setStatus = function() end,
      },
      rebuildChrBankWindow = function() end,
    }, utils
  end

  it("D toggles showChrDiffMode and refreshes toolbar", function()
    local diffUpdates = 0
    local focus = {
      kind = "chr",
      currentBank = 1,
      orderMode = "normal",
      showChrDiffMode = false,
      specializedToolbar = {
        updateDiffModeButton = function()
          diffUpdates = diffUpdates + 1
        end,
        triggerLayerLabelFlash = function() end,
      },
    }
    local ctx, utils = makeCtx(focus, {
      ctrlDown = function()
        return false
      end,
      shiftDown = function()
        return false
      end,
      altDown = function()
        return false
      end,
    })

    expect(
      KeyboardNavigationController.handleChrBankKeys(ctx, utils, "d", focus)
    ).toBe(true)
    expect(focus.showChrDiffMode).toBe(true)
    expect(diffUpdates).toBe(1)

    KeyboardNavigationController.handleChrBankKeys(ctx, utils, "d", focus)
    expect(focus.showChrDiffMode).toBe(false)
    expect(diffUpdates).toBe(2)
  end)
end)
