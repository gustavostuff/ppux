-- E2E coverage for 0.2.0 features: Sketch canvas + Gallery ROM, Swap 2 colors,
-- relocation pointer calculator, and PPU attribute grid mode.

local P = require("test.e2e_visible.scenarios.prelude")
local BubbleExample, pause, call, appendClick, keyPress, appQuickButtonCenter,
  ppuToolbarButtonCenter, menuRowCenterByText, setFocusedTextFieldValue,
  setupDeterministicPpuFixture
  = P.BubbleExample, P.pause, P.call, P.appendClick, P.keyPress, P.appQuickButtonCenter,
  P.ppuToolbarButtonCenter, P.menuRowCenterByText, P.setFocusedTextFieldValue,
  P.setupDeterministicPpuFixture

local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local RelocationPointerMath = require("utils.relocation_pointer_math")

local function buildSketchCanvasAndGalleryScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local steps = {
    pause("Start", 0.3),
    call("Create sketch canvas + pattern table fixtures", function(_, currentApp, currentRunner)
      for _, win in ipairs(currentApp.wm:getWindows() or {}) do
        if win and not win._closed then
          win._closed = true
        end
      end

      local sketch = assert(currentApp.wm:createSketchCanvasWindow({
        title = "Sketch E2E",
        x = 80,
        y = 60,
        zoom = 1,
      }), "expected sketch canvas window")
      local pt = assert(currentApp.wm:createPatternTableWindow({
        title = "Sketch PT E2E",
        x = 380,
        y = 60,
        zoom = 2,
      }), "expected pattern table window")
      assert(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, currentApp.wm))
      currentRunner.sketchWin = sketch
      currentRunner.sketchPtWin = pt
      currentApp.wm:setFocus(sketch)
    end),
    pause("Observe sketch fixtures", 0.45),
    keyPress("Switch to edit mode", "tab"),
    pause("Observe edit mode", 0.25),
    keyPress("Choose paint color 3", "4"),
    pause("Prepare paint", 0.1),
  }

  steps[#steps + 1] = call("Paint a small block on the sketch canvas", function(currentHarness, _, currentRunner)
    local sketch = assert(currentRunner.sketchWin, "expected sketch window")
    local x1, y1 = currentHarness:windowPixelCenter(sketch, 2, 2, 2, 2)
    local x2, y2 = currentHarness:windowPixelCenter(sketch, 5, 5, 4, 4)
    currentHarness:moveMouse(x1, y1)
    currentHarness:mouseDown(1, x1, y1)
    currentHarness:wait(0.05)
    currentHarness:moveMouse(x2, y2)
    currentHarness:wait(0.08)
    currentHarness:mouseUp(1, x2, y2)
  end)
  steps[#steps + 1] = pause("Observe painted pixels", 0.35)

  appendClick(steps, "Generate sketch patterns", ppuToolbarButtonCenter("sketchWin", function(toolbar)
    return toolbar.generateButton
  end), {
    moveDuration = 0.1,
    postPause = 0.35,
  })

  steps[#steps + 1] = call("Assert sketch pack + gallery toolbar enabled", function(_, currentApp, currentRunner)
    local sketch = assert(currentRunner.sketchWin, "expected sketch window")
    assert(SketchCanvasPackController.hasPackData(sketch), "expected pack data after Generate")
    assert(
      type(sketch.linkedPatternTableWindowId) == "string" and sketch.linkedPatternTableWindowId ~= "",
      "expected sketch linked to pattern table"
    )
    AppTopToolbarController.syncLayout(currentApp)
    local galleryBtn = assert(
      currentApp._appTopQuickButtons and currentApp._appTopQuickButtons.galleryRom,
      "expected gallery ROM toolbar button"
    )
    assert(galleryBtn.enabled == true, "expected gallery ROM button enabled after pack")
  end)
  steps[#steps + 1] = pause("Observe packed sketch", 0.35)

  appendClick(steps, "Open gallery ROM from app toolbar", appQuickButtonCenter("galleryRom"), {
    moveDuration = 0.1,
    postPause = 0.35,
  })

  steps[#steps + 1] = call("Assert gallery confirm or result modal", function(_, currentApp, currentRunner)
    local confirm = currentApp.galleryRomConfirmModal
    local result = currentApp.galleryRomResultModal
    local confirmVisible = confirm and confirm:isVisible()
    local resultVisible = result and result:isVisible()
    assert(
      confirmVisible or resultVisible,
      "expected gallery confirm modal (cc65 present) or result modal (missing tools / failure)"
    )
    currentRunner.galleryOpenedConfirm = confirmVisible == true
    if confirmVisible then
      assert(
        tostring(confirm.summaryText or ""):find("packed sketch", 1, true) ~= nil,
        "expected confirm summary about packed sketch canvases"
      )
      assert(confirm.thumbStrip and #(confirm.thumbStrip.entries or {}) >= 1, "expected thumb strip entries")
    end
  end)
  steps[#steps + 1] = pause("Observe gallery modal", 0.55)
  steps[#steps + 1] = keyPress("Close gallery modal", "escape")
  steps[#steps + 1] = pause("Scenario complete", 0.4)

  runner.harness = harness
  return steps
end

local function buildSwapTwoColorsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local bankWindow = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )

  local steps = {
    pause("Start", 0.3),
    call("Focus CHR bank for swap modal", function(_, currentApp)
      currentApp.wm:setFocus(bankWindow)
    end),
    pause("Observe CHR bank", 0.35),
    call("Open CHR tile context menu", function(currentHarness, currentApp)
      local x, y = currentHarness:windowCellCenter(bankWindow, 1, 1)
      currentHarness:click(x, y, { button = 2, wait = false })
      currentHarness:wait(0.14)
      assert(
        currentApp.ppuTileContextMenu and currentApp.ppuTileContextMenu:isVisible(),
        "expected CHR tile context menu"
      )
    end),
  }

  appendClick(steps, "Open Swap 2 colors from context menu", menuRowCenterByText(function(currentApp)
    return currentApp.ppuTileContextMenu
  end, "Swap 2 colors"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.3,
  })

  steps[#steps + 1] = call("Assert Swap 2 colors modal visible", function(_, currentApp)
    local modal = assert(currentApp.swapTwoColorsModal, "expected swapTwoColorsModal")
    assert(modal:isVisible(), "expected Swap 2 colors modal visible")
  end)
  steps[#steps + 1] = pause("Observe swap modal", 0.4)

  steps[#steps + 1] = call("Select palette indices 0 and 3", function(_, currentApp)
    local modal = assert(currentApp.swapTwoColorsModal, "expected swap modal")
    assert(modal.colorRamp, "expected color ramp")
    modal.colorRamp.selected = { 0, 3 }
    if modal._refreshAfterPreview then
      modal:_refreshAfterPreview()
    end
    if modal._updateApplyEnabled then
      modal:_updateApplyEnabled()
    end
    assert(modal.applyButton and modal.applyButton.enabled == true, "expected Swap button enabled")
  end)
  steps[#steps + 1] = pause("Observe color selection", 0.25)

  steps[#steps + 1] = call("Apply color swap", function(currentHarness, currentApp)
    local modal = assert(currentApp.swapTwoColorsModal, "expected swap modal")
    local btn = assert(modal.applyButton, "expected Swap button")
    local x = btn.x + math.floor(btn.w * 0.5)
    local y = btn.y + math.floor(btn.h * 0.5)
    currentHarness:click(x, y, { wait = false })
    currentHarness:wait(0.2)
    assert(not modal:isVisible(), "expected Swap 2 colors modal to close after apply")
  end)
  steps[#steps + 1] = pause("Observe swapped tile", 0.55)
  steps[#steps + 1] = pause("Scenario complete", 0.35)

  runner.harness = harness
  return steps
end

local function buildRelocationAndAttrModeScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local steps = {
    pause("Start", 0.3),
    call("Create PPU fixture for attr mode", function(_, currentApp, currentRunner)
      for _, win in ipairs(currentApp.wm:getWindows() or {}) do
        if win and not win._closed then
          win._closed = true
        end
      end
      setupDeterministicPpuFixture(currentApp, currentRunner)
      local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
      ppu.x = 120
      ppu.y = 70
      ppu.title = "Attr Mode E2E"
      currentApp.wm:setFocus(ppu)
    end),
    pause("Observe PPU fixture", 0.4),
    call("Force tile mode before attr toggle", function(_, currentApp)
      currentApp.mode = "tile"
    end),
  }

  steps[#steps + 1] = keyPress("Toggle attribute grid mode", "a")
  steps[#steps + 1] = pause("Observe attribute grid", 0.45)
  steps[#steps + 1] = call("Assert attribute grid enabled", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    local layer = nil
    for _, L in ipairs(ppu.layers or {}) do
      if L and L.kind == "tile" then
        layer = L
        break
      end
    end
    assert(layer, "expected PPU tile layer")
    assert(layer.attrMode == true, "expected attrMode on after pressing A")
  end)

  steps[#steps + 1] = keyPress("Toggle attribute grid off", "a")
  steps[#steps + 1] = pause("Observe normal nametable grid", 0.3)
  steps[#steps + 1] = call("Assert attribute grid disabled", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    local layer = nil
    for _, L in ipairs(ppu.layers or {}) do
      if L and L.kind == "tile" then
        layer = L
        break
      end
    end
    assert(layer, "expected PPU tile layer")
    assert(layer.attrMode ~= true, "expected attrMode off after second A")
  end)

  appendClick(steps, "Open relocation pointer calculator", appQuickButtonCenter("relocationPointerCalc"), {
    moveDuration = 0.1,
    postPause = 0.3,
  })

  steps[#steps + 1] = call("Assert relocation calculator visible", function(_, currentApp)
    local modal = assert(currentApp.relocationPointerCalculatorModal, "expected relocation modal")
    assert(modal:isVisible(), "expected relocation calculator visible")
  end)
  steps[#steps + 1] = pause("Observe relocation calculator", 0.35)

  steps[#steps + 1] = call("Enter sample ROM offset", function(_, currentApp)
    local modal = assert(currentApp.relocationPointerCalculatorModal, "expected relocation modal")
    setFocusedTextFieldValue(modal.offsetField, "0x001234")
  end)
  steps[#steps + 1] = pause("Observe offset field", 0.2)

  steps[#steps + 1] = call("Calculate pointer bytes", function(currentHarness, currentApp)
    local modal = assert(currentApp.relocationPointerCalculatorModal, "expected relocation modal")
    local btn = assert(modal.calculateButton, "expected Calculate button")
    local x = btn.x + math.floor(btn.w * 0.5)
    local y = btn.y + math.floor(btn.h * 0.5)
    currentHarness:click(x, y, { wait = false })
    currentHarness:wait(0.18)
    assert(modal.resultLo ~= nil and modal.resultHi ~= nil, "expected lo/hi pointer results")
    local _, lo, hi = RelocationPointerMath.fileOffsetToPointer(0x001234, {})
    assert(modal.resultLo == lo, string.format("expected lo %s got %s", tostring(lo), tostring(modal.resultLo)))
    assert(modal.resultHi == hi, string.format("expected hi %s got %s", tostring(hi), tostring(modal.resultHi)))
  end)
  steps[#steps + 1] = pause("Observe calculated pointer bytes", 0.5)
  steps[#steps + 1] = keyPress("Close relocation calculator", "escape")
  steps[#steps + 1] = pause("Scenario complete", 0.35)

  runner.harness = harness
  return steps
end

return {
  sketch_canvas_and_gallery = {
    title = "Sketch Canvas + Gallery ROM",
    build = buildSketchCanvasAndGalleryScenario,
  },
  swap_two_colors_modal = {
    title = "Swap 2 Colors Modal",
    build = buildSwapTwoColorsScenario,
  },
  relocation_and_attr_mode = {
    title = "Relocation Calculator + Attr Grid",
    build = buildRelocationAndAttrModeScenario,
  },
}
