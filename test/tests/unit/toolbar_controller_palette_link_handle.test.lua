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
        isGroupedPaletteWindowsEnabled = function()
          return true
        end,
      },
    }
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("creates a specialized toolbar without a link handle for a single global palette window", function()
    local wm = WM.new()
    local win = wm:createPaletteWindow({
      title = "Palette A",
    })

    ToolbarController.createToolbarsForWindow(win, _G.ctx, wm)

    expect(win.specializedToolbar).toBeTruthy()
    expect(win.specializedToolbar.linkButton).toBeNil()
    expect(win.specializedToolbar.prevButton).toBeTruthy()
    expect(win.specializedToolbar.nextButton).toBeTruthy()
    expect(win.specializedToolbar.buttons[1]).toBe(win.specializedToolbar.prevButton)
    expect(win.specializedToolbar.buttons[2]).toBe(win.specializedToolbar.nextButton)
    expect(win.specializedToolbar.compactButton).toBeTruthy()
  end)

  it("creates a specialized toolbar with a link handle for ROM palette windows", function()
    local wm = WM.new()
    local win = wm:createRomPaletteWindow({
      title = "ROM Palette",
    })

    ToolbarController.createToolbarsForWindow(win, _G.ctx, wm)

    expect(win.specializedToolbar).toBeTruthy()
    expect(win.specializedToolbar.prevButton).toBeTruthy()
    expect(win.specializedToolbar.nextButton).toBeTruthy()
    expect(win.specializedToolbar.buttons[1]).toBe(win.specializedToolbar.prevButton)
    expect(win.specializedToolbar.buttons[2]).toBe(win.specializedToolbar.nextButton)
    expect(win.specializedToolbar.linkButton).toBeTruthy()
  end)

  it("hides grouped navigation buttons when grouped mode is off", function()
    _G.ctx.app.isGroupedPaletteWindowsEnabled = function()
      return false
    end
    local wm = WM.new()
    local win = wm:createPaletteWindow({
      title = "Palette B",
    })

    ToolbarController.createToolbarsForWindow(win, _G.ctx, wm)
    win.specializedToolbar:updateIcons()

    expect(win.specializedToolbar.prevButton.visible).toBe(false)
    expect(win.specializedToolbar.nextButton.visible).toBe(false)
  end)
end)
