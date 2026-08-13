-- Pattern-table badge linking: all consumer paths + CHR mapping consequences.
local P = require("test.e2e_visible.scenarios.prelude")
local H = require("test.e2e_visible.scenarios.builders.link_helpers")
local BubbleExample, pause, call, appendClick, keyPress, setFocusedTextFieldValue, setupDeterministicPpuFixture,
  ensureSpriteLayerReadyForAddSprite
  = P.BubbleExample, P.pause, P.call, P.appendClick, P.keyPress, P.setFocusedTextFieldValue, P.setupDeterministicPpuFixture,
  P.ensureSpriteLayerReadyForAddSprite

local function buildPatternTableLinkConsequencesScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local steps = {
    pause("Start", 0.3),
    call("Create PT consequence fixtures", function(_, currentApp, currentRunner)
      if currentApp._applyWindowLinksSetting then
        currentApp:_applyWindowLinksSetting("always", false)
      end
      H.closeAllOpenWindows(currentApp)

      setupDeterministicPpuFixture(currentApp, currentRunner)
      local ppu = currentRunner.ppuFixtureWin
      ppu.x = 520
      ppu.y = 48
      ppu.title = "PPU PT Consequence"

      local BankViewController = require("controllers.chr.bank_view_controller")
      local state = currentApp.appEditState
      BankViewController.ensureBankTiles(state, 1)
      local bankCount = math.max(1, #((state and state.chrBanksBytes) or {}))
      local bankB = (bankCount >= 2) and 2 or 1
      if bankB == 2 then
        BankViewController.ensureBankTiles(state, 2)
      end
      currentRunner.ptBankA = 1
      currentRunner.ptBankB = bankB
      -- PT A: identity map (logical 6 -> CHR tile 6 on bank A).
      currentRunner.patternTableAWin = assert(currentApp.wm:createPatternTableWindow({
        title = "PT A Identity",
        x = 36,
        y = 48,
        zoom = 2,
        patternTable = {
          ranges = {
            { bank = currentRunner.ptBankA, from = 0, to = 255 },
          },
        },
      }), "expected PT A")
      -- PT B: either another CHR bank, or a shifted range on bank 1 so logical 6 maps to tile 106.
      local rangesB
      if currentRunner.ptBankB ~= currentRunner.ptBankA then
        rangesB = { { bank = currentRunner.ptBankB, from = 0, to = 255 } }
        currentRunner.ptBExpectedTileByte = 6
      else
        rangesB = { { bank = 1, from = 100, to = 355 } }
        currentRunner.ptBExpectedTileByte = 106
      end
      currentRunner.patternTableBWin = assert(currentApp.wm:createPatternTableWindow({
        title = "PT B Retarget",
        x = 36,
        y = 250,
        zoom = 2,
        patternTable = {
          ranges = rangesB,
        },
      }), "expected PT B")

      local oam = assert(currentRunner.oamFixtureWin, "expected OAM fixture")
      oam.x = 280
      oam.y = 250
      oam.title = "OAM PT Consequence"

      currentRunner.sketchWin = assert(currentApp.wm:createSketchCanvasWindow({
        title = "Sketch PT Consequence",
        x = 520,
        y = 280,
      }), "expected sketch canvas")

      currentApp.wm:setFocus(ppu)
    end),
    pause("Observe PT fixtures", 0.45),
  }

  -- Sprite layer on PPU so sprite-slot linking is available.
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
  steps[#steps + 1] = call("Stub sprite PT gate for Add sprite", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local spriteIdx = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected sprite layer")
    ensureSpriteLayerReadyForAddSprite(ppu.layers[spriteIdx])
  end)
  H.appendClickToolbarButton(steps, "Open add sprite modal", "ppuFixtureWin", function(toolbar)
    return toolbar.addSpriteButton
  end, { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = call("Fill add sprite modal and confirm", function(currentHarness, currentApp)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected ppuFrameAddSpriteModal")
    assert(modal:isVisible(), "expected add sprite modal visible")
    setFocusedTextFieldValue(modal.oamStartField, "0x000020")
    currentHarness:keyPress("return", { wait = false })
    currentHarness:wait(0.18)
  end)
  steps[#steps + 1] = call("Clear stub sprite gate link before real badge links", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local spriteIdx = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected sprite layer")
    local layer = ppu.layers[spriteIdx]
    if layer and layer.linkedPatternTableWindowId == "e2e_sprite_pt_gate" then
      layer.linkedPatternTableWindowId = nil
    end
  end)

  -- Background: badge-drag PT A, hydrate NT, assert CHR mapping for fixture tile 6 at 4,4.
  H.appendBadgeDragLink(
    steps,
    "Badge-drag PT A onto PPU bg slot",
    "patternTableAWin",
    "pattern_source",
    "ppuFixtureWin",
    "ppu_pattern_bg"
  )
  steps[#steps + 1] = call("Assert PPU bg linked to PT A + NT maps to bank A tile 6", function(_, currentApp, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local ptA = H.requireRunnerWindow(currentRunner, "patternTableAWin")
    local bgIdx = assert(H.findFirstLayerIndexByKind(ppu, "tile"), "expected bg layer")
    assert(H.layerPatternTableWinId(ppu, bgIdx) == ptA._id, "expected bg linked to PT A")
    local layer = ppu.layers[bgIdx]
    assert(layer.patternTable == ptA.layers[1].patternTable, "expected shared patternTable ref with PT A")
    H.assertPatternMapBankAndTile(layer, currentRunner.ppuFixtureExpectedTile, currentRunner.ptBankA, 6)
    H.assertPpuCellMatchesPatternMap(
      currentApp,
      currentRunner,
      4,
      4,
      currentRunner.ppuFixtureExpectedTile
    )
  end)
  steps[#steps + 1] = pause("Observe NT tile via PT A / CHR bank", 0.35)

  -- Retarget background to PT B: mapping must flip.
  H.appendBadgeDragLink(
    steps,
    "Retarget PPU bg badge to PT B",
    "ppuFixtureWin",
    "ppu_pattern_bg",
    "patternTableBWin",
    "pattern_source"
  )
  steps[#steps + 1] = call("Assert PPU bg retarget to PT B changes CHR mapping", function(_, currentApp, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local ptB = H.requireRunnerWindow(currentRunner, "patternTableBWin")
    local bgIdx = assert(H.findFirstLayerIndexByKind(ppu, "tile"), "expected bg layer")
    assert(H.layerPatternTableWinId(ppu, bgIdx) == ptB._id, "expected bg linked to PT B")
    local layer = ppu.layers[bgIdx]
    H.assertPatternMapBankAndTile(
      layer,
      currentRunner.ppuFixtureExpectedTile,
      currentRunner.ptBankB,
      currentRunner.ptBExpectedTileByte
    )
    local tile = H.assertPpuCellMatchesPatternMap(
      currentApp,
      currentRunner,
      4,
      4,
      currentRunner.ppuFixtureExpectedTile
    )
    assert(
      tonumber(tile._bankIndex) == tonumber(currentRunner.ptBankB),
      "expected NT cell bank to follow PT B"
    )
  end)
  steps[#steps + 1] = pause("Observe NT tile remapped via PT B", 0.35)

  steps[#steps + 1] = keyPress("Undo PT B retarget", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe PT undo", 0.2)
  steps[#steps + 1] = call("Assert undo restored PT A mapping", function(_, currentApp, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local ptA = H.requireRunnerWindow(currentRunner, "patternTableAWin")
    local bgIdx = assert(H.findFirstLayerIndexByKind(ppu, "tile"), "expected bg layer")
    assert(H.layerPatternTableWinId(ppu, bgIdx) == ptA._id, "expected undo back to PT A")
    H.assertPatternMapBankAndTile(ppu.layers[bgIdx], currentRunner.ppuFixtureExpectedTile, currentRunner.ptBankA, 6)
    H.assertPpuCellMatchesPatternMap(
      currentApp,
      currentRunner,
      4,
      4,
      currentRunner.ppuFixtureExpectedTile
    )
  end)
  steps[#steps + 1] = keyPress("Redo PT B retarget", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe PT redo", 0.2)
  steps[#steps + 1] = call("Assert redo restored PT B mapping", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local ptB = H.requireRunnerWindow(currentRunner, "patternTableBWin")
    local bgIdx = assert(H.findFirstLayerIndexByKind(ppu, "tile"), "expected bg layer")
    assert(H.layerPatternTableWinId(ppu, bgIdx) == ptB._id, "expected redo to PT B")
    H.assertPatternMapBankAndTile(
      ppu.layers[bgIdx],
      currentRunner.ppuFixtureExpectedTile,
      currentRunner.ptBankB,
      currentRunner.ptBExpectedTileByte
    )
  end)

  -- Sprite layer pattern link.
  H.appendBadgeDragLink(
    steps,
    "Badge-drag PT A onto PPU sprite slot",
    "patternTableAWin",
    "pattern_source",
    "ppuFixtureWin",
    "ppu_pattern_sprite"
  )
  steps[#steps + 1] = call("Assert PPU sprite layer linked + maps through PT A", function(_, currentApp, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local ptA = H.requireRunnerWindow(currentRunner, "patternTableAWin")
    local sprIdx = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected sprite layer")
    assert(H.layerPatternTableWinId(ppu, sprIdx) == ptA._id, "expected sprite linked to PT A")
    local layer = ppu.layers[sprIdx]
    assert(layer.patternTable == ptA.layers[1].patternTable, "expected sprite patternTable ref == PT A")
    H.assertPatternMapBankAndTile(layer, 6, currentRunner.ptBankA, 6)
    if currentApp._afterPatternTableLinkChange then
      currentApp:_afterPatternTableLinkChange(ppu, sprIdx)
    end
    local item = layer.items and layer.items[1]
    if item and type(item.index) == "number" then
      local entry = H.patternMapEntry(layer, item.index % 256)
      assert(
        tonumber(item._bankIndex) == tonumber(entry.bank)
          or tonumber(item._bankIndex) == tonumber(currentRunner.ptBankA),
        "expected sprite item bank to follow linked PT"
      )
    end
  end)

  -- OAM bulk link (drop on body: stacked oam_pattern + layout_palette badges are ambiguous).
  H.appendBadgeDragToWindowBody(
    steps,
    "Badge-drag PT A onto OAM window body",
    "patternTableAWin",
    "pattern_source",
    "oamFixtureWin",
    3,
    3
  )
  steps[#steps + 1] = call("Assert every OAM sprite layer linked to PT A", function(_, _, currentRunner)
    local WindowCaps = require("controllers.window.window_capabilities")
    local oam = H.requireRunnerWindow(currentRunner, "oamFixtureWin")
    local ptA = H.requireRunnerWindow(currentRunner, "patternTableAWin")
    assert(WindowCaps.isOamAnimation(oam), "expected OAM animation fixture")
    local linked = 0
    for _, layer in ipairs(oam.layers or {}) do
      if layer and layer.kind == "sprite" then
        assert(layer.linkedPatternTableWindowId == ptA._id, "expected OAM sprite layer linked to PT A")
        assert(layer.patternTable == ptA.layers[1].patternTable, "expected OAM patternTable ref == PT A")
        H.assertPatternMapBankAndTile(layer, 0, currentRunner.ptBankA, 0)
        linked = linked + 1
      end
    end
    assert(linked >= 1, "expected at least one OAM sprite layer")
  end)

  -- Same-side source→source before sketch owns PT A.
  -- PT B's right-edge source badge sits on the OAM window; park OAM so the drop hits PT B.
  steps[#steps + 1] = call("Park OAM so PT B source badge is droppable", function(_, currentApp, currentRunner)
    local oam = H.requireRunnerWindow(currentRunner, "oamFixtureWin")
    currentRunner.oamPosBeforePtSourceMove = { x = oam.x, y = oam.y }
    oam.x = 520
    oam.y = 280
    local ptB = H.requireRunnerWindow(currentRunner, "patternTableBWin")
    if currentApp.wm.bringToFront then
      currentApp.wm:bringToFront(ptB)
    end
  end)
  H.appendBadgeDragLink(
    steps,
    "Move all PT A consumers onto PT B source badge",
    "patternTableAWin",
    "pattern_source",
    "patternTableBWin",
    "pattern_source"
  )
  steps[#steps + 1] = call("Assert source-to-source moved PPU sprite and OAM onto PT B", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local oam = H.requireRunnerWindow(currentRunner, "oamFixtureWin")
    local ptA = H.requireRunnerWindow(currentRunner, "patternTableAWin")
    local ptB = H.requireRunnerWindow(currentRunner, "patternTableBWin")
    local sprIdx = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected sprite layer")
    assert(H.layerPatternTableWinId(ppu, sprIdx) == ptB._id, "expected PPU sprite moved onto PT B")
    assert(H.layerPatternTableWinId(ppu, sprIdx) ~= ptA._id, "expected PPU sprite no longer on PT A")
    H.assertPatternMapBankAndTile(ppu.layers[sprIdx], 6, currentRunner.ptBankB, currentRunner.ptBExpectedTileByte)
    for _, layer in ipairs(oam.layers or {}) do
      if layer and layer.kind == "sprite" then
        assert(layer.linkedPatternTableWindowId == ptB._id, "expected OAM moved onto PT B")
        H.assertPatternMapBankAndTile(layer, 0, currentRunner.ptBankB, currentRunner.ptBExpectedTileByte - 6)
      end
    end
  end)
  steps[#steps + 1] = pause("Observe PT source move", 0.25)
  steps[#steps + 1] = keyPress("Undo PT source move", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe PT source-move undo", 0.2)
  steps[#steps + 1] = call("Assert undo restored PPU sprite and OAM onto PT A", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local oam = H.requireRunnerWindow(currentRunner, "oamFixtureWin")
    local ptA = H.requireRunnerWindow(currentRunner, "patternTableAWin")
    local sprIdx = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected sprite layer")
    assert(H.layerPatternTableWinId(ppu, sprIdx) == ptA._id, "expected undo back to PT A")
    H.assertPatternMapBankAndTile(ppu.layers[sprIdx], 6, currentRunner.ptBankA, 6)
    for _, layer in ipairs(oam.layers or {}) do
      if layer and layer.kind == "sprite" then
        assert(layer.linkedPatternTableWindowId == ptA._id, "expected OAM undo back to PT A")
      end
    end
  end)
  steps[#steps + 1] = call("Restore OAM position after PT source move", function(_, _, currentRunner)
    local oam = H.requireRunnerWindow(currentRunner, "oamFixtureWin")
    local pos = currentRunner.oamPosBeforePtSourceMove
    if pos then
      oam.x = pos.x
      oam.y = pos.y
    end
  end)

  -- Same-side dest→dest: PPU sprite (A) onto OAM sprite slot moves A onto OAM and unlinks PPU sprite.
  H.appendBadgeDragLink(
    steps,
    "Move PPU sprite dest badge onto OAM pattern badge",
    "ppuFixtureWin",
    "ppu_pattern_sprite",
    "oamFixtureWin",
    "oam_pattern"
  )
  steps[#steps + 1] = call("Assert dest-to-dest unlinked PPU sprite and kept OAM on PT A", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local oam = H.requireRunnerWindow(currentRunner, "oamFixtureWin")
    local ptA = H.requireRunnerWindow(currentRunner, "patternTableAWin")
    local sprIdx = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected sprite layer")
    assert(H.layerPatternTableWinId(ppu, sprIdx) ~= ptA._id, "expected PPU sprite unlinked after dest move")
    for _, layer in ipairs(oam.layers or {}) do
      if layer and layer.kind == "sprite" then
        assert(layer.linkedPatternTableWindowId == ptA._id, "expected OAM still on PT A")
      end
    end
  end)
  H.appendBadgeDragLink(
    steps,
    "Restore PPU sprite link to PT A after dest move",
    "patternTableAWin",
    "pattern_source",
    "ppuFixtureWin",
    "ppu_pattern_sprite"
  )

  -- Sketch window-level link.
  H.appendBadgeDragLink(
    steps,
    "Badge-drag PT A onto sketch bg pattern slot",
    "patternTableAWin",
    "pattern_source",
    "sketchWin",
    "ppu_pattern_bg"
  )
  steps[#steps + 1] = call("Assert sketch canvas linked to PT A", function(_, _, currentRunner)
    local sketch = H.requireRunnerWindow(currentRunner, "sketchWin")
    local ptA = H.requireRunnerWindow(currentRunner, "patternTableAWin")
    assert(sketch.linkedPatternTableWindowId == ptA._id, "expected sketch linkedPatternTableWindowId")
    assert(ptA.linkedSketchCanvasWindowId == sketch._id, "expected PT linkedSketchCanvasWindowId")
  end)

  -- Source menu remove-all clears consumer links created above (except sketch uses window-level unlink).
  H.appendClickPaletteHandle(steps, "Open PT A source badge menu", "patternTableAWin", "pattern_source")
  appendClick(steps, "Remove all PT A links", H.paletteLinkMenuRowByText("Remove all links"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.28,
  })
  steps[#steps + 1] = call("Assert PT A remove-all cleared layer consumers", function(_, _, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local oam = H.requireRunnerWindow(currentRunner, "oamFixtureWin")
    local ptA = H.requireRunnerWindow(currentRunner, "patternTableAWin")
    local bgIdx = assert(H.findFirstLayerIndexByKind(ppu, "tile"), "expected bg")
    local sprIdx = assert(H.findFirstLayerIndexByKind(ppu, "sprite"), "expected sprite")
    -- Bg may still be on PT B from redo; sprite/OAM should clear if they pointed at A.
    assert(H.layerPatternTableWinId(ppu, sprIdx) ~= ptA._id, "expected PPU sprite unlinked from PT A")
    for _, layer in ipairs(oam.layers or {}) do
      if layer and layer.kind == "sprite" then
        assert(layer.linkedPatternTableWindowId ~= ptA._id, "expected OAM unlinked from PT A")
      end
    end
    -- Sketch unlink is part of source remove when listed as consumer.
    local sketch = H.requireRunnerWindow(currentRunner, "sketchWin")
    assert(
      sketch.linkedPatternTableWindowId ~= ptA._id,
      "expected sketch unlinked from PT A after remove-all"
    )
    assert(bgIdx and sprIdx)
  end)

  steps[#steps + 1] = pause("Scenario complete", 0.4)
  return steps
end

return {
  pattern_table_link_consequences = {
    title = "Pattern Table Link Consequences",
    build = buildPatternTableLinkConsequencesScenario,
  },
}
