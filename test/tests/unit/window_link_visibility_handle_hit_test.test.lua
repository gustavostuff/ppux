local WindowLinkVisibility = require("controllers.window.window_link_visibility")
local ResolutionController = require("controllers.app.resolution_controller")

describe("window_link_visibility.lua - pivot handle hover hit test", function()
  local function makeWindow(opts)
    opts = opts or {}
    return {
      _closed = false,
      _minimized = false,
      _groupHidden = false,
      x = opts.x or 0,
      y = opts.y or 0,
      w = opts.w or 100,
      h = opts.h or 80,
      isInContentArea = function(self, px, py)
        return px >= self.x and px <= (self.x + self.w) and py >= self.y and py <= (self.y + self.h)
      end,
    }
  end

  it("uses a 7x7 hit box matching the drawn outer chrome", function()
    -- cx=10,cy=20 → rect floor(10-3.5)=6, floor(20-3.5)=16, size 7 → [6,13) x [16,23)
    expect(WindowLinkVisibility.isPointInHandle(10, 20, 6, 16)).toBe(true)
    expect(WindowLinkVisibility.isPointInHandle(10, 20, 12, 22)).toBe(true)
    expect(WindowLinkVisibility.isPointInHandle(10, 20, 5, 16)).toBe(false)
    expect(WindowLinkVisibility.isPointInHandle(10, 20, 13, 16)).toBe(false)
    expect(WindowLinkVisibility.isPointInHandle(10, 20, 6, 15)).toBe(false)
    expect(WindowLinkVisibility.isPointInHandle(10, 20, 6, 23)).toBe(false)
  end)

  it("omits tooltip for unlinked pivot handles", function()
    local LinkVisual = require("controllers.window.window_link_visual_controller")
    local win = makeWindow({ x = 100, y = 20, w = 80, h = 60 })
    win.kind = "ppu_frame"
    win.getHeaderRect = function(self)
      return self.x, self.y, self.w, 16
    end
    win.getScreenRect = function(self)
      return self.x, self.y, self.w, self.h
    end
    win.layers = { { kind = "tile" } }
    local app = {
      windowLinksMode = "always",
      canvas = { getWidth = function() return 640 end, getHeight = function() return 360 end },
      wm = {
        getWindows = function()
          return { win }
        end,
        getFocus = function()
          return win
        end,
        findWindowById = function()
          return nil
        end,
      },
    }

    local state = LinkVisual.prepareLinkDrawState(app)
    expect(state).toBeTruthy()
    local entry = state.layouts[win] and state.layouts[win].ppu_palette
    expect(entry).toBeTruthy()
    expect(entry.pulseInner).toBe(false)

    local candidate = WindowLinkVisibility.getPivotHandleTooltipCandidateAt(app, entry.cx, entry.cy)
    expect(candidate).toBeNil()
  end)

  it("ignores handles occluded by a foreground window body", function()
    local back = makeWindow({ x = 0, y = 0 })
    local front = makeWindow({ x = 0, y = 0, w = 200 })
    local app = {
      windowLinksMode = "on_hover",
      wm = {
        getWindows = function()
          return { back, front }
        end,
      },
    }
    local layouts = {
      [back] = {
        ppu_palette = { cx = 10, cy = 20 },
      },
    }

    local win, slot = WindowLinkVisibility.getTopLinkHandleAt(app, 10, 20, layouts)
    expect(win).toBeNil()
    expect(slot).toBeNil()
  end)

  it("returns a foreground handle even when it sits over a background window body", function()
    local back = makeWindow({ x = 0, y = 0, w = 500 })
    local front = makeWindow({ x = 100, y = 0 })
    local app = {
      windowLinksMode = "on_hover",
      wm = {
        getWindows = function()
          return { back, front }
        end,
      },
    }
    local layouts = {
      [front] = {
        ppu_palette = { cx = 93, cy = 20 },
      },
    }

    local win, slot = WindowLinkVisibility.getTopLinkHandleAt(app, 93, 20, layouts)
    expect(win).toBe(front)
    expect(slot).toBe("ppu_palette")
  end)

  it("returns the frontmost handle when not occluded", function()
    local back = makeWindow({ x = 0, y = 0 })
    local front = makeWindow({ x = 200, y = 0 })
    local app = {
      windowLinksMode = "on_hover",
      wm = {
        getWindows = function()
          return { back, front }
        end,
      },
    }
    local layouts = {
      [back] = {
        ppu_palette = { cx = 10, cy = 20 },
      },
      [front] = {
        layout_palette = { cx = 190, cy = 20 },
      },
    }

    local win, slot = WindowLinkVisibility.getTopLinkHandleAt(app, 10, 20, layouts)
    expect(win).toBe(back)
    expect(slot).toBe("ppu_palette")

    win, slot = WindowLinkVisibility.getTopLinkHandleAt(app, 190, 20, layouts)
    expect(win).toBe(front)
    expect(slot).toBe("layout_palette")
  end)

  it("does not treat handles under an open context menu as hovered", function()
    local originalGetScaledMouse = ResolutionController.getScaledMouse
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = 20 }
    end

    local win = makeWindow({ x = 0, y = 0 })
    local app = {
      windowLinksMode = "on_hover",
      emptySpaceContextMenu = {
        isVisible = function()
          return true
        end,
        contains = function(_, px, py)
          return px == 10 and py == 20
        end,
      },
      wm = {
        getWindows = function()
          return { win }
        end,
      },
    }
    local edge = {
      fromWin = win,
      fromSlot = "ppu_palette",
      toWin = win,
      toSlot = "palette_source",
    }
    local layouts = {
      [win] = {
        ppu_palette = { cx = 10, cy = 20 },
        palette_source = { cx = 40, cy = 20 },
      },
    }

    expect(WindowLinkVisibility.isHoveringEdgeHandles(app, edge, layouts)).toBe(false)

    app.emptySpaceContextMenu.contains = function()
      return false
    end
    expect(WindowLinkVisibility.isHoveringEdgeHandles(app, edge, layouts)).toBe(true)

    ResolutionController.getScaledMouse = originalGetScaledMouse
  end)

  it("does not treat handles under the taskbar main menu as hovered", function()
    local originalGetScaledMouse = ResolutionController.getScaledMouse
    ResolutionController.getScaledMouse = function()
      return { x = 10, y = 20 }
    end

    local win = makeWindow({ x = 0, y = 0 })
    local app = {
      windowLinksMode = "on_hover",
      taskbar = {
        menuController = {
          isVisible = function()
            return true
          end,
          contains = function(_, px, py)
            return px == 10 and py == 20
          end,
        },
      },
      wm = {
        getWindows = function()
          return { win }
        end,
      },
    }
    local edge = {
      fromWin = win,
      fromSlot = "pattern_source",
      toWin = win,
      toSlot = "ppu_pattern_bg",
    }
    local layouts = {
      [win] = {
        pattern_source = { cx = 10, cy = 20 },
        ppu_pattern_bg = { cx = 40, cy = 20 },
      },
    }

    expect(WindowLinkVisibility.isHoveringEdgeHandles(app, edge, layouts)).toBe(false)

    ResolutionController.getScaledMouse = originalGetScaledMouse
  end)
end)
