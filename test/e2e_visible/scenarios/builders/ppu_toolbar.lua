-- Scenario builder chunk (split from definitions.lua).
local P = require("test.e2e_visible.scenarios.prelude")
local BubbleExample, PaletteLinkController, ContextualMenuController, images,
  normalizeSpeedMultiplier, pause, moveTo, mouseDown, mouseUp, keyPress, textInput, call, assertDelay, appendClick, appendDrag,
  newWindowOptionCenter, newWindowOptionCenterByText, newWindowModeToggleCenter,
  textFieldDemoFieldCenter, textFieldDemoFieldTextPoint, spriteItemCenter, toolbarLinkHandleCenter,
  windowHeaderCenter, saveOptionCenter, menuRowCenter, taskbarRootMenu, childMenuRowCenter,
  rootMenuItemCenter, resizeHandleCenter, taskbarMenuGapPoint, assertTaskbarChildState,
  buttonCenter, appQuickButtonCenter, ppuToolbarButtonCenter, menuRowCenterByText, setFocusedTextFieldValue,
  setupDeterministicPpuFixture, harnessHoldShiftForGridResize, assertStatusContainsOccupiedLayout
  = P.BubbleExample, P.PaletteLinkController, P.ContextualMenuController, P.images,
  P.normalizeSpeedMultiplier, P.pause, P.moveTo, P.mouseDown, P.mouseUp, P.keyPress, P.textInput, P.call, P.assertDelay, P.appendClick, P.appendDrag,
  P.newWindowOptionCenter, P.newWindowOptionCenterByText, P.newWindowModeToggleCenter,
  P.textFieldDemoFieldCenter, P.textFieldDemoFieldTextPoint, P.spriteItemCenter, P.toolbarLinkHandleCenter,
  P.windowHeaderCenter, P.saveOptionCenter, P.menuRowCenter, P.taskbarRootMenu, P.childMenuRowCenter,
  P.rootMenuItemCenter, P.resizeHandleCenter, P.taskbarMenuGapPoint, P.assertTaskbarChildState,
  P.buttonCenter, P.appQuickButtonCenter, P.ppuToolbarButtonCenter, P.menuRowCenterByText, P.setFocusedTextFieldValue,
  P.setupDeterministicPpuFixture, P.harnessHoldShiftForGridResize, P.assertStatusContainsOccupiedLayout


local function buildPpuToolbarRangesSetupScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local steps = {
    pause("Start", 0.35),
    call("Create deterministic PPU fixture", function(_, currentApp, currentRunner)
      setupDeterministicPpuFixture(currentApp, currentRunner)
    end),
    pause("Observe PPU fixture", 0.45),
    call("Focus PPU fixture window", function(_, currentApp, currentRunner)
      currentApp.wm:setFocus(currentRunner.ppuFixtureWin)
      if currentRunner.ppuFixtureWin.setActiveLayerIndex then
        currentRunner.ppuFixtureWin:setActiveLayerIndex(1)
      end
    end),
  }

  appendClick(steps, "Open PPU nametable range modal", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.rangeButton
  end), { moveDuration = 0.1, postPause = 0.2 })

  steps[#steps + 1] = call("Fill range modal and confirm", function(currentHarness, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected ppuFrameRangeModal")
    assert(modal:isVisible(), "expected PPU range modal visible")
    setFocusedTextFieldValue(modal.startField, string.format("0x%06X", currentRunner.ppuFixtureRangeStart))
    setFocusedTextFieldValue(modal.endField, string.format("0x%06X", currentRunner.ppuFixtureRangeEnd))
    currentHarness:keyPress("return", { wait = false })
    currentHarness:wait(0.16)
  end)

  steps[#steps + 1] = call("Assert nametable range applied and hydrated", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture window")
    local layer = assert(ppu.layers and ppu.layers[1], "expected PPU tile layer")
    assert(layer.nametableStartAddr == currentRunner.ppuFixtureRangeStart, "expected PPU nametable start address to match fixture")
    assert(layer.nametableEndAddr == currentRunner.ppuFixtureRangeEnd, "expected PPU nametable end address to match fixture")
    local tile = ppu:get(4, 4, 1)
    assert(tile ~= nil, "expected hydrated tile after range setup")
  end)
  steps[#steps + 1] = pause("Observe hydrated range setup", 0.7)
  return steps
end

local function buildPpuToolbarPatternRangesScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local steps = {
    pause("Start", 0.35),
    call("Create deterministic PPU fixture", function(_, currentApp, currentRunner)
      setupDeterministicPpuFixture(currentApp, currentRunner)
      local ppu = currentRunner.ppuFixtureWin
      local layer = ppu.layers and ppu.layers[1]
      layer.patternTable = { ranges = {} }
      currentApp.wm:setFocus(ppu)
    end),
    pause("Observe clean pattern-range fixture", 0.45),
  }

  appendClick(steps, "Open Add tile range modal", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.addTileRangeButton
  end), { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Add first pattern range", function(currentHarness, currentApp)
    local modal = assert(currentApp.ppuFramePatternRangeModal, "expected ppuFramePatternRangeModal")
    assert(modal:isVisible(), "expected pattern range modal visible")
    setFocusedTextFieldValue(modal.bankField, "1")
    setFocusedTextFieldValue(modal.fromField, "0")
    setFocusedTextFieldValue(modal.toField, "31")
    modal.pageSpinner:setValue(1)
    currentHarness:keyPress("return", { wait = false })
    currentHarness:wait(0.16)
  end)
  steps[#steps + 1] = call("Assert add-range auto enables pattern mode", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    local layer = assert(ppu.layers and ppu.layers[1], "expected tile layer")
    local ranges = layer.patternTable and layer.patternTable.ranges or {}
    assert(#ranges == 1, "expected one pattern range after first add")
    assert(ppu.patternLayerSoloMode == true, "expected pattern layer solo mode after add range")
  end)

  appendClick(steps, "Open Add tile range modal again", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.addTileRangeButton
  end), { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Add second pattern range", function(currentHarness, currentApp)
    local modal = assert(currentApp.ppuFramePatternRangeModal, "expected ppuFramePatternRangeModal")
    assert(modal:isVisible(), "expected pattern range modal visible for second add")
    setFocusedTextFieldValue(modal.bankField, "1")
    setFocusedTextFieldValue(modal.fromField, "32")
    setFocusedTextFieldValue(modal.toField, "47")
    modal.pageSpinner:setValue(1)
    currentHarness:keyPress("return", { wait = false })
    currentHarness:wait(0.16)
  end)
  steps[#steps + 1] = call("Assert second range appended", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    local layer = assert(ppu.layers and ppu.layers[1], "expected tile layer")
    local ranges = layer.patternTable and layer.patternTable.ranges or {}
    assert(#ranges == 2, "expected two pattern ranges after second add")
  end)

  appendClick(steps, "Toggle pattern layer mode off", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.patternLayerToggleButton
  end), { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Assert normal mode restored", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    assert(ppu.patternLayerSoloMode ~= true, "expected pattern mode to be off")
  end)

  steps[#steps + 1] = keyPress("Navigate layer in normal mode", "up", { "lshift" })
  steps[#steps + 1] = call("Assert normal navigation excludes pattern layer", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    local active = (ppu.getActiveLayerIndex and ppu:getActiveLayerIndex()) or ppu.activeLayer
    if ppu.findPatternReferenceLayerIndex then
      local patternIndex = ppu:findPatternReferenceLayerIndex()
      assert(active ~= patternIndex, "expected normal mode navigation to skip pattern layer")
    end
  end)

  appendClick(steps, "Toggle pattern layer mode on", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.patternLayerToggleButton
  end), { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = keyPress("Try layer navigation in pattern mode", "up", { "lshift" })
  steps[#steps + 1] = call("Assert navigation locked to pattern layer", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    assert(ppu.patternLayerSoloMode == true, "expected pattern mode on")
    if ppu.findPatternReferenceLayerIndex then
      local patternIndex = ppu:findPatternReferenceLayerIndex()
      local active = (ppu.getActiveLayerIndex and ppu:getActiveLayerIndex()) or ppu.activeLayer
      assert(active == patternIndex, "expected active layer to remain pattern layer in solo mode")
    end
  end)

  steps[#steps + 1] = keyPress("Undo last add-range event (remove range)", "z", { "lctrl" })
  steps[#steps + 1] = call("Assert undo removed last range", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    local layer = assert(ppu.layers and ppu.layers[1], "expected tile layer")
    local ranges = layer.patternTable and layer.patternTable.ranges or {}
    assert(#ranges == 1, "expected undo to remove last added range")
  end)
  steps[#steps + 1] = pause("Observe pattern range workflow", 0.75)
  return steps
end

local function buildPpuToolbarSpriteAndModeControlsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local steps = {
    pause("Start", 0.35),
    call("Create deterministic PPU fixture", function(_, currentApp, currentRunner)
      setupDeterministicPpuFixture(currentApp, currentRunner)
      currentApp.wm:setFocus(currentRunner.ppuFixtureWin)
    end),
    pause("Observe sprite controls fixture", 0.45),
  }

  appendClick(steps, "Click Add sprite toolbar button", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.addSpriteButton
  end), { moveDuration = 0.1, postPause = 0.2 })

  steps[#steps + 1] = call("Handle sprite-layer mode modal when needed", function(currentHarness, currentApp)
    local modeModal = currentApp.ppuFrameSpriteLayerModeModal
    if modeModal and modeModal:isVisible() then
      currentHarness:keyPress("return", { wait = false })
      currentHarness:wait(0.14)
      return
    end
  end)

  appendClick(steps, "Open add sprite modal after layer creation", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.addSpriteButton
  end), { moveDuration = 0.1, postPause = 0.2 })

  steps[#steps + 1] = call("Fill add sprite modal and confirm", function(currentHarness, currentApp)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected ppuFrameAddSpriteModal")
    assert(modal:isVisible(), "expected add sprite modal visible after sprite layer exists")
    setFocusedTextFieldValue(modal.bankField, "1")
    setFocusedTextFieldValue(modal.tileField, "6")
    setFocusedTextFieldValue(modal.oamStartField, "0x000020")
    currentHarness:keyPress("return", { wait = false })
    currentHarness:wait(0.18)
  end)

  steps[#steps + 1] = call("Assert sprite layer created/selected with item", function(_, currentApp, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    local spriteLayers = ppu.getSpriteLayers and ppu:getSpriteLayers() or {}
    assert(#spriteLayers >= 1, "expected at least one sprite layer after add sprite")
    local info = spriteLayers[1]
    local layer = assert(info.layer, "expected sprite layer info")
    assert(#(layer.items or {}) >= 1, "expected at least one sprite after add")
    currentRunner.ppuSpriteLayerIndex = info.index
    currentApp.wm:setFocus(ppu)
  end)

  appendClick(steps, "Toggle origin guides on", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.toggleOriginGuidesButton
  end), { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Assert origin guides enabled", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    assert(ppu.showSpriteOriginGuides == true, "expected origin guides enabled")
  end)
  appendClick(steps, "Toggle origin guides off", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.toggleOriginGuidesButton
  end), { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Assert origin guides disabled", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    assert(ppu.showSpriteOriginGuides ~= true, "expected origin guides disabled")
  end)

  appendClick(steps, "Enable pattern layer mode", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.patternLayerToggleButton
  end), { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Assert pattern mode toggle action ran", function(currentHarness)
    assert(tostring(currentHarness:getStatusText() or "") ~= "", "expected status feedback after enabling pattern mode")
  end)
  appendClick(steps, "Disable pattern layer mode", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.patternLayerToggleButton
  end), { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Assert pattern mode disable action ran", function(currentHarness)
    assert(tostring(currentHarness:getStatusText() or "") ~= "", "expected status feedback after disabling pattern mode")
  end)

  appendClick(steps, "Previous layer toolbar button", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.buttons and toolbar.buttons[1]
  end), { moveDuration = 0.08, postPause = 0.15 })
  appendClick(steps, "Next layer toolbar button", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.buttons and toolbar.buttons[2]
  end), { moveDuration = 0.08, postPause = 0.2 })
  steps[#steps + 1] = pause("Observe sprite and mode controls workflow", 0.75)

  return steps
end


return {
  ppu_toolbar_ranges_setup = { title = "PPU Toolbar Ranges Setup", build = buildPpuToolbarRangesSetupScenario },
  ppu_toolbar_pattern_ranges = { title = "PPU Toolbar Pattern Ranges", build = buildPpuToolbarPatternRangesScenario },
  ppu_toolbar_sprite_and_mode_controls = {
    title = "PPU Toolbar Sprite + Mode Controls",
    build = buildPpuToolbarSpriteAndModeControlsScenario,
  },
}
