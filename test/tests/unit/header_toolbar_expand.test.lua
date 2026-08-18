local HeaderToolbar = require("ui.toolbars.header_toolbar")
local ChrHeaderToolbar = require("ui.toolbars.chr_header_toolbar")
local Window = require("ui.windows_system.window")
local images = require("images")

describe("header collapse button - shift expand", function()
  local originalIsDown
  local shiftHeld

  local function makeWin()
    local win = Window.new(40, 80, 8, 8, 8, 6, 1, {
      title = "Grid",
      visibleCols = 2,
      visibleRows = 3,
    })
    win.scrollCol = 2
    win.scrollRow = 1
    win._collapsed = false
    return win
  end

  local function makeWm(win)
    return {
      setFocus = function() end,
      getFocus = function()
        return win
      end,
    }
  end

  beforeEach(function()
    shiftHeld = false
    originalIsDown = love.keyboard.isDown
    love.keyboard.isDown = function(key)
      if key == "lshift" or key == "rshift" then
        return shiftHeld == true
      end
      if originalIsDown then
        return originalIsDown(key)
      end
      return false
    end
  end)

  afterEach(function()
    love.keyboard.isDown = originalIsDown
  end)

  it("expandContent shows every cell and keeps x/y", function()
    local win = makeWin()
    win:expandContent()
    expect(win.x).toBe(40)
    expect(win.y).toBe(80)
    expect(win.visibleCols).toBe(8)
    expect(win.visibleRows).toBe(6)
    expect(win.scrollCol).toBe(0)
    expect(win.scrollRow).toBe(0)
  end)

  it("shows the expand icon while Shift is held", function()
    local win = makeWin()
    local tb = HeaderToolbar.new(win, {}, makeWm(win))
    tb:updateCollapseIcon()
    expect(tb.collapseButton.icon).toBe(images.icons.chrome.icon_up)
    expect(tb.collapseButton.tooltip).toBe("Collapse window")

    shiftHeld = true
    tb:updateCollapseIcon()
    expect(tb.collapseButton.icon).toBe(images.icons.chrome.icon_expand)
    expect(tb.collapseButton.tooltip).toBe("Expand window")
    expect(tb.collapseButton.enabled).toBe(true)
  end)

  it("does not switch to expand on palette windows", function()
    local win = makeWin()
    win.kind = "rom_palette"
    win.isPalette = true
    local tb = HeaderToolbar.new(win, {}, makeWm(win))
    shiftHeld = true
    tb:updateCollapseIcon()
    expect(tb.collapseButton.icon).toBe(images.icons.chrome.icon_up)
    expect(tb.collapseButton.tooltip).toBe("Collapse window")
    tb:_onCollapse()
    expect(win._collapsed).toBe(true)
    expect(win.visibleCols).toBe(2)
  end)

  it("disables expand when the window already shows all content", function()
    local win = makeWin()
    win.visibleCols = 8
    win.visibleRows = 6
    win.scrollCol = 0
    win.scrollRow = 0
    local tb = HeaderToolbar.new(win, {}, makeWm(win))
    shiftHeld = true
    tb:updateCollapseIcon()
    expect(tb.collapseButton.icon).toBe(images.icons.chrome.icon_expand)
    expect(tb.collapseButton.enabled).toBe(false)
    tb:_onCollapse()
    expect(win.visibleCols).toBe(8)
    expect(win._collapsed).toBe(false)
  end)

  it("Shift-click expands viewport in place and uncollapses", function()
    local win = makeWin()
    win._collapsed = true
    local tb = HeaderToolbar.new(win, {}, makeWm(win))
    shiftHeld = true
    tb:_onCollapse()

    expect(win._collapsed).toBe(false)
    expect(win.x).toBe(40)
    expect(win.y).toBe(80)
    expect(win.visibleCols).toBe(8)
    expect(win.visibleRows).toBe(6)
    expect(win.scrollCol).toBe(0)
  end)

  it("click without Shift still toggles collapse", function()
    local win = makeWin()
    local tb = ChrHeaderToolbar.new(win, {}, makeWm(win))
    tb:_onCollapse()
    expect(win._collapsed).toBe(true)
    expect(win.visibleCols).toBe(2)
    expect(win.x).toBe(40)
    expect(win.y).toBe(80)
  end)
end)
