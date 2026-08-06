local LinkVisual = require("controllers.window.window_link_visual_controller")
local WM = require("controllers.window.window_controller")
local colors = require("app_colors")

describe("window_link_visual_controller.lua", function()
  it("computes pivot handle geometry from window left edge", function()
    local handleCx = LinkVisual.handleCenterXForWindowLeft(100)
    expect(handleCx).toBe(96.5)

    local ox, oy, ow, oh = LinkVisual.getPivotHandleRect(handleCx, 40)
    expect(ox).toBe(93)
    expect(oy).toBe(36)
    expect(ow).toBe(7)
    expect(oh).toBe(7)

    local ix, iy, iw, ih = LinkVisual.getInnerRectForHandleCenter(handleCx, 40)
    expect(iw).toBe(3)
    expect(ih).toBe(3)

    local cx, cy = LinkVisual.getInnerRectCenterPoint(handleCx, 40)
    expect(cx).toBe(ix + 1)
    expect(cy).toBe(iy + 1)
  end)

  it("detects pattern and palette link state per window kind", function()
    local wm = WM.new()
    local pt = wm:createPatternTableWindow({ title = "PT", x = 10, y = 10 })
    local ppu = wm:createPPUFrameWindow({ title = "PPU", x = 200, y = 10, romRaw = string.rep("\0", 256) })
    local oam = wm:createSpriteWindow({ animated = true, oamBacked = true, title = "OAM", x = 40, y = 180 })

    ppu.layers[1].linkedPatternTableWindowId = pt._id
    oam.layers[1].linkedPatternTableWindowId = pt._id
    table.insert(ppu.layers, {
      kind = "sprite",
      items = {},
      linkedPatternTableWindowId = "orphan",
    })

    expect(LinkVisual.ppuPatternBgLinked(ppu, wm)).toBe(true)
    expect(LinkVisual.ppuPatternSpriteLinked(ppu, wm)).toBe(true)
    expect(LinkVisual.oamPatternLinked(oam, wm)).toBe(true)
    expect(LinkVisual.innerColorForSlot(ppu, "ppu_pattern_bg", wm)[1]).toBe(colors.red[1])
    expect(LinkVisual.innerColorForSlot(oam, "oam_pattern", wm)[1]).toBe(colors.green[1])
  end)

  it("collects palette link edges and builds anchor layouts", function()
    local wm = WM.new()
    local art = wm:createTileWindow({ title = "Art", x = 20, y = 20 })
    local rom = wm:createRomPaletteWindow({ title = "ROM", x = 300, y = 20 })
    art.layers[1].paletteData = { winId = rom._id }

    local app = {
      wm = wm,
      windowLinksMode = "always",
      canvas = { getWidth = function() return 640 end, getHeight = function() return 360 end },
    }

    local edges = LinkVisual.collectWindowLinkEdges(app)
    expect(#edges).toBe(1)
    expect(edges[1].fromWin).toBe(art)
    expect(edges[1].toWin).toBe(rom)
    expect(edges[1].color).toBe(colors.blue)

    local layouts, handles = LinkVisual.buildAnchorLayouts(app, edges)
    expect(layouts[art]).toBeTruthy()
    expect(layouts[art].layout_palette).toBeTruthy()
    expect(layouts[rom]).toBeTruthy()
    expect(layouts[rom].palette_source).toBeTruthy()
    expect(#handles >= 2).toBe(true)

    local cx, cy = LinkVisual.getLeftAnchorPoint(art, "layout_palette", layouts)
    expect(type(cx)).toBe("number")
    expect(type(cy)).toBe("number")
  end)

  it("gives sketch canvas the same three PPU-style link handles", function()
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "Sketch", x = 40, y = 40 })
    local pt = wm:createPatternTableWindow({ title = "PT", x = 300, y = 40 })
    local rom = wm:createRomPaletteWindow({ title = "ROM", x = 300, y = 200 })
    sketch.linkedPatternTableWindowId = pt._id
    pt.linkedSketchCanvasWindowId = sketch._id
    sketch.layers[1].paletteData = { winId = rom._id }

    local app = {
      wm = wm,
      windowLinksMode = "always",
      canvas = { getWidth = function() return 640 end, getHeight = function() return 360 end },
    }

    expect(LinkVisual.ppuPatternBgLinked(sketch, wm)).toBe(true)
    expect(LinkVisual.ppuPatternSpriteLinked(sketch, wm)).toBe(false)
    expect(LinkVisual.innerColorForSlot(sketch, "ppu_pattern_bg", wm)[1]).toBe(colors.red[1])
    expect(LinkVisual.innerColorForSlot(sketch, "ppu_pattern_sprite", wm)).toBe(colors.transparent)
    expect(LinkVisual.innerColorForSlot(sketch, "ppu_palette", wm)[1]).toBe(colors.blue[1])

    local edges = LinkVisual.collectWindowLinkEdges(app)
    local sawPalette, sawPattern = false, false
    for _, edge in ipairs(edges) do
      if edge.fromWin == sketch and edge.fromSlot == "ppu_palette" and edge.toWin == rom then
        sawPalette = true
      end
      if edge.toWin == sketch and edge.toSlot == "ppu_pattern_bg" and edge.fromWin == pt then
        sawPattern = true
        expect(edge.color).toBe(colors.red)
      end
    end
    expect(sawPalette).toBe(true)
    expect(sawPattern).toBe(true)

    local layouts = LinkVisual.buildAnchorLayouts(app, edges)
    expect(layouts[sketch]).toBeTruthy()
    expect(layouts[sketch].ppu_pattern_bg).toBeTruthy()
    expect(layouts[sketch].ppu_pattern_sprite).toBeTruthy()
    expect(layouts[sketch].ppu_palette).toBeTruthy()
  end)

  it("uses brown for pattern-table handles linked to both BG and sprite layers", function()
    local wm = WM.new()
    local pt = wm:createPatternTableWindow({ title = "PT", x = 10, y = 10 })
    local ppu = wm:createPPUFrameWindow({ title = "PPU", x = 200, y = 10, romRaw = string.rep("\0", 256) })
    ppu.layers[1].linkedPatternTableWindowId = pt._id
    table.insert(ppu.layers, {
      kind = "sprite",
      items = {},
      linkedPatternTableWindowId = pt._id,
    })

    local app = {
      wm = wm,
      windowLinksMode = "always",
      canvas = { getWidth = function() return 640 end, getHeight = function() return 360 end },
    }
    local edges = LinkVisual.collectWindowLinkEdges(app)
    local layouts = LinkVisual.buildAnchorLayouts(app, edges)
    expect(layouts[pt]).toBeTruthy()
    expect(layouts[pt].pattern_source).toBeTruthy()
    expect(layouts[pt].pattern_source.innerColor).toBe(colors.brown)
    expect(layouts[pt].pattern_source.innerSplit).toBeNil()
  end)

  it("prepareLinkDrawState returns nil when modals block workspace", function()
    local app = {
      wm = WM.new(),
      windowLinksMode = "always",
      settingsModal = { isVisible = function() return true end },
    }
    expect(LinkVisual.prepareLinkDrawState(app)).toBe(nil)
  end)

  it("collects partner windows for a pivot handle slot", function()
    local a = { _id = "a" }
    local b = { _id = "b" }
    local c = { _id = "c" }
    local edges = {
      { fromWin = a, fromSlot = "palette_source", toWin = b, toSlot = "layout_palette" },
      { fromWin = a, fromSlot = "palette_source", toWin = c, toSlot = "ppu_palette" },
      { fromWin = b, fromSlot = "layout_palette", toWin = a, toSlot = "palette_source" },
    }
    local partners = LinkVisual.collectLinkedWindowsForSlot(edges, a, "palette_source")
    expect(#partners).toBe(2)
    expect(partners[1] == b or partners[2] == b).toBe(true)
    expect(partners[1] == c or partners[2] == c).toBe(true)
  end)

  it("focuses and restores minimized partners when a pivot handle is clicked", function()
    local restored = {}
    local focused = {}
    local brought = {}
    local source = {
      _id = "src",
      _closed = false,
      _minimized = false,
      _groupHidden = false,
      kind = "rom_palette",
    }
    local partner = {
      _id = "dst",
      _closed = false,
      _minimized = true,
      _groupHidden = false,
      kind = "ppu_frame",
    }
    local app = {
      windowLinksMode = "always",
      wm = {
        windows = { source, partner },
        getWindows = function(self)
          return self.windows
        end,
        getFocus = function()
          return source
        end,
        restoreMinimizedWindow = function(_, win, opts)
          restored[#restored + 1] = { win = win, focus = opts and opts.focus }
          win._minimized = false
          return true
        end,
        setFocus = function(_, win)
          focused[#focused + 1] = win
        end,
        bringToFront = function(self, win)
          brought[#brought + 1] = win
          for i, w in ipairs(self.windows) do
            if w == win then
              table.remove(self.windows, i)
              break
            end
          end
          self.windows[#self.windows + 1] = win
        end,
      },
    }

    local ok = LinkVisual.focusWindowsLinkedToHandle(app, source, "palette_source", {
      {
        fromWin = partner,
        fromSlot = "ppu_palette",
        toWin = source,
        toSlot = "palette_source",
        color = colors.blue,
      },
    })
    expect(ok).toBe(true)
    expect(#restored).toBe(1)
    expect(restored[1].win).toBe(partner)
    expect(restored[1].focus).toBe(true)
    expect(#brought).toBe(1)
    expect(brought[1]).toBe(partner)
  end)

  it("records one undo event that restores minimize and z-order for link-handle activate", function()
    local UndoRedoController = require("controllers.input_support.undo_redo_controller")
    local UndoRedoCommandRegistry = require("controllers.input_support.undo_redo_command_registry")
    local ur = UndoRedoController.new(10)
    local source = {
      _id = "src",
      _closed = false,
      _minimized = false,
      _groupHidden = false,
      _collapsed = false,
      kind = "rom_palette",
    }
    local partner = {
      _id = "dst",
      _closed = false,
      _minimized = true,
      _groupHidden = false,
      _collapsed = false,
      kind = "ppu_frame",
    }
    local other = {
      _id = "other",
      _closed = false,
      _minimized = false,
      _groupHidden = false,
      _collapsed = false,
      kind = "chr",
    }
    local focused = source
    local wm = {
      windows = { source, partner, other },
      getWindows = function(self)
        return self.windows
      end,
      getFocus = function()
        return focused
      end,
      setFocus = function(_, win)
        focused = win
      end,
      restoreMinimizedWindow = function(_, win, opts)
        win._minimized = false
        if opts and opts.focus ~= false then
          focused = win
        end
        return true
      end,
      minimizeWindow = function(_, win)
        win._minimized = true
        if focused == win then
          focused = nil
        end
        return true
      end,
      bringToFront = function(self, win)
        for i, w in ipairs(self.windows) do
          if w == win then
            table.remove(self.windows, i)
            break
          end
        end
        self.windows[#self.windows + 1] = win
      end,
      _restoreWindowsArrayOrder = function(self, order)
        self.windows = {}
        for i = 1, #order do
          self.windows[i] = order[i]
        end
      end,
      _setCollapsedWithToolbarIcon = function(_, win, collapsed)
        win._collapsed = collapsed == true
      end,
    }
    local app = {
      windowLinksMode = "always",
      undoRedo = ur,
      wm = wm,
    }

    expect(LinkVisual.focusWindowsLinkedToHandle(app, source, "palette_source", {
      {
        fromWin = partner,
        fromSlot = "ppu_palette",
        toWin = source,
        toSlot = "palette_source",
        color = colors.blue,
      },
    })).toBe(true)

    expect(#ur.stack).toBe(1)
    expect(ur.stack[1].type).toBe("window_link_handle_activate")
    expect(partner._minimized).toBe(false)
    expect(wm.windows[#wm.windows]).toBe(partner)

    expect(UndoRedoCommandRegistry.applyEvent(ur.stack[1], "undo", app)).toBe(true)
    expect(partner._minimized).toBe(true)
    expect(wm.windows[1]).toBe(source)
    expect(wm.windows[2]).toBe(partner)
    expect(wm.windows[3]).toBe(other)
    expect(focused).toBe(source)

    expect(UndoRedoCommandRegistry.applyEvent(ur.stack[1], "redo", app)).toBe(true)
    expect(partner._minimized).toBe(false)
    expect(wm.windows[#wm.windows]).toBe(partner)
  end)

  it("tryHandlePivotHandleClick consumes handle hits and ignores misses", function()
    local partnerFocused = 0
    local source = {
      _id = "src",
      _closed = false,
      _minimized = false,
      _groupHidden = false,
      kind = "rom_palette",
      x = 100,
      y = 20,
      w = 80,
      h = 60,
      getHeaderRect = function(self)
        return self.x, self.y, self.w, 16
      end,
      getScreenRect = function(self)
        return self.x, self.y, self.w, self.h
      end,
    }
    local partner = {
      _id = "dst",
      _closed = false,
      _minimized = false,
      _groupHidden = false,
      kind = "static_art",
      x = 300,
      y = 20,
      w = 80,
      h = 60,
      layers = { { kind = "tile", paletteData = { winId = "src" } } },
      getHeaderRect = function(self)
        return self.x, self.y, self.w, 16
      end,
      getScreenRect = function(self)
        return self.x, self.y, self.w, self.h
      end,
    }
    local app = {
      windowLinksMode = "always",
      canvas = { getWidth = function() return 640 end, getHeight = function() return 360 end },
      wm = {
        getWindows = function()
          return { source, partner }
        end,
        findWindowById = function(_, id)
          if id == "src" then return source end
          return nil
        end,
        setFocus = function(_, win)
          if win == partner then
            partnerFocused = partnerFocused + 1
          end
        end,
        bringToFront = function() end,
        getFocus = function()
          return source
        end,
      },
    }

    local state = LinkVisual.prepareLinkDrawState(app)
    expect(state).toBeTruthy()
    local entry = state.layouts[source] and state.layouts[source].palette_source
    expect(entry).toBeTruthy()

    expect(LinkVisual.tryHandlePivotHandleClick(app, entry.cx, entry.cy, 1)).toBe(true)
    expect(partnerFocused > 0).toBe(true)
    expect(LinkVisual.tryHandlePivotHandleClick(app, entry.cx, entry.cy, 2)).toBe(false)
    expect(LinkVisual.tryHandlePivotHandleClick(app, 0, 0, 1)).toBe(false)
  end)
end)
