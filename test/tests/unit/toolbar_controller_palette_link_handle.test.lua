local ToolbarController = require("controllers.window.toolbar_controller")
local WM = require("controllers.window.window_controller")

describe("toolbar_controller.lua - palette link handle", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = {
      app = {
        appEditState = {
          romRaw = string.rep(string.char(0x0F), 64),
        },
      },
    }
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("creates a specialized toolbar with a link handle for a single global palette window", function()
    local wm = WM.new()
    local win = wm:createPaletteWindow({
      title = "Palette A",
    })

    ToolbarController.createToolbarsForWindow(win, _G.ctx, wm)

    expect(win.specializedToolbar).toBeTruthy()
    expect(win.specializedToolbar.linkButton).toBeTruthy()
    expect(win.specializedToolbar.compactButton).toBeTruthy()
    expect(win.specializedToolbar.linkButton.icon).toBeTruthy()
  end)

  it("creates a specialized toolbar with a link handle for ROM palette windows", function()
    local wm = WM.new()
    local win = wm:createRomPaletteWindow({
      title = "ROM Palette",
    })

    ToolbarController.createToolbarsForWindow(win, _G.ctx, wm)

    expect(win.specializedToolbar).toBeTruthy()
    expect(win.specializedToolbar.linkButton).toBeTruthy()
    expect(win.specializedToolbar.linkButton.icon).toBeTruthy()
  end)
end)
