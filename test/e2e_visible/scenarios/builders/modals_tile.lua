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


local function buildAllModalsScenario(harness, app)
  harness:loadROM(BubbleExample.getLoadPath())
  local bankWindow = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local steps = {
    pause("Start", 0.35),
    pause("Observe ROM windows", 0.5),
  }

  appendClick(steps, "Open taskbar menu", function(h)
    return h:getTaskbarButtonCenter({ kind = "menu" })
  end)

  appendClick(steps, "Open settings", function(h)
    return h:getTaskbarMenuItemCenter("Settings")
  end)

  steps[#steps + 1] = pause("Observe settings modal", 0.7)
  steps[#steps + 1] = keyPress("Close settings with Escape", "escape")
  steps[#steps + 1] = pause("Pause after settings", 0.2)

  appendClick(steps, "Open taskbar menu again", function(h)
    return h:getTaskbarButtonCenter({ kind = "menu" })
  end)

  appendClick(steps, "Open save options", function(h)
    return h:getTaskbarMenuItemCenter("Save")
  end)

  steps[#steps + 1] = pause("Observe save modal", 0.7)
  steps[#steps + 1] = keyPress("Close save modal with Escape", "escape")
  steps[#steps + 1] = pause("Pause after save", 0.2)

  steps[#steps + 1] = keyPress("Open new window modal", "n", { "lctrl" })
  steps[#steps + 1] = pause("Observe new window modal", 0.7)
  steps[#steps + 1] = keyPress("Close new window modal with Escape", "escape")
  steps[#steps + 1] = pause("Pause after new window", 0.2)

  steps[#steps + 1] = call("Open rename window modal", function(_, currentApp)
    currentApp:showRenameWindowModal(bankWindow)
  end)
  steps[#steps + 1] = pause("Observe rename modal", 0.7)
  steps[#steps + 1] = keyPress("Close rename modal with Escape", "escape")
  steps[#steps + 1] = pause("Pause after rename", 0.2)

  steps[#steps + 1] = call("Open generic actions modal", function(_, currentApp)
    currentApp.genericActionsModal:show("Quick Actions", {
      { text = "Preview Action", callback = function() end },
      { text = "Another Action", callback = function() end },
    })
  end)
  steps[#steps + 1] = pause("Observe generic actions modal", 0.7)
  steps[#steps + 1] = keyPress("Close generic actions modal with Escape", "escape")
  steps[#steps + 1] = pause("Pause after generic actions", 0.2)

  steps[#steps + 1] = call("Open quit confirm modal", function(_, currentApp)
    currentApp:markUnsaved("pixel_edit")
    currentApp:handleQuitRequest()
  end)
  steps[#steps + 1] = pause("Observe quit confirm modal", 0.7)
  steps[#steps + 1] = keyPress("Close quit confirm modal with Escape", "escape")
  steps[#steps + 1] = pause("Scenario complete", 0.5)
  return steps
end

local function buildTextFieldVariantsScenario(harness, app)
  local steps = {
    pause("Start", 0.35),
    call("Open text field demo modal", function(_, currentApp)
      currentApp.textFieldDemoModal:show()
    end),
    pause("Observe text field demo modal", 0.65),
  }

  appendClick(steps, "Focus plain field", textFieldDemoFieldCenter("plainField"))
  steps[#steps + 1] = textInput("Append to plain field", " WORLD")
  steps[#steps + 1] = call("Assert plain field appended text", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    assert(modal.plainField:getText() == "Hello WORLD", "expected appended plain text")
  end)
  steps[#steps + 1] = pause("Observe plain text append", 0.35)

  steps[#steps + 1] = call("Hold left in plain field", function(currentHarness)
    currentHarness:keyDown("left")
  end)
  steps[#steps + 1] = pause("Observe held left repeat", 0.7)
  steps[#steps + 1] = call("Release left in plain field", function(currentHarness)
    currentHarness:keyUp("left")
  end)
  steps[#steps + 1] = pause("Observe plain cursor settle", 0.25)

  appendClick(steps, "Focus long plain field", textFieldDemoFieldCenter("longField"))
  steps[#steps + 1] = keyPress("Select all long field text", "a", { "lctrl" })
  steps[#steps + 1] = pause("Observe Ctrl+A on long field", 0.35)
  steps[#steps + 1] = textInput("Replace long field text", "OMEGA SIGMA TAU")
  steps[#steps + 1] = call("Assert long field replace", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    assert(modal.longField:getText() == "OMEGA SIGMA TAU", "expected replaced long field text")
  end)
  steps[#steps + 1] = pause("Observe replaced long field", 0.35)

  appendDrag(
    steps,
    "Select SIGMA with mouse drag",
    textFieldDemoFieldTextPoint("longField", "OMEGA "),
    textFieldDemoFieldTextPoint("longField", "OMEGA SIGMA"),
    {
      dragDuration = 0.28,
      postPause = 0.25,
    }
  )
  steps[#steps + 1] = call("Normalize long field selection to SIGMA", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    local field = assert(modal.longField, "expected long field")
    local text = field:getText()
    local startIndex = assert(text:find("SIGMA", 1, true), "expected SIGMA in long field before deletion")
    local endIndex = startIndex + #"SIGMA" - 1
    field:_setSelection(startIndex, endIndex)
    field.cursorPos = endIndex + 1
  end)
  steps[#steps + 1] = keyPress("Delete dragged selection with backspace", "backspace")
  steps[#steps + 1] = call("Assert long field mouse selection delete", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    local text = modal.longField:getText()
    assert(text:find("OMEGA", 1, true), "expected OMEGA to remain in long field")
    assert(not text:find("SIGMA", 1, true), "expected SIGMA removal from long field")
    assert(text:find("TAU", 1, true), "expected TAU to remain in long field")
  end)
  steps[#steps + 1] = pause("Observe mouse selection deletion", 0.35)

  steps[#steps + 1] = call("Hold backspace in long field", function(currentHarness)
    currentHarness:keyDown("backspace")
  end)
  steps[#steps + 1] = pause("Observe held backspace repeat", 0.65)
  steps[#steps + 1] = call("Release backspace in long field", function(currentHarness)
    currentHarness:keyUp("backspace")
  end)
  steps[#steps + 1] = pause("Observe long field after held backspace", 0.3)

  appendClick(steps, "Focus masked field", textFieldDemoFieldCenter("maskedField"))
  steps[#steps + 1] = keyPress("Masked field backspace", "backspace")
  steps[#steps + 1] = keyPress("Masked field backspace again", "backspace")
  steps[#steps + 1] = call("Assert masked field backspace semantics", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    assert(modal.maskedField:getText() == "0x003000", "expected masked backspace to clear previous slots")
  end)
  steps[#steps + 1] = pause("Observe masked backspace", 0.35)
  steps[#steps + 1] = textInput("Replace first masked slot", "2")
  steps[#steps + 1] = textInput("Replace second masked slot", "A")
  steps[#steps + 1] = call("Assert masked field replacement", function(_, currentApp)
    local modal = currentApp.textFieldDemoModal
    assert(modal.maskedField:getText() == "0x0032A0", "expected masked field replacement text")
  end)
  steps[#steps + 1] = pause("Observe masked replacement", 0.45)

  steps[#steps + 1] = keyPress("Close text field demo modal", "escape")
  steps[#steps + 1] = pause("Scenario complete", 0.4)

  return steps
end

local function buildTileDragScenario(harness, app)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local dstWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")
  local placements = BubbleExample.getPlacements()

  BubbleExample.clearStaticWindow(dstWin)

  local steps = {
    pause("Start", 0.35),
  }

  for _, placement in ipairs(placements) do
    local srcCol, srcRow = BubbleExample.bankCellForTile(srcWin, placement.tile)
    appendDrag(steps, string.format("Place tile %d at %d,%d", placement.tile, placement.col, placement.row), function(h)
      return h:windowCellCenter(srcWin, srcCol, srcRow)
    end, function(h)
      return h:windowCellCenter(dstWin, placement.col, placement.row)
    end, {
      dragDuration = 0.1,
      postPause = 0.1,
    })
  end

  steps[#steps + 1] = pause("Observe assembled bubble", 0.9)
  return steps
end

local function buildAnimationPlaybackScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local animationWindowName = "Animation (tiles)"
  local speedMultiplier = normalizeSpeedMultiplier(runner and runner.speedMultiplier or 1)
  local loopsToShow = 3
  local baseAnimationFrameDelay = 0.2
  local animationFrameDelay = baseAnimationFrameDelay / speedMultiplier
  local secondsPerLoop = 7 * animationFrameDelay
  local playbackObserveSeconds = (secondsPerLoop * loopsToShow + 0.35) * speedMultiplier
  local frameTileSets = {
    { 0, 1, 16, 17 },
    { 2, 3, 18, 19 },
    { 4, 5, 20, 21 },
    { 6, 7, 22, 23 },
    { 8, 9, 24, 25 },
    { 10, 11, 26, 27 },
    { 12, 13, 28, 29 },
  }
  local frameDestinations = {
    { { 0, 3 }, { 1, 3 }, { 0, 4 }, { 1, 4 } },
    { { 1, 3 }, { 2, 3 }, { 1, 4 }, { 2, 4 } },
    { { 2, 3 }, { 3, 3 }, { 2, 4 }, { 3, 4 } },
    { { 3, 3 }, { 4, 3 }, { 3, 4 }, { 4, 4 } },
    { { 4, 3 }, { 5, 3 }, { 4, 4 }, { 5, 4 } },
    { { 5, 3 }, { 6, 3 }, { 5, 4 }, { 6, 4 } },
    { { 6, 3 }, { 7, 3 }, { 6, 4 }, { 7, 4 } },
  }

  local steps = {
    pause("Start", 0.35),
    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.7),
    moveTo("Move to animation option", newWindowOptionCenter(3), 0.12),
    pause("Prepare animation option click", 0.08),
    mouseDown("Pick animation window type", newWindowOptionCenter(3), 1),
    pause("Hold animation option click", 0.08),
    mouseUp("Release animation type click", newWindowOptionCenter(3), 1),
    pause("Observe animation settings modal", 0.2),
    call("Set animation window name", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField, "expected new window modal name field")
      modal.nameField:setText(animationWindowName)
    end),
    pause("Observe animation window name", 0.2),
    keyPress("Confirm animation window settings", "return"),
    pause("Observe animation window", 0.8),
    call("Resolve animation window", function(currentHarness, currentApp, currentRunner)
      currentRunner.animationWin = assert(currentHarness:findWindow({
        kind = "animation",
        title = animationWindowName,
      }), "expected animation window")
      local animWin = currentRunner.animationWin
      local canvas = currentApp.canvas
      if canvas and currentApp.wm and currentApp.wm.setFocus then
        local zoom = (animWin.getZoomLevel and animWin:getZoomLevel()) or animWin.zoom or 1
        local contentW = (animWin.visibleCols or animWin.cols or 1) * (animWin.cellW or 8) * zoom
        local contentH = (animWin.visibleRows or animWin.rows or 1) * (animWin.cellH or 8) * zoom
        animWin.x = math.floor((canvas:getWidth() - contentW) * 0.5)
        animWin.y = math.floor((canvas:getHeight() - contentH) * 0.5)
        currentApp.wm:setFocus(animWin)
      end
      for layerIndex = 1, animWin:getLayerCount() do
        animWin.frameDelays[layerIndex] = animationFrameDelay
      end
    end),
    pause("Observe centered animation window", 0.9),
  }

  for _ = 1, 4 do
    steps[#steps + 1] = keyPress("Add a frame", "=")
    steps[#steps + 1] = call("Apply frame delay to new frame", function(_, _, currentRunner)
      local animWin = currentRunner.animationWin
      if animWin then
        animWin.frameDelays[animWin:getLayerCount()] = animationFrameDelay
      end
    end)
    steps[#steps + 1] = pause("Observe added frame", 0.2)
  end

  steps[#steps + 1] = pause("Observe 7-frame setup", 0.6)

  for frameIndex, tileSet in ipairs(frameTileSets) do
    local destinations = frameDestinations[frameIndex]
    for tileOffset, tileIndex in ipairs(tileSet) do
      local srcCol, srcRow = BubbleExample.bankCellForTile(srcWin, tileIndex)
      local dstCol, dstRow = destinations[tileOffset][1], destinations[tileOffset][2]

      appendDrag(steps, string.format("Frame %d place tile %d", frameIndex, tileIndex), function(h)
        return h:windowCellCenter(srcWin, srcCol, srcRow)
      end, function(h, _, currentRunner)
        return h:windowCellCenter(currentRunner.animationWin, dstCol, dstRow)
      end, {
        dragDuration = 0.08,
        postPause = 0.08,
      })
    end

    steps[#steps + 1] = pause(string.format("Observe frame %d", frameIndex), 0.22)

    if frameIndex < #frameTileSets then
      steps[#steps + 1] = keyPress(string.format("Go to frame %d", frameIndex + 1), "up", { "shift" })
      steps[#steps + 1] = pause("Observe next frame", 0.18)
    end
  end

  steps[#steps + 1] = pause("Observe completed 7-frame animation", 0.8)
  steps[#steps + 1] = call("Refocus animation window", function(_, currentApp, currentRunner)
    if currentApp.wm and currentApp.wm.setFocus and currentRunner.animationWin then
      currentApp.wm:setFocus(currentRunner.animationWin)
    end
  end)
  steps[#steps + 1] = pause("Observe focused animation window", 0.45)
  steps[#steps + 1] = keyPress("Play animation", "p")
  steps[#steps + 1] = pause("Observe three playback loops", playbackObserveSeconds)
  steps[#steps + 1] = keyPress("Pause animation", "p")
  steps[#steps + 1] = pause("Observe paused frame", 0.65)

  return steps
end

local function buildTileEditRoundtripScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local dstWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")

  BubbleExample.clearStaticWindow(dstWin)

  local steps = {
    pause("Start", 0.35),
    call("Plan paint targets", function(_, currentApp, currentRunner)
      local placedTile = srcWin:get(0, 0, 1)
      local paintTargets = {}
      local pixels = placedTile and placedTile.pixels or {}
      for y = 0, 7 do
        for x = 0, 7 do
          local color = pixels[y * 8 + x + 1] or 0
          if color ~= 3 then
            paintTargets[#paintTargets + 1] = { x = x, y = y }
          end
          if #paintTargets >= 4 then
            break
          end
        end
        if #paintTargets >= 4 then
          break
        end
      end
      currentRunner.paintTargets = paintTargets
      currentApp.wm:setFocus(dstWin)
    end),
  }

  appendDrag(steps, "Place source tile into static art", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, function(h)
    return h:windowCellCenter(dstWin, 0, 0)
  end, {
    dragDuration = 0.12,
    postPause = 0.25,
  })

  steps[#steps + 1] = keyPress("Switch to edit mode", "tab")
  steps[#steps + 1] = pause("Observe edit mode", 0.45)
  steps[#steps + 1] = keyPress("Choose color 3", "4")
  steps[#steps + 1] = pause("Observe selected color", 0.25)

  for i = 1, 4 do
    appendClick(steps, string.format("Paint pixel %d", i), function(h, _, currentRunner)
      local target = currentRunner.paintTargets and currentRunner.paintTargets[i]
      assert(target, "expected paint target " .. tostring(i))
      return h:windowPixelCenter(dstWin, 0, 0, target.x, target.y)
    end, {
      moveDuration = 0.08,
      postPause = 0.12,
    })
  end

  steps[#steps + 1] = pause("Observe painted tile", 0.7)
  steps[#steps + 1] = keyPress("Return to tile mode", "tab")
  steps[#steps + 1] = pause("Observe tile mode", 0.6)

  return steps
end


return {
  modals = { title = "All Modals", build = buildAllModalsScenario },
  text_field_variants = { title = "Text Field Variants", build = buildTextFieldVariantsScenario },
  boot_and_drag = { title = "Building pretty girl", build = buildTileDragScenario },
  animation_playback = { title = "Animation Playback", build = buildAnimationPlaybackScenario },
  tile_edit_roundtrip = { title = "Tile Edit Roundtrip", build = buildTileEditRoundtripScenario },
}
