local WindowLinkVisibility = require("controllers.window.window_link_visibility")
local WM = require("controllers.window.window_controller")

describe("window_link_visibility.lua - focus behavior", function()
  local function makeWm(bringToFrontSpy)
    local brought = bringToFrontSpy or {}
    return {
      brought = brought,
      findWindowById = function(_, id)
        if id == "pt1" then
          return {
            kind = "pattern_table",
            _closed = false,
            _minimized = false,
            _groupHidden = false,
          }
        end
        return nil
      end,
      bringToFront = function(_, win)
        brought[#brought + 1] = win
      end,
    }
  end

  it("does not bring linked pattern table forward when focusing an OAM animation window", function()
    local brought = {}
    local wm = makeWm(brought)
    local oamWin = {
      kind = "oam_animation",
      _closed = false,
      _minimized = false,
      _groupHidden = false,
      layers = {
        { kind = "sprite", linkedPatternTableWindowId = "pt1" },
      },
    }
    local app = { windowLinksMode = "auto_hide" }

    WindowLinkVisibility.onWindowFocused(app, wm, oamWin)

    expect(#brought).toBe(0)
  end)

  it("does not bring linked pattern table forward when focusing a PPU frame window", function()
    local brought = {}
    local wm = makeWm(brought)
    local ppuWin = {
      kind = "ppu_frame",
      _closed = false,
      _minimized = false,
      _groupHidden = false,
      activeLayer = 1,
      layers = {
        { linkedPatternTableWindowId = "pt1" },
      },
    }
    local app = { windowLinksMode = "auto_hide" }

    WindowLinkVisibility.onWindowFocused(app, wm, ppuWin)

    expect(#brought).toBe(0)
  end)

  it("setFocus does not bring linked pattern table to the front", function()
    local previousCtx = rawget(_G, "ctx")
    _G.ctx = nil

    local wm = WM.new()
    local ptWin = {
      kind = "pattern_table",
      _closed = false,
      _minimized = false,
      _id = "pt1",
    }
    local oamWin = {
      kind = "oam_animation",
      _closed = false,
      _minimized = false,
      layers = {
        { kind = "sprite", linkedPatternTableWindowId = "pt1" },
      },
    }
    wm.windows = { ptWin, oamWin }
    wm:setFocus(oamWin)

    expect(wm.windows[#wm.windows]).toBe(oamWin)
    expect(wm.windows[1]).toBe(ptWin)

    _G.ctx = previousCtx
  end)
end)
