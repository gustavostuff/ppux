local AppCoreController = require("controllers.app.core_controller")

describe("core_controller.lua - contextual menu helpers", function()
  it("shows the shared new window modal when a ROM is loaded", function()
    local shownTitle = nil
    local shownOptions = nil
    local app = setmetatable({
      hasLoadedROM = function() return true end,
      newWindowModal = {
        show = function(_, title, options)
          shownTitle = title
          shownOptions = options
        end,
      },
    }, AppCoreController)

    local ok = app:showNewWindowModal()

    expect(ok).toBe(true)
    expect(shownTitle).toBe("New Window")
    expect(type(shownOptions)).toBe("table")
    expect(#shownOptions).toBe(7)
    expect(shownOptions[1].text).toBe("Static Art window (tiles)")
    expect(shownOptions[4].text).toBe("Animation window  (sprites)")
    expect(shownOptions[5].text).toBe("Palette window")
    expect(shownOptions[6].text).toBe("ROM Palette window")
    expect(shownOptions[7].text).toBe("Pattern Table Builder")
  end)

  it("refuses to show the new window modal when no ROM is loaded", function()
    local status = nil
    local shown = 0
    local app = setmetatable({
      hasLoadedROM = function() return false end,
      setStatus = function(_, text)
        status = text
      end,
      newWindowModal = {
        show = function()
          shown = shown + 1
        end,
      },
    }, AppCoreController)

    local ok = app:showNewWindowModal()

    expect(ok).toBe(false)
    expect(status).toBe("Open a ROM before creating windows.")
    expect(shown).toBe(0)
  end)

  it("builds the window header context menu entries in the expected order", function()
    local app = setmetatable({}, AppCoreController)
    local items = app:_buildWindowHeaderContextMenuItems({
      _closed = false,
      _minimized = false,
    })

    expect(#items).toBe(3)
    expect(items[1].text).toBe("Close")
    expect(items[2].text).toBe("Collapse")
    expect(items[3].text).toBe("Minimize")
    expect(items[1].enabled).toBe(true)
    expect(items[2].enabled).toBe(true)
    expect(items[3].enabled).toBe(true)
  end)

  it("builds the empty-space context menu entries in the expected order", function()
    local app = setmetatable({
      hasLoadedROM = function() return true end,
      wm = {
        getWindows = function()
          return {
            { title = "A" },
          }
        end,
      },
    }, AppCoreController)

    local items = app:_buildEmptySpaceContextMenuItems()

    expect(#items).toBe(3)
    expect(items[1].text).toBe("New Window")
    expect(items[2].text).toBe("Minimize all")
    expect(items[3].text).toBe("Collapse all")
    expect(items[1].enabled).toBe(true)
    expect(items[2].enabled).toBe(true)
    expect(items[3].enabled).toBe(true)
  end)
end)
