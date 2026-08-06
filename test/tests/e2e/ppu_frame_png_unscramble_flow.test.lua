local E2EHarness = require("test.e2e_harness")
local BankViewController = require("controllers.chr.bank_view_controller")

local function firstReadablePath(candidates)
  for _, path in ipairs(candidates or {}) do
    local f = io.open(path, "rb")
    if f then
      f:close()
      return path
    end
  end
  return nil
end

describe("ppu_frame PNG drop flow - routing", function()
  it("does not unscramble when PNG is dropped on a PPU Frame tile layer", function()
    local harness = E2EHarness.new()
    local ok, err = pcall(function()
      local app = harness:boot()
      harness:loadROM()
      BankViewController.ensureBankTiles(app.appEditState, 1)

      local nametablePngPath = firstReadablePath({
        "test/test_nametable.png",
        "test_nametable.png",
        "../test/test_nametable.png",
      })
      assert(nametablePngPath, "could not find test nametable PNG")

      local ppuWin = assert(
        app.wm:createPPUFrameWindow({
          title = "PPU Frame E2E",
          romRaw = app.appEditState and app.appEditState.romRaw,
          patternTable = {
            ranges = {
              { bank = 1, from = 0, to = 255 },
            },
          },
        }),
        "failed to create PPU frame window"
      )

      -- Ensure tile layer is active (not sprite).
      ppuWin.activeLayer = 1
      if ppuWin.getActiveLayerIndex then
        -- keep default tile layer
      end

      app.wm:setFocus(ppuWin)
      do
        local x, y = harness:windowCellCenter(ppuWin, 0, 0)
        harness:moveMouse(x, y)
      end
      harness:dropFile(nametablePngPath)

      local statusText = tostring(app.statusText or "")
      assert(
        statusText:find("Sketch canvas", 1, true)
          or statusText:find("OAM Animation", 1, true)
          or statusText:find("PPU Frame sprite", 1, true),
        "expected PNG routing status for unsupported PPU tile drop, got: " .. statusText
      )
      assert(not statusText:find("unscrambl", 1, true), "tile-layer PNG should not run unscramble: " .. statusText)

      local layer = assert(ppuWin.layers and ppuWin.layers[1], "expected tile layer in PPU frame window")
      assert(layer.kind == "tile", "expected first layer to be a tile layer")
      -- Unscramble would fill 32x30 items; without it the layer stays empty / sparse.
      local itemCount = 0
      if type(layer.items) == "table" then
        for i = 1, #layer.items do
          if layer.items[i] ~= nil then
            itemCount = itemCount + 1
          end
        end
      end
      assert(itemCount < 32 * 30, "expected PPU tile layer not filled by nametable PNG unscramble")
    end)

    harness:destroy()
    if not ok then
      error(err)
    end
  end)
end)
