local WM = require("controllers.window.window_controller")
local StaticArtToolbar = require("ui.toolbars.static_art_toolbar")

describe("static_art_toolbar.lua", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = nil
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("builds an empty specialized toolbar (palette links use on-canvas badges)", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = false,
      spriteMode = "8x16",
      cols = 8,
      rows = 8,
    })

    local ctx = { setStatus = function() end }
    local toolbar = StaticArtToolbar.new(win, ctx, wm)
    expect(toolbar.linkButton).toBeNil()
    expect(toolbar.getLinkHandleRect).toBeNil()
    expect(#toolbar.buttons).toBe(0)
  end)
end)
