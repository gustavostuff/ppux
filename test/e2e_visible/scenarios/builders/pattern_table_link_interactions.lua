-- Pattern-table link interactions via toolbar buttons (PPU bg/sprites, pattern table, OAM).
local P = require("test.e2e_visible.scenarios.prelude")
local H = require("test.e2e_visible.scenarios.builders.link_helpers")
local BubbleExample, pause, call, appendClick, keyPress, setFocusedTextFieldValue, setupDeterministicPpuFixture
  = P.BubbleExample, P.pause, P.call, P.appendClick, P.keyPress, P.setFocusedTextFieldValue, P.setupDeterministicPpuFixture

local function buildPatternTableLinkInteractionsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local steps = {
    pause("Start", 0.35),
    call("Create pattern-table link fixtures", function(_, currentApp, currentRunner)
      if currentApp and currentApp._applyWindowLinksSetting then
        currentApp:_applyWindowLinksSetting("always", false)
      end

      -- Default BubbleExample windows sit on top of our link targets; close them.
      for _, win in ipairs(currentApp.wm:getWindows() or {}) do
        if win and not win._closed then
          win._closed = true
        end
      end

      setupDeterministicPpuFixture(currentApp, currentRunner)
      local ppu = currentRunner.ppuFixtureWin
      ppu.x = 560
      ppu.y = 56
      ppu.title = "PPU Link Fixture"

      currentRunner.patternTableFixtureWin = assert(currentApp.wm:createPatternTableWindow({
        title = "Pattern Link Fixture",
        x = 560,
        y = 250,
        zoom = 2,
        patternTable = {
          ranges = {
            { bank = 1, from = 0, to = 63 },
          },
        },
      }), "expected pattern table fixture")

      local oam = assert(currentRunner.oamFixtureWin, "expected OAM fixture from PPU setup")
      -- Keep OAM pivots above the taskbar; taskbar mousepressed runs before pivot hit-testing.
      oam.x = 36
      oam.y = 200
      oam.title = "OAM Link Fixture"

      currentApp.wm:setFocus(currentRunner.ppuFixtureWin)
    end),
    pause("Observe pattern-table link fixtures", 0.6),
  }

  -- Ensure PPU has a sprite layer so "Link sprites pattern table" appears.
  H.appendClickToolbarButton(steps, "Add sprite layer via PPU toolbar", "ppuFixtureWin", function(toolbar)
    return toolbar.addSpriteButton
  end, { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Confirm sprite-layer mode modal if shown", function(currentHarness, currentApp)
    local modeModal = currentApp.ppuFrameSpriteLayerModeModal
    if modeModal and modeModal:isVisible() then
      currentHarness:keyPress("return", { wait = false })
      currentHarness:wait(0.14)
    end
  end)
  H.appendClickToolbarButton(steps, "Open add sprite modal", "ppuFixtureWin", function(toolbar)
    return toolbar.addSpriteButton
  end, { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Fill add sprite modal and confirm", function(currentHarness, currentApp)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected ppuFrameAddSpriteModal")
    assert(modal:isVisible(), "expected add sprite modal visible")
    setFocusedTextFieldValue(modal.bankField, "1")
    setFocusedTextFieldValue(modal.tileField, "6")
    setFocusedTextFieldValue(modal.oamStartField, "0x000020")
    currentHarness:keyPress("return", { wait = false })
    currentHarness:wait(0.18)
  end)
  steps[#steps + 1] = call("Record PPU background/sprite layer indexes", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    currentRunner.ppuBgLayerIndex = assert(H.findFirstLayerIndexByKind(ppu, "tile"), "expected PPU background tile layer")
    currentRunner.ppuSpriteLayerIndex = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected PPU sprite layer")
  end)

  -- Pattern table links from PPU toolbar button.
  H.appendClickToolbarButton(steps, "Open PPU pattern-table link menu", "ppuFixtureWin", function(toolbar)
    return toolbar.patternTableLinkButton
  end)
  steps[#steps + 1] = call("Assert PPU pattern-table destination menu", H.assertPaletteLinkMenuTexts({
    "Link background pattern table",
    "Link sprites pattern table",
  }))
  steps[#steps + 1] = call(
    "Open Link background pattern table child menu",
    H.openPaletteLinkChildMenuByText("Link background pattern table")
  )
  appendClick(steps, "Link PPU background to pattern fixture", H.paletteLinkChildMenuItemByText("Pattern Link Fixture"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.24,
  })
  steps[#steps + 1] = call("Assert PPU background pattern-table link", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local pt = H.requireRunnerWindow(currentRunner, "patternTableFixtureWin")
    local bgIdx = assert(H.findFirstLayerIndexByKind(ppu, "tile"), "expected PPU background tile layer")
    currentRunner.ppuBgLayerIndex = bgIdx
    assert(
      H.layerPatternTableWinId(ppu, bgIdx) == pt._id,
      "expected PPU background layer linked to pattern table fixture"
    )
  end)

  H.appendClickToolbarButton(steps, "Open PPU pattern-table link menu for sprites", "ppuFixtureWin", function(toolbar)
    return toolbar.patternTableLinkButton
  end)
  steps[#steps + 1] = call("Assert PPU menu still offers sprite linking", H.assertPaletteLinkMenuTexts({
    "Link background pattern table",
    "Link sprites pattern table",
    "Jump to background pattern table",
    "Unlink background pattern table",
  }))
  steps[#steps + 1] = call(
    "Open Link sprites pattern table child menu",
    H.openPaletteLinkChildMenuByText("Link sprites pattern table")
  )
  appendClick(steps, "Link PPU sprites to pattern fixture", H.paletteLinkChildMenuItemByText("Pattern Link Fixture"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.3,
  })
  steps[#steps + 1] = call("Assert PPU sprite pattern-table link", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local pt = H.requireRunnerWindow(currentRunner, "patternTableFixtureWin")
    local sprIdx = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected PPU sprite layer after link")
    currentRunner.ppuSpriteLayerIndex = sprIdx
    local layer = ppu.layers[sprIdx]
    assert(
      layer.linkedPatternTableWindowId == pt._id,
      string.format(
        "expected PPU sprite layer %d linked to pattern table fixture, got %s",
        sprIdx,
        tostring(layer.linkedPatternTableWindowId)
      )
    )
  end)

  H.appendClickToolbarButton(steps, "Open PPU pattern-table menu after links", "ppuFixtureWin", function(toolbar)
    return toolbar.patternTableLinkButton
  end)
  steps[#steps + 1] = call("Assert linked PPU pattern-table menu items", H.assertPaletteLinkMenuTexts({
    "Link background pattern table",
    "Link sprites pattern table",
    "Jump to background pattern table",
    "Jump to sprites pattern table",
    "Unlink background pattern table",
    "Unlink sprites pattern table",
  }))
  appendClick(steps, "Jump to background pattern table from PPU", H.paletteLinkMenuRowByText("Jump to background pattern table"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert jump focused pattern table fixture", H.assertFocusedWindow("patternTableFixtureWin"))

  -- Pattern table source toolbar button.
  H.appendClickToolbarButton(steps, "Open pattern-table source link menu", "patternTableFixtureWin", function(toolbar)
    return toolbar.linkButton
  end)
  steps[#steps + 1] = call("Assert pattern-table source menu items", H.assertPaletteLinkMenuTexts({
    "Jump to linked layer",
    "Remove all links",
  }))
  steps[#steps + 1] = call("Open Jump to linked layer from pattern table", H.openPaletteLinkChildMenuByText("Jump to linked layer"))
  appendClick(steps, "Jump to PPU from pattern-table source menu", H.paletteLinkChildMenuItemByText("PPU Link Fixture"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert pattern-table jump focused PPU", H.assertFocusedWindow("ppuFixtureWin"))

  -- On-canvas pivot handles: un-minimize + bring linked partner to front/focus.
  steps[#steps + 1] = call("Minimize pattern table before PPU pivot click", H.minimizeWindowByKey("patternTableFixtureWin"))
  steps[#steps + 1] = call("Cover stack with OAM before restoring via PPU pivot", H.bringWindowToFrontByKey("oamFixtureWin"))
  steps[#steps + 1] = call("Hide menus before PPU pattern pivot click", function(_, currentApp)
    if currentApp.hideAppContextMenus then
      currentApp:hideAppContextMenus()
    end
  end)
  H.appendClickPivotHandle(steps, "Click PPU bg pattern pivot to restore pattern table", "ppuFixtureWin", "ppu_pattern_bg")
  steps[#steps + 1] = call("Assert PPU pivot un-minimized pattern table", H.assertWindowMinimized("patternTableFixtureWin", false))
  steps[#steps + 1] = call("Assert PPU pivot focused pattern table", H.assertFocusedWindow("patternTableFixtureWin"))
  steps[#steps + 1] = call("Assert PPU pivot brought pattern table frontmost", H.assertWindowFrontmost("patternTableFixtureWin"))

  steps[#steps + 1] = keyPress("Undo PPU pattern pivot activate", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe pattern pivot activate undo", 0.22)
  steps[#steps + 1] = call("Assert undo re-minimized pattern table", H.assertWindowMinimized("patternTableFixtureWin", true))
  steps[#steps + 1] = keyPress("Redo PPU pattern pivot activate", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe pattern pivot activate redo", 0.22)
  steps[#steps + 1] = call("Assert redo un-minimized pattern table", H.assertWindowMinimized("patternTableFixtureWin", false))
  steps[#steps + 1] = call("Assert redo focused pattern table", H.assertFocusedWindow("patternTableFixtureWin"))
  steps[#steps + 1] = call("Assert redo brought pattern table frontmost", H.assertWindowFrontmost("patternTableFixtureWin"))

  steps[#steps + 1] = call("Minimize PPU before pattern-table pivot click", H.minimizeWindowByKey("ppuFixtureWin"))
  steps[#steps + 1] = call("Cover stack with OAM before restoring via pattern-table pivot", H.bringWindowToFrontByKey("oamFixtureWin"))
  steps[#steps + 1] = call("Hide menus before pattern-table pivot click", function(_, currentApp)
    if currentApp.hideAppContextMenus then
      currentApp:hideAppContextMenus()
    end
  end)
  H.appendClickPivotHandle(steps, "Click pattern-table pivot to restore PPU", "patternTableFixtureWin", "pattern_source")
  steps[#steps + 1] = call("Assert pattern-table pivot un-minimized PPU", H.assertWindowMinimized("ppuFixtureWin", false))
  steps[#steps + 1] = call("Assert pattern-table pivot focused PPU", H.assertFocusedWindow("ppuFixtureWin"))
  steps[#steps + 1] = call("Assert pattern-table pivot brought PPU frontmost", H.assertWindowFrontmost("ppuFixtureWin"))

  -- OAM pattern-table toolbar button.
  H.appendClickToolbarButton(steps, "Open OAM pattern-table link menu", "oamFixtureWin", function(toolbar)
    return toolbar.patternTableLinkButton
  end)
  steps[#steps + 1] = call("Assert OAM pattern-table destination menu", H.assertPaletteLinkMenuTexts({
    "Link pattern table",
  }))
  steps[#steps + 1] = call("Open OAM Link pattern table child menu", H.openPaletteLinkChildMenuByText("Link pattern table"))
  appendClick(steps, "Link OAM frames to pattern fixture", H.paletteLinkChildMenuItemByText("Pattern Link Fixture"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.24,
  })
  steps[#steps + 1] = call("Assert OAM sprite layers linked to pattern table", function(_, _, currentRunner)
    local oam = H.requireRunnerWindow(currentRunner, "oamFixtureWin")
    local pt = H.requireRunnerWindow(currentRunner, "patternTableFixtureWin")
    local linkedCount = 0
    for _, layer in ipairs(oam.layers or {}) do
      if layer and layer.kind == "sprite" then
        assert(
          layer.linkedPatternTableWindowId == pt._id,
          "expected every OAM sprite layer linked to pattern table fixture"
        )
        linkedCount = linkedCount + 1
      end
    end
    assert(linkedCount >= 1, "expected at least one OAM sprite layer")
  end)

  steps[#steps + 1] = call("Minimize pattern table before OAM pivot click", H.minimizeWindowByKey("patternTableFixtureWin"))
  steps[#steps + 1] = call("Bring OAM front before its pattern pivot click", H.bringWindowToFrontByKey("oamFixtureWin"))
  steps[#steps + 1] = call("Hide menus before OAM pattern pivot click", function(_, currentApp)
    if currentApp.hideAppContextMenus then
      currentApp:hideAppContextMenus()
    end
  end)
  H.appendClickPivotHandle(steps, "Click OAM pattern pivot to restore pattern table", "oamFixtureWin", "oam_pattern")
  steps[#steps + 1] = call("Assert OAM pivot un-minimized pattern table", H.assertWindowMinimized("patternTableFixtureWin", false))
  steps[#steps + 1] = call("Assert OAM pivot focused pattern table", H.assertFocusedWindow("patternTableFixtureWin"))
  steps[#steps + 1] = call("Assert OAM pivot brought pattern table frontmost", H.assertWindowFrontmost("patternTableFixtureWin"))

  H.appendClickToolbarButton(steps, "Open pattern-table source menu for remove-all", "patternTableFixtureWin", function(toolbar)
    return toolbar.linkButton
  end)
  appendClick(steps, "Remove all pattern-table links from source", H.paletteLinkMenuRowByText("Remove all links"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.24,
  })
  steps[#steps + 1] = call("Assert pattern-table remove-all cleared PPU and OAM links", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local oam = H.requireRunnerWindow(currentRunner, "oamFixtureWin")
    local bgIdx = assert(H.findFirstLayerIndexByKind(ppu, "tile"), "expected PPU background tile layer")
    local sprIdx = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected PPU sprite layer")
    assert(H.layerPatternTableWinId(ppu, bgIdx) == nil, "expected PPU background unlinked")
    assert(H.layerPatternTableWinId(ppu, sprIdx) == nil, "expected PPU sprites unlinked")
    for _, layer in ipairs(oam.layers or {}) do
      if layer and layer.kind == "sprite" then
        assert(layer.linkedPatternTableWindowId == nil, "expected OAM sprite layer unlinked")
      end
    end
  end)

  steps[#steps + 1] = pause("Scenario complete", 0.5)
  return steps
end

return {
  pattern_table_link_interactions = {
    title = "Pattern Table Link Interactions",
    build = buildPatternTableLinkInteractionsScenario,
  },
}
