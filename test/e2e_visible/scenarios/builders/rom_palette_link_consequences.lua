-- ROM palette badge linking: consumer paths + resolved color consequences.
local P = require("test.e2e_visible.scenarios.prelude")
local H = require("test.e2e_visible.scenarios.builders.link_helpers")
local BubbleExample, pause, call, appendClick, keyPress, setupDeterministicPpuFixture
  = P.BubbleExample, P.pause, P.call, P.appendClick, P.keyPress, P.setupDeterministicPpuFixture

local function paintPaletteRow(win, row, codes)
  for col = 0, 3 do
    win.codes2D = win.codes2D or {}
    win.codes2D[row] = win.codes2D[row] or {}
    win.codes2D[row][col] = codes[col + 1]
  end
end

local function buildRomPaletteLinkConsequencesScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local steps = {
    pause("Start", 0.3),
    call("Create ROM palette consequence fixtures", function(_, currentApp, currentRunner)
      if currentApp._applyWindowLinksSetting then
        currentApp:_applyWindowLinksSetting("always", false)
      end
      H.closeAllOpenWindows(currentApp)

      setupDeterministicPpuFixture(currentApp, currentRunner)
      local ppu = currentRunner.ppuFixtureWin
      ppu.x = 520
      ppu.y = 48
      ppu.title = "PPU Palette Consequence"

      currentRunner.romPaletteAWin = assert(currentApp.wm:createRomPaletteWindow({
        title = "ROM Palette A",
        x = 36,
        y = 48,
      }), "expected ROM palette A")
      currentRunner.romPaletteBWin = assert(currentApp.wm:createRomPaletteWindow({
        title = "ROM Palette B",
        x = 36,
        y = 230,
      }), "expected ROM palette B")
      -- Distinct NES codes so retarget visibly changes resolved consumer colors.
      paintPaletteRow(currentRunner.romPaletteAWin, 0, { "0F", "16", "27", "36" })
      paintPaletteRow(currentRunner.romPaletteBWin, 0, { "0F", "12", "21", "30" })

      currentRunner.staticArtWin = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Static Palette Consumer",
        x = 280,
        y = 48,
        cols = 6,
        rows = 6,
        zoom = 2,
      }), "expected static art")
      currentRunner.spriteArtWin = assert(currentApp.wm:createSpriteWindow({
        animated = false,
        title = "Sprite Palette Consumer",
        x = 280,
        y = 230,
        cols = 6,
        rows = 6,
        zoom = 2,
      }), "expected sprite art")

      -- Fixture OAM sits on palette B's source badge; park it so dest→B drops hit B.
      local oam = currentRunner.oamFixtureWin
      if oam then
        oam.x = 520
        oam.y = 280
      end

      currentApp.wm:setFocus(currentRunner.romPaletteAWin)
    end),
    pause("Observe palette fixtures", 0.4),
  }

  -- Static art: badge-drag A, assert winId + resolved codes match A.
  H.appendBadgeDragLink(
    steps,
    "Badge-drag palette A onto static art",
    "romPaletteAWin",
    "palette_source",
    "staticArtWin",
    "layout_palette"
  )
  steps[#steps + 1] = call("Assert static art linked to A with A's colors", function(_, currentApp, currentRunner)
    local staticWin = H.requireRunnerWindow(currentRunner, "staticArtWin")
    local palA = H.requireRunnerWindow(currentRunner, "romPaletteAWin")
    assert(H.activeLayerPaletteWinId(staticWin) == palA._id, "expected static linked to palette A")
    local layer = staticWin.layers[1]
    local codes = H.assertLayerPaletteCodesMatchWindow(currentApp, layer, palA, 1)
    assert(codes[2] == "16", "expected static consumer to see palette A code 16")
  end)
  steps[#steps + 1] = pause("Observe static art following palette A", 0.3)

  -- Retarget static -> B via destination badge drag.
  H.appendBadgeDragLink(
    steps,
    "Retarget static art badge onto palette B",
    "staticArtWin",
    "layout_palette",
    "romPaletteBWin",
    "palette_source"
  )
  steps[#steps + 1] = call("Assert static art retarget follows palette B colors", function(_, currentApp, currentRunner)
    local staticWin = H.requireRunnerWindow(currentRunner, "staticArtWin")
    local palB = H.requireRunnerWindow(currentRunner, "romPaletteBWin")
    assert(H.activeLayerPaletteWinId(staticWin) == palB._id, "expected static linked to palette B")
    local codes = H.assertLayerPaletteCodesMatchWindow(currentApp, staticWin.layers[1], palB, 1)
    assert(codes[2] == "12", "expected static consumer to see palette B code 12 after retarget")
  end)
  steps[#steps + 1] = pause("Observe static art following palette B", 0.3)

  steps[#steps + 1] = keyPress("Undo palette retarget", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette undo", 0.2)
  steps[#steps + 1] = call("Assert undo restored palette A colors on static art", function(_, currentApp, currentRunner)
    local staticWin = H.requireRunnerWindow(currentRunner, "staticArtWin")
    local palA = H.requireRunnerWindow(currentRunner, "romPaletteAWin")
    assert(H.activeLayerPaletteWinId(staticWin) == palA._id, "expected undo back to palette A")
    local codes = H.assertLayerPaletteCodesMatchWindow(currentApp, staticWin.layers[1], palA, 1)
    assert(codes[2] == "16", "expected undo to restore palette A codes")
  end)
  steps[#steps + 1] = keyPress("Redo palette retarget", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette redo", 0.2)
  steps[#steps + 1] = call("Assert redo restored palette B colors on static art", function(_, currentApp, currentRunner)
    local staticWin = H.requireRunnerWindow(currentRunner, "staticArtWin")
    local palB = H.requireRunnerWindow(currentRunner, "romPaletteBWin")
    assert(H.activeLayerPaletteWinId(staticWin) == palB._id, "expected redo to palette B")
    H.assertLayerPaletteCodesMatchWindow(currentApp, staticWin.layers[1], palB, 1)
  end)

  -- Live mutation on linked palette must flow to consumer resolution.
  steps[#steps + 1] = call("Mutate linked palette B code while static is linked", function(_, _, currentRunner)
    local palB = H.requireRunnerWindow(currentRunner, "romPaletteBWin")
    currentRunner.paletteBBeforeMutate = palB.codes2D[0][1]
    palB.codes2D[0][1] = "2A"
  end)
  steps[#steps + 1] = pause("Observe palette B mutation", 0.25)
  steps[#steps + 1] = call("Assert static art resolves mutated palette B code", function(_, currentApp, currentRunner)
    local staticWin = H.requireRunnerWindow(currentRunner, "staticArtWin")
    local palB = H.requireRunnerWindow(currentRunner, "romPaletteBWin")
    local codes = H.assertLayerPaletteCodesMatchWindow(currentApp, staticWin.layers[1], palB, 1)
    assert(codes[2] == "2A", "expected live palette mutation to reach consumer")
  end)

  -- Sprite art path.
  H.appendBadgeDragLink(
    steps,
    "Badge-drag palette A onto sprite art",
    "romPaletteAWin",
    "palette_source",
    "spriteArtWin",
    "layout_palette"
  )
  steps[#steps + 1] = call("Assert sprite art linked to A with A's colors", function(_, currentApp, currentRunner)
    local spriteWin = H.requireRunnerWindow(currentRunner, "spriteArtWin")
    local palA = H.requireRunnerWindow(currentRunner, "romPaletteAWin")
    assert(H.activeLayerPaletteWinId(spriteWin) == palA._id, "expected sprite linked to palette A")
    H.assertLayerPaletteCodesMatchWindow(currentApp, spriteWin.layers[1], palA, 1)
  end)

  -- PPU palette slot.
  H.appendBadgeDragLink(
    steps,
    "Badge-drag palette A onto PPU palette slot",
    "romPaletteAWin",
    "palette_source",
    "ppuFixtureWin",
    "ppu_palette"
  )
  steps[#steps + 1] = call("Assert PPU active layer linked to A with A's colors", function(_, currentApp, currentRunner)
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    local palA = H.requireRunnerWindow(currentRunner, "romPaletteAWin")
    assert(H.activeLayerPaletteWinId(ppu) == palA._id, "expected PPU linked to palette A")
    local li = (ppu.getActiveLayerIndex and ppu:getActiveLayerIndex()) or ppu.activeLayer or 1
    H.assertLayerPaletteCodesMatchWindow(currentApp, ppu.layers[li], palA, 1)
  end)
  steps[#steps + 1] = pause("Observe PPU following palette A", 0.3)

  -- Click-to-focus still works on a linked badge.
  steps[#steps + 1] = call("Minimize palette A before PPU pivot click", H.minimizeWindowByKey("romPaletteAWin"))
  steps[#steps + 1] = call("Cover stack with palette B before pivot restore", H.bringWindowToFrontByKey("romPaletteBWin"))
  H.appendClickPivotHandle(steps, "Click PPU palette badge to restore palette A", "ppuFixtureWin", "ppu_palette")
  steps[#steps + 1] = call("Assert pivot restored palette A", H.assertWindowMinimized("romPaletteAWin", false))
  steps[#steps + 1] = call("Assert pivot focused palette A", H.assertFocusedWindow("romPaletteAWin"))

  -- Source remove-all clears remaining consumers of palette A.
  H.appendClickPaletteHandle(steps, "Open palette A source badge menu", "romPaletteAWin", "palette_source")
  appendClick(steps, "Remove all palette A links", H.paletteLinkMenuRowByText("Remove all links"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.28,
  })
  steps[#steps + 1] = call("Assert palette A remove-all cleared consumers", function(_, _, currentRunner)
    local palA = H.requireRunnerWindow(currentRunner, "romPaletteAWin")
    local spriteWin = H.requireRunnerWindow(currentRunner, "spriteArtWin")
    local ppu = H.requireRunnerWindow(currentRunner, "ppuFixtureWin")
    assert(H.activeLayerPaletteWinId(spriteWin) ~= palA._id, "expected sprite unlinked from palette A")
    assert(H.activeLayerPaletteWinId(ppu) ~= palA._id, "expected PPU unlinked from palette A")
    -- Static remains on B after redo; remove-all on A must not touch it.
    assert(H.activeLayerPaletteWinId(H.requireRunnerWindow(currentRunner, "staticArtWin"))
      == H.requireRunnerWindow(currentRunner, "romPaletteBWin")._id, "expected static still on palette B")
  end)

  -- Same-side source→source: relink sprite to A, then drag A onto B (move, A emptied).
  H.appendBadgeDragLink(
    steps,
    "Badge-drag palette A onto sprite art for source move",
    "romPaletteAWin",
    "palette_source",
    "spriteArtWin",
    "layout_palette"
  )
  H.appendBadgeDragLink(
    steps,
    "Move all palette A consumers onto palette B source badge",
    "romPaletteAWin",
    "palette_source",
    "romPaletteBWin",
    "palette_source"
  )
  steps[#steps + 1] = call("Assert source-to-source moved sprite onto B and emptied A", function(_, currentApp, currentRunner)
    local spriteWin = H.requireRunnerWindow(currentRunner, "spriteArtWin")
    local palA = H.requireRunnerWindow(currentRunner, "romPaletteAWin")
    local palB = H.requireRunnerWindow(currentRunner, "romPaletteBWin")
    assert(H.activeLayerPaletteWinId(spriteWin) == palB._id, "expected sprite moved onto palette B")
    assert(H.activeLayerPaletteWinId(H.requireRunnerWindow(currentRunner, "staticArtWin")) == palB._id, "expected static still on B")
    local PaletteLinkController = require("controllers.palette.palette_link_controller")
    assert(#PaletteLinkController.getLinkedTargetsForPalette(currentApp.wm, palA) == 0, "expected palette A emptied")
    local codes = H.assertLayerPaletteCodesMatchWindow(currentApp, spriteWin.layers[1], palB, 1)
    assert(codes[2] == "2A", "expected sprite to resolve palette B after source move")
  end)
  steps[#steps + 1] = keyPress("Undo palette source move", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette source-move undo", 0.2)
  steps[#steps + 1] = call("Assert undo restored sprite onto palette A", function(_, currentApp, currentRunner)
    local spriteWin = H.requireRunnerWindow(currentRunner, "spriteArtWin")
    local palA = H.requireRunnerWindow(currentRunner, "romPaletteAWin")
    assert(H.activeLayerPaletteWinId(spriteWin) == palA._id, "expected undo back to palette A")
    H.assertLayerPaletteCodesMatchWindow(currentApp, spriteWin.layers[1], palA, 1)
  end)

  -- Same-side dest→dest: sprite (A) onto static (B) moves A onto static and unlinks sprite.
  H.appendBadgeDragLink(
    steps,
    "Move sprite dest palette badge onto static dest badge",
    "spriteArtWin",
    "layout_palette",
    "staticArtWin",
    "layout_palette"
  )
  steps[#steps + 1] = call("Assert dest-to-dest moved palette A onto static and unlinked sprite", function(_, currentApp, currentRunner)
    local staticWin = H.requireRunnerWindow(currentRunner, "staticArtWin")
    local spriteWin = H.requireRunnerWindow(currentRunner, "spriteArtWin")
    local palA = H.requireRunnerWindow(currentRunner, "romPaletteAWin")
    assert(H.activeLayerPaletteWinId(staticWin) == palA._id, "expected static replaced onto palette A")
    assert(H.activeLayerPaletteWinId(spriteWin) ~= palA._id, "expected sprite unlinked after dest move")
    local codes = H.assertLayerPaletteCodesMatchWindow(currentApp, staticWin.layers[1], palA, 1)
    assert(codes[2] == "16", "expected static to resolve palette A after dest move")
  end)

  steps[#steps + 1] = pause("Scenario complete", 0.4)
  return steps
end

return {
  rom_palette_link_consequences = {
    title = "ROM Palette Link Consequences",
    build = buildRomPaletteLinkConsequencesScenario,
  },
}
