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


local function buildSaveReloadPersistenceScenario(harness, app, runner)
  local tempSuffix = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local tempRomPath = "/tmp/ppux_e2e_visible_persist_" .. tempSuffix .. ".nes"
  local tempProjectPath = tempRomPath:gsub("%.nes$", ".lua")
  local tempEncodedPath = tempRomPath:gsub("%.nes$", ".ppux")
  local tempEditedPath = tempRomPath:gsub("%.nes$", "_edited.nes")
  local sourceRomPath = BubbleExample.getRomPath()
  local persistWindowName = "Persisted Draft"

  local function copyFile(srcPath, dstPath)
    local src = assert(io.open(srcPath, "rb"))
    local bytes = assert(src:read("*a"))
    src:close()
    local dst = assert(io.open(dstPath, "wb"))
    assert(dst:write(bytes))
    dst:close()
  end

  local function removeIfExists(path)
    if path and path ~= "" then
      os.remove(path)
    end
  end

  copyFile(sourceRomPath, tempRomPath)
  runner._cleanupPaths = { tempRomPath, tempProjectPath, tempEncodedPath, tempEditedPath }
  harness:loadROM(tempRomPath)
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )

  local steps = {
    pause("Start", 0.35),
    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.5),
    moveTo("Move to static tiles option", newWindowOptionCenter(1), 0.12),
    pause("Prepare static type click", 0.08),
    mouseDown("Pick static tiles window type", newWindowOptionCenter(1), 1),
    pause("Hold static type click", 0.08),
    mouseUp("Release static type click", newWindowOptionCenter(1), 1),
    pause("Observe persisted window settings", 0.2),
    call("Type persisted window name", function(currentHarness)
      local modal = currentHarness:getApp().newWindowModal
      assert(modal and modal.nameField, "expected new window modal name field")
      modal.nameField:setText(persistWindowName)
    end),
    pause("Observe persisted name", 0.25),
    keyPress("Confirm persisted window settings", "return"),
    pause("Resolve persisted window", 0.25),
    call("Store persisted window", function(currentHarness, _, currentRunner)
      currentRunner.persistedWin = assert(currentHarness:findWindow({
        kind = "static_art",
        title = persistWindowName,
      }), "expected persisted static art window")
    end),
  }

  appendDrag(steps, "Place tile into persisted window", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.persistedWin, 1, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.25,
  })

  steps[#steps + 1] = keyPress("Open save options", "s", { "lctrl" })
  steps[#steps + 1] = pause("Observe save options", 0.55)
  steps[#steps + 1] = moveTo("Move to save lua option", saveOptionCenter(2), 0.12)
  steps[#steps + 1] = pause("Observe save lua option", 0.18)
  steps[#steps + 1] = call("Save Lua project", function(_, currentApp)
    if currentApp.saveOptionsModal and currentApp.saveOptionsModal.hide then
      currentApp.saveOptionsModal:hide()
    end
    assert(currentApp:saveProject({ toast = false }), "expected lua project save to succeed")
    local projectFile = io.open(tempProjectPath, "rb")
    assert(projectFile, "expected saved lua project file")
    projectFile:close()
  end)
  steps[#steps + 1] = pause("Observe save complete", 0.75)
  steps[#steps + 1] = call("Reload ROM and project", function(_, currentApp, currentRunner)
    local RomProjectController = require("controllers.rom.rom_project_controller")
    assert(RomProjectController.loadROM(currentApp, tempRomPath), "expected ROM reload to succeed")
    currentRunner.reloadedWin = assert(currentRunner.harness:findWindow({
      kind = "static_art",
      title = persistWindowName,
    }), "expected reloaded persisted window")
  end)
  steps[#steps + 1] = pause("Observe reloaded persisted layout", 1.0)
  steps[#steps + 1] = call("Cleanup temp files", function(_, _, currentRunner)
    for _, path in ipairs(currentRunner._cleanupPaths or {}) do
      removeIfExists(path)
    end
  end)

  runner.harness = harness
  return steps
end

local function buildDefaultActionDelayScenario()
  local steps = {
    pause("Start", 0.35),
    moveTo("Move to mode indicator", function(h)
      return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
    end, 0.12),
    pause("Prepare first click", 0.08),
    {
      kind = "mouse_down",
      label = "First click down",
      pointResolver = function(h)
        return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
      end,
      button = 1,
    },
    pause("Hold first click", 0.06),
    {
      kind = "mouse_up",
      label = "First click up",
      pointResolver = function(h)
        return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
      end,
      button = 1,
      recordKey = "first_action_end",
    },
    pause("Default inter-action delay", 0.1),
    {
      kind = "mouse_down",
      label = "Second click down",
      pointResolver = function(h)
        return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
      end,
      button = 1,
      recordKey = "second_action_start",
    },
    pause("Hold second click", 0.06),
    {
      kind = "mouse_up",
      label = "Second click up",
      pointResolver = function(h)
        return h:getTaskbarButtonCenter({ kind = "mode_indicator" })
      end,
      button = 1,
    },
    assertDelay("Assert 0.1s delay", "first_action_end", "second_action_start", 0.1, 0.001),
    pause("Observe result", 0.6),
  }

  return steps
end

local function buildModalNavigationKeyboardOnlyScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local bankWindow = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local originalBankTitle = tostring(bankWindow.title or "")

  local function repeatKey(steps, labelPrefix, key, count, mods, pauseSeconds)
    for i = 1, count do
      steps[#steps + 1] = keyPress(string.format("%s %d", labelPrefix, i), key, mods)
      if pauseSeconds and pauseSeconds > 0 then
        steps[#steps + 1] = pause(labelPrefix, pauseSeconds)
      end
    end
  end

  local steps = {
    pause("Start", 0.35),

    call("Open settings modal", function(_, currentApp)
      currentApp:showSettingsModal()
    end),
    pause("Observe settings modal", 0.55),
    keyPress("Focus next settings option", "tab"),
    pause("Observe settings focus", 0.18),
    keyPress("Toggle focused settings option", "space"),
    pause("Observe settings toggle", 0.5),
    keyPress("Focus previous settings option", "left"),
    pause("Observe reversed settings focus", 0.18),
    keyPress("Toggle second settings option", "space"),
    pause("Observe second settings toggle", 0.5),
    keyPress("Close settings modal", "escape"),
    pause("Pause after settings", 0.25),

    keyPress("Open save options modal", "s", { "lctrl" }),
    pause("Observe save options modal", 0.55),
    keyPress("Close save options modal", "escape"),
    pause("Pause after save options", 0.25),

    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.55),
  }

  repeatKey(steps, "Backspace new window name", "backspace", #"New Window", nil, 0.02)
  steps[#steps + 1] = textInput("Type new window modal name", "KB Demo")
  steps[#steps + 1] = pause("Observe typed new window name", 0.45)
  steps[#steps + 1] = keyPress("Close new window modal", "escape")
  steps[#steps + 1] = pause("Pause after new window modal", 0.25)

  steps[#steps + 1] = call("Open rename window modal", function(_, currentApp)
    currentApp:showRenameWindowModal(bankWindow)
  end)
  steps[#steps + 1] = pause("Observe rename modal", 0.55)
  repeatKey(steps, "Backspace rename title", "backspace", #originalBankTitle, nil, 0.02)
  steps[#steps + 1] = textInput("Type renamed window title", "CHR KB")
  steps[#steps + 1] = pause("Observe typed rename title", 0.4)
  steps[#steps + 1] = keyPress("Confirm rename with Enter", "return")
  steps[#steps + 1] = pause("Observe renamed window title", 0.55)
  steps[#steps + 1] = call("Assert rename applied", function()
    assert(bankWindow.title == "CHR KB", string.format("expected renamed bank window title, got %s", tostring(bankWindow.title)))
  end)

  steps[#steps + 1] = call("Open generic actions modal", function(_, currentApp, currentRunner)
    currentRunner.genericActionChoice = nil
    currentApp.genericActionsModal:show("Quick Actions", {
      { text = "Preview Action", callback = function() currentRunner.genericActionChoice = 1 end },
      { text = "Another Action", callback = function() currentRunner.genericActionChoice = 2 end },
    })
  end)
  steps[#steps + 1] = pause("Observe generic actions modal", 0.55)
  steps[#steps + 1] = keyPress("Choose generic action 2", "2")
  steps[#steps + 1] = pause("Observe generic action close", 0.35)
  steps[#steps + 1] = call("Assert generic action choice", function(_, _, currentRunner)
    assert(currentRunner.genericActionChoice == 2, string.format("expected generic action 2, got %s", tostring(currentRunner.genericActionChoice)))
  end)

  steps[#steps + 1] = call("Open quit confirm modal", function(_, currentApp)
    currentApp:markUnsaved("pixel_edit")
    currentApp:handleQuitRequest()
  end)
  steps[#steps + 1] = pause("Observe quit confirm modal", 0.55)
  steps[#steps + 1] = keyPress("Move quit confirm focus to No", "right")
  steps[#steps + 1] = pause("Observe quit confirm focus change", 0.18)
  steps[#steps + 1] = keyPress("Confirm No with Enter", "return")
  steps[#steps + 1] = pause("Observe quit confirm close", 0.4)
  steps[#steps + 1] = call("Assert quit was cancelled", function(currentHarness, currentApp)
    assert(not currentApp.quitConfirmModal:isVisible(), "expected quit confirm modal to be hidden")
    assert(currentHarness.quitRequested ~= true, "expected quit to be cancelled")
  end)
  steps[#steps + 1] = pause("Scenario complete", 0.5)

  return steps
end



return {
  save_reload_persistence = { title = "Save Reload Persistence", build = buildSaveReloadPersistenceScenario },
  default_action_delay = { title = "Default Action Delay", build = buildDefaultActionDelayScenario },
  modal_navigation_keyboard_only = {
    title = "Modal Navigation Keyboard Only",
    build = buildModalNavigationKeyboardOnlyScenario,
  },
}
