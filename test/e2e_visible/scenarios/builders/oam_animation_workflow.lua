-- OAM animation window: frame navigation, playback, sprite add/remove smoke.

local P = require("test.e2e_visible.scenarios.prelude")
local BubbleExample, normalizeSpeedMultiplier, pause, keyPress, call, appendClick,
  ppuToolbarButtonCenter, setFocusedTextFieldValue
  = P.BubbleExample, P.normalizeSpeedMultiplier, P.pause, P.keyPress, P.call, P.appendClick,
  P.ppuToolbarButtonCenter, P.setFocusedTextFieldValue

local function buildOamAnimationWorkflowScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local speedMultiplier = normalizeSpeedMultiplier(runner and runner.speedMultiplier or 1)
  local frameDelay = 0.15 / speedMultiplier
  local playbackObserve = 0.45 * speedMultiplier

  local steps = {
    pause("Start", 0.35),
    call("Create OAM animation fixture window", function(_, currentApp, currentRunner)
      local oamWin = assert(currentApp.wm:createSpriteWindow({
        animated = true,
        oamBacked = true,
        numFrames = 2,
        title = "OAM E2E",
        x = 180,
        y = 90,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected OAM animation window")
      currentRunner.oamWin = oamWin
      for layerIndex = 1, oamWin:getLayerCount() do
        oamWin.frameDelays[layerIndex] = frameDelay
      end
      currentApp.wm:setFocus(oamWin)
    end),
    pause("Observe OAM window", 0.45),
    keyPress("Add animation frame", "="),
    pause("Observe third frame", 0.25),
    keyPress("Go to next frame", "up", { "shift" }),
    pause("Observe frame navigation forward", 0.2),
    keyPress("Go to previous frame", "down", { "shift" }),
    pause("Observe frame navigation backward", 0.2),
    keyPress("Play OAM animation", "p"),
    pause("Observe short playback", playbackObserve),
    keyPress("Pause OAM animation", "p"),
    pause("Observe paused frame", 0.35),
  }

  appendClick(steps, "Open add sprite toolbar action", ppuToolbarButtonCenter("oamWin", function(toolbar)
    return toolbar.addSpriteButton
  end), {
    moveDuration = 0.1,
    postPause = 0.25,
  })

  steps[#steps + 1] = call("Confirm add sprite modal", function(currentHarness, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected ppuFrameAddSpriteModal")
    assert(modal:isVisible(), "expected add sprite modal visible")
    setFocusedTextFieldValue(modal.oamStartField, "0x000020")
    currentHarness:keyPress("return", { wait = false })
    currentHarness:wait(0.16)
    local oamWin = assert(currentRunner.oamWin, "expected OAM window")
    local layer = assert(oamWin.layers and oamWin.layers[oamWin.activeLayer or 1], "expected active sprite layer")
    assert(#(layer.items or {}) >= 1, "expected sprite after OAM add")
    currentRunner.oamSpriteIndex = #layer.items
  end)
  steps[#steps + 1] = pause("Observe added sprite", 0.35)

  steps[#steps + 1] = call("Select added OAM sprite", function(_, currentApp, currentRunner)
    local oamWin = assert(currentRunner.oamWin, "expected OAM window")
    local li = oamWin.activeLayer or 1
    local layer = assert(oamWin.layers and oamWin.layers[li], "expected sprite layer")
    local idx = assert(currentRunner.oamSpriteIndex, "expected sprite index")
    layer.selectedSpriteIndex = idx
    layer.multiSpriteSelection = { [idx] = true }
    layer.multiSpriteSelectionOrder = { idx }
    currentApp.wm:setFocus(oamWin)
  end)

  steps[#steps + 1] = keyPress("Delete selected OAM sprite", "delete")
  steps[#steps + 1] = pause("Observe sprite delete", 0.25)
  steps[#steps + 1] = call("Assert OAM sprite removed", function(_, _, currentRunner)
    local oamWin = assert(currentRunner.oamWin, "expected OAM window")
    local layer = assert(oamWin.layers and oamWin.layers[oamWin.activeLayer or 1], "expected active sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.oamSpriteIndex], "expected sprite item")
    assert(sprite.removed == true, "expected OAM sprite to be marked removed")
  end)
  steps[#steps + 1] = pause("Scenario complete", 0.5)

  runner.harness = harness
  return steps
end

return {
  oam_animation_workflow = { title = "OAM Animation Workflow", build = buildOamAnimationWorkflowScenario },
}
