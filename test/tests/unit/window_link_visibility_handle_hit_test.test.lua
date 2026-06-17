local WindowLinkVisibility = require("controllers.window.window_link_visibility")

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
end)
