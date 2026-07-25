-- ROM palette link interactions via real toolbar handles (right-drag, menus, double-click).
local P = require("test.e2e_visible.scenarios.prelude")
local H = require("test.e2e_visible.scenarios.builders.link_helpers")
local BubbleExample, pause, call, appendClick = P.BubbleExample, P.pause, P.call, P.appendClick

local function buildRomPaletteLinkInteractionsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local steps = {
    pause("Start", 0.35),
    call("Create ROM palette link fixtures", function(_, currentApp, currentRunner)
      if currentApp and currentApp._applyWindowLinksSetting then
        currentApp:_applyWindowLinksSetting("always", false)
      end

      -- Default BubbleExample windows sit on top of our link targets; close them so
      -- right-drag drops hit the fixtures we create below.
      for _, win in ipairs(currentApp.wm:getWindows() or {}) do
        if win and not win._closed then
          win._closed = true
        end
      end

      currentRunner.romLinkPaletteAWin = assert(currentApp.wm:createRomPaletteWindow({
        title = "ROM Link Palette A",
        x = 36,
        y = 64,
      }), "expected ROM palette A")
      currentRunner.romLinkPaletteBWin = assert(currentApp.wm:createRomPaletteWindow({
        title = "ROM Link Palette B",
        x = 36,
        y = 210,
      }), "expected ROM palette B")

      currentRunner.linkTarget1 = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Link Target 1",
        x = 200,
        y = 56,
        cols = 6,
        rows = 6,
        zoom = 2,
      }), "expected link target 1")
      currentRunner.linkTarget2 = assert(currentApp.wm:createSpriteWindow({
        animated = false,
        title = "Link Target 2",
        x = 420,
        y = 56,
        cols = 6,
        rows = 6,
        zoom = 2,
      }), "expected link target 2")
      currentRunner.linkTarget3 = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Link Target 3",
        x = 200,
        y = 230,
        cols = 6,
        rows = 6,
        zoom = 2,
      }), "expected link target 3")

      currentApp.wm:setFocus(currentRunner.romLinkPaletteAWin)
    end),
    pause("Observe ROM palette link fixtures", 0.6),
  }

  -- Create via right-drag from palette handle onto targets.
  H.appendRightDragPaletteLink(steps, "Right-drag palette A handle onto target 1", "romLinkPaletteAWin", "linkTarget1")
  steps[#steps + 1] = call("Assert right-drag linked target 1 to palette A", H.assertPaletteLinks({
    linkTarget1 = "romLinkPaletteAWin",
  }))
  steps[#steps + 1] = call("Clear palette-handle double-click arming before next drag", function()
    -- Visible E2E runs at 8x by default; wall-clock gaps between right-drags can stay
    -- inside the 0.35s double-click window and accidentally unlink-all.
    H.resetDoubleClickState()
  end)
  H.appendRightDragPaletteLink(steps, "Right-drag palette A handle onto target 2", "romLinkPaletteAWin", "linkTarget2")
  steps[#steps + 1] = call("Assert right-drag linked target 2 to palette A", H.assertPaletteLinks({
    linkTarget1 = "romLinkPaletteAWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = nil,
  }))

  -- Reverse create: destination handle -> palette B.
  H.appendRightDragPaletteLink(steps, "Right-drag target 3 handle onto palette B", "linkTarget3", "romLinkPaletteBWin")
  steps[#steps + 1] = call("Assert reverse-drag linked target 3 to palette B", H.assertPaletteLinks({
    linkTarget1 = "romLinkPaletteAWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteBWin",
  }))

  -- On-canvas pivot handles: un-minimize + bring linked partner to front/focus.
  steps[#steps + 1] = call("Minimize link target 3 before palette pivot click", H.minimizeWindowByKey("linkTarget3"))
  steps[#steps + 1] = call("Cover stack with palette A before restoring via B pivot", H.bringWindowToFrontByKey("romLinkPaletteAWin"))
  steps[#steps + 1] = call("Hide menus before palette B pivot click", function(_, currentApp)
    if currentApp.hideAppContextMenus then
      currentApp:hideAppContextMenus()
    end
  end)
  H.appendClickPivotHandle(steps, "Click palette B pivot handle to restore target 3", "romLinkPaletteBWin", "palette_source")
  steps[#steps + 1] = call("Assert pivot click un-minimized target 3", H.assertWindowMinimized("linkTarget3", false))
  steps[#steps + 1] = call("Assert pivot click focused target 3", H.assertFocusedWindow("linkTarget3"))
  steps[#steps + 1] = call("Assert pivot click brought target 3 frontmost", H.assertWindowFrontmost("linkTarget3"))

  steps[#steps + 1] = call("Minimize palette B before destination pivot click", H.minimizeWindowByKey("romLinkPaletteBWin"))
  steps[#steps + 1] = call("Cover stack with palette A before restoring via target 3 pivot", H.bringWindowToFrontByKey("romLinkPaletteAWin"))
  steps[#steps + 1] = call("Hide menus before target 3 pivot click", function(_, currentApp)
    if currentApp.hideAppContextMenus then
      currentApp:hideAppContextMenus()
    end
  end)
  H.appendClickPivotHandle(steps, "Click target 3 pivot handle to restore palette B", "linkTarget3", "layout_palette")
  steps[#steps + 1] = call("Assert destination pivot un-minimized palette B", H.assertWindowMinimized("romLinkPaletteBWin", false))
  steps[#steps + 1] = call("Assert destination pivot focused palette B", H.assertFocusedWindow("romLinkPaletteBWin"))
  steps[#steps + 1] = call("Assert destination pivot brought palette B frontmost", H.assertWindowFrontmost("romLinkPaletteBWin"))

  -- Source menu: jump + remove-all.
  H.appendClickPaletteHandle(steps, "Open palette A source menu", "romLinkPaletteAWin")
  steps[#steps + 1] = call("Assert palette A source menu items", H.assertPaletteLinkMenuTexts({
    "Jump to linked layer",
    "Remove all links",
  }))
  steps[#steps + 1] = call("Open Jump to linked layer child menu", H.openPaletteLinkChildMenuByText("Jump to linked layer"))
  appendClick(steps, "Jump to link target 2 from palette A", H.paletteLinkChildMenuItemByText("Link Target 2 / layer 1"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert source jump focused target 2", H.assertFocusedWindow("linkTarget2", 1))

  H.appendClickPaletteHandle(steps, "Open linked destination menu on target 2", "linkTarget2")
  steps[#steps + 1] = call("Assert linked destination menu items", H.assertPaletteLinkMenuTexts({
    "Link To Palette",
    "Jump to linked palette",
    "Remove ROM palette link",
  }))
  appendClick(steps, "Jump to linked palette from target 2", H.paletteLinkMenuRowByText("Jump to linked palette"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert destination jump focused palette A", H.assertFocusedWindow("romLinkPaletteAWin"))

  -- Destination menu link (target already linked to A; reconnect to B via menu).
  H.appendClickPaletteHandle(steps, "Open destination menu on target 1 for reconnect", "linkTarget1")
  steps[#steps + 1] = call("Open Link To Palette child menu on target 1", H.openPaletteLinkChildMenuByText("Link To Palette"))
  appendClick(steps, "Choose palette B for target 1", H.paletteLinkChildMenuItemByText(function(currentRunner)
    return H.requireRunnerWindow(currentRunner, "romLinkPaletteBWin").title
  end), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert target 1 reconnected to palette B via menu", H.assertPaletteLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteBWin",
  }))

  H.appendClickPaletteHandle(steps, "Open destination menu on target 2 for unlink", "linkTarget2")
  appendClick(steps, "Remove ROM palette link on target 2", H.paletteLinkMenuRowByText("Remove ROM palette link"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert target 2 unlinked via destination menu", H.assertPaletteLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = nil,
    linkTarget3 = "romLinkPaletteBWin",
  }))

  -- Double-click palette B handle to remove all remaining B links.
  H.appendFocusWindow(steps, "Focus palette B before double-click unlink", "romLinkPaletteBWin")
  steps[#steps + 1] = call("Arm clean double-click state for palette B", function()
    H.resetDoubleClickState()
  end)
  appendClick(steps, "First click palette B handle (arm double-click)", H.paletteHandleCenterByKey("romLinkPaletteBWin"), {
    button = 1,
    moveDuration = 0.06,
    prePressPause = 0.04,
    holdDuration = 0.04,
    postPause = 0.08,
  })
  steps[#steps + 1] = call("Hide menu before second double-click", function(_, currentApp)
    if currentApp.hideAppContextMenus then
      currentApp:hideAppContextMenus()
    end
  end)
  appendClick(steps, "Second click palette B handle (unlink all)", H.paletteHandleCenterByKey("romLinkPaletteBWin"), {
    button = 1,
    moveDuration = 0.04,
    prePressPause = 0.02,
    holdDuration = 0.04,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert double-click removed palette B links", H.assertPaletteLinks({
    linkTarget1 = nil,
    linkTarget2 = nil,
    linkTarget3 = nil,
  }))

  steps[#steps + 1] = pause("Scenario complete", 0.5)
  return steps
end

return {
  rom_palette_link_interactions = {
    title = "ROM Palette Link Interactions",
    build = buildRomPaletteLinkInteractionsScenario,
  },
}
