local WM = require("controllers.window.window_controller")
local StaticArtToolbar = require("user_interface.toolbars.static_art_toolbar")

describe("static_art_toolbar.lua - sprite layer mode inheritance", function()
  local previousCtx

  beforeEach(function()
    previousCtx = rawget(_G, "ctx")
    _G.ctx = nil
  end)

  afterEach(function()
    _G.ctx = previousCtx
  end)

  it("adds sprite layers preserving 8x16 mode in static sprite windows", function()
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = false,
      spriteMode = "8x16",
      cols = 8,
      rows = 8,
    })

    local ctx = { setStatus = function() end }
    local toolbar = StaticArtToolbar.new(win, ctx, wm)
    toolbar:_onAddLayer()

    expect(#win.layers).toBe(2)
    expect(win.layers[2].kind).toBe("sprite")
    expect(win.layers[2].mode).toBe("8x16")
  end)
end)
