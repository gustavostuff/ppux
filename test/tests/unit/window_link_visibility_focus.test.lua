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

  it("does not raise linked windows on focus (OAM / pattern table)", function()
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

  it("does not raise linked windows on focus (PPU / pattern table)", function()
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

  it("does not raise linked palette consumers when focusing a ROM palette", function()
    local brought = {}
    local PaletteLinkController = require("controllers.palette.palette_link_controller")
    local original = PaletteLinkController.getLinkedTargetsForPalette
    PaletteLinkController.getLinkedTargetsForPalette = function()
      return {
        {
          win = {
            kind = "ppu_frame",
            _closed = false,
            _minimized = false,
            _groupHidden = false,
          },
        },
      }
    end

    local wm = makeWm(brought)
    local paletteWin = {
      kind = "rom_palette",
      _closed = false,
      _minimized = false,
      _groupHidden = false,
    }
    WindowLinkVisibility.onWindowFocused({ windowLinksMode = "auto_hide" }, wm, paletteWin)
    expect(#brought).toBe(0)

    PaletteLinkController.getLinkedTargetsForPalette = original
  end)

  it("setFocus raises only the focused window, not linked partners", function()
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
    local paletteWin = {
      kind = "rom_palette",
      _closed = false,
      _minimized = false,
      _id = "pal1",
    }
    oamWin.layers[1].paletteData = { winId = "pal1" }
    wm.windows = { ptWin, paletteWin, oamWin }
    wm.findWindowById = function(_, id)
      if id == "pt1" then return ptWin end
      if id == "pal1" then return paletteWin end
      return nil
    end
    wm:setFocus(oamWin)

    expect(wm.windows[#wm.windows]).toBe(oamWin)
    expect(wm.windows[1] == ptWin or wm.windows[1] == paletteWin).toBe(true)
    expect(wm.windows[2] == ptWin or wm.windows[2] == paletteWin).toBe(true)

    _G.ctx = previousCtx
  end)
end)
