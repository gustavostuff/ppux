local Taskbar = require("user_interface.taskbar")
local WM = require("controllers.window.window_controller")
local images = require("images")

describe("taskbar.lua - minimized windows strip", function()
  local function countScrollButtons(toolbar)
    local n = 0
    for _, b in ipairs(toolbar.buttons or {}) do
      if b.isMinimizedScrollButton == true then
        n = n + 1
      end
    end
    return n
  end

  local function minimizedToolbarButtons(toolbar)
    local out = {}
    for _, b in ipairs(toolbar.buttons or {}) do
      if b.isMinimizedWindowButton == true then
        out[#out + 1] = b
      end
    end
    return out
  end

  local function buttonForWindow(toolbar, win)
    for _, b in ipairs(minimizedToolbarButtons(toolbar)) do
      if b.minimizedWindow == win then
        return b
      end
    end
    return nil
  end

  local function iconSource(icon)
    -- Taskbar may wrap icons in a katsudo animation object.
    if icon and icon.img then
      return icon.img
    end
    return icon
  end

  local function menuItemTexts(menu)
    local texts = {}
    for _, item in ipairs(menu.items or {}) do
      texts[#texts + 1] = item.text
    end
    return texts
  end

  local function mainMenuPanel(taskbar)
    return taskbar.menuController and taskbar.menuController.panel or nil
  end

  local function panelMenuTexts(panel)
    local texts = {}
    for row = 1, panel.rows or 0 do
      local rowCells = panel.cells[row] or {}
      for col = 1, panel.cols or 0 do
        local cell = rowCells[col]
        local text = cell and cell.button and cell.button.text or nil
        if text then
          texts[#texts + 1] = text
          break
        end
      end
    end
    return texts
  end

  it("shows minimized window button and restores window on click while preserving collapse", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar
    taskbar:updateLayout(320, 240)

    local win = {
      title = "Palette",
      kind = "palette",
      _closed = false,
      _collapsed = true,
      _minimized = false,
      dragging = false,
      resizing = false,
    }
    wm:add(win)
    wm:setFocus(win)

    -- Window taskbar button exists before minimizing.
    taskbar:updateLayout(320, 240)
    expect(#taskbar.minimizedWindows).toBe(1)
    expect(#taskbar.buttons).toBe(4) -- Menu + 2 scroll placeholders + taskbar button
    expect(countScrollButtons(taskbar)).toBe(2)

    local minimized = wm:minimizeWindow(win)
    expect(minimized).toBeTruthy()
    expect(win._minimized).toBeTruthy()
    expect(win._collapsed).toBeTruthy()

    taskbar:updateLayout(320, 240)

    expect(#taskbar.minimizedWindows).toBe(1)
    expect(#taskbar.buttons).toBe(4) -- Menu + 2 scroll placeholders + minimized button
    expect(countScrollButtons(taskbar)).toBe(2)

    local minis = minimizedToolbarButtons(taskbar)
    expect(#minis).toBe(1)
    local btn = minis[1]
    expect(btn).toBeTruthy()
    expect(btn.text).toBeNil()

    local clickX = btn.x + math.floor(btn.w / 2)
    local clickY = btn.y + math.floor(btn.h / 2)
    expect(taskbar:mousepressed(clickX, clickY, 1)).toBeTruthy()
    expect(taskbar:mousereleased(clickX, clickY, 1)).toBeTruthy()

    expect(win._minimized).toBeFalsy()
    expect(win._collapsed).toBeTruthy()
    expect(#taskbar.minimizedWindows).toBe(1)
    expect(#taskbar.buttons).toBe(4) -- Menu + 2 scroll placeholders + taskbar button
    expect(countScrollButtons(taskbar)).toBe(2)
    expect(wm:getFocus()).toBe(win)
  end)

  it("uses the ROM window icon for ROM-backed bank windows", function()
    images.windows_icons = images.windows_icons or {}
    local originalChrIcon = images.windows_icons.icon_chr_window
    local originalRomIcon = images.windows_icons.icon_rom_window
    local chrIcon = {
      getWidth = function() return 15 end,
      getHeight = function() return 15 end,
    }
    local romIcon = {
      getWidth = function() return 15 end,
      getHeight = function() return 15 end,
    }
    images.windows_icons.icon_chr_window = chrIcon
    images.windows_icons.icon_rom_window = romIcon

    local ok, err = pcall(function()
      local wm = WM.new()
      local app = {
        wm = wm,
        canvas = {
          getWidth = function() return 320 end,
          getHeight = function() return 240 end,
        },
      }
      local taskbar = Taskbar.new(app, { h = 15 })
      wm.taskbar = taskbar
      taskbar:updateLayout(320, 240)

      local chrWin = {
        title = "CHR Banks",
        kind = "chr",
        _closed = false,
        _minimized = false,
      }
      local romWin = {
        title = "ROM Banks",
        kind = "chr",
        isRomWindow = true,
        _closed = false,
        _minimized = false,
      }
      wm:add(chrWin)
      wm:add(romWin)

      taskbar:updateLayout(320, 240)

      local chrButton = buttonForWindow(taskbar, chrWin)
      local romButton = buttonForWindow(taskbar, romWin)
      expect(chrButton).toBeTruthy()
      expect(romButton).toBeTruthy()
      expect(iconSource(chrButton.icon)).toBe(chrIcon)
      expect(iconSource(romButton.icon)).toBe(romIcon)
    end)

    images.windows_icons.icon_chr_window = originalChrIcon
    images.windows_icons.icon_rom_window = originalRomIcon
    if not ok then
      error(err)
    end
  end)

  it("minimizes all windows and appends their buttons to the strip", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar
    taskbar:updateLayout(320, 240)

    local w1 = { title = "Alpha", _closed = false, _minimized = false, _collapsed = false }
    local w2 = { title = "Beta", _closed = false, _minimized = false, _collapsed = true }
    wm:add(w1)
    wm:add(w2)
    wm:setFocus(w2)

    taskbar:updateLayout(320, 240)
    expect(#taskbar.minimizedWindows).toBe(2)
    expect(#taskbar.buttons).toBe(5) -- Menu + 2 scroll placeholders + 2 taskbar buttons
    expect(countScrollButtons(taskbar)).toBe(2)

    expect(wm:minimizeAll()).toBeTruthy()
    taskbar:updateLayout(320, 240)

    expect(w1._minimized).toBeTruthy()
    expect(w2._minimized).toBeTruthy()
    expect(w2._collapsed).toBeTruthy()
    expect(#taskbar.minimizedWindows).toBe(2)
    expect(#taskbar.buttons).toBe(5) -- Menu + 2 scroll placeholders + 2 minimized buttons
    expect(countScrollButtons(taskbar)).toBe(2)
    local minis = minimizedToolbarButtons(taskbar)
    expect(#minis).toBe(2)
    expect(minis[1].text).toBeNil()
    expect(minis[2].text).toBeNil()
    expect(minis[1].minimizedWindow).toBe(w1)
    expect(minis[2].minimizedWindow).toBe(w2)
  end)

  it("maximizes all windows by restoring minimized state while preserving collapse", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar
    taskbar:updateLayout(320, 240)

    local wins = {
      { title = "Alpha", _closed = false, _minimized = false, _collapsed = true },
      { title = "Beta", _closed = false, _minimized = false, _collapsed = false },
      { title = "Gamma", _closed = false, _minimized = false, _collapsed = true },
      { title = "Delta", _closed = false, _minimized = false, _collapsed = false },
      { title = "Epsilon", _closed = false, _minimized = false, _collapsed = false },
    }
    for _, w in ipairs(wins) do
      wm:add(w)
    end
    wm:minimizeAll()
    taskbar:updateLayout(320, 240)
    expect(#taskbar.minimizedWindows).toBe(5)

    expect(wm:maximizeAll()).toBeTruthy()
    taskbar:updateLayout(320, 240)

    for _, w in ipairs(wins) do
      expect(w._minimized).toBeFalsy()
    end
    expect(wins[1]._collapsed).toBeTruthy()
    expect(wins[2]._collapsed).toBeFalsy()
    expect(wins[3]._collapsed).toBeTruthy()
    expect(#taskbar.minimizedWindows).toBe(5)
    expect(#taskbar.buttons).toBe(8) -- Menu + 2 scroll placeholders + 5 taskbar buttons
    expect(countScrollButtons(taskbar)).toBe(2)
  end)

  it("shows recent projects in a submenu and disambiguates duplicate stems", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      recentProjects = {
        "/tmp/project_a/foo",
        "/tmp/project_b/foo",
        "/tmp/project_c/bar",
      },
      hasLoadedROM = function()
        return true
      end,
      getRecentProjects = function(self)
        return self.recentProjects
      end,
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar
    taskbar:updateLayout(320, 240)

    local items = taskbar:_buildMainMenuItems()
    local recentItem = nil
    for _, item in ipairs(items) do
      if item.text == "Recent Projects" then
        recentItem = item
        break
      end
    end

    expect(recentItem).toBeTruthy()
    expect(recentItem.enabled).toBe(true)
    expect(items[1].text).toBe("Recent Projects")
    expect(items[2].text).toBe("Windows")
    expect(items[3].text).toBe("Quit")
    expect(items[4].text).toBe("Close Project")
    expect(items[5].text).toBe("Settings")
    expect(items[6].text).toBe("Save")

    local children = recentItem.children()
    expect(menuItemTexts({ items = children })).toEqual({
      "project_a/foo",
      "project_b/foo",
      "bar",
    })

    local windowsItem = items[2]
    expect(windowsItem.enabled).toBe(true)
    local windowsChildren = windowsItem.children()
    expect(menuItemTexts({ items = windowsChildren })).toEqual({
      "New Window",
      "Expand all",
      "Collapse all",
      "Sort by title",
      "Sort by kind",
      "Minimize all",
      "Maximize all",
    })
  end)

  it("dragging a minimized button over another reorders the minimized strip", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar
    taskbar:updateLayout(320, 240)

    local wins = {
      { title = "Beta", kind = "static_art", _closed = false, _minimized = false },
      { title = "Alpha", kind = "palette", _closed = false, _minimized = false },
      { title = "Gamma", kind = "animation", _closed = false, _minimized = false },
    }
    for _, w in ipairs(wins) do
      wm:add(w)
      wm:minimizeWindow(w)
    end
    taskbar:updateLayout(320, 240)

    local minis = minimizedToolbarButtons(taskbar)
    expect(minis[1].minimizedWindow).toBe(wins[1]) -- insertion order before drag
    expect(minis[2].minimizedWindow).toBe(wins[2])
    expect(minis[3].minimizedWindow).toBe(wins[3])

    local dragged = minis[1]
    local target = minis[3]
    local sx = dragged.x + math.floor(dragged.w / 2)
    local sy = dragged.y + math.floor(dragged.h / 2)
    local tx = target.x + math.floor(target.w / 2)
    local ty = target.y + math.floor(target.h / 2)

    expect(taskbar:mousepressed(sx, sy, 1)).toBeTruthy()
    taskbar:mousemoved(tx, ty)
    expect(taskbar:mousereleased(tx, ty, 1)).toBeTruthy()

    minis = minimizedToolbarButtons(taskbar)
    expect(minis[1].minimizedWindow).toBe(wins[2])
    expect(minis[2].minimizedWindow).toBe(wins[3])
    expect(minis[3].minimizedWindow).toBe(wins[1])
    -- Drag reorder should not restore the dragged window.
    expect(wins[1]._minimized).toBeTruthy()
  end)

  it("marks the focused window button as focused for full-opacity content", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar
    taskbar:updateLayout(320, 240)

    local w1 = { title = "Alpha", kind = "static_art", _closed = false, _minimized = false }
    local w2 = { title = "Beta", kind = "palette", _closed = false, _minimized = false }
    wm:add(w1)
    wm:add(w2)

    wm:setFocus(w2)
    taskbar:updateLayout(320, 240)

    local b1 = buttonForWindow(taskbar, w1)
    local b2 = buttonForWindow(taskbar, w2)
    expect(b1).toBeTruthy()
    expect(b2).toBeTruthy()
    expect(b1.alwaysOpaqueContent).toBe(false)
    expect(b2.alwaysOpaqueContent).toBe(false)
    expect(b1.normalContentAlpha).toBe(0.5)
    expect(b2.normalContentAlpha).toBe(0.5)
    expect(b1.underlayOnHoverOnly).toBe(true)
    expect(b2.underlayOnHoverOnly).toBe(true)
    expect(b1.bgColor).toBeNil()
    expect(b2.bgColor).toBeNil()
    expect(b1.focused).toBeFalsy()
    expect(b2.focused).toBeTruthy()

    wm:setFocus(w1)
    taskbar:updateLayout(320, 240)

    b1 = buttonForWindow(taskbar, w1)
    b2 = buttonForWindow(taskbar, w2)
    expect(b1.bgColor).toBeNil()
    expect(b2.bgColor).toBeNil()
    expect(b1.focused).toBeTruthy()
    expect(b2.focused).toBeFalsy()
  end)

  it("hides ROM-dependent menu actions when no ROM is loaded", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      appEditState = {},
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
      hasLoadedROM = function() return false end,
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar

    taskbar:updateLayout(320, 240)

    local panel = mainMenuPanel(taskbar)
    expect(panel).toBeTruthy()
    expect(panelMenuTexts(panel)).toEqual({
      "Quit",
      "Settings",
    })
  end)

  it("treats the bottom-right mode indicator as interactive", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      mode = "tile",
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar

    taskbar:updateLayout(320, 240)

    local hoverY = taskbar.y + math.floor(taskbar.h / 2)
    local hoverX = nil
    for x = taskbar.x + taskbar.w, taskbar.x, -1 do
      if taskbar:isInteractiveAt(x, hoverY) and not taskbar:getButtonAt(x, hoverY) then
        hoverX = x
        break
      end
    end

    expect(hoverX ~= nil).toBe(true)
    expect(taskbar:isInteractiveAt(hoverX, hoverY)).toBe(true)
  end)

  it("sorts minimized windows by the defined visual kind order", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar
    taskbar:updateLayout(320, 240)

    local wins = {
      {
        title = "Zulu Other",
        kind = "mystery",
        layers = {},
        _closed = false,
        _minimized = false,
      },
      {
        title = "Hotel ROM Palette",
        kind = "rom_palette",
        layers = {},
        _closed = false,
        _minimized = false,
      },
      {
        title = "Golf Palette",
        kind = "palette",
        layers = {},
        _closed = false,
        _minimized = false,
      },
      {
        title = "Foxtrot PPU",
        kind = "ppu_frame",
        layers = {},
        _closed = false,
        _minimized = false,
      },
      {
        title = "Echo Static Tile",
        kind = "static_art",
        layers = {
          { kind = "tile" },
        },
        getActiveLayerIndex = function() return 1 end,
        _closed = false,
        _minimized = false,
      },
      {
        title = "Delta Static Sprite",
        kind = "static_art",
        layers = {
          { kind = "sprite" },
        },
        getActiveLayerIndex = function() return 1 end,
        _closed = false,
        _minimized = false,
      },
      {
        title = "Charlie Animated Tile",
        kind = "animation",
        layers = {
          { kind = "tile" },
        },
        getActiveLayerIndex = function() return 1 end,
        _closed = false,
        _minimized = false,
      },
      {
        title = "Bravo Animated Sprite",
        kind = "animation",
        layers = {
          { kind = "sprite" },
        },
        getActiveLayerIndex = function() return 1 end,
        _closed = false,
        _minimized = false,
      },
      {
        title = "Alpha CHR",
        kind = "chr",
        layers = {},
        _closed = false,
        _minimized = false,
      },
    }

    for _, win in ipairs(wins) do
      wm:add(win)
      wm:minimizeWindow(win)
    end
    taskbar:updateLayout(320, 240)

    taskbar.sortKindButton.action()

    local minis = minimizedToolbarButtons(taskbar)
    local orderedTitles = {}
    for i, btn in ipairs(minis) do
      orderedTitles[i] = btn.minimizedWindow.title
    end

    expect(orderedTitles).toEqual({
      "Alpha CHR",
      "Bravo Animated Sprite",
      "Charlie Animated Tile",
      "Delta Static Sprite",
      "Echo Static Tile",
      "Foxtrot PPU",
      "Golf Palette",
      "Hotel ROM Palette",
      "Zulu Other",
    })
  end)

  it("keeps taskbar strip buttons fully opaque while menus use their own alpha", function()
    local wm = WM.new()
    local app = {
      wm = wm,
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
    }
    local taskbar = Taskbar.new(app, { h = 15 })
    wm.taskbar = taskbar
    taskbar:updateLayout(320, 240)

    for _, button in ipairs(taskbar.buttons) do
      if not button.isMinimizedWindowButton then
        expect(button.alwaysOpaqueContent).toBe(true)
      end
    end

    local panel = mainMenuPanel(taskbar)
    expect(panel).toBeTruthy()
    for row = 1, panel.rows do
      local cell = panel.cells[row][1]
      if cell and cell.button then
        expect(cell.button.alwaysOpaqueContent).toBeFalsy()
      end
    end
  end)
end)
