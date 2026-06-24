-- Open Project modal happy path + invalid file selection.

local P = require("test.e2e_visible.scenarios.prelude")
local FixtureHelpers = require("test.e2e_visible.scenarios.fixture_helpers")
local BubbleExample, pause, call, appendClick, appQuickButtonCenter, openProjectFileSlotCenter
  = P.BubbleExample, P.pause, P.call, P.appendClick, P.appQuickButtonCenter, P.openProjectFileSlotCenter

local function assertLoadedTestRomProject(currentApp, currentHarness)
  assert(currentApp:hasLoadedROM(), "expected ROM to be loaded after opening project")
  assert(BubbleExample.findBankWindow(currentApp), "expected CHR bank window")
  assert(BubbleExample.findStaticWindow(currentApp), "expected static art window")
  assert(
    currentHarness:findWindow({ kind = "animation", title = "Animation (sprites)" }),
    "expected animation window from fixture project"
  )
  assert(currentHarness:findWindow({ kind = "palette" }), "expected palette window from fixture project")
end

local function buildOpenProjectHappyPathScenario(harness, app, runner)
  local steps = {
    pause("Start", 0.35),
    call("Prepare open-project fixture tree", function(_, _, currentRunner)
      FixtureHelpers.setupOpenProjectFixture(currentRunner)
    end),
  }

  appendClick(steps, "Open project from app toolbar", appQuickButtonCenter("open"), {
    moveDuration = 0.1,
    postPause = 0.35,
  })

  steps[#steps + 1] = call("Browse to fixture directory", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.openProjectModal, "expected openProjectModal")
    assert(modal:isVisible(), "expected open project modal visible")
    modal:_setDirectory(currentRunner.fixtureDir)
  end)
  steps[#steps + 1] = pause("Observe fixture directory", 0.25)

  steps[#steps + 1] = call("Resolve nested folder slot", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.openProjectModal, "expected openProjectModal")
    local slot = FixtureHelpers.findVisibleSlotForName(modal, "nested")
    assert(slot, "expected nested/ folder in open project modal")
    currentRunner.nestedFolderSlot = slot
  end)

  appendClick(steps, "Enter nested fixture folder", function(_, currentApp, currentRunner)
    return openProjectFileSlotCenter(currentRunner.nestedFolderSlot)(nil, currentApp, currentRunner)
  end, {
    moveDuration = 0.1,
    postPause = 0.25,
  })

  steps[#steps + 1] = call("Resolve project file slot", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.openProjectModal, "expected openProjectModal")
    assert(modal:getCurrentDir() == currentRunner.fixtureNestedDir, "expected nested fixture directory")
    local slot = FixtureHelpers.findVisibleSlotForName(modal, "test_rom.lua")
    assert(slot, "expected test_rom.lua in open project modal")
    currentRunner.projectFileSlot = slot
  end)

  appendClick(steps, "Open fixture project file", function(_, currentApp, currentRunner)
    return openProjectFileSlotCenter(currentRunner.projectFileSlot)(nil, currentApp, currentRunner)
  end, {
    moveDuration = 0.1,
    postPause = 0.45,
  })

  steps[#steps + 1] = call("Assert loaded project windows", function(currentHarness, currentApp)
    assert(not currentApp.openProjectModal:isVisible(), "expected open project modal to close")
    assertLoadedTestRomProject(currentApp, currentHarness)
  end)
  steps[#steps + 1] = pause("Observe loaded workspace", 0.6)
  steps[#steps + 1] = call("Cleanup open-project fixture files", function(_, _, currentRunner)
    FixtureHelpers.cleanupPaths(currentRunner._cleanupPaths)
  end)

  runner.harness = harness
  return steps
end

local function buildOpenProjectInvalidFileScenario(harness, app, runner)
  local steps = {
    pause("Start", 0.35),
    call("Prepare open-project fixture tree", function(_, _, currentRunner)
      FixtureHelpers.setupOpenProjectFixture(currentRunner)
    end),
  }

  appendClick(steps, "Open project from app toolbar", appQuickButtonCenter("open"), {
    moveDuration = 0.1,
    postPause = 0.35,
  })

  steps[#steps + 1] = call("Browse to fixture directory", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.openProjectModal, "expected openProjectModal")
    assert(modal:isVisible(), "expected open project modal visible")
    modal:_setDirectory(currentRunner.fixtureDir)
  end)
  steps[#steps + 1] = pause("Observe fixture directory", 0.25)

  steps[#steps + 1] = call("Resolve invalid project slot", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.openProjectModal, "expected openProjectModal")
    local slot = FixtureHelpers.findVisibleSlotForName(modal, "invalid_project.lua")
    assert(slot, "expected invalid_project.lua in open project modal")
    currentRunner.invalidFileSlot = slot
  end)

  appendClick(steps, "Select invalid project file", function(_, currentApp, currentRunner)
    return openProjectFileSlotCenter(currentRunner.invalidFileSlot)(nil, currentApp, currentRunner)
  end, {
    moveDuration = 0.1,
    postPause = 0.35,
  })

  steps[#steps + 1] = call("Assert invalid project error feedback", function(currentHarness, currentApp, currentRunner)
    assert(not currentApp.openProjectModal:isVisible(), "expected open project modal to close after selection")
    assert(not currentApp:hasLoadedROM(), "expected ROM to remain unloaded after invalid project")
    local status = tostring(currentHarness:getStatusText() or "")
    assert(
      status:find("not a valid", 1, true) ~= nil or status:find("Project", 1, true) ~= nil,
      string.format("expected project error in status, got: %q", status)
    )
  end)
  steps[#steps + 1] = pause("Observe invalid project handling", 0.5)
  steps[#steps + 1] = call("Cleanup open-project fixture files", function(_, _, currentRunner)
    FixtureHelpers.cleanupPaths(currentRunner._cleanupPaths)
  end)

  runner.harness = harness
  return steps
end

return {
  open_project_happy_path = { title = "Open Project Happy Path", build = buildOpenProjectHappyPathScenario },
  open_project_invalid_file = { title = "Open Project Invalid File", build = buildOpenProjectInvalidFileScenario },
}
