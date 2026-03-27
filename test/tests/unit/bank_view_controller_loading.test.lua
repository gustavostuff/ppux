local BankViewController = require("controllers.chr.bank_view_controller")
local ChrBankWindow = require("user_interface.windows_system.chr_bank_window")
local Tile = require("user_interface.windows_system.tile_item")

describe("bank_view_controller.lua", function()
  local originalFromCHR

  beforeEach(function()
    originalFromCHR = Tile.fromCHR
  end)

  afterEach(function()
    Tile.fromCHR = originalFromCHR
  end)

  it("builds one bank-window layer per bank and lazily resolves tiles for the current bank", function()
    Tile.fromCHR = function(_, idx)
      return {
        index = idx,
        draw = function() end,
      }
    end

    local state = {
      chrBanksBytes = {
        [1] = {},
        [2] = {},
        [3] = {},
      },
      tilesPool = {},
      currentBank = 2,
    }

    local win = ChrBankWindow.new(0, 0, 8, 8, 16, 32, 1, {
      currentBank = 2,
    })

    BankViewController.rebuildBankWindowItems(win, state, "normal")

    expect(#win.layers).toBe(3)
    expect(win.currentBank).toBe(2)
    expect(win.activeLayer).toBe(2)
    expect(win.layers[1].name).toBe("Bank 1")
    expect(win.layers[2].name).toBe("Bank 2")
    expect(win.layers[3].name).toBe("Bank 3")
    expect(win.layers[1].items[1]).toBeNil()
    expect(state.tilesPool[2]).toBeNil()

    local handle = win:getVirtualTileHandle(0, 0, 2)
    expect(handle.index).toBe(0)
    expect(handle._bankIndex).toBe(2)
    expect(handle._virtual).toBe(true)
    expect(state.tilesPool[2]).toBeNil()

    local tileA = win:get(0, 0, 2)
    local tileB = win:get(15, 31, 3)

    expect(tileA.index).toBe(0)
    expect(tileA._bankIndex).toBe(2)
    expect(tileB.index).toBe(511)
    expect(tileB._bankIndex).toBe(3)
  end)
end)
