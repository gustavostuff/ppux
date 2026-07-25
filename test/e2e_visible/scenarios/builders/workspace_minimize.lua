-- Workspace minimize chrome: minimize-other-not-linked + taskbar minimize/restore.
local P = require("test.e2e_visible.scenarios.prelude")
local H = require("test.e2e_visible.scenarios.builders.link_helpers")
local BubbleExample, pause, call, appendClick, keyPress
  = P.BubbleExample, P.pause, P.call, P.appendClick, P.keyPress

local function closeDefaultWindows(currentApp)
  for _, win in ipairs(currentApp.wm:getWindows() or {}) do
    if win and not win._closed then
      win._closed = true
    end
  end
end

local function buildMinimizeOtherNotLinkedScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local steps = {
    pause("Start", 0.35),
    call("Create minimize-other-not-linked fixtures", function(_, currentApp, currentRunner)
      if currentApp and currentApp._applyWindowLinksSetting then
        currentApp:_applyWindowLinksSetting("always", false)
      end
      closeDefaultWindows(currentApp)

      currentRunner.keepPaletteWin = assert(currentApp.wm:createRomPaletteWindow({
        title = "Keep Palette",
        x = 36,
        y = 64,
      }), "expected keep palette")
      currentRunner.linkedTargetWin = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Linked Target",
        x = 220,
        y = 56,
        cols = 6,
        rows = 6,
        zoom = 2,
      }), "expected linked target")
      currentRunner.unlinkedAWin = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Unlinked A",
        x = 420,
        y = 56,
        cols = 6,
        rows = 6,
        zoom = 2,
      }), "expected unlinked A")
      currentRunner.unlinkedBWin = assert(currentApp.wm:createSpriteWindow({
        animated = false,
        title = "Unlinked B",
        x = 220,
        y = 230,
        cols = 6,
        rows = 6,
        zoom = 2,
      }), "expected unlinked B")

      currentApp.wm:setFocus(currentRunner.keepPaletteWin)
    end),
    pause("Observe minimize-other fixtures", 0.5),
  }

  H.appendRightDragPaletteLink(steps, "Link keep palette to linked target", "keepPaletteWin", "linkedTargetWin")
  steps[#steps + 1] = call("Assert linked target palette link", H.assertPaletteLinks({
    linkedTargetWin = "keepPaletteWin",
    unlinkedAWin = nil,
    unlinkedBWin = nil,
  }))

  H.appendFocusWindow(steps, "Focus linked target before minimize-other menu", "linkedTargetWin")
  H.appendOpenWindowHeaderMenu(steps, "Open linked target header menu", "linkedTargetWin")
  appendClick(steps, "Choose Minimize other (not linked)", H.windowHeaderMenuRowByText("Minimize other (not linked)"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.28,
  })
  steps[#steps + 1] = call("Assert minimize-other-not-linked keep set", H.assertWindowsMinimized({
    linkedTargetWin = false,
    keepPaletteWin = false,
    unlinkedAWin = true,
    unlinkedBWin = true,
  }))
  steps[#steps + 1] = call("Assert keep window focused after minimize-other", H.assertFocusedWindow("linkedTargetWin"))
  steps[#steps + 1] = call("Assert keep window frontmost after minimize-other", H.assertWindowFrontmost("linkedTargetWin"))

  steps[#steps + 1] = keyPress("Undo minimize other (not linked)", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe minimize-other undo", 0.24)
  steps[#steps + 1] = call("Assert undo restored unlinked windows", H.assertWindowsMinimized({
    linkedTargetWin = false,
    keepPaletteWin = false,
    unlinkedAWin = false,
    unlinkedBWin = false,
  }))

  steps[#steps + 1] = keyPress("Redo minimize other (not linked)", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe minimize-other redo", 0.24)
  steps[#steps + 1] = call("Assert redo re-minimized unlinked windows", H.assertWindowsMinimized({
    linkedTargetWin = false,
    keepPaletteWin = false,
    unlinkedAWin = true,
    unlinkedBWin = true,
  }))

  steps[#steps + 1] = pause("Scenario complete", 0.4)
  return steps
end

local function buildTaskbarMinimizeRestoreScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local steps = {
    pause("Start", 0.35),
    call("Create taskbar minimize/restore fixtures", function(_, currentApp, currentRunner)
      closeDefaultWindows(currentApp)

      currentRunner.restoreTargetWin = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Restore Target",
        x = 80,
        y = 70,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected restore target")
      currentRunner.coverWin = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Cover Window",
        x = 300,
        y = 70,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected cover window")

      currentApp.wm:setFocus(currentRunner.restoreTargetWin)
    end),
    pause("Observe taskbar minimize fixtures", 0.45),
  }

  H.appendClickHeaderMinimize(steps, "Click header minimize on restore target", "restoreTargetWin")
  steps[#steps + 1] = call("Assert restore target minimized via header button", H.assertWindowMinimized("restoreTargetWin", true))
  steps[#steps + 1] = call("Assert cover window remains open", H.assertWindowMinimized("coverWin", false))

  steps[#steps + 1] = call("Bring cover window front before taskbar restore", H.bringWindowToFrontByKey("coverWin"))
  H.appendClickTaskbarWindowButton(steps, "Click taskbar button to restore target", "restoreTargetWin")
  steps[#steps + 1] = call("Assert taskbar restore un-minimized target", H.assertWindowMinimized("restoreTargetWin", false))
  steps[#steps + 1] = call("Assert taskbar restore focused target", H.assertFocusedWindow("restoreTargetWin"))
  steps[#steps + 1] = call("Assert taskbar restore brought target frontmost", H.assertWindowFrontmost("restoreTargetWin"))

  steps[#steps + 1] = keyPress("Undo taskbar restore", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe restore undo", 0.22)
  steps[#steps + 1] = call("Assert undo re-minimized restore target", H.assertWindowMinimized("restoreTargetWin", true))
  steps[#steps + 1] = keyPress("Redo taskbar restore", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe restore redo", 0.22)
  steps[#steps + 1] = call("Assert redo un-minimized restore target", H.assertWindowMinimized("restoreTargetWin", false))
  steps[#steps + 1] = call("Assert redo focused restore target", H.assertFocusedWindow("restoreTargetWin"))

  steps[#steps + 1] = pause("Scenario complete", 0.4)
  return steps
end

return {
  minimize_other_not_linked = {
    title = "Minimize Other Not Linked",
    build = buildMinimizeOtherNotLinkedScenario,
  },
  taskbar_minimize_restore = {
    title = "Taskbar Minimize Restore",
    build = buildTaskbarMinimizeRestoreScenario,
  },
}
