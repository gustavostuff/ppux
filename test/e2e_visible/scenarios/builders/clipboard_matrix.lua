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


local function buildClipboardMatrixScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(assert(BubbleExample.findBankWindow(app), "expected CHR bank window"))
  local staticTileWin = assert(BubbleExample.findStaticWindow(app), "expected static tile window")
  BubbleExample.clearStaticWindow(staticTileWin)

  local steps = {
    pause("Start", 0.35),
    call("Create sprite + PPU clipboard fixture windows", function(currentHarness, currentApp, currentRunner)
      currentRunner.clipboardSpriteWin = assert(currentApp.wm:createSpriteWindow({
        animated = false,
        title = "Clipboard Sprite",
        x = 304,
        y = 184,
        cols = 10,
        rows = 8,
        zoom = 2,
      }), "expected clipboard sprite window")
      currentRunner.clipboardTileDropTargetWin = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Clipboard Tile Drop Target",
        x = 520,
        y = 70,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected clipboard tile target window")
      setupDeterministicPpuFixture(currentApp, currentRunner)
      currentApp.wm:setFocus(staticTileWin)
    end),
    pause("Observe created fixture windows", 0.45),
  }

  local function countTileItems(win)
    local layer = win.layers and win.layers[1] or nil
    local count = 0
    for _, item in pairs(layer and layer.items or {}) do
      if item ~= nil then
        count = count + 1
      end
    end
    return count
  end

  local function cloneTilePixels(tile)
    local out = {}
    for i = 1, 64 do
      out[i] = tile and tile.pixels and tile.pixels[i] or 0
    end
    return out
  end

  local function pixelsEqual(a, b)
    for i = 1, 64 do
      if (a and a[i] or 0) ~= (b and b[i] or 0) then
        return false
      end
    end
    return true
  end

  local function pixelsAreZero(pixels)
    for i = 1, 64 do
      if (pixels and pixels[i] or 0) ~= 0 then
        return false
      end
    end
    return true
  end

  local function countSpritesInLayer(win, layerIndex)
    if not (win and win.layers) then
      return 0
    end
    local idx = tonumber(layerIndex) or 1
    local layer = win.layers[idx]
    return #(layer and layer.items or {})
  end

  local function getEditedTileMap(currentApp, bankIdx, tileIdx)
    if not (currentApp and currentApp.edits and currentApp.edits.banks) then
      return nil
    end
    local bank = currentApp.edits.banks[bankIdx]
    if type(bank) ~= "table" then
      return nil
    end
    return bank[tileIdx]
  end

  appendDrag(steps, "Place source tile A", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, function(h)
    return h:windowCellCenter(staticTileWin, 1, 1)
  end, { dragDuration = 0.12, postPause = 0.2 })

  appendDrag(steps, "Place source tile B", function(h)
    return h:windowCellCenter(srcWin, 1, 0)
  end, function(h)
    return h:windowCellCenter(staticTileWin, 2, 1)
  end, { dragDuration = 0.12, postPause = 0.2 })

  steps[#steps + 1] = call("Record source tile identity", function(_, currentApp, currentRunner)
    currentApp.wm:setFocus(staticTileWin)
    local item = assert(staticTileWin:get(1, 1, 1), "expected tile at 1,1")
    currentRunner.clipboardSourceTileIndex = item.index
    currentRunner.clipboardSourceTileBank = item._bankIndex
  end)

  appendClick(steps, "Select source tile for keyboard copy", function(h)
    return h:windowCellCenter(staticTileWin, 1, 1)
  end, { moveDuration = 0.08, postPause = 0.18 })
  steps[#steps + 1] = call("Record tile count before keyboard paste", function(_, _, currentRunner)
    currentRunner.clipboardTileCountBeforeKeyboardPaste = countTileItems(staticTileWin)
  end)
  steps[#steps + 1] = keyPress("Copy tile (Ctrl+C)", "c", { "lctrl" })
  appendClick(steps, "Select tile paste target", function(h)
    return h:windowCellCenter(staticTileWin, 4, 1)
  end, { moveDuration = 0.08, postPause = 0.18 })
  steps[#steps + 1] = keyPress("Paste tile (Ctrl+V)", "v", { "lctrl" })
  steps[#steps + 1] = call("Assert keyboard tile paste", function(_, _, currentRunner)
    local afterCount = countTileItems(staticTileWin)
    assert(
      afterCount > (currentRunner.clipboardTileCountBeforeKeyboardPaste or 0),
      string.format("expected tile count to increase after paste (before=%d after=%d)",
        tonumber(currentRunner.clipboardTileCountBeforeKeyboardPaste) or -1,
        afterCount)
    )
  end)
  steps[#steps + 1] = pause("Observe keyboard tile paste", 0.35)

  appendDrag(steps, "Attempt non-CHR inter-window tile drag (should block)", function(h)
    return h:windowCellCenter(staticTileWin, 1, 1)
  end, function(h, _, currentRunner)
    local dst = assert(currentRunner.clipboardTileDropTargetWin, "expected tile drop target window")
    return h:windowCellCenter(dst, 1, 1)
  end, { dragDuration = 0.12, postPause = 0.18 })
  steps[#steps + 1] = call("Assert non-CHR inter-window tile drag is blocked", function(_, _, currentRunner)
    local dst = assert(currentRunner.clipboardTileDropTargetWin, "expected tile drop target window")
    assert(dst:get(1, 1, 1) == nil, "expected blocked inter-window drag to leave destination empty")
    assert(staticTileWin:get(1, 1, 1) ~= nil, "expected blocked inter-window drag to keep source tile")
  end)
  steps[#steps + 1] = pause("Observe blocked non-CHR inter-window drag", 0.3)

  steps[#steps + 1] = call("Prepare no-selection tile cursor paste fallback", function(_, currentApp, currentRunner)
    currentApp.wm:setFocus(staticTileWin)
    local layer = staticTileWin.layers and staticTileWin.layers[1]
    if layer then
      layer.multiTileSelection = nil
    end
    if staticTileWin.clearSelected then
      staticTileWin:clearSelected(1)
    end
    currentRunner.clipboardTileCursorTargetCol = 6
    currentRunner.clipboardTileCursorTargetRow = 2
  end)
  steps[#steps + 1] = moveTo("Move cursor to tile fallback destination", function(h, _, currentRunner)
    return h:windowCellCenter(staticTileWin, currentRunner.clipboardTileCursorTargetCol, currentRunner.clipboardTileCursorTargetRow)
  end, 0.1)
  steps[#steps + 1] = keyPress("Paste tile with no selection (Ctrl+V)", "v", { "lctrl" })
  steps[#steps + 1] = call("Assert no-selection tile paste uses cursor position", function(_, _, currentRunner)
    local pasted = staticTileWin:get(currentRunner.clipboardTileCursorTargetCol, currentRunner.clipboardTileCursorTargetRow, 1)
    assert(pasted ~= nil, "expected tile pasted at cursor fallback destination")
    assert(
      pasted.index == currentRunner.clipboardSourceTileIndex and tonumber(pasted._bankIndex) == tonumber(currentRunner.clipboardSourceTileBank),
      string.format(
        "expected cursor-fallback pasted tile to match copied source (index=%s bank=%s), got (index=%s bank=%s)",
        tostring(currentRunner.clipboardSourceTileIndex),
        tostring(currentRunner.clipboardSourceTileBank),
        tostring(pasted.index),
        tostring(pasted._bankIndex)
      )
    )
  end)
  steps[#steps + 1] = pause("Observe no-selection tile cursor fallback", 0.35)

  appendClick(steps, "Select tile to cut", function(h)
    return h:windowCellCenter(staticTileWin, 2, 1)
  end, { moveDuration = 0.08, postPause = 0.18 })
  steps[#steps + 1] = keyPress("Cut tile (Ctrl+X)", "x", { "lctrl" })
  steps[#steps + 1] = call("Assert tile cut cleared source cell", function()
    local afterCut = staticTileWin:get(2, 1, 1)
    assert(afterCut == nil, "expected cut tile cell to be empty")
  end)

  appendClick(steps, "Select cut paste destination", function(h)
    return h:windowCellCenter(staticTileWin, 5, 1)
  end, { moveDuration = 0.08, postPause = 0.18 })
  steps[#steps + 1] = keyPress("Paste cut tile (Ctrl+V)", "v", { "lctrl" })
  steps[#steps + 1] = call("Assert cut-paste action executed", function(currentHarness)
    local status = tostring(currentHarness:getStatusText() or "")
    assert(status ~= "", "expected status feedback after cut/paste")
  end)
  steps[#steps + 1] = pause("Observe cut/paste tile move", 0.4)

  appendClick(steps, "Select tile for toolbar copy", function(h)
    return h:windowCellCenter(staticTileWin, 1, 1)
  end, { moveDuration = 0.08, postPause = 0.18 })
  appendClick(steps, "Toolbar copy click", appQuickButtonCenter("copy"), { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = pause("Observe toolbar copy action parity", 0.25)

  appendClick(steps, "Select tile for toolbar cut", function(h)
    return h:windowCellCenter(staticTileWin, 4, 1)
  end, { moveDuration = 0.08, postPause = 0.18 })
  appendClick(steps, "Toolbar cut click", appQuickButtonCenter("cut"), { moveDuration = 0.08, postPause = 0.18 })
  steps[#steps + 1] = call("Assert toolbar cut cleared tile", function()
    assert(staticTileWin:get(4, 1, 1) == nil, "expected toolbar cut to clear source tile")
  end)
  steps[#steps + 1] = pause("Observe toolbar parity on tile clipboard", 0.45)

  appendDrag(steps, "Place source tile C for 2x2 multi-selection", function(h)
    return h:windowCellCenter(srcWin, 2, 0)
  end, function(h)
    return h:windowCellCenter(staticTileWin, 1, 2)
  end, { dragDuration = 0.12, postPause = 0.15 })
  appendDrag(steps, "Place source tile D for 2x2 multi-selection", function(h)
    return h:windowCellCenter(srcWin, 3, 0)
  end, function(h)
    return h:windowCellCenter(staticTileWin, 2, 2)
  end, { dragDuration = 0.12, postPause = 0.15 })
  steps[#steps + 1] = call("Prepare 2x2 tile selection for shift-to-fit", function(_, currentApp, currentRunner)
    currentApp.wm:setFocus(staticTileWin)
    local layer = assert(staticTileWin.layers and staticTileWin.layers[1], "expected static tile layer")
    layer.multiTileSelection = {}
    local cols = staticTileWin.cols or 1
    local selected = {
      { col = 1, row = 1 },
      { col = 2, row = 1 },
      { col = 1, row = 2 },
      { col = 2, row = 2 },
    }
    for _, cell in ipairs(selected) do
      local idx = (cell.row * cols + cell.col) + 1
      layer.multiTileSelection[idx] = true
    end
    if staticTileWin.setSelected then
      staticTileWin:setSelected(1, 1, 1)
    end
    currentRunner.shiftToFitExpectedCol = math.max(0, (staticTileWin.cols or 1) - 2)
    currentRunner.shiftToFitExpectedRow = math.max(0, (staticTileWin.rows or 1) - 2)
  end)
  steps[#steps + 1] = keyPress("Copy prepared 2x2 selection (Ctrl+C)", "c", { "lctrl" })
  appendClick(steps, "Paste near bottom-right to trigger shift-to-fit", function(h)
    return h:windowCellCenter(staticTileWin, (staticTileWin.cols or 1) - 1, (staticTileWin.rows or 1) - 1)
  end, { moveDuration = 0.1, postPause = 0.2 })
  steps[#steps + 1] = keyPress("Paste 2x2 selection near edge (Ctrl+V)", "v", { "lctrl" })
  steps[#steps + 1] = call("Assert tile paste shifted to fit bounds", function(currentHarness, _, currentRunner)
    local col, row = staticTileWin:getSelected()
    assert(
      col == currentRunner.shiftToFitExpectedCol and row == currentRunner.shiftToFitExpectedRow,
      string.format(
        "expected shifted anchor (%d,%d), got (%s,%s)",
        currentRunner.shiftToFitExpectedCol,
        currentRunner.shiftToFitExpectedRow,
        tostring(col),
        tostring(row)
      )
    )
    local status = tostring(currentHarness:getStatusText() or "")
    assert(status:match("shifted to fit bounds") ~= nil, "expected shift-to-fit status suffix")
  end)
  steps[#steps + 1] = pause("Observe tile shift-to-fit behavior", 0.45)

  steps[#steps + 1] = call("Assert shift-to-fit on all tile boundaries", function(currentHarness, currentApp, currentRunner)
    currentApp.wm:setFocus(staticTileWin)
    if staticTileWin.setActiveLayerIndex then
      staticTileWin:setActiveLayerIndex(1)
    end
    local expected = {
      left = { anchorCol = -99, anchorRow = 1, col = 0, row = 1 },
      top = { anchorCol = 1, anchorRow = -99, col = 1, row = 0 },
      right = {
        anchorCol = (staticTileWin.cols or 1) + 99,
        anchorRow = 1,
        col = math.max(0, (staticTileWin.cols or 1) - 2),
        row = 1,
      },
      bottom = {
        anchorCol = 1,
        anchorRow = (staticTileWin.rows or 1) + 99,
        col = 1,
        row = math.max(0, (staticTileWin.rows or 1) - 2),
      },
    }

    local function assertShift(caseDef, name)
      currentApp:performClipboardToolbarAction("paste", staticTileWin, 1, {
        anchorCol = caseDef.anchorCol,
        anchorRow = caseDef.anchorRow,
      })
      local col, row = staticTileWin:getSelected()
      assert(
        col == caseDef.col and row == caseDef.row,
        string.format("expected %s shift-to-fit selected (%d,%d), got (%s,%s)", name, caseDef.col, caseDef.row, tostring(col), tostring(row))
      )
      local status = tostring(currentHarness:getStatusText() or "")
      assert(status:match("shifted to fit bounds") ~= nil, string.format("expected shift-to-fit status on %s boundary", name))
    end

    assertShift(expected.left, "left")
    assertShift(expected.top, "top")
    assertShift(expected.right, "right")
    assertShift(expected.bottom, "bottom")
  end)
  steps[#steps + 1] = pause("Observe boundary shift-to-fit matrix", 0.45)

  steps[#steps + 1] = call("Assert oversized payload paste is cancelled", function(currentHarness, currentApp, currentRunner)
    currentRunner.clipboardTinyTileWin = assert(currentApp.wm:createTileWindow({
      animated = false,
      title = "Clipboard Tiny Tile",
      x = 530,
      y = 210,
      cols = 1,
      rows = 1,
      zoom = 2,
    }), "expected tiny tile window")
    currentApp.wm:setFocus(currentRunner.clipboardTinyTileWin)
    currentApp:performClipboardToolbarAction("paste", currentRunner.clipboardTinyTileWin, 1, {
      anchorCol = 0,
      anchorRow = 0,
    })
    local status = tostring(currentHarness:getStatusText() or "")
    assert(status:match("Selection does not fit in target layer") ~= nil, "expected oversized payload rejection status")
    assert(currentRunner.clipboardTinyTileWin:get(0, 0, 1) == nil, "expected no partial paste into tiny window")
  end)
  steps[#steps + 1] = pause("Observe oversized payload cancellation", 0.4)

  appendDrag(steps, "Place initial sprite from bank", function(h)
    return h:windowCellCenter(srcWin, 6, 0)
  end, function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.clipboardSpriteWin, 1, 1)
  end, { dragDuration = 0.12, postPause = 0.2 })
  appendClick(steps, "Select sprite for copy", function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.clipboardSpriteWin, 1, 1)
  end, { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = call("Record sprite baseline before paste", function(_, _, currentRunner)
    local spriteWin = assert(currentRunner.clipboardSpriteWin, "expected clipboard sprite window")
    local spriteLayerIndex = nil
    if spriteWin.getSpriteLayers then
      local spriteLayers = spriteWin:getSpriteLayers() or {}
      if #spriteLayers > 0 then
        spriteLayerIndex = spriteLayers[1].index
      end
    end
    if not spriteLayerIndex and spriteWin.layers then
      for li, layerInfo in ipairs(spriteWin.layers) do
        if layerInfo and layerInfo.kind == "sprite" then
          spriteLayerIndex = li
          break
        end
      end
    end
    assert(type(spriteLayerIndex) == "number", "expected sprite layer index in clipboard sprite window")
    if spriteWin.setActiveLayerIndex then
      spriteWin:setActiveLayerIndex(spriteLayerIndex)
    else
      spriteWin.activeLayer = spriteLayerIndex
    end
    local layer = assert(spriteWin.layers and spriteWin.layers[spriteLayerIndex], "expected sprite layer")
    currentRunner.clipboardSpriteLayerIndex = spriteLayerIndex
    layer.items = layer.items or {}
    if #layer.items == 0 then
      layer.items[1] = {
        worldX = 8,
        worldY = 8,
        x = 8,
        y = 8,
        baseX = 8,
        baseY = 8,
        dx = 0,
        dy = 0,
        removed = false,
      }
    end
    currentRunner.clipboardSpriteCountBeforePaste = #(layer.items or {})
    local selected = nil
    local selectedIndex = tonumber(layer.selectedSpriteIndex)
    if selectedIndex and layer.items then
      selected = layer.items[selectedIndex]
    end
    if not selected and layer.items then
      for idx, item in ipairs(layer.items) do
        if item and item.removed ~= true then
          selected = item
          selectedIndex = idx
          break
        end
      end
    end
    assert(selected, "expected selected sprite before copy/paste")
    layer.selectedSpriteIndex = selectedIndex
    layer.multiSpriteSelection = { [selectedIndex] = true }
    layer.multiSpriteSelectionOrder = { selectedIndex }
    currentRunner.clipboardSpriteSelectedX = selected.worldX or selected.x or 0
    currentRunner.clipboardSpriteSelectedY = selected.worldY or selected.y or 0
  end)
  steps[#steps + 1] = call("Copy sprite through clipboard controller", function(_, currentApp, currentRunner)
    local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
    local spriteWin = assert(currentRunner.clipboardSpriteWin, "expected clipboard sprite window")
    currentApp.wm:setFocus(spriteWin)
    local ok = KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), spriteWin, "copy", {
      layerIndex = currentRunner.clipboardSpriteLayerIndex,
    })
    assert(ok == true, "expected sprite copy action to execute")
  end)
  steps[#steps + 1] = call("Paste sprite through clipboard controller", function(_, currentApp, currentRunner)
    local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
    local spriteWin = assert(currentRunner.clipboardSpriteWin, "expected clipboard sprite window")
    currentApp.wm:setFocus(spriteWin)
    local ok = KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), spriteWin, "paste", {
      layerIndex = currentRunner.clipboardSpriteLayerIndex,
    })
    assert(ok == true, "expected sprite paste action to execute")
  end)
  steps[#steps + 1] = call("Assert sprite copy/paste count and coordinates", function(currentHarness, _, currentRunner)
    local spriteWin = assert(currentRunner.clipboardSpriteWin, "expected clipboard sprite window")
    local li = tonumber(currentRunner.clipboardSpriteLayerIndex) or 1
    local layer = assert(spriteWin.layers and spriteWin.layers[li], "expected sprite layer")
    local items = layer.items or {}
    assert(
      #items == (currentRunner.clipboardSpriteCountBeforePaste or 0) + 1,
      string.format(
        "expected sprite count +1 after paste (before=%d after=%d)",
        tonumber(currentRunner.clipboardSpriteCountBeforePaste) or -1,
        #items
      )
    )
    local pasted = assert(items[#items], "expected pasted sprite at end of layer")
    local px = pasted.worldX or pasted.x or 0
    local py = pasted.worldY or pasted.y or 0
    assert(
      px == currentRunner.clipboardSpriteSelectedX and py == currentRunner.clipboardSpriteSelectedY,
      string.format(
        "expected selection-anchored sprite paste at (%d,%d), got (%s,%s)",
        tonumber(currentRunner.clipboardSpriteSelectedX) or -1,
        tonumber(currentRunner.clipboardSpriteSelectedY) or -1,
        tostring(px),
        tostring(py)
      )
    )
    local status = tostring(currentHarness:getStatusText() or "")
    assert(status ~= "", "expected status feedback after sprite clipboard actions")
  end)
  steps[#steps + 1] = call("Prepare no-selection sprite cursor fallback", function(_, currentApp, currentRunner)
    local spriteWin = assert(currentRunner.clipboardSpriteWin, "expected clipboard sprite window")
    currentApp.wm:setFocus(spriteWin)
    local li = tonumber(currentRunner.clipboardSpriteLayerIndex) or 1
    if spriteWin.setActiveLayerIndex then
      spriteWin:setActiveLayerIndex(li)
    else
      spriteWin.activeLayer = li
    end
    local layer = assert(spriteWin.layers and spriteWin.layers[li], "expected sprite layer")
    layer.multiSpriteSelection = nil
    layer.multiSpriteSelectionOrder = nil
    layer.selectedSpriteIndex = nil
    currentRunner.clipboardSpriteCountBeforeCursorFallback = #(layer.items or {})
    currentRunner.clipboardSpriteCursorCol = 4
    currentRunner.clipboardSpriteCursorRow = 2
    currentRunner.clipboardSpriteCursorPx = 0
    currentRunner.clipboardSpriteCursorPy = 0
    local cellW = spriteWin.cellW or 8
    local cellH = spriteWin.cellH or 8
    currentRunner.clipboardSpriteCursorExpectedX = currentRunner.clipboardSpriteCursorCol * cellW + currentRunner.clipboardSpriteCursorPx
    currentRunner.clipboardSpriteCursorExpectedY = currentRunner.clipboardSpriteCursorRow * cellH + currentRunner.clipboardSpriteCursorPy
  end)
  steps[#steps + 1] = moveTo("Move cursor to sprite fallback destination", function(h, _, currentRunner)
    local spriteWin = assert(currentRunner.clipboardSpriteWin, "expected clipboard sprite window")
    return h:windowPixelCenter(
      spriteWin,
      currentRunner.clipboardSpriteCursorCol,
      currentRunner.clipboardSpriteCursorRow,
      currentRunner.clipboardSpriteCursorPx,
      currentRunner.clipboardSpriteCursorPy
    )
  end, 0.1)
  steps[#steps + 1] = call("Paste sprite with no selection through clipboard controller", function(_, currentApp, currentRunner)
    local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
    local spriteWin = assert(currentRunner.clipboardSpriteWin, "expected clipboard sprite window")
    currentApp.wm:setFocus(spriteWin)
    local ok = KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), spriteWin, "paste", {
      layerIndex = currentRunner.clipboardSpriteLayerIndex,
    })
    assert(ok == true, "expected no-selection sprite paste action to execute")
  end)
  steps[#steps + 1] = call("Assert no-selection sprite paste uses cursor coordinates", function(_, _, currentRunner)
    local spriteWin = assert(currentRunner.clipboardSpriteWin, "expected clipboard sprite window")
    local li = tonumber(currentRunner.clipboardSpriteLayerIndex) or 1
    local layer = assert(spriteWin.layers and spriteWin.layers[li], "expected sprite layer")
    local items = layer.items or {}
    assert(
      #items == (currentRunner.clipboardSpriteCountBeforeCursorFallback or 0) + 1,
      string.format(
        "expected sprite count +1 after cursor fallback paste (before=%d after=%d)",
        tonumber(currentRunner.clipboardSpriteCountBeforeCursorFallback) or -1,
        #items
      )
    )
    local pasted = assert(items[#items], "expected cursor-fallback pasted sprite")
    local px = pasted.worldX or pasted.x or 0
    local py = pasted.worldY or pasted.y or 0
    assert(
      px == currentRunner.clipboardSpriteCursorExpectedX and py == currentRunner.clipboardSpriteCursorExpectedY,
      string.format(
        "expected cursor-fallback sprite paste at (%d,%d), got (%s,%s)",
        tonumber(currentRunner.clipboardSpriteCursorExpectedX) or -1,
        tonumber(currentRunner.clipboardSpriteCursorExpectedY) or -1,
        tostring(px),
        tostring(py)
      )
    )
  end)
  steps[#steps + 1] = pause("Observe no-selection sprite cursor fallback", 0.35)
  steps[#steps + 1] = call("Validate no-focus warning branch", function(_, currentApp)
    local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
    currentApp.wm:setFocus(nil)
    local avail = KeyboardClipboardController.getActionAvailability(currentApp:_buildCtx(), nil, "paste", {})
    assert(avail and avail.allowed == false and avail.noFocus == true, "expected no-focus availability rejection")
    KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), nil, "paste", {})
  end)

  steps[#steps + 1] = call("Assert empty-clipboard behavior", function(_, currentApp)
    local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
    KeyboardClipboardController.reset()
    currentApp.wm:setFocus(staticTileWin)
    if staticTileWin.setActiveLayerIndex then
      staticTileWin:setActiveLayerIndex(1)
    end
    local beforeCount = countTileItems(staticTileWin)
    local avail = KeyboardClipboardController.getActionAvailability(currentApp:_buildCtx(), staticTileWin, "paste", { layerIndex = 1 })
    assert(avail and avail.allowed == false, "expected empty clipboard to reject paste")
    assert(tostring(avail.reason or ""):match("Clipboard is empty") ~= nil, "expected empty clipboard rejection reason")
    KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), staticTileWin, "paste", { layerIndex = 1 })
    local afterCount = countTileItems(staticTileWin)
    assert(beforeCount == afterCount, "expected empty clipboard paste attempt to not change tile count")
  end)

  steps[#steps + 1] = call("Assert tile-to-sprite clipboard interoperability", function(currentHarness, currentApp, currentRunner)
    local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
    currentApp.wm:setFocus(staticTileWin)
    if staticTileWin.setActiveLayerIndex then
      staticTileWin:setActiveLayerIndex(1)
    end
    local sourceTile = srcWin.get and srcWin:get(0, 0, 1) or nil
    if sourceTile and staticTileWin.set then
      staticTileWin:set(1, 1, sourceTile, 1)
    end
    if staticTileWin.setSelected then
      staticTileWin:setSelected(1, 1, 1)
    end
    local copied = KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), staticTileWin, "copy", { layerIndex = 1 })
    assert(copied == true, "expected deterministic tile copy before cross-type paste")
    assert(KeyboardClipboardController.hasClipboardData() == true, "expected non-empty clipboard before cross-type paste")

    local spriteWin = assert(currentRunner.clipboardSpriteWin, "expected clipboard sprite window")
    currentApp.wm:setFocus(spriteWin)
    if spriteWin.setActiveLayerIndex then
      spriteWin:setActiveLayerIndex(1)
    end
    local beforeSprites = countSpritesInLayer(spriteWin, 1)
    local avail = KeyboardClipboardController.getActionAvailability(currentApp:_buildCtx(), spriteWin, "paste", { layerIndex = 1 })
    assert(avail and avail.allowed == true, "expected tile-to-sprite paste to be allowed")
    KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), spriteWin, "paste", { layerIndex = 1 })
    local afterSprites = countSpritesInLayer(spriteWin, 1)
    assert(afterSprites == beforeSprites + 1, "expected tile-to-sprite paste to add one sprite")
    local status = tostring(currentHarness:getStatusText() or "")
    assert(status:match("Pasted") ~= nil, "expected cross-type paste status message")
  end)
  steps[#steps + 1] = pause("Observe clipboard cross-type matrix", 0.45)

  steps[#steps + 1] = call("Assert CHR destination is intra-window only", function(_, currentApp)
    local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
    currentApp.wm:setFocus(staticTileWin)
    if staticTileWin.setActiveLayerIndex then
      staticTileWin:setActiveLayerIndex(1)
    end
    if staticTileWin.setSelected then
      staticTileWin:setSelected(1, 1, 1)
    end
    KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), staticTileWin, "copy", { layerIndex = 1 })

    currentApp.wm:setFocus(srcWin)
    if srcWin.setActiveLayerIndex then
      srcWin:setActiveLayerIndex(1)
    end
    if srcWin.setSelected then
      srcWin:setSelected(2, 0, 1)
    end
    local avail = KeyboardClipboardController.getActionAvailability(currentApp:_buildCtx(), srcWin, "paste", { layerIndex = 1 })
    assert(avail and avail.allowed == false, "expected CHR destination cross-window paste to be blocked")
    assert(
      tostring(avail.reason or ""):match("same window") ~= nil,
      string.format("expected same-window CHR rejection reason, got '%s'", tostring(avail.reason))
    )
  end)

  steps[#steps + 1] = call("Assert sprite8x16 blocks 8x8 tile payload and allows CHR oddEven payload", function(_, currentApp)
    local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
    local sprite8x16Win = assert(currentApp.wm:createSpriteWindow({
      animated = false,
      title = "Clipboard Sprite 8x16",
      x = 520,
      y = 184,
      cols = 10,
      rows = 8,
      zoom = 2,
      spriteMode = "8x16",
    }), "expected sprite 8x16 fixture")
    local li = (sprite8x16Win.getActiveLayerIndex and sprite8x16Win:getActiveLayerIndex()) or 1
    local layer = assert(sprite8x16Win.layers and sprite8x16Win.layers[li], "expected sprite 8x16 layer")

    currentApp.wm:setFocus(staticTileWin)
    if staticTileWin.setActiveLayerIndex then
      staticTileWin:setActiveLayerIndex(1)
    end
    if staticTileWin.setSelected then
      staticTileWin:setSelected(1, 1, 1)
    end
    KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), staticTileWin, "copy", { layerIndex = 1 })
    local blockedAvail = KeyboardClipboardController.getActionAvailability(currentApp:_buildCtx(), sprite8x16Win, "paste", { layerIndex = li })
    assert(blockedAvail and blockedAvail.allowed == false, "expected 8x8 tile payload to be blocked for sprite 8x16")
    assert(
      tostring(blockedAvail.reason or ""):match("8x8 tile payload") ~= nil,
      string.format("expected 8x16 rejection reason, got '%s'", tostring(blockedAvail.reason))
    )
    local beforeBlocked = #(layer.items or {})
    KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), sprite8x16Win, "paste", { layerIndex = li })
    assert(#(layer.items or {}) == beforeBlocked, "expected blocked 8x8 payload to not paste into sprite 8x16")

    currentApp.wm:setFocus(srcWin)
    local sourceLayer = assert(srcWin.layers and srcWin.layers[1], "expected CHR source layer")
    if srcWin.setActiveLayerIndex then
      srcWin:setActiveLayerIndex(1)
    end
    srcWin.orderMode = "oddEven"
    sourceLayer.multiTileSelection = nil
    if srcWin.setSelected then
      srcWin:setSelected(0, 0, 1)
    end
    KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), srcWin, "copy", { layerIndex = 1 })

    currentApp.wm:setFocus(sprite8x16Win)
    if sprite8x16Win.setActiveLayerIndex then
      sprite8x16Win:setActiveLayerIndex(li)
    end
    local allowedAvail = KeyboardClipboardController.getActionAvailability(currentApp:_buildCtx(), sprite8x16Win, "paste", { layerIndex = li })
    assert(allowedAvail and allowedAvail.allowed == true, "expected CHR oddEven payload to allow sprite 8x16 paste")
    local beforeAllowed = #(layer.items or {})
    KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), sprite8x16Win, "paste", {
      layerIndex = li,
      anchorX = 8,
      anchorY = 8,
    })
    assert(#(layer.items or {}) == beforeAllowed + 1, "expected CHR oddEven payload to paste into sprite 8x16")
  end)

  steps[#steps + 1] = call("Attempt restricted paste on OAM sprite layer", function(_, currentApp, currentRunner)
    local oam = assert(currentRunner.oamFixtureWin, "expected OAM fixture window")
    currentApp.wm:setFocus(oam)
    if oam.setActiveLayerIndex then
      oam:setActiveLayerIndex(1)
    else
      oam.activeLayer = 1
    end
    local layer = oam.layers and oam.layers[1]
    currentRunner.oamSpriteCountBeforePaste = #(layer and layer.items or {})
  end)
  steps[#steps + 1] = keyPress("Paste on OAM sprite layer (should block)", "v", { "lctrl" })
  steps[#steps + 1] = call("Assert OAM sprite-layer paste restriction", function(currentHarness, _, currentRunner)
    local oam = assert(currentRunner.oamFixtureWin, "expected OAM fixture window")
    local layer = oam.layers and oam.layers[1]
    assert(#(layer and layer.items or {}) == (currentRunner.oamSpriteCountBeforePaste or 0), "expected no sprite paste on OAM sprite layer")
    assert(tostring(currentHarness:getStatusText() or "") ~= "", "expected status feedback after blocked OAM paste")
  end)

  steps[#steps + 1] = call("Attempt restricted paste on PPU sprite layer", function(_, currentApp, currentRunner)
    local ppu = assert(currentRunner.ppuFixtureWin, "expected PPU fixture window")
    currentApp.wm:setFocus(ppu)
    if ppu.getSpriteLayers then
      local spriteLayers = ppu:getSpriteLayers() or {}
      if #spriteLayers == 0 and ppu.addLayer then
        ppu:addLayer({ kind = "sprite", mode = "8x8", items = {}, name = "Sprite Layer" })
        spriteLayers = ppu:getSpriteLayers() or {}
      end
      local info = assert(spriteLayers[1], "expected PPU sprite layer for restriction check")
      if ppu.setActiveLayerIndex then
        ppu:setActiveLayerIndex(info.index)
      else
        ppu.activeLayer = info.index
      end
      currentRunner.ppuSpriteLayerIndex = info.index
    end
  end)
  steps[#steps + 1] = keyPress("Paste on PPU sprite layer (should block)", "v", { "lctrl" })
  steps[#steps + 1] = call("Assert PPU sprite-layer paste restriction", function(currentHarness)
    assert(tostring(currentHarness:getStatusText() or "") ~= "", "expected status feedback after blocked PPU paste")
  end)

  steps[#steps + 1] = call("Prepare CHR->CHR clipboard assertions", function(_, currentApp, currentRunner)
    currentApp.wm:setFocus(srcWin)
    local sourceTile = assert(srcWin:get(0, 0, 1), "expected CHR source tile")
    local sourcePixels = cloneTilePixels(sourceTile)
    local targetCol, targetRow, targetTileBefore = nil, nil, nil
    local cutPasteTargetCol, cutPasteTargetRow, cutPasteTargetBefore = nil, nil, nil
    local cols = srcWin.cols or 16
    local rows = srcWin.rows or 16
    for row = 0, rows - 1 do
      for col = 0, cols - 1 do
        if not (col == 0 and row == 0) then
          local candidate = srcWin:get(col, row, 1)
          if candidate then
            local candidatePixels = cloneTilePixels(candidate)
            if not targetTileBefore and not pixelsEqual(candidatePixels, sourcePixels) then
              targetCol, targetRow, targetTileBefore = col, row, candidate
            elseif targetTileBefore and not cutPasteTargetBefore and not (col == targetCol and row == targetRow) then
              cutPasteTargetCol, cutPasteTargetRow, cutPasteTargetBefore = col, row, candidate
            end
          end
          if targetTileBefore and cutPasteTargetBefore then
            break
          end
        end
      end
      if targetTileBefore and cutPasteTargetBefore then
        break
      end
    end
    assert(targetTileBefore, "expected a CHR target tile with different pixels")
    assert(cutPasteTargetBefore, "expected a second CHR target tile for cut/paste verification")
    currentRunner.chrClipboardTargetCol = targetCol
    currentRunner.chrClipboardTargetRow = targetRow
    currentRunner.chrClipboardCutPasteTargetCol = cutPasteTargetCol
    currentRunner.chrClipboardCutPasteTargetRow = cutPasteTargetRow
    currentRunner.chrClipboardSourceBeforeCutCol = 0
    currentRunner.chrClipboardSourceBeforeCutRow = 0
    currentRunner.chrClipboardSourcePixels = cloneTilePixels(sourceTile)
    currentRunner.chrClipboardTargetPixelsBefore = cloneTilePixels(targetTileBefore)
    currentRunner.chrClipboardCutPasteTargetPixelsBefore = cloneTilePixels(cutPasteTargetBefore)
  end)
  appendClick(steps, "Select CHR source tile for in-window copy", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = keyPress("Copy CHR tile in same window (Ctrl+C)", "c", { "lctrl" })
  appendClick(steps, "Select CHR target tile for in-window paste", function(h, _, currentRunner)
    return h:windowCellCenter(srcWin, currentRunner.chrClipboardTargetCol, currentRunner.chrClipboardTargetRow)
  end, { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = keyPress("Paste CHR tile in same window (Ctrl+V)", "v", { "lctrl" })
  steps[#steps + 1] = call("Assert CHR->CHR copy/paste changed pixels", function(_, _, currentRunner)
    local targetAfter = assert(
      srcWin:get(currentRunner.chrClipboardTargetCol, currentRunner.chrClipboardTargetRow, 1),
      "expected CHR target tile after copy/paste"
    )
    local afterPixels = cloneTilePixels(targetAfter)
    assert(
      pixelsEqual(afterPixels, currentRunner.chrClipboardSourcePixels),
      "expected CHR copy/paste target pixels to equal source pixels"
    )
    assert(
      not pixelsEqual(afterPixels, currentRunner.chrClipboardTargetPixelsBefore),
      "expected CHR copy/paste target pixels to change"
    )
  end)
  steps[#steps + 1] = call("Assert CHR->CHR paste marks destination tile edited", function(_, currentApp, currentRunner)
    local targetAfter = assert(
      srcWin:get(currentRunner.chrClipboardTargetCol, currentRunner.chrClipboardTargetRow, 1),
      "expected CHR target tile for edit-mark assertion"
    )
    local bankIdx = tonumber(targetAfter._bankIndex)
    local tileIdx = tonumber(targetAfter.index)
    assert(type(bankIdx) == "number" and type(tileIdx) == "number", "expected CHR target tile bank/index metadata")
    local edits = getEditedTileMap(currentApp, bankIdx, tileIdx)
    assert(type(edits) == "table", string.format("expected edit marks for bank=%s tile=%s", tostring(bankIdx), tostring(tileIdx)))
    assert(
      edits["0_0"] == currentRunner.chrClipboardSourcePixels[1],
      string.format("expected edited pixel 0_0=%s, got %s", tostring(currentRunner.chrClipboardSourcePixels[1]), tostring(edits["0_0"]))
    )
    assert(
      edits["7_7"] == currentRunner.chrClipboardSourcePixels[64],
      string.format("expected edited pixel 7_7=%s, got %s", tostring(currentRunner.chrClipboardSourcePixels[64]), tostring(edits["7_7"]))
    )
  end)
  steps[#steps + 1] = pause("Observe CHR in-window copy/paste path", 0.35)

  appendClick(steps, "Select CHR source tile for in-window cut", function(h, _, currentRunner)
    return h:windowCellCenter(srcWin, currentRunner.chrClipboardSourceBeforeCutCol, currentRunner.chrClipboardSourceBeforeCutRow)
  end, { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = keyPress("Cut CHR tile in same window (Ctrl+X)", "x", { "lctrl" })
  steps[#steps + 1] = call("Assert CHR cut zeroed source tile pixels", function(_, _, currentRunner)
    local sourceAfterCut = assert(
      srcWin:get(currentRunner.chrClipboardSourceBeforeCutCol, currentRunner.chrClipboardSourceBeforeCutRow, 1),
      "expected CHR source tile after cut"
    )
    assert(
      pixelsAreZero(cloneTilePixels(sourceAfterCut)),
      "expected CHR source tile pixels to be zeroed after cut"
    )
  end)

  appendClick(steps, "Select CHR cut-paste target tile", function(h, _, currentRunner)
    return h:windowCellCenter(srcWin, currentRunner.chrClipboardCutPasteTargetCol, currentRunner.chrClipboardCutPasteTargetRow)
  end, { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = keyPress("Paste CHR cut tile in same window (Ctrl+V)", "v", { "lctrl" })
  steps[#steps + 1] = call("Assert CHR cut/paste restored copied tile pixels", function(_, _, currentRunner)
    local targetAfter = assert(
      srcWin:get(currentRunner.chrClipboardCutPasteTargetCol, currentRunner.chrClipboardCutPasteTargetRow, 1),
      "expected CHR cut/paste target tile after paste"
    )
    local afterPixels = cloneTilePixels(targetAfter)
    assert(
      pixelsEqual(afterPixels, currentRunner.chrClipboardSourcePixels),
      "expected CHR cut/paste target pixels to equal original source pixels"
    )
    assert(
      not pixelsEqual(afterPixels, currentRunner.chrClipboardCutPasteTargetPixelsBefore),
      "expected CHR cut/paste target pixels to change"
    )
  end)
  steps[#steps + 1] = call("Assert CHR cut/paste marks destination tile edited", function(_, currentApp, currentRunner)
    local targetAfter = assert(
      srcWin:get(currentRunner.chrClipboardCutPasteTargetCol, currentRunner.chrClipboardCutPasteTargetRow, 1),
      "expected CHR cut/paste target tile for edit-mark assertion"
    )
    local bankIdx = tonumber(targetAfter._bankIndex)
    local tileIdx = tonumber(targetAfter.index)
    assert(type(bankIdx) == "number" and type(tileIdx) == "number", "expected CHR cut/paste target tile bank/index metadata")
    local edits = getEditedTileMap(currentApp, bankIdx, tileIdx)
    assert(type(edits) == "table", string.format("expected edit marks for bank=%s tile=%s", tostring(bankIdx), tostring(tileIdx)))
    assert(
      edits["0_0"] == currentRunner.chrClipboardSourcePixels[1],
      string.format("expected edited pixel 0_0=%s, got %s", tostring(currentRunner.chrClipboardSourcePixels[1]), tostring(edits["0_0"]))
    )
    assert(
      edits["7_7"] == currentRunner.chrClipboardSourcePixels[64],
      string.format("expected edited pixel 7_7=%s, got %s", tostring(currentRunner.chrClipboardSourcePixels[64]), tostring(edits["7_7"]))
    )
  end)
  steps[#steps + 1] = pause("Observe CHR in-window cut/paste path", 0.35)

  steps[#steps + 1] = call("Focus CHR bank for context-menu paste", function(_, currentApp)
    currentApp.wm:setFocus(srcWin)
  end)
  appendClick(steps, "Copy CHR tile before context paste", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, { moveDuration = 0.08, postPause = 0.15 })
  steps[#steps + 1] = keyPress("Copy CHR tile (Ctrl+C)", "c", { "lctrl" })
  steps[#steps + 1] = call("Open CHR context menu with right click", function(currentHarness, currentApp)
    local x, y = currentHarness:windowCellCenter(srcWin, 3, 0)
    currentHarness:click(x, y, { button = 2, wait = false })
    currentHarness:wait(0.14)
    assert(currentApp.ppuTileContextMenu and currentApp.ppuTileContextMenu:isVisible(), "expected tile context menu to be visible")
  end)
  appendClick(steps, "Click Paste in context menu", menuRowCenterByText(function(currentApp)
    return currentApp.ppuTileContextMenu
  end, "Paste"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.2,
  })
  steps[#steps + 1] = pause("Observe context-menu paste path", 0.5)

  return steps
end


return {
  clipboard_matrix = { title = "Clipboard Matrix", build = buildClipboardMatrixScenario },
}
