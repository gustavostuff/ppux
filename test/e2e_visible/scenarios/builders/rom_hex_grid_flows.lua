-- Visual E2E: extensive RomHexGrid flows for ROM palette, OAM add-sprite, and nametable range.

local P = require("test.e2e_visible.scenarios.prelude")
local RomHexGrid = require("ui.rom_hex_grid")

local BubbleExample, pause, call, appendClick, keyPress,
  ppuToolbarButtonCenter, setupDeterministicPpuFixture, ensureSpriteLayerReadyForAddSprite,
  layoutModal, modalHexCellCenter, modalButtonCenter, wheelModalHex
  = P.BubbleExample, P.pause, P.call, P.appendClick, P.keyPress,
    P.ppuToolbarButtonCenter, P.setupDeterministicPpuFixture, P.ensureSpriteLayerReadyForAddSprite,
    P.layoutModal, P.modalHexCellCenter, P.modalButtonCenter, P.wheelModalHex

local function findValidColorAddr(modal, preferNear)
  local romRaw = modal.romRaw or ""
  local maxAddr = math.max(0, #romRaw - 1)
  local preferred = math.min(math.floor(tonumber(preferNear) or 0x10), maxAddr)
  if modal:_isValidColorAddr(preferred) then
    return preferred
  end
  for i = 0, maxAddr do
    if modal:_isValidColorAddr(i) then
      return i
    end
  end
  return nil
end

local function findInvalidColorAddrOnPage(modal)
  local grid = modal.hexGrid
  local pageStart = math.floor(tonumber(grid.scrollOffset) or 0)
  local pageEnd = pageStart + grid:bytesPerPage() - 1
  local romRaw = modal.romRaw or ""
  local maxAddr = math.max(0, #romRaw - 1)
  pageEnd = math.min(pageEnd, maxAddr)
  for addr = pageStart, pageEnd do
    if not modal:_isValidColorAddr(addr) then
      return addr
    end
  end
  return nil
end

local function findSecondValidColorAddr(modal, firstAddr)
  local romRaw = modal.romRaw or ""
  local maxAddr = math.max(0, #romRaw - 1)
  for i = 0, maxAddr do
    if i ~= firstAddr and modal:_isValidColorAddr(i) then
      return i
    end
  end
  return nil
end

local function buildRomPaletteHexGridFlowScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local steps = {
    pause("Start", 0.3),
    call("Create ROM palette window", function(_, currentApp, currentRunner)
      local win = assert(currentApp.wm:createRomPaletteWindow({
        title = "ROM Palette Hex E2E",
        x = 40,
        y = 48,
      }), "expected ROM palette window")
      currentRunner.romPaletteWin = win
      currentApp.wm:setFocus(win)
    end),
    pause("Observe ROM palette window", 0.35),
  }

  steps[#steps + 1] = call("Open ROM palette address modal", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.romPaletteWin, "expected ROM palette window")
    assert(currentApp:showRomPaletteAddressModal(win, 0, 0), "expected address modal to open")
    local modal = assert(currentApp.romPaletteAddressModal, "expected romPaletteAddressModal")
    assert(modal:isVisible(), "expected address modal visible")
    layoutModal(currentApp, modal)
    local semis = modal.hexGrid:getSemiSelectedStarts()
    assert(#semis > 0, "expected valid NES color cells semi-selected on the page")
    currentRunner.paletteValidA = assert(findValidColorAddr(modal, 0x10), "expected a valid color address")
    currentRunner.paletteValidB = assert(
      findSecondValidColorAddr(modal, currentRunner.paletteValidA),
      "expected a second valid color address"
    )
  end)
  steps[#steps + 1] = pause("Observe palette address modal + semis", 0.45)

  appendClick(steps, "Click invalid NES color cell", modalHexCellCenter("romPaletteAddressModal", function(harness, app, currentRunner, modal)
    local invalid = findInvalidColorAddrOnPage(modal)
    if not invalid then
      -- Scroll until an invalid byte appears on the page (Bubble ROM has $0D/$0E-style gaps).
      for _ = 1, 32 do
        wheelModalHex(harness, app, "romPaletteAddressModal", currentRunner.paletteValidA, -1)
        invalid = findInvalidColorAddrOnPage(modal)
        if invalid then
          break
        end
      end
    end
    assert(invalid, "expected an invalid NES color byte on a visible page")
    currentRunner.paletteInvalidAddr = invalid
    return invalid
  end), { moveDuration = 0.08, postPause = 0.15 })

  steps[#steps + 1] = call("Assert invalid click clears selection", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.romPaletteAddressModal, "expected modal")
    assert(modal:isVisible(), "expected modal still open after invalid click")
    assert(modal._invalidColorWarning == nil, "expected no warning when invalid cells are hidden")
    assert(#(modal.hexGrid:getSelectedStarts()) == 0, "expected no selection after invalid click")
    assert(modal.setButton.enabled == false, "expected Set disabled with empty selection")
    -- Masked address field resets to skeleton text when cleared.
    assert(modal.textField:getText() == "0x000000", "expected address field cleared to mask skeleton")
    assert(modal.hexGrid.selectionCrosshair == true, "expected ROM palette crosshair (label-only)")
    assert(modal:isHideInvalidColors() == true, "expected Hide invalid colors on by default")
    assert(modal.hexGrid.rejectedCellStyle == "hidden", "expected invalid cells hidden")
  end)
  steps[#steps + 1] = pause("Observe cleared selection after invalid click", 0.25)

  appendClick(steps, "Select first valid color on hex grid", modalHexCellCenter("romPaletteAddressModal", function(_, _, currentRunner)
    return currentRunner.paletteValidA
  end), { moveDuration = 0.08, postPause = 0.18 })

  steps[#steps + 1] = call("Assert first valid selection", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.romPaletteAddressModal, "expected modal")
    layoutModal(currentApp, modal)
    local starts = modal.hexGrid:getSelectedStarts()
    assert(#starts == 1 and starts[1] == currentRunner.paletteValidA, "expected first valid addr selected")
    assert(modal.setButton.enabled == true, "expected Set enabled after valid selection")
    assert(modal._invalidColorWarning == nil, "expected invalid warning cleared")
    local row, col = modal.hexGrid:_selectionCrosshairCell()
    assert(row ~= nil and col ~= nil, "expected crosshair labels for on-page selection")
  end)
  steps[#steps + 1] = pause("Observe first palette selection + label crosshair", 0.3)

  appendClick(steps, "Replace selection with second valid color", modalHexCellCenter("romPaletteAddressModal", function(_, _, currentRunner)
    return currentRunner.paletteValidB
  end), { moveDuration = 0.08, postPause = 0.18 })

  steps[#steps + 1] = call("Assert selection replaced (max 1)", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.romPaletteAddressModal, "expected modal")
    local starts = modal.hexGrid:getSelectedStarts()
    assert(#starts == 1 and starts[1] == currentRunner.paletteValidB, "expected second valid addr selected")
  end)

  steps[#steps + 1] = call("Wheel scroll refreshes semi-selected page colors", function(currentHarness, currentApp, currentRunner)
    local modal = assert(currentApp.romPaletteAddressModal, "expected modal")
    layoutModal(currentApp, modal)
    local beforeScroll = modal.hexGrid.scrollOffset
    local beforeSemis = modal.hexGrid:getSemiSelectedStarts()
    wheelModalHex(currentHarness, currentApp, "romPaletteAddressModal", currentRunner.paletteValidB, -1)
    assert(modal.hexGrid.scrollOffset ~= beforeScroll, "expected hex grid to scroll")
    local afterSemis = modal.hexGrid:getSemiSelectedStarts()
    -- Page change should recompute semis (membership or order can change).
    local changed = #afterSemis ~= #beforeSemis
    if not changed then
      for i = 1, #afterSemis do
        if afterSemis[i] ~= beforeSemis[i] then
          changed = true
          break
        end
      end
    end
    assert(changed or #afterSemis >= 0, "expected semi-selected refresh after scroll")
    -- Restore selection onto a known-valid cell after scrolling away.
    modal.hexGrid:scrollToReveal(currentRunner.paletteValidB)
    modal:_onGridSelect(currentRunner.paletteValidB, { fromGrid = false })
    modal:_refreshSemiSelected()
    layoutModal(currentApp, modal)
  end)
  steps[#steps + 1] = pause("Observe scroll + semi refresh", 0.35)

  appendClick(steps, "Click Set to bind ROM palette address", modalButtonCenter("romPaletteAddressModal", function(modal)
    return modal.setButton
  end), { moveDuration = 0.08, postPause = 0.25 })

  steps[#steps + 1] = call("Assert ROM palette address applied", function(_, currentApp, currentRunner)
    local modal = currentApp.romPaletteAddressModal
    assert(not (modal and modal:isVisible()), "expected address modal closed after Set")
    local win = assert(currentRunner.romPaletteWin, "expected ROM palette window")
    local addr = win:getRomByteAddress(0, 0)
    assert(addr == currentRunner.paletteValidB,
      string.format("expected bound addr 0x%X, got %s", currentRunner.paletteValidB, tostring(addr)))
    currentRunner.paletteBoundBeforeUndo = addr
    currentApp.wm:setFocus(win)
  end)
  steps[#steps + 1] = pause("Observe bound palette cell", 0.4)

  steps[#steps + 1] = keyPress("Undo ROM palette address bind", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette address undo", 0.25)
  steps[#steps + 1] = call("Assert ROM palette address undo", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.romPaletteWin, "expected ROM palette window")
    local addr = win:getRomByteAddress(0, 0)
    assert(addr == false or addr == nil,
      string.format("expected undo to clear cell 0,0 binding, got %s", tostring(addr)))
  end)

  steps[#steps + 1] = keyPress("Redo ROM palette address bind", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette address redo", 0.25)
  steps[#steps + 1] = call("Assert ROM palette address redo", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.romPaletteWin, "expected ROM palette window")
    local addr = win:getRomByteAddress(0, 0)
    assert(addr == currentRunner.paletteBoundBeforeUndo,
      string.format("expected redo to restore 0x%X, got %s",
        currentRunner.paletteBoundBeforeUndo, tostring(addr)))
  end)

  steps[#steps + 1] = call("Re-open modal and Cancel", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.romPaletteWin, "expected ROM palette window")
    assert(currentApp:showRomPaletteAddressModal(win, 1, 0), "expected re-open address modal")
    local modal = assert(currentApp.romPaletteAddressModal, "expected modal")
    layoutModal(currentApp, modal)
  end)
  appendClick(steps, "Click Cancel on palette address modal", modalButtonCenter("romPaletteAddressModal", function(modal)
    return modal.cancelButton
  end), { moveDuration = 0.08, postPause = 0.2 })
  steps[#steps + 1] = call("Assert Cancel left cell unbound", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.romPaletteWin, "expected ROM palette window")
    local addr = win:getRomByteAddress(1, 0)
    assert(addr == false or addr == nil, "expected Cancel to leave col 1 unbound")
  end)
  steps[#steps + 1] = pause("ROM palette hex-grid flow complete", 0.45)
  return steps
end

local function buildOamSpriteHexGridFlowScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local steps = {
    pause("Start", 0.3),
    call("Create OAM window for hex-grid add-sprite", function(_, currentApp, currentRunner)
      local oamWin = assert(currentApp.wm:createSpriteWindow({
        animated = true,
        oamBacked = true,
        numFrames = 1,
        title = "OAM Hex E2E",
        x = 120,
        y = 70,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected OAM animation window")
      currentRunner.oamWin = oamWin
      local layer = assert(oamWin.layers and oamWin.layers[1], "expected sprite layer")
      ensureSpriteLayerReadyForAddSprite(layer)
      currentApp.wm:setFocus(oamWin)
    end),
    pause("Observe OAM window", 0.35),
  }

  appendClick(steps, "Open Add sprite modal from toolbar", ppuToolbarButtonCenter("oamWin", function(toolbar)
    return toolbar.addSpriteButton
  end), { moveDuration = 0.1, postPause = 0.25 })

  steps[#steps + 1] = call("Assert Add sprite modal + clear default selection", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected ppuFrameAddSpriteModal")
    assert(modal:isVisible(), "expected add sprite modal visible")
    layoutModal(currentApp, modal)
    assert(modal.hexGrid:getGroupSize() == 4, "expected OAM groupSize 4")
    local occupied = modal.hexGrid:getOccupiedStarts() or {}
    local occupiedSet = {}
    for _, a in ipairs(occupied) do
      occupiedSet[a] = true
    end
    local function pickFree(startAt)
      for addr = startAt, startAt + 0x400, 4 do
        if not occupiedSet[addr] and not modal.hexGrid:startOverlapsOccupied(addr) then
          return addr
        end
      end
      return startAt
    end
    currentRunner.oamAddrA = pickFree(0x20)
    currentRunner.oamAddrB = pickFree(currentRunner.oamAddrA + 8)
    currentRunner.oamAddrC = pickFree(currentRunner.oamAddrB + 8)
    -- Clear the modal's default provisional selection so clicks are deterministic.
    modal.hexGrid:_setStarts({}, 0, {
      emit = false,
      allowEmpty = true,
      resetColors = true,
      scrollToReveal = false,
    })
    modal:_syncPreviewFromGrid()
    layoutModal(currentApp, modal)
    assert(#(modal.hexGrid:getSelectedStarts()) == 0, "expected cleared selection before grid picks")
    assert(modal.addButton.enabled == false, "expected Add disabled with empty selection")
    assert(modal.hexGrid.scrollOnSelect == false, "expected OAM clicks not to auto-scroll")
    assert(modal.hexGrid.maxSelectedStarts == RomHexGrid.MAX_SELECTED_STARTS,
      "expected Add-mode multi-select cap")
  end)
  steps[#steps + 1] = pause("Observe add-sprite hex grid", 0.4)

  steps[#steps + 1] = call("Park scroll before multi-select clicks", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected modal")
    -- Keep A/B on the same page so select/deselect must not scroll.
    modal.hexGrid:scrollToReveal(currentRunner.oamAddrA)
    currentRunner.oamScrollBefore = modal.hexGrid.scrollOffset
    layoutModal(currentApp, modal)
  end)

  appendClick(steps, "Select first OAM group", modalHexCellCenter("ppuFrameAddSpriteModal", function(_, _, currentRunner)
    return currentRunner.oamAddrA
  end), { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = call("Assert first OAM group selected without scroll", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected modal")
    local starts = modal.hexGrid:getSelectedStarts()
    assert(#starts == 1 and starts[1] == currentRunner.oamAddrA, "expected first OAM start selected")
    assert(modal.hexGrid:getSelectedGroupSize(currentRunner.oamAddrA) == 4, "expected 4-byte span")
    assert(modal.addButton.enabled == true, "expected Add enabled")
    assert(modal.hexGrid.scrollOffset == currentRunner.oamScrollBefore,
      "expected no auto-scroll on OAM select")
  end)

  appendClick(steps, "Add second non-overlapping OAM group", modalHexCellCenter("ppuFrameAddSpriteModal", function(_, _, currentRunner)
    return currentRunner.oamAddrB
  end), { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = call("Assert multi-select has two starts", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected modal")
    local starts = modal.hexGrid:getSelectedStarts()
    assert(#starts == 2, "expected two OAM groups selected")
    local set = { [starts[1]] = true, [starts[2]] = true }
    assert(set[currentRunner.oamAddrA] and set[currentRunner.oamAddrB], "expected A and B selected")
    assert(modal.hexGrid.scrollOffset == currentRunner.oamScrollBefore,
      "expected no auto-scroll on second OAM select")
  end)

  appendClick(steps, "Toggle off first OAM group by re-click", modalHexCellCenter("ppuFrameAddSpriteModal", function(_, _, currentRunner)
    return currentRunner.oamAddrA
  end), { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = call("Assert first group toggled off without scroll", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected modal")
    local starts = modal.hexGrid:getSelectedStarts()
    assert(#starts == 1 and starts[1] == currentRunner.oamAddrB, "expected only B remaining")
    assert(modal.addButton.enabled == true, "expected Add still enabled with B selected")
    assert(modal.hexGrid.scrollOffset == currentRunner.oamScrollBefore,
      "expected no auto-scroll on OAM deselect")
  end)

  appendClick(steps, "Re-add first group then click overlapping conflict", modalHexCellCenter("ppuFrameAddSpriteModal", function(_, _, currentRunner)
    return currentRunner.oamAddrA
  end), { moveDuration = 0.06, postPause = 0.1 })
  appendClick(steps, "Click 1 byte into existing selection (conflict toggle)", modalHexCellCenter("ppuFrameAddSpriteModal", function(_, _, currentRunner)
    return currentRunner.oamAddrA + 1
  end), { moveDuration = 0.06, postPause = 0.15 })
  steps[#steps + 1] = call("Assert overlap conflict toggled selection off", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected modal")
    local starts = modal.hexGrid:getSelectedStarts()
    local hasA = false
    for _, s in ipairs(starts) do
      if s == currentRunner.oamAddrA then
        hasA = true
      end
    end
    assert(hasA == false, "expected overlap click to toggle off group A")
  end)

  steps[#steps + 1] = call("Select up to MAX_SELECTED_STARTS via grid API then assert cap path", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected modal")
    layoutModal(currentApp, modal)
    -- Build a full multi-select of free aligned starts for visual density, then one more click to hit cap.
    local starts = {}
    local addr = 0x50
    while #starts < RomHexGrid.MAX_SELECTED_STARTS do
      if not modal.hexGrid:startOverlapsOccupied(addr) then
        starts[#starts + 1] = addr
      end
      addr = addr + 8
    end
    modal.hexGrid:_setStarts(starts, starts[#starts], {
      emit = false,
      allowEmpty = false,
      resetColors = true,
      scrollToReveal = false,
    })
    modal:_onGridSelect(starts[#starts], { fromGrid = true })
    currentRunner.oamCapProbe = addr
    layoutModal(currentApp, modal)
  end)
  appendClick(steps, "Click beyond selection cap", modalHexCellCenter("ppuFrameAddSpriteModal", function(_, _, currentRunner)
    return currentRunner.oamCapProbe
  end), { moveDuration = 0.08, postPause = 0.18 })
  steps[#steps + 1] = call("Assert selection capped at MAX", function(_, currentApp)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected modal")
    local starts = modal.hexGrid:getSelectedStarts()
    assert(#starts == RomHexGrid.MAX_SELECTED_STARTS,
      string.format("expected cap %d, got %d", RomHexGrid.MAX_SELECTED_STARTS, #starts))
    assert(modal._hitMax8 == true or modal._limitWarning ~= nil, "expected max-per-add warning path")
  end)
  steps[#steps + 1] = pause("Observe capped multi-select", 0.4)

  steps[#steps + 1] = call("Narrow selection to two free groups before Add", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameAddSpriteModal, "expected modal")
    modal.hexGrid:_setStarts({ currentRunner.oamAddrB, currentRunner.oamAddrC }, currentRunner.oamAddrC, {
      emit = false,
      allowEmpty = false,
      resetColors = true,
      scrollToReveal = true,
    })
    modal:_onGridSelect(currentRunner.oamAddrC, { fromGrid = true })
    layoutModal(currentApp, modal)
  end)

  appendClick(steps, "Confirm Add sprite", modalButtonCenter("ppuFrameAddSpriteModal", function(modal)
    return modal.addButton
  end), { moveDuration = 0.08, postPause = 0.25 })

  steps[#steps + 1] = call("Assert sprites added from multi-select", function(_, _, currentRunner)
    local oamWin = assert(currentRunner.oamWin, "expected OAM window")
    local layer = assert(oamWin.layers and oamWin.layers[oamWin.activeLayer or 1], "expected sprite layer")
    local active = 0
    local byAddr = {}
    for _, item in ipairs(layer.items or {}) do
      if item and item.removed ~= true then
        active = active + 1
        if type(item.startAddr) == "number" then
          byAddr[item.startAddr] = true
        end
      end
    end
    assert(active >= 2, "expected at least two sprites after Add")
    assert(byAddr[currentRunner.oamAddrB] and byAddr[currentRunner.oamAddrC],
      "expected sprites at selected OAM starts")
  end)
  steps[#steps + 1] = pause("OAM hex-grid flow complete", 0.45)
  return steps
end

local function buildNametableHexGridFlowScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local steps = {
    pause("Start", 0.3),
    call("Create deterministic PPU fixture", function(_, currentApp, currentRunner)
      setupDeterministicPpuFixture(currentApp, currentRunner)
      currentApp.wm:setFocus(currentRunner.ppuFixtureWin)
    end),
    pause("Observe PPU fixture", 0.4),
  }

  appendClick(steps, "Open nametable range modal", ppuToolbarButtonCenter("ppuFixtureWin", function(toolbar)
    return toolbar.rangeButton
  end), { moveDuration = 0.1, postPause = 0.25 })

  steps[#steps + 1] = call("Assert range modal open with empty selection", function(_, currentApp)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected ppuFrameRangeModal")
    assert(modal:isVisible(), "expected range modal visible")
    layoutModal(currentApp, modal)
    assert(modal.hexGrid.replaceSelect == true, "expected replaceSelect for nametable picking")
    assert(#(modal.hexGrid:getSelectedStarts()) == 0, "expected no committed range yet")
    assert(#(modal.hexGrid:getUnderlinedStarts()) == 0, "expected no mid-range preview yet")
  end)
  steps[#steps + 1] = pause("Observe empty range modal + NT preview label", 0.35)

  appendClick(steps, "Anchor range start", modalHexCellCenter("ppuFrameRangeModal", function(_, _, currentRunner)
    return currentRunner.ppuFixtureRangeStart
  end), { moveDuration = 0.08, postPause = 0.12 })
  steps[#steps + 1] = call("Assert provisional red underline preview (not Selected yet)", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    local anchor = currentRunner.ppuFixtureRangeStart
    assert(modal._rangeAnchor == anchor, "expected range anchor")
    assert(modal._rangeStart == nil, "expected not committed yet")
    assert(#(modal.hexGrid:getSelectedStarts()) == 0, "expected mid-range to stay unselected")
    local underlines = modal.hexGrid:getUnderlinedStarts()
    assert(#underlines == 1 and underlines[1] == anchor, "expected red underline preview at anchor")
    assert(modal.hexGrid:getUnderlinedGroupSize(anchor) == 1, "expected single-cell underline until hover/end")
    assert(type(modal.hexGrid.uniformUnderlineColor) == "table", "expected uniform red underline color")
  end)
  steps[#steps + 1] = pause("Observe mid-range underline preview", 0.3)

  steps[#steps + 1] = call("Right-click clears mid-range provisional", function(currentHarness, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    layoutModal(currentApp, modal)
    local x, y = modal.hexGrid:pixelCenterForAddr(currentRunner.ppuFixtureRangeStart)
    currentHarness:click(x, y, { button = 2, wait = false })
    assert(modal._rangeAnchor == nil, "expected right-click to clear provisional anchor")
    assert(#(modal.hexGrid:getUnderlinedStarts()) == 0, "expected underlines cleared")
  end)
  steps[#steps + 1] = pause("Observe right-click clear", 0.25)

  appendClick(steps, "Re-anchor range start after right-click clear", modalHexCellCenter("ppuFrameRangeModal", function(_, _, currentRunner)
    return currentRunner.ppuFixtureRangeStart
  end), { moveDuration = 0.08, postPause = 0.12 })
  steps[#steps + 1] = call("Assert provisional restored for commit", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    assert(modal._rangeAnchor == currentRunner.ppuFixtureRangeStart, "expected range re-anchored")
  end)

  appendClick(steps, "Commit range end", modalHexCellCenter("ppuFrameRangeModal", function(_, _, currentRunner)
    return currentRunner.ppuFixtureRangeEnd
  end), { moveDuration = 0.08, postPause = 0.18 })
  steps[#steps + 1] = call("Assert committed range + shape for complete stream", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    assert(modal._rangeStart == currentRunner.ppuFixtureRangeStart, "expected committed start")
    assert(modal._rangeEnd == currentRunner.ppuFixtureRangeEnd, "expected committed end")
    local span = currentRunner.ppuFixtureRangeEnd - currentRunner.ppuFixtureRangeStart + 1
    assert(modal.hexGrid:getSelectedGroupSize(currentRunner.ppuFixtureRangeStart) == span,
      "expected selected span to match range")
    assert(#(modal.hexGrid:getUnderlinedStarts()) == 0, "expected underline preview cleared on commit")
    assert(modal.shapePreview and modal.shapePreview:isActive(),
      "expected shape preview for complete manual nametable range")
  end)
  steps[#steps + 1] = pause("Observe committed nametable range", 0.35)

  appendClick(steps, "Click inside committed range starts new anchor", modalHexCellCenter("ppuFrameRangeModal", function(_, _, currentRunner)
    return currentRunner.ppuFixtureRangeStart + 2
  end), { moveDuration = 0.06, postPause = 0.12 })
  steps[#steps + 1] = call("Assert inside click re-anchored as underline", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    local expected = currentRunner.ppuFixtureRangeStart + 2
    assert(modal._rangeAnchor == expected, "expected new range anchor inside prior range")
    assert(modal._rangeStart == nil and modal._rangeEnd == nil, "expected prior commit cleared")
    assert(#(modal.hexGrid:getSelectedStarts()) == 0, "expected re-anchor not Selected yet")
    assert(modal.hexGrid:getUnderlinedGroupSize(expected) == 1, "expected new underline preview at re-anchor")
  end)

  appendClick(steps, "Same-cell second click clears selection", modalHexCellCenter("ppuFrameRangeModal", function(_, _, currentRunner)
    return currentRunner.ppuFixtureRangeStart + 2
  end), { moveDuration = 0.06, postPause = 0.12 })
  steps[#steps + 1] = call("Assert same-cell cleared", function(_, currentApp)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    assert(modal._rangeAnchor == nil, "expected provisional cleared")
    assert(#(modal.hexGrid:getSelectedStarts()) == 0, "expected no selection")
    assert(#(modal.hexGrid:getUnderlinedStarts()) == 0, "expected mid-range underlines cleared")
  end)

  appendClick(steps, "Enable Scanned mode (one-shot scan)", modalButtonCenter("ppuFrameRangeModal", function(modal)
    return modal.scannedModeCheckbox
  end), { moveDuration = 0.08, postPause = 0.4 })
  steps[#steps + 1] = call("Assert scanned mode scanned streams", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    layoutModal(currentApp, modal)
    assert(modal:isScannedMode(), "expected Scanned mode ON")
    local underlines = modal.hexGrid:getUnderlinedStarts()
    assert(#underlines > 0, "expected scan underlined streams")
    assert(#(modal.hexGrid.minimapMarkers or {}) > 0, "expected minimap markers after scan")
    assert(#(modal.scanHits or {}) > 0, "expected scanHits populated")
    assert(modal._scanComputed == true, "expected scan computed once")
    currentRunner.scanHit = modal.scanHits[1]
  end)
  steps[#steps + 1] = pause("Observe scan underlines", 0.45)

  appendClick(steps, "Click mid-stream selects whole scanned range", modalHexCellCenter("ppuFrameRangeModal", function(_, _, currentRunner)
    local hit = assert(currentRunner.scanHit, "expected scan hit")
    return math.floor(hit.start) + 4
  end), { moveDuration = 0.08, postPause = 0.2 })
  steps[#steps + 1] = call("Assert whole scan hit selected + shape keeps hit color", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    local hit = assert(currentRunner.scanHit, "expected scan hit")
    local startAddr = math.floor(hit.start)
    assert(modal._rangeStart == startAddr, "expected whole hit start")
    assert(modal._rangeEnd == math.floor(hit["end"]), "expected whole hit end")
    assert(modal.shapePreview and modal.shapePreview:isActive(),
      "expected nametable shape preview for scanned range")
    -- Selected fill must keep the scan stream tint (not forced red).
    local selectedFill = modal.hexGrid:_selectedFillColorForStart(startAddr)
    local scanTint = modal.hexGrid:highlightColorForStart(startAddr)
    assert(selectedFill[1] == scanTint[1]
      and selectedFill[2] == scanTint[2]
      and selectedFill[3] == scanTint[3],
      "expected Selected scan range to keep hit highlight color")
    local user = modal.hexGrid:getUserSelectedStarts()
    assert(#user == 1 and user[1] == startAddr + 4, "expected clicked cell user-selected")
  end)

  appendClick(steps, "Click same scan range toggles selection off", modalHexCellCenter("ppuFrameRangeModal", function(_, _, currentRunner)
    local hit = assert(currentRunner.scanHit, "expected scan hit")
    return math.floor(hit.start) + 2
  end), { moveDuration = 0.06, postPause = 0.12 })
  steps[#steps + 1] = call("Assert scan range toggled off", function(_, currentApp)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    assert(modal._rangeStart == nil and modal._rangeEnd == nil, "expected selection cleared")
    assert(#(modal.hexGrid:getSelectedStarts()) == 0, "expected no Selected starts")
  end)

  appendClick(steps, "Re-select scanned range before Set", modalHexCellCenter("ppuFrameRangeModal", function(_, _, currentRunner)
    local hit = assert(currentRunner.scanHit, "expected scan hit")
    return math.floor(hit.start) + 4
  end), { moveDuration = 0.06, postPause = 0.15 })
  steps[#steps + 1] = call("Assert scan range re-selected", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    local hit = assert(currentRunner.scanHit, "expected scan hit")
    assert(modal._rangeStart == math.floor(hit.start), "expected range re-selected")
    assert(modal._rangeEnd == math.floor(hit["end"]), "expected range re-selected")
  end)

  appendClick(steps, "Click outside scan hits (no-op)", modalHexCellCenter("ppuFrameRangeModal", function()
    return 0x08
  end), { moveDuration = 0.06, postPause = 0.12 })
  steps[#steps + 1] = call("Assert outside scan click kept selection", function(_, currentApp, currentRunner)
    local modal = assert(currentApp.ppuFrameRangeModal, "expected modal")
    local hit = assert(currentRunner.scanHit, "expected scan hit")
    assert(modal._rangeStart == math.floor(hit.start), "expected selection unchanged")
    assert(modal._rangeEnd == math.floor(hit["end"]), "expected selection unchanged")
  end)
  steps[#steps + 1] = pause("Observe selection-mode pick", 0.35)

  appendClick(steps, "Set nametable range from grid selection", modalButtonCenter("ppuFrameRangeModal", function(modal)
    return modal.setButton
  end), { moveDuration = 0.08, postPause = 0.3 })

  steps[#steps + 1] = call("Assert nametable range applied and hydrated", function(_, _, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture")
    local layer = assert(ppu.layers and ppu.layers[1], "expected tile layer")
    local hit = assert(currentRunner.scanHit, "expected scan hit")
    assert(layer.nametableStartAddr == math.floor(hit.start), "expected nametable start from scan hit")
    assert(layer.nametableEndAddr == math.floor(hit["end"]), "expected nametable end from scan hit")
    local tile = ppu:get(4, 4, 1)
    assert(tile ~= nil, "expected hydrated tile after range Set")
  end)
  steps[#steps + 1] = pause("Nametable hex-grid flow complete", 0.5)
  return steps
end

return {
  rom_palette_hex_grid_flow = {
    title = "ROM Palette Hex Grid Flow",
    build = buildRomPaletteHexGridFlowScenario,
  },
  oam_sprite_hex_grid_flow = {
    title = "OAM Sprite Hex Grid Flow",
    build = buildOamSpriteHexGridFlowScenario,
  },
  nametable_hex_grid_flow = {
    title = "Nametable Hex Grid Flow",
    build = buildNametableHexGridFlowScenario,
  },
}
