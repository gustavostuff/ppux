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


local function buildUndoRedoEventsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local staticWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")
  local globalPaletteWin = assert(harness:findWindow({
    kind = "palette",
    title = "Global palette",
  }), "expected global palette window")
  local createdSpriteWindowName = "Undo Sprite Window"
  local renamedSpriteWindowName = "Undo Sprite Renamed"

  BubbleExample.clearStaticWindow(staticWin)
  if staticWin.layers and staticWin.layers[1] then
    staticWin.layers[1].paletteData = nil
  end

  local steps = {
    pause("Start", 0.35),
    call("Create runtime ROM palette window", function(_, currentApp, currentRunner)
      local win = currentApp.wm:createRomPaletteWindow({
        title = "Undo ROM Palette",
        x = 520,
        y = 210,
      })
      assert(win, "expected runtime ROM palette window")
      currentRunner.undoRomPaletteWin = win
      currentApp.wm:setFocus(win)
    end),
    pause("Observe runtime ROM palette window", 0.35),
    call("Plan paint target on CHR bank", function(_, _, currentRunner)
      local tile = assert(srcWin:get(0, 0, 1), "expected source bank tile")
      local pixels = tile.pixels or {}
      local target = nil
      for y = 0, 7 do
        for x = 0, 7 do
          local value = pixels[y * 8 + x + 1] or 0
          if value ~= 3 then
            target = { x = x, y = y, before = value }
            break
          end
        end
        if target then
          break
        end
      end
      assert(target, "expected paint target on source tile")
      currentRunner.undoPaintTarget = target
    end),
    pause("Observe planned undo targets", 0.15),

    keyPress("Open new window modal", "n", { "lctrl" }),
    pause("Observe new window modal", 0.5),
    moveTo("Move to undo sprite window type", newWindowOptionCenterByText("Static Sprites window"), 0.08),
    pause("Prepare undo sprite type click", 0.06),
    mouseDown("Pick undo sprite window type", newWindowOptionCenterByText("Static Sprites window"), 1),
    pause("Hold undo sprite type click", 0.06),
    mouseUp("Release undo sprite type click", newWindowOptionCenterByText("Static Sprites window"), 1),
    pause("Observe undo sprite settings modal", 0.2),
    call("Configure undo sprite window", function(_, currentApp)
      local modal = currentApp.newWindowModal
      assert(modal and modal.nameField, "expected new window modal")
      modal.nameField:setText(createdSpriteWindowName)
    end),
    pause("Observe undo sprite window name", 0.2),
  }

  steps[#steps + 1] = keyPress("Confirm undo sprite window settings", "return")
  steps[#steps + 1] = pause("Resolve created undo sprite window", 0.3)

  steps[#steps + 1] = call("Resolve created undo sprite window", function(currentHarness, currentApp, currentRunner)
    local win = assert(currentHarness:findWindow({
      kind = "static_art",
      title = createdSpriteWindowName,
    }), "expected created undo sprite window")
    assert(win.layers and win.layers[1] and win.layers[1].kind == "sprite", "expected created sprite layer")
    win.x = 560
    win.y = 120
    currentRunner.undoSpriteWin = win
    currentApp.wm:setFocus(win)
  end)
  steps[#steps + 1] = pause("Observe created undo sprite window", 0.35)
  steps[#steps + 1] = keyPress("Undo window create", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe window create undo", 0.35)
  steps[#steps + 1] = call("Assert window create undo", function(_, _, currentRunner)
    local win = assert(currentRunner.undoSpriteWin, "expected undo sprite window ref")
    assert(win._closed == true, "expected created sprite window to be closed after undo")
  end)
  steps[#steps + 1] = keyPress("Redo window create", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe window create redo", 0.35)
  steps[#steps + 1] = call("Assert window create redo", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.undoSpriteWin, "expected undo sprite window ref")
    assert(not win._closed, "expected created sprite window to reopen on redo")
    currentApp.wm:setFocus(win)
  end)

  steps[#steps + 1] = call("Rename created sprite window", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.undoSpriteWin, "expected undo sprite window")
    assert(currentApp:showRenameWindowModal(win), "expected rename modal to open")
    assert(currentApp.renameWindowModal and currentApp.renameWindowModal.textField, "expected rename window modal")
    currentApp.renameWindowModal.textField:setText(renamedSpriteWindowName)
    assert(currentApp.renameWindowModal:_confirm(), "expected rename confirm")
  end)
  steps[#steps + 1] = pause("Observe renamed sprite window", 0.3)
  steps[#steps + 1] = call("Assert window rename applied", function(_, _, currentRunner)
    assert(currentRunner.undoSpriteWin.title == renamedSpriteWindowName,
      string.format("expected renamed title %s, got %s", renamedSpriteWindowName, tostring(currentRunner.undoSpriteWin.title)))
  end)
  steps[#steps + 1] = keyPress("Undo window rename", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe window rename undo", 0.25)
  steps[#steps + 1] = call("Assert window rename undo", function(_, _, currentRunner)
    assert(currentRunner.undoSpriteWin.title == createdSpriteWindowName,
      string.format("expected reverted title %s, got %s", createdSpriteWindowName, tostring(currentRunner.undoSpriteWin.title)))
  end)
  steps[#steps + 1] = keyPress("Redo window rename", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe window rename redo", 0.25)
  steps[#steps + 1] = call("Assert window rename redo", function(_, currentApp, currentRunner)
    assert(currentRunner.undoSpriteWin.title == renamedSpriteWindowName,
      string.format("expected redone title %s, got %s", renamedSpriteWindowName, tostring(currentRunner.undoSpriteWin.title)))
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  appendDrag(steps, "Place tile into static window", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, function(h)
    return h:windowCellCenter(staticWin, 1, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert tile drag applied", function()
    assert(staticWin:get(1, 1, 1) ~= nil, "expected tile at 1,1 after tile drag")
  end)
  steps[#steps + 1] = keyPress("Undo tile drag", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe tile drag undo", 0.25)
  steps[#steps + 1] = call("Assert tile drag undo", function()
    assert(staticWin:get(1, 1, 1) == nil, "expected tile drag undo to clear 1,1")
  end)
  steps[#steps + 1] = keyPress("Redo tile drag", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe tile drag redo", 0.25)
  steps[#steps + 1] = call("Assert tile drag redo", function(_, currentApp)
    assert(staticWin:get(1, 1, 1) ~= nil, "expected tile drag redo to restore 1,1")
    currentApp.wm:setFocus(srcWin)
  end)

  steps[#steps + 1] = keyPress("Switch to edit mode", "tab")
  steps[#steps + 1] = pause("Observe edit mode", 0.2)
  steps[#steps + 1] = keyPress("Choose color 3", "4")
  steps[#steps + 1] = pause("Observe selected edit color", 0.15)
  appendClick(steps, "Paint source bank pixel", function(h, _, currentRunner)
    local target = assert(currentRunner.undoPaintTarget, "expected paint target")
    return h:windowPixelCenter(srcWin, 0, 0, target.x, target.y)
  end, {
    moveDuration = 0.08,
    postPause = 0.2,
  })
  steps[#steps + 1] = call("Assert paint applied", function(_, _, currentRunner)
    local target = assert(currentRunner.undoPaintTarget, "expected paint target")
    local tile = assert(srcWin:get(0, 0, 1), "expected source bank tile")
    local after = tile.pixels and tile.pixels[target.y * 8 + target.x + 1]
    currentRunner.undoPaintAfter = after
    assert(after == 3, string.format("expected painted pixel to be 3, got %s", tostring(after)))
  end)
  steps[#steps + 1] = keyPress("Undo paint", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe paint undo", 0.25)
  steps[#steps + 1] = call("Assert paint undo", function(_, _, currentRunner)
    local target = assert(currentRunner.undoPaintTarget, "expected paint target")
    local tile = assert(srcWin:get(0, 0, 1), "expected source bank tile")
    local value = tile.pixels and tile.pixels[target.y * 8 + target.x + 1]
    assert(value == target.before,
      string.format("expected paint undo value %s, got %s", tostring(target.before), tostring(value)))
  end)
  steps[#steps + 1] = keyPress("Redo paint", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe paint redo", 0.25)
  steps[#steps + 1] = call("Assert paint redo", function(_, currentApp, currentRunner)
    local target = assert(currentRunner.undoPaintTarget, "expected paint target")
    local tile = assert(srcWin:get(0, 0, 1), "expected source bank tile")
    local value = tile.pixels and tile.pixels[target.y * 8 + target.x + 1]
    assert(value == 3, string.format("expected paint redo value 3, got %s", tostring(value)))
    currentApp.wm:setFocus(globalPaletteWin)
  end)
  steps[#steps + 1] = keyPress("Return to tile mode", "tab")
  steps[#steps + 1] = pause("Observe tile mode", 0.2)

  steps[#steps + 1] = call("Store palette code before edit", function(_, currentApp, currentRunner)
    currentRunner.undoPaletteBefore = assert(
      globalPaletteWin.codes2D and globalPaletteWin.codes2D[0] and globalPaletteWin.codes2D[0][2],
      "expected original global palette code"
    )
    currentApp.wm:setFocus(globalPaletteWin)
  end)
  appendClick(steps, "Select editable global palette color", function(h)
    return h:windowCellCenter(globalPaletteWin, 2, 0)
  end, {
    moveDuration = 0.08,
    postPause = 0.16,
  })
  steps[#steps + 1] = keyPress("Change global palette color", "right", { "lshift" })
  steps[#steps + 1] = pause("Observe palette color change", 0.3)
  steps[#steps + 1] = call("Assert palette color change applied", function(_, _, currentRunner)
    local code = globalPaletteWin.codes2D and globalPaletteWin.codes2D[0] and globalPaletteWin.codes2D[0][2]
    currentRunner.undoPaletteAfter = code
    assert(code ~= currentRunner.undoPaletteBefore, "expected palette code to change")
  end)
  steps[#steps + 1] = keyPress("Undo palette color change", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette color undo", 0.25)
  steps[#steps + 1] = call("Assert palette color undo", function(_, _, currentRunner)
    local code = globalPaletteWin.codes2D and globalPaletteWin.codes2D[0] and globalPaletteWin.codes2D[0][2]
    assert(code == currentRunner.undoPaletteBefore,
      string.format("expected palette undo %s, got %s", tostring(currentRunner.undoPaletteBefore), tostring(code)))
  end)
  steps[#steps + 1] = keyPress("Redo palette color change", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette color redo", 0.25)
  steps[#steps + 1] = call("Assert palette color redo", function(_, currentApp, currentRunner)
    local code = globalPaletteWin.codes2D and globalPaletteWin.codes2D[0] and globalPaletteWin.codes2D[0][2]
    assert(code == currentRunner.undoPaletteAfter,
      string.format("expected palette redo %s, got %s", tostring(currentRunner.undoPaletteAfter), tostring(code)))
    currentApp.wm:setFocus(currentRunner.undoRomPaletteWin)
  end)

  steps[#steps + 1] = call("Assign ROM palette address through modal", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.undoRomPaletteWin, "expected runtime ROM palette window")
    local beforeAddr = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[1] and win.paletteData.romColors[1][1]
    currentRunner.undoRomPaletteBeforeAddr = beforeAddr
    local romRaw = currentApp.appEditState and currentApp.appEditState.romRaw or ""
    local maxAddr = math.max(0, #tostring(romRaw) - 1)
    local addr = math.min(0x10, maxAddr)
    currentRunner.undoRomPaletteAddr = addr
    assert(currentApp:showRomPaletteAddressModal(win, 0, 0), "expected ROM palette address modal")
    assert(currentApp.romPaletteAddressModal and currentApp.romPaletteAddressModal.textField, "expected ROM palette modal text field")
    currentApp.romPaletteAddressModal.textField:setText(string.format("%06X", addr))
    assert(currentApp.romPaletteAddressModal:_confirm(), "expected ROM palette address confirm")
  end)
  steps[#steps + 1] = pause("Observe ROM palette address assignment", 0.35)
  steps[#steps + 1] = call("Assert ROM palette address applied", function(_, _, currentRunner)
    local win = assert(currentRunner.undoRomPaletteWin, "expected runtime ROM palette window")
    local addr = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[1] and win.paletteData.romColors[1][1]
    assert(addr == currentRunner.undoRomPaletteAddr,
      string.format("expected ROM palette address %s, got %s", tostring(currentRunner.undoRomPaletteAddr), tostring(addr)))
  end)
  steps[#steps + 1] = keyPress("Undo ROM palette address", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe ROM palette address undo", 0.25)
  steps[#steps + 1] = call("Assert ROM palette address undo", function(_, _, currentRunner)
    local win = assert(currentRunner.undoRomPaletteWin, "expected runtime ROM palette window")
    local addr = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[1] and win.paletteData.romColors[1][1]
    assert(addr == currentRunner.undoRomPaletteBeforeAddr,
      string.format("expected ROM palette address undo to restore %s, got %s",
        tostring(currentRunner.undoRomPaletteBeforeAddr), tostring(addr)))
  end)
  steps[#steps + 1] = keyPress("Redo ROM palette address", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe ROM palette address redo", 0.25)
  steps[#steps + 1] = call("Assert ROM palette address redo", function(_, currentApp, currentRunner)
    local win = assert(currentRunner.undoRomPaletteWin, "expected runtime ROM palette window")
    local addr = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[1] and win.paletteData.romColors[1][1]
    assert(addr == currentRunner.undoRomPaletteAddr,
      string.format("expected ROM palette address redo %s, got %s", tostring(currentRunner.undoRomPaletteAddr), tostring(addr)))
    currentApp.wm:setFocus(win)
  end)
  steps[#steps + 1] = call("Normalize static layer palette link before link test", function(_, _, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    assert(layer, "expected static layer")
    currentRunner.undoPaletteLinkPreviousWinId = "__e2e_prev_link__"
    layer.paletteData = { winId = currentRunner.undoPaletteLinkPreviousWinId }
  end)

  steps[#steps + 1] = call("Link ROM palette to static window (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local paletteWin = currentRunner.undoRomPaletteWin
    currentApp.wm:setFocus(staticWin)
    PLC.linkLayerToPalette(staticWin, 1, paletteWin)
  end)
  steps[#steps + 1] = pause("Observe palette link", 0.35)
  steps[#steps + 1] = call("Assert palette link applied", function(_, _, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    assert(layer and layer.paletteData and layer.paletteData.winId == currentRunner.undoRomPaletteWin._id,
      "expected static window to link to runtime ROM palette")
  end)
  steps[#steps + 1] = keyPress("Undo palette link", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette link undo", 0.25)
  steps[#steps + 1] = call("Assert palette link undo", function(_, _, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    local winId = layer and layer.paletteData and layer.paletteData.winId or nil
    assert(
      winId == currentRunner.undoPaletteLinkPreviousWinId,
      string.format(
        "expected palette link undo to restore previous winId %s, got %s",
        tostring(currentRunner.undoPaletteLinkPreviousWinId),
        tostring(winId)
      )
    )
  end)
  steps[#steps + 1] = keyPress("Redo palette link", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe palette link redo", 0.25)
  steps[#steps + 1] = call("Assert palette link redo", function(_, currentApp, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    assert(layer and layer.paletteData and layer.paletteData.winId == currentRunner.undoRomPaletteWin._id,
      "expected palette link redo to restore paletteData")
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  appendDrag(steps, "Place sprite into undo sprite window", function(h)
    local srcCol, srcRow = BubbleExample.bankCellForTile(srcWin, 6)
    return h:windowCellCenter(srcWin, srcCol, srcRow)
  end, function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.undoSpriteWin, 1, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Resolve placed sprite index", function(_, currentApp, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    assert(#(layer.items or {}) >= 1, "expected placed sprite in undo sprite window")
    currentRunner.undoSpriteItemIndex = #layer.items
    local sprite = assert(layer.items[currentRunner.undoSpriteItemIndex], "expected placed sprite item")
    currentRunner.undoSpriteDragBefore = {
      worldX = sprite.worldX,
      worldY = sprite.worldY,
    }
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  appendDrag(steps, "Move sprite inside undo sprite window", function(_, currentApp, currentRunner)
    return spriteItemCenter(function(r) return r.undoSpriteWin end, function(r) return r.undoSpriteItemIndex end)(nil, currentApp, currentRunner)
  end, function(h, _, currentRunner)
    return h:windowCellCenter(currentRunner.undoSpriteWin, 4, 2)
  end, {
    dragDuration = 0.15,
    postPause = 0.28,
  })
  steps[#steps + 1] = call("Assert sprite drag applied", function(_, _, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected moved sprite")
    currentRunner.undoSpriteDragAfter = {
      worldX = sprite.worldX,
      worldY = sprite.worldY,
    }
    assert(
      sprite.worldX ~= currentRunner.undoSpriteDragBefore.worldX
        or sprite.worldY ~= currentRunner.undoSpriteDragBefore.worldY,
      "expected sprite drag to change sprite position"
    )
  end)
  steps[#steps + 1] = keyPress("Undo sprite drag", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe sprite drag undo", 0.25)
  steps[#steps + 1] = call("Assert sprite drag undo", function(_, _, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected moved sprite")
    assert(sprite.worldX == currentRunner.undoSpriteDragBefore.worldX, "expected sprite drag undo worldX")
    assert(sprite.worldY == currentRunner.undoSpriteDragBefore.worldY, "expected sprite drag undo worldY")
  end)
  steps[#steps + 1] = keyPress("Redo sprite drag", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe sprite drag redo", 0.25)
  steps[#steps + 1] = call("Assert sprite drag redo", function(_, currentApp, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected moved sprite")
    assert(sprite.worldX == currentRunner.undoSpriteDragAfter.worldX, "expected sprite drag redo worldX")
    assert(sprite.worldY == currentRunner.undoSpriteDragAfter.worldY, "expected sprite drag redo worldY")
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  appendClick(steps, "Select moved sprite for delete", function(_, currentApp, currentRunner)
    return spriteItemCenter(function(r) return r.undoSpriteWin end, function(r) return r.undoSpriteItemIndex end)(nil, currentApp, currentRunner)
  end, {
    moveDuration = 0.08,
    postPause = 0.16,
  })
  steps[#steps + 1] = keyPress("Delete selected sprite", "delete")
  steps[#steps + 1] = pause("Observe sprite delete", 0.25)
  steps[#steps + 1] = call("Assert sprite remove applied", function(_, _, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected sprite item")
    assert(sprite.removed == true, "expected sprite to be marked removed")
  end)
  steps[#steps + 1] = keyPress("Undo sprite delete", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe sprite delete undo", 0.25)
  steps[#steps + 1] = call("Assert sprite remove undo", function(_, _, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected sprite item")
    assert(sprite.removed ~= true, "expected sprite delete undo to restore sprite")
  end)
  steps[#steps + 1] = keyPress("Redo sprite delete", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe sprite delete redo", 0.25)
  steps[#steps + 1] = call("Assert sprite remove redo", function(_, currentApp, currentRunner)
    local layer = assert(currentRunner.undoSpriteWin.layers and currentRunner.undoSpriteWin.layers[1], "expected sprite layer")
    local sprite = assert(layer.items and layer.items[currentRunner.undoSpriteItemIndex], "expected sprite item")
    assert(sprite.removed == true, "expected sprite delete redo to remove sprite")
    currentApp.wm:setFocus(currentRunner.undoSpriteWin)
  end)

  steps[#steps + 1] = call("Close undo sprite window", function(_, _, currentRunner)
    local win = assert(currentRunner.undoSpriteWin, "expected undo sprite window")
    assert(win.headerToolbar and win.headerToolbar._onClose, "expected closable header toolbar")
    win.headerToolbar:_onClose()
  end)
  steps[#steps + 1] = pause("Observe window close", 0.35)
  steps[#steps + 1] = call("Assert window close applied", function(_, _, currentRunner)
    assert(currentRunner.undoSpriteWin._closed == true, "expected undo sprite window to close")
  end)
  steps[#steps + 1] = keyPress("Undo window close", "z", { "lctrl" })
  steps[#steps + 1] = pause("Observe window close undo", 0.35)
  steps[#steps + 1] = call("Assert window close undo", function(_, _, currentRunner)
    assert(not currentRunner.undoSpriteWin._closed, "expected undo window close to reopen window")
  end)
  steps[#steps + 1] = keyPress("Redo window close", "y", { "lctrl" })
  steps[#steps + 1] = pause("Observe window close redo", 0.35)
  steps[#steps + 1] = call("Assert window close redo", function(_, _, currentRunner)
    assert(currentRunner.undoSpriteWin._closed == true, "expected redo window close to close window again")
  end)
  steps[#steps + 1] = pause("Observe final undo/redo coverage", 0.8)

  return steps
end

local function buildPaletteEditRoundtripScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local staticWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")
  local paletteWin = assert(harness:findWindow({
    kind = "palette",
    title = "Global palette",
  }), "expected global palette window")

  BubbleExample.clearStaticWindow(staticWin)

  local steps = {
    pause("Start", 0.35),
  }

  appendDrag(steps, "Place first tile into static window", function(h)
    return h:windowCellCenter(srcWin, 0, 0)
  end, function(h)
    return h:windowCellCenter(staticWin, 1, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.22,
  })

  appendDrag(steps, "Place second tile into static window", function(h)
    return h:windowCellCenter(srcWin, 1, 0)
  end, function(h)
    return h:windowCellCenter(staticWin, 2, 1)
  end, {
    dragDuration = 0.12,
    postPause = 0.3,
  })

  steps[#steps + 1] = call("Store original global palette code", function(_, _, currentRunner)
    currentRunner.originalPaletteCode = assert(
      paletteWin.codes2D and paletteWin.codes2D[0] and paletteWin.codes2D[0][2],
      "expected original global palette code"
    )
  end)

  appendClick(steps, "Select third global palette color", function(h)
    return h:windowCellCenter(paletteWin, 2, 0)
  end, {
    moveDuration = 0.08,
    postPause = 0.2,
  })

  steps[#steps + 1] = keyPress("Shift right to change palette code", "right", { "lshift" })
  steps[#steps + 1] = pause("Observe first palette change", 0.45)
  steps[#steps + 1] = keyPress("Shift down to change palette code again", "down", { "lshift" })
  steps[#steps + 1] = pause("Observe updated CHR and static art colors", 0.8)
  steps[#steps + 1] = call("Assert palette code changed", function(_, _, currentRunner)
    local newCode = paletteWin.codes2D and paletteWin.codes2D[0] and paletteWin.codes2D[0][2]
    assert(newCode and newCode ~= currentRunner.originalPaletteCode,
      string.format("expected global palette code to change from %s", tostring(currentRunner.originalPaletteCode)))
  end)

  steps[#steps + 1] = keyPress("Shift up to restore palette high nibble", "up", { "lshift" })
  steps[#steps + 1] = pause("Observe partial palette restore", 0.35)
  steps[#steps + 1] = keyPress("Shift left to restore palette low nibble", "left", { "lshift" })
  steps[#steps + 1] = pause("Observe restored palette colors", 0.8)
  steps[#steps + 1] = call("Assert palette code restored", function(_, _, currentRunner)
    local restoredCode = paletteWin.codes2D and paletteWin.codes2D[0] and paletteWin.codes2D[0][2]
    assert(restoredCode == currentRunner.originalPaletteCode,
      string.format("expected restored palette code %s, got %s",
        tostring(currentRunner.originalPaletteCode), tostring(restoredCode)))
  end)

  return steps
end

local function buildRomPaletteLinkScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local staticWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")

  local steps = {
    pause("Start", 0.35),
    call("Create ROM palette link windows", function(_, currentApp, currentRunner)
      local win = currentApp.wm:createRomPaletteWindow({
        title = "ROM Link Palette",
        x = 470,
        y = 220,
      })
      assert(win, "expected ROM palette window to be created")
      currentRunner.romLinkPaletteWin = win
      for row = 0, 3 do
        for col = 0, 3 do
          local addr = row * 4 + col
          local ok = win:setCellAddress(col, row, addr)
          assert(ok == true, string.format("expected ROM palette address assignment for %d,%d", col, row))
        end
      end
      win:setSelected(2, 1)
      currentApp.wm:setFocus(win)
      local spriteWin = currentApp.wm:createSpriteWindow({
        animated = false,
        title = "ROM Link Sprite Window",
        x = 620,
        y = 110,
        cols = 4,
        rows = 4,
        zoom = 2,
      })
      assert(spriteWin, "expected runtime sprite link window to be created")
      currentRunner.romLinkSpriteWin = spriteWin
      currentApp.wm:setFocus(win)
    end),
    pause("Observe created ROM palette and sprite windows", 0.7),
  }

  steps[#steps + 1] = call("Link ROM palette to static art window (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local paletteWin = currentRunner.romLinkPaletteWin
    currentApp.wm:setFocus(staticWin)
    PLC.linkLayerToPalette(staticWin, 1, paletteWin)
  end)
  steps[#steps + 1] = pause("Observe static palette link", 0.45)

  steps[#steps + 1] = call("Assert static art palette link applied", function(_, _, currentRunner)
    local layer = staticWin.layers and staticWin.layers[1]
    assert(layer and layer.paletteData and layer.paletteData.winId == currentRunner.romLinkPaletteWin._id,
      "expected static art layer to link to runtime ROM palette window")
  end)
  steps[#steps + 1] = call("Bring ROM palette window to front for next link", function(_, currentApp, currentRunner)
    assert(currentRunner.romLinkPaletteWin, "expected runtime ROM palette window")
    currentApp.wm:setFocus(currentRunner.romLinkPaletteWin)
  end)
  steps[#steps + 1] = pause("Observe ROM palette brought to front", 0.18)
  steps[#steps + 1] = call("Normalize sprite window active layer before link", function(_, currentApp)
    local spriteWin = assert(runner.romLinkSpriteWin, "expected runtime sprite link window")
    if spriteWin.setActiveLayerIndex then
      spriteWin:setActiveLayerIndex(1)
    else
      spriteWin.activeLayer = 1
    end
    currentApp.wm:setFocus(spriteWin)
  end)
  steps[#steps + 1] = pause("Observe sprite window ready for link", 0.12)
  steps[#steps + 1] = call("Bring ROM palette back to front after sprite normalization", function(_, currentApp, currentRunner)
    assert(currentRunner.romLinkPaletteWin, "expected runtime ROM palette window")
    currentApp.wm:setFocus(currentRunner.romLinkPaletteWin)
  end)
  steps[#steps + 1] = pause("Observe ROM palette ready for sprite link", 0.12)
  steps[#steps + 1] = call("Verify sprite link drop point resolves to sprite window", function(_, currentApp)
    local x, y = windowHeaderCenter(function()
      return assert(runner.romLinkSpriteWin, "expected runtime sprite link window")
    end)(nil, currentApp, runner)
    local target = currentApp.wm:windowAt(x, y)
    assert(target == runner.romLinkSpriteWin, "expected sprite window to be topmost at link drop point")
  end)

  steps[#steps + 1] = call("Link ROM palette to sprite window (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local paletteWin = currentRunner.romLinkPaletteWin
    local spriteWin = assert(currentRunner.romLinkSpriteWin, "expected runtime sprite link window")
    currentApp.wm:setFocus(spriteWin)
    local li = (spriteWin.getActiveLayerIndex and spriteWin:getActiveLayerIndex()) or spriteWin.activeLayer or 1
    PLC.linkLayerToPalette(spriteWin, li, paletteWin)
  end)
  steps[#steps + 1] = pause("Observe sprite palette link", 0.45)

  steps[#steps + 1] = call("Assert sprite window palette link applied", function(_, _, currentRunner)
    local spriteWin = assert(currentRunner.romLinkSpriteWin, "expected runtime sprite link window")
    local linkedLayerIndex = nil
    for i, layer in ipairs(spriteWin.layers or {}) do
      if layer and layer.kind == "sprite" and layer.paletteData and layer.paletteData.winId == currentRunner.romLinkPaletteWin._id then
        linkedLayerIndex = i
        break
      end
    end
    currentRunner.linkedSpriteLayerIndex = linkedLayerIndex
    assert(linkedLayerIndex, "expected sprite layer to link to runtime ROM palette window")
  end)

  steps[#steps + 1] = call("Set palette links to auto-hide and focus sprite target", function(_, currentApp)
    local spriteWin = assert(runner.romLinkSpriteWin, "expected runtime sprite link window")
    currentApp:_applyPaletteLinksSetting("auto_hide", false)
    currentApp.wm:setFocus(spriteWin)
  end)
  steps[#steps + 1] = pause("Observe auto-hide with palette unfocused", 0.45)
  steps[#steps + 1] = moveTo("Hover ROM palette link handle while unfocused", toolbarLinkHandleCenter(function(_, currentRunner)
    return currentRunner.romLinkPaletteWin
  end), 0.12)
  steps[#steps + 1] = pause("Observe handle hover reveal", 0.65)
  steps[#steps + 1] = moveTo("Move away from ROM palette handle", function(h)
    local spriteWin = assert(runner.romLinkSpriteWin, "expected runtime sprite link window")
    return h:windowCellCenter(spriteWin, 0, 0)
  end, 0.12)
  steps[#steps + 1] = pause("Observe hidden connector after moving away", 0.45)

  appendDrag(steps, "Drag linked static art window", windowHeaderCenter(function()
    return staticWin
  end), function(_, _, currentRunner)
    local win = staticWin
    return win.x + 70, win.y - 2
  end, {
    dragDuration = 0.18,
    postPause = 0.22,
  })

  steps[#steps + 1] = call("Assert drag reveal timer was set", function(currentHarness)
    assert(staticWin._paletteLinkRevealUntil and staticWin._paletteLinkRevealUntil > currentHarness._timerNow,
      "expected palette link reveal timer after linked window drag")
  end)
  steps[#steps + 1] = pause("Observe post-drag connector fade", 1.1)
  steps[#steps + 1] = call("Assert drag reveal faded", function(currentHarness)
    assert((staticWin._paletteLinkRevealUntil or 0) <= currentHarness._timerNow,
      "expected drag reveal timer to expire")
  end)

  steps[#steps + 1] = call("Set palette links to never", function(_, currentApp)
    currentApp:_applyPaletteLinksSetting("never", false)
  end)
  steps[#steps + 1] = pause("Observe squares-only palette link mode", 0.6)
  steps[#steps + 1] = call("Restore palette links to always", function(_, currentApp)
    currentApp:_applyPaletteLinksSetting("always", false)
  end)
  steps[#steps + 1] = pause("Observe full connector restore", 0.6)

  steps[#steps + 1] = call("Remove all ROM palette links (API)", function(_, currentApp, currentRunner)
    PaletteLinkController.removeAllLinksForPalette(currentApp.wm, currentRunner.romLinkPaletteWin)
  end)
  steps[#steps + 1] = pause("Observe unlink all result", 0.65)
  steps[#steps + 1] = call("Assert both palette links were removed", function(_, _, currentRunner)
    local staticLayer = staticWin.layers and staticWin.layers[1]
    local spriteWin = assert(currentRunner.romLinkSpriteWin, "expected runtime sprite link window")
    local spriteLayer = nil
    if currentRunner.linkedSpriteLayerIndex then
      spriteLayer = spriteWin.layers and spriteWin.layers[currentRunner.linkedSpriteLayerIndex]
    end
    assert(not (staticLayer and staticLayer.paletteData), "expected static art palette link to be removed")
    assert(not (spriteLayer and spriteLayer.paletteData), "expected sprite palette link to be removed")
    assert(currentRunner.romLinkPaletteWin and currentRunner.romLinkPaletteWin._id, "expected ROM palette window to remain")
  end)
  steps[#steps + 1] = pause("Scenario complete", 0.5)

  return steps
end

local function buildRomPaletteLinkInteractionsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())

  local function activeLayerLinkWinId(win)
    local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
    local layer = win.layers and win.layers[li] or nil
    return layer and layer.paletteData and layer.paletteData.winId or nil
  end

  local function requireRunnerWindow(currentRunner, key)
    local win = currentRunner and currentRunner[key] or nil
    assert(win, "expected runner window: " .. tostring(key))
    return win
  end

  local function paletteHandleCenterByKey(key)
    return toolbarLinkHandleCenter(function(_, currentRunner)
      return requireRunnerWindow(currentRunner, key)
    end)
  end

  local function appendFocusWindow(steps, label, key)
    steps[#steps + 1] = call(label, function(_, currentApp, currentRunner)
      currentApp.wm:setFocus(requireRunnerWindow(currentRunner, key))
    end)
    steps[#steps + 1] = pause("Observe focus: " .. tostring(key), 0.12)
  end

  local function appendLinkFromPalette(steps, paletteKey, targetKey)
    steps[#steps + 1] = call(string.format("Link %s to %s (API)", tostring(paletteKey), tostring(targetKey)), function(_, currentApp, currentRunner)
      local PLC = require("controllers.palette.palette_link_controller")
      local paletteWin = requireRunnerWindow(currentRunner, paletteKey)
      local targetWin = requireRunnerWindow(currentRunner, targetKey)
      currentApp.wm:setFocus(targetWin)
      local li = (targetWin.getActiveLayerIndex and targetWin:getActiveLayerIndex()) or targetWin.activeLayer or 1
      PLC.linkLayerToPalette(targetWin, li, paletteWin)
    end)
    steps[#steps + 1] = pause("Observe palette link", 0.18)
  end

  local function paletteLinkMenu(currentApp)
    local menu = currentApp and currentApp.paletteLinkContextMenu or nil
    assert(menu and menu:isVisible(), "expected visible palette link context menu")
    return menu
  end

  local function paletteLinkMenuRowByText(itemText)
    return rootMenuItemCenter(function(currentApp)
      return paletteLinkMenu(currentApp)
    end, itemText)
  end

  local function openPaletteLinkChildMenuByText(itemText)
    return function(_, currentApp)
      local menu = paletteLinkMenu(currentApp)
      local items = menu.visibleItems or {}
      local targetRow = nil
      for index, item in ipairs(items) do
        if item and item.text == itemText then
          targetRow = index
          break
        end
      end
      assert(targetRow, "expected palette link menu item: " .. tostring(itemText))
      assert(menu._openChildForRow, "expected palette link menu child opener")
      local opened = menu:_openChildForRow(targetRow)
      assert(opened == true, "expected palette link child menu to open for " .. tostring(itemText))
    end
  end

  local function assertPaletteLinkMenuTexts(expectedTexts)
    return function(_, currentApp)
      local menu = paletteLinkMenu(currentApp)
      local actualTexts = {}
      for _, item in ipairs(menu.visibleItems or {}) do
        actualTexts[#actualTexts + 1] = tostring(item and item.text or "")
      end
      assert(#actualTexts == #expectedTexts,
        string.format(
          "expected %d palette link menu items, got %d (%s)",
          #expectedTexts,
          #actualTexts,
          table.concat(actualTexts, ", ")
        )
      )
      for index, expectedText in ipairs(expectedTexts) do
        assert(
          actualTexts[index] == expectedText,
          string.format(
            "expected palette link menu row %d to be %s, got %s",
            index,
            tostring(expectedText),
            tostring(actualTexts[index])
          )
        )
      end
    end
  end

  local function assertFocusedWindow(expectedKey, expectedLayerIndex)
    return function(_, currentApp, currentRunner)
      local expectedWin = requireRunnerWindow(currentRunner, expectedKey)
      local focusedWin = currentApp.wm:getFocus()
      assert(focusedWin == expectedWin, string.format(
        "expected focused window %s, got %s",
        tostring(expectedKey),
        tostring(focusedWin and (focusedWin.title or focusedWin._id) or nil)
      ))
      if expectedLayerIndex ~= nil then
        local actualLayerIndex = (focusedWin.getActiveLayerIndex and focusedWin:getActiveLayerIndex()) or focusedWin.activeLayer or 1
        assert(
          actualLayerIndex == expectedLayerIndex,
          string.format("expected focused layer %d, got %d", expectedLayerIndex, actualLayerIndex)
        )
      end
    end
  end

  local function paletteLinkChildMenuRow(row)
    return childMenuRowCenter(function(currentApp)
      return paletteLinkMenu(currentApp)
    end, row)
  end

  local function paletteLinkChildMenuItemByText(textResolver)
    return function(_, currentApp, currentRunner)
      local expectedText = textResolver
      if type(textResolver) == "function" then
        expectedText = textResolver(currentRunner)
      end
      expectedText = tostring(expectedText or "")
      local menu = paletteLinkMenu(currentApp)
      local childMenu = assert(menu.childMenu, "expected visible palette link child menu")
      local items = childMenu.visibleItems or {}
      local targetRow = nil
      for index, item in ipairs(items) do
        if item and item.text == expectedText then
          targetRow = index
          break
        end
      end
      if not targetRow and expectedText ~= "" then
        for index, item in ipairs(items) do
          local itemText = item and tostring(item.text or "") or ""
          if itemText:find(expectedText, 1, true) then
            targetRow = index
            break
          end
        end
      end
      assert(targetRow, "expected palette link child menu item: " .. tostring(expectedText))
      return paletteLinkChildMenuRow(targetRow)(nil, currentApp, currentRunner)
    end
  end

  local function appendClickPaletteHandle(steps, label, key)
    appendFocusWindow(steps, "Focus " .. tostring(key) .. " before palette handle click", key)
    appendClick(steps, label, paletteHandleCenterByKey(key), {
      button = 1,
      moveDuration = 0.08,
      prePressPause = 0.06,
      holdDuration = 0.05,
      postPause = 0.18,
    })
  end

  local function assertLinks(expectedPaletteKeyByTargetKey)
    return function(_, _, currentRunner)
      for targetKey, expectedPaletteKey in pairs(expectedPaletteKeyByTargetKey) do
        local targetWin = requireRunnerWindow(currentRunner, targetKey)
        local actualWinId = activeLayerLinkWinId(targetWin)
        local expectedWinId = nil
        if expectedPaletteKey ~= nil then
          expectedWinId = requireRunnerWindow(currentRunner, expectedPaletteKey)._id
        end
        assert(
          actualWinId == expectedWinId,
          string.format(
            "expected %s linked to %s (winId=%s), got %s",
            tostring(targetKey),
            tostring(expectedPaletteKey),
            tostring(expectedWinId),
            tostring(actualWinId)
          )
        )
      end
    end
  end

  local steps = {
    pause("Start", 0.35),
    call("Create palette link interaction windows", function(_, currentApp, currentRunner)
      if currentApp and currentApp._applyPaletteLinksSetting then
        currentApp:_applyPaletteLinksSetting("always", false)
      end

      currentRunner.romLinkPaletteAWin = assert(currentApp.wm:createRomPaletteWindow({
        title = "ROM Link Palette A",
        x = 44,
        y = 86,
      }), "expected ROM palette A")
      currentRunner.romLinkPaletteBWin = assert(currentApp.wm:createRomPaletteWindow({
        title = "ROM Link Palette B",
        x = 44,
        y = 220,
      }), "expected ROM palette B")

      currentRunner.linkTarget1 = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Link Target 1",
        x = 230,
        y = 64,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected link target 1")

      currentRunner.linkTarget2 = assert(currentApp.wm:createSpriteWindow({
        animated = false,
        title = "Link Target 2",
        x = 420,
        y = 64,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected link target 2")

      currentRunner.linkTarget3 = assert(currentApp.wm:createTileWindow({
        animated = true,
        numFrames = 1,
        title = "Link Target 3",
        x = 230,
        y = 212,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected link target 3")

      currentRunner.linkTarget4 = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Link Target 4",
        x = 420,
        y = 212,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected link target 4")

      currentApp.wm:setFocus(currentRunner.romLinkPaletteAWin)
    end),
    pause("Observe two palettes and four link targets", 0.75),
  }

  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget1")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget2")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget3")
  steps[#steps + 1] = call("Assert initial links A->(1,2,3)", assertLinks({
    linkTarget1 = "romLinkPaletteAWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = nil,
  }))
  steps[#steps + 1] = pause("Observe initial link setup", 0.4)

  appendClickPaletteHandle(steps, "Open palette A source menu for jump", "romLinkPaletteAWin")
  steps[#steps + 1] = call("Assert source menu items while linked", assertPaletteLinkMenuTexts({
    "Jump to linked layer",
    "Remove all links",
  }))
  steps[#steps + 1] = call("Open Jump to linked layer child menu", openPaletteLinkChildMenuByText("Jump to linked layer"))
  appendClick(steps, "Choose link target 3 from source jump menu", paletteLinkChildMenuItemByText("Link Target 3 / layer 1"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert source jump focused link target 3", assertFocusedWindow("linkTarget3", 1))

  appendClickPaletteHandle(steps, "Open linked destination menu on target3", "linkTarget3")
  steps[#steps + 1] = call("Assert linked destination menu items", assertPaletteLinkMenuTexts({
    "Link To Palette",
    "Jump to linked palette",
    "Remove ROM palette link",
  }))
  appendClick(steps, "Choose Jump to linked palette on target3", paletteLinkMenuRowByText("Jump to linked palette"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert destination jump focused palette A", assertFocusedWindow("romLinkPaletteAWin"))

  appendClickPaletteHandle(steps, "Open unlinked destination menu on target4", "linkTarget4")
  steps[#steps + 1] = call("Assert unlinked destination menu items", assertPaletteLinkMenuTexts({
    "Link To Palette",
  }))
  steps[#steps + 1] = call("Open Link To Palette child menu on target4", openPaletteLinkChildMenuByText("Link To Palette"))
  appendClick(steps, "Choose palette B in target4 link menu", paletteLinkChildMenuItemByText(function(currentRunner)
    return requireRunnerWindow(currentRunner, "romLinkPaletteBWin").title
  end), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.22,
  })
  steps[#steps + 1] = call("Assert target4 linked to palette B via destination menu", assertLinks({
    linkTarget1 = "romLinkPaletteAWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = "romLinkPaletteBWin",
  }))

  appendFocusWindow(steps, "Focus target1 before reconnecting destination link", "linkTarget1")
  steps[#steps + 1] = call("Reconnect target1 from palette A to B (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local t = requireRunnerWindow(currentRunner, "linkTarget1")
    local b = requireRunnerWindow(currentRunner, "romLinkPaletteBWin")
    currentApp.wm:setFocus(t)
    local li = (t.getActiveLayerIndex and t:getActiveLayerIndex()) or t.activeLayer or 1
    PLC.linkLayerToPalette(t, li, b)
  end)
  steps[#steps + 1] = pause("Observe destination reconnect", 0.35)
  steps[#steps + 1] = call("Assert target1 moved from palette A to palette B", assertLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = "romLinkPaletteBWin",
  }))
  appendClickPaletteHandle(steps, "Open palette link menu on target2", "linkTarget2")
  appendClick(steps, "Choose Remove ROM palette link on target2", paletteLinkMenuRowByText("Remove ROM palette link"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.24,
  })
  steps[#steps + 1] = pause("Observe destination unlink", 0.22)
  steps[#steps + 1] = call("Assert destination menu unlink", assertLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = nil,
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = "romLinkPaletteBWin",
  }))

  appendClickPaletteHandle(steps, "Open palette A source menu", "romLinkPaletteAWin")
  appendClick(steps, "Choose Remove all links on palette A", paletteLinkMenuRowByText("Remove all links"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.24,
  })
  steps[#steps + 1] = pause("Observe source remove-all", 0.22)
  steps[#steps + 1] = call("Assert source remove-all", assertLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = nil,
    linkTarget3 = nil,
    linkTarget4 = "romLinkPaletteBWin",
  }))
  appendClickPaletteHandle(steps, "Open palette A source menu while unlinked", "romLinkPaletteAWin")
  steps[#steps + 1] = call("Assert source menu items while unlinked", assertPaletteLinkMenuTexts({
    "Jump to linked layer",
    "Remove all links",
  }))
  steps[#steps + 1] = call("Hide unlinked source menu", function(_, currentApp)
    currentApp:hideAppContextMenus()
  end)
  steps[#steps + 1] = pause("Observe menu close before relinking", 0.08)

  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget1")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget2")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget3")
  appendLinkFromPalette(steps, "romLinkPaletteAWin", "linkTarget4")
  steps[#steps + 1] = call("Assert all four targets linked to palette A", assertLinks({
    linkTarget1 = "romLinkPaletteAWin",
    linkTarget2 = "romLinkPaletteAWin",
    linkTarget3 = "romLinkPaletteAWin",
    linkTarget4 = "romLinkPaletteAWin",
  }))

  steps[#steps + 1] = call("Move all links from palette A to B (API)", function(_, currentApp, currentRunner)
    local PLC = require("controllers.palette.palette_link_controller")
    local a = requireRunnerWindow(currentRunner, "romLinkPaletteAWin")
    local b = requireRunnerWindow(currentRunner, "romLinkPaletteBWin")
    PLC.moveAllLinksToPalette(currentApp.wm, a, b)
  end)
  steps[#steps + 1] = pause("Observe move-all links", 0.2)
  steps[#steps + 1] = call("Assert all links moved to palette B", assertLinks({
    linkTarget1 = "romLinkPaletteBWin",
    linkTarget2 = "romLinkPaletteBWin",
    linkTarget3 = "romLinkPaletteBWin",
    linkTarget4 = "romLinkPaletteBWin",
  }))

  appendClickPaletteHandle(steps, "Open palette B source menu for remove-all", "romLinkPaletteBWin")
  appendClick(steps, "Choose Remove all links on palette B", paletteLinkMenuRowByText("Remove all links"), {
    moveDuration = 0.08,
    prePressPause = 0.05,
    holdDuration = 0.05,
    postPause = 0.24,
  })
  steps[#steps + 1] = call("Assert palette B remove-all", assertLinks({
    linkTarget1 = nil,
    linkTarget2 = nil,
    linkTarget3 = nil,
    linkTarget4 = nil,
  }))
  steps[#steps + 1] = pause("Scenario complete", 0.6)

  return steps
end


return {
  undo_redo_events = { title = "Undo Redo Events", build = buildUndoRedoEventsScenario },
  palette_edit_roundtrip = { title = "Palette Edit Roundtrip", build = buildPaletteEditRoundtripScenario },
  rom_palette_links = { title = "ROM Palette Links", build = buildRomPaletteLinkScenario },
  rom_palette_link_interactions = {
    title = "ROM Palette Link Interactions",
    build = buildRomPaletteLinkInteractionsScenario,
  },
}
