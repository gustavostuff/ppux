local WM = require("controllers.window.window_controller")
local StaticArtToolbar = require("user_interface.toolbars.static_art_toolbar")

describe("static_art_toolbar.lua", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = nil
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("exposes a palette link handle for static art windows", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = false,
      spriteMode = "8x16",
      cols = 8,
      rows = 8,
    })

    local ctx = { setStatus = function() end }
    local toolbar = StaticArtToolbar.new(win, ctx, wm)
    expect(toolbar.linkButton).toBeTruthy()
    expect(toolbar:getLinkHandleRect()).toBeTruthy()
  end)
end)
