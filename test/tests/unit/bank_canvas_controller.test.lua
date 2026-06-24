local BankCanvasController = require("controllers.chr.bank_canvas_controller")
local chr = require("chr")

local function newBankBytes()
  local bank = {}
  for i = 1, 8192 do
    bank[i] = 0
  end
  return bank
end

local function pixelGray(imageData, x, y)
  local r = imageData:getPixel(x, y)
  return r
end

describe("bank_canvas_controller.lua", function()
  it("reports bank canvas dimensions", function()
    local canvas = BankCanvasController.new()
    local w, h = canvas:getCanvasSize()
    expect(w).toBe(128)
    expect(h).toBe(256)
  end)

  it("repaints tile pixels into the bank image", function()
    local controller = BankCanvasController.new()
    local bank = newBankBytes()
    chr.setTilePixel(bank, 0, 0, 0, 3)

    controller:setView(1, "normal")
    expect(controller:repaint({ chrBanksBytes = { [1] = bank } })).toBe(true)

    local gray = pixelGray(controller.imageData, 0, 0)
    expect(gray > 0.99).toBe(true)
  end)

  it("repaints only invalidated tiles on partial updates", function()
    local controller = BankCanvasController.new()
    local bank = newBankBytes()
    chr.setTilePixel(bank, 0, 0, 0, 0)
    chr.setTilePixel(bank, 5, 0, 0, 3)

    controller:setView(1, "normal")
    expect(controller:repaint({ chrBanksBytes = { [1] = bank } })).toBe(true)

    chr.setTilePixel(bank, 5, 7, 7, 1)
    controller:invalidateTile(1, 5)
    expect(controller:repaint({ chrBanksBytes = { [1] = bank } })).toBe(true)

    local tileFiveGray = pixelGray(controller.imageData, (5 % 16) * 8 + 7, math.floor(5 / 16) * 8 + 7)
    expect(tileFiveGray > 0.2 and tileFiveGray < 0.4).toBe(true)
  end)

  it("maps tiles differently for oddEven order mode", function()
    local controller = BankCanvasController.new()
    local bank = newBankBytes()
    chr.setTilePixel(bank, 0, 7, 7, 3)
    chr.setTilePixel(bank, 1, 0, 0, 1)

    controller:setView(1, "oddEven")
    expect(controller:repaint({ chrBanksBytes = { [1] = bank } })).toBe(true)

    expect(pixelGray(controller.imageData, 7, 7) > 0.99).toBe(true)
    expect(pixelGray(controller.imageData, 0, 8) > 0.2).toBe(true)
    expect(pixelGray(controller.imageData, 0, 8) < 0.4).toBe(true)
  end)

  it("invalidateAll resets view and dirty tracking", function()
    local controller = BankCanvasController.new()
    controller:setView(2, "oddEven")
    controller:invalidateTile(2, 3)
    controller:invalidateAll()

    expect(controller.currentBank).toBe(nil)
    expect(controller.currentOrderMode).toBe("normal")
    expect(controller._fullRepaintNeeded).toBe(true)
  end)
end)
