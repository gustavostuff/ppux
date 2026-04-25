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


local function buildClipboardIntraInterPathsScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
  local SpriteController = require("controllers.sprite.sprite_controller")

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

  local function pixelsAreZero(a)
    for i = 1, 64 do
      if (a and a[i] or 0) ~= 0 then
        return false
      end
    end
    return true
  end

  local function countTileItems(win)
    local layer = win and win.layers and win.layers[1] or nil
    local items = layer and layer.items or {}
    local count = 0
    for _, item in pairs(items) do
      if item ~= nil then
        count = count + 1
      end
    end
    return count
  end

  local function countSprites(win, layerIndex)
    local li = tonumber(layerIndex) or 1
    local layer = win and win.layers and win.layers[li] or nil
    return #(layer and layer.items or {})
  end

  local function setActiveLayer(win, layerIndex)
    local li = tonumber(layerIndex) or 1
    if win.setActiveLayerIndex then
      win:setActiveLayerIndex(li)
    else
      win.activeLayer = li
    end
    return li
  end

  local function selectTile(win, col, row, layerIndex)
    local li = setActiveLayer(win, layerIndex or 1)
    local layer = win.layers and win.layers[li]
    if layer then
      layer.multiTileSelection = nil
    end
    if win.setSelected then
      win:setSelected(col, row, li)
    end
    return li
  end

  local function selectSingleSprite(win, layerIndex, spriteIndex)
    local li = setActiveLayer(win, layerIndex or 1)
    local layer = assert(win.layers and win.layers[li], "expected sprite layer")
    assert(layer.kind == "sprite", "expected sprite layer kind")
    local idx = tonumber(spriteIndex) or 1
    assert(layer.items and layer.items[idx], "expected sprite index for selection")
    layer.selectedSpriteIndex = idx
    layer.multiSpriteSelection = { [idx] = true }
    layer.multiSpriteSelectionOrder = { idx }
    return li, layer
  end

  local function doClipboardAction(currentApp, win, action, opts)
    currentApp.wm:setFocus(win)
    local ok = KeyboardClipboardController.performClipboardAction(currentApp:_buildCtx(), win, action, opts or {})
    assert(ok == true, string.format("expected %s action to execute", tostring(action)))
  end

  local steps = {
    pause("Start", 0.35),
    call("Create clipboard intra/inter fixture windows", function(_, currentApp, currentRunner)
      local srcWin = BubbleExample.prepareBankWindow(assert(BubbleExample.findBankWindow(currentApp), "expected CHR bank window"))
      local tileWinA = assert(BubbleExample.findStaticWindow(currentApp), "expected base static tile window")
      BubbleExample.clearStaticWindow(tileWinA)
      tileWinA.title = "Clipboard Tile A"

      local tileWinB = assert(currentApp.wm:createTileWindow({
        animated = false,
        title = "Clipboard Tile B",
        x = 520,
        y = 70,
        cols = 8,
        rows = 8,
        zoom = 2,
      }), "expected secondary tile window")

      local spriteWinA = assert(currentApp.wm:createSpriteWindow({
        animated = false,
        title = "Clipboard Sprite A",
        x = 304,
        y = 184,
        cols = 10,
        rows = 8,
        zoom = 2,
      }), "expected first sprite window")

      local spriteWinB = assert(currentApp.wm:createSpriteWindow({
        animated = false,
        title = "Clipboard Sprite B",
        x = 520,
        y = 184,
        cols = 10,
        rows = 8,
        zoom = 2,
      }), "expected second sprite window")

      local chrTileA = assert(srcWin:get(0, 0, 1), "expected CHR tile A")
      local chrTileB = assert(srcWin:get(1, 0, 1), "expected CHR tile B")
      local chrTileC = assert(srcWin:get(2, 0, 1), "expected CHR tile C")
      local chrTileD = assert(srcWin:get(3, 0, 1), "expected CHR tile D")

      tileWinA:set(1, 1, chrTileA, 1)
      tileWinA:set(2, 1, chrTileB, 1)
      tileWinA:set(3, 1, chrTileC, 1)
      tileWinB:set(1, 1, chrTileD, 1)

      local spriteLayerA = assert(spriteWinA.layers and spriteWinA.layers[1], "expected sprite layer A")
      local spriteLayerB = assert(spriteWinB.layers and spriteWinB.layers[1], "expected sprite layer B")
      spriteLayerA.items = spriteLayerA.items or {}
      spriteLayerB.items = spriteLayerB.items or {}

      SpriteController.addSpriteToLayer(spriteLayerA, chrTileA, 8, 8, currentApp.tilesPool)
      SpriteController.addSpriteToLayer(spriteLayerA, chrTileB, 24, 8, currentApp.tilesPool)
      SpriteController.addSpriteToLayer(spriteLayerB, chrTileC, 8, 8, currentApp.tilesPool)

      currentRunner.clipboardPathSrcWin = srcWin
      currentRunner.clipboardPathTileWinA = tileWinA
      currentRunner.clipboardPathTileWinB = tileWinB
      currentRunner.clipboardPathSpriteWinA = spriteWinA
      currentRunner.clipboardPathSpriteWinB = spriteWinB
      currentApp.wm:setFocus(tileWinA)
    end),
    pause("Observe clipboard matrix fixtures", 0.45),
  }

  steps[#steps + 1] = call("Assert tile intra-window copy/paste path", function(_, currentApp, currentRunner)
    local tileWinA = assert(currentRunner.clipboardPathTileWinA, "expected tile window A")
    local source = assert(tileWinA:get(1, 1, 1), "expected source tile for intra-window copy/paste")
    selectTile(tileWinA, 1, 1, 1)
    doClipboardAction(currentApp, tileWinA, "copy", { layerIndex = 1 })
    selectTile(tileWinA, 4, 1, 1)
    doClipboardAction(currentApp, tileWinA, "paste", { layerIndex = 1 })
    local pasted = assert(tileWinA:get(4, 1, 1), "expected pasted tile in same window")
    assert(pasted.index == source.index, "expected same tile index for intra-window copy/paste")
    assert(tonumber(pasted._bankIndex) == tonumber(source._bankIndex), "expected same tile bank for intra-window copy/paste")
  end)
  steps[#steps + 1] = pause("Observe tile intra-window copy/paste", 0.35)

  steps[#steps + 1] = call("Assert tile intra-window cut/paste path", function(_, currentApp, currentRunner)
    local tileWinA = assert(currentRunner.clipboardPathTileWinA, "expected tile window A")
    local cutSource = assert(tileWinA:get(2, 1, 1), "expected source tile for intra-window cut")
    selectTile(tileWinA, 2, 1, 1)
    doClipboardAction(currentApp, tileWinA, "cut", { layerIndex = 1 })
    assert(tileWinA:get(2, 1, 1) == nil, "expected source tile cleared after cut")
    selectTile(tileWinA, 5, 1, 1)
    doClipboardAction(currentApp, tileWinA, "paste", { layerIndex = 1 })
    local pasted = assert(tileWinA:get(5, 1, 1), "expected pasted tile after intra-window cut/paste")
    assert(pasted.index == cutSource.index, "expected cut tile payload to be preserved")
    assert(tonumber(pasted._bankIndex) == tonumber(cutSource._bankIndex), "expected cut tile bank to be preserved")
  end)
  steps[#steps + 1] = pause("Observe tile intra-window cut/paste", 0.35)

  steps[#steps + 1] = call("Assert tile inter-window copy/paste path", function(_, currentApp, currentRunner)
    local tileWinA = assert(currentRunner.clipboardPathTileWinA, "expected tile window A")
    local tileWinB = assert(currentRunner.clipboardPathTileWinB, "expected tile window B")
    local source = assert(tileWinA:get(1, 1, 1), "expected source tile for inter-window copy/paste")
    selectTile(tileWinA, 1, 1, 1)
    doClipboardAction(currentApp, tileWinA, "copy", { layerIndex = 1 })
    selectTile(tileWinB, 2, 1, 1)
    doClipboardAction(currentApp, tileWinB, "paste", { layerIndex = 1 })
    local pasted = assert(tileWinB:get(2, 1, 1), "expected tile pasted in destination tile window")
    assert(pasted.index == source.index, "expected inter-window copied tile index to match")
    assert(tonumber(pasted._bankIndex) == tonumber(source._bankIndex), "expected inter-window copied tile bank to match")
  end)
  steps[#steps + 1] = pause("Observe tile inter-window copy/paste", 0.35)

  steps[#steps + 1] = call("Assert tile inter-window cut/paste path", function(_, currentApp, currentRunner)
    local tileWinA = assert(currentRunner.clipboardPathTileWinA, "expected tile window A")
    local tileWinB = assert(currentRunner.clipboardPathTileWinB, "expected tile window B")
    local source = assert(tileWinA:get(3, 1, 1), "expected source tile for inter-window cut/paste")
    selectTile(tileWinA, 3, 1, 1)
    doClipboardAction(currentApp, tileWinA, "cut", { layerIndex = 1 })
    assert(tileWinA:get(3, 1, 1) == nil, "expected inter-window cut to clear source tile")
    selectTile(tileWinB, 3, 1, 1)
    doClipboardAction(currentApp, tileWinB, "paste", { layerIndex = 1 })
    local pasted = assert(tileWinB:get(3, 1, 1), "expected pasted tile after inter-window cut/paste")
    assert(pasted.index == source.index, "expected inter-window cut/paste index to match")
    assert(tonumber(pasted._bankIndex) == tonumber(source._bankIndex), "expected inter-window cut/paste bank to match")
  end)
  steps[#steps + 1] = pause("Observe tile inter-window cut/paste", 0.35)

  steps[#steps + 1] = call("Assert sprite intra-window copy/cut/paste paths", function(_, currentApp, currentRunner)
    local spriteWinA = assert(currentRunner.clipboardPathSpriteWinA, "expected sprite window A")
    local li, layer = selectSingleSprite(spriteWinA, 1, 1)
    local beforeCopyPaste = countSprites(spriteWinA, li)
    doClipboardAction(currentApp, spriteWinA, "copy", { layerIndex = li })
    doClipboardAction(currentApp, spriteWinA, "paste", { layerIndex = li, anchorX = 40, anchorY = 8 })
    local afterCopyPaste = countSprites(spriteWinA, li)
    assert(afterCopyPaste == beforeCopyPaste + 1, "expected sprite intra-window copy/paste to add one sprite")

    local liCut = setActiveLayer(spriteWinA, 1)
    local layerCut = assert(spriteWinA.layers and spriteWinA.layers[liCut], "expected sprite layer for cut")
    local cutIndex = 1
    assert(layerCut.items and layerCut.items[cutIndex], "expected sprite to cut")
    layerCut.selectedSpriteIndex = cutIndex
    layerCut.multiSpriteSelection = { [cutIndex] = true }
    layerCut.multiSpriteSelectionOrder = { cutIndex }
    local beforeCut = countSprites(spriteWinA, liCut)
    doClipboardAction(currentApp, spriteWinA, "cut", { layerIndex = liCut })
    local afterCut = countSprites(spriteWinA, liCut)
    assert(afterCut == beforeCut - 1, "expected sprite intra-window cut to remove one sprite")
    doClipboardAction(currentApp, spriteWinA, "paste", { layerIndex = liCut, anchorX = 56, anchorY = 8 })
    local afterCutPaste = countSprites(spriteWinA, liCut)
    assert(afterCutPaste == beforeCut, "expected sprite intra-window cut/paste to restore sprite count")
  end)
  steps[#steps + 1] = pause("Observe sprite intra-window paths", 0.35)

  steps[#steps + 1] = call("Assert sprite inter-window copy/cut/paste paths", function(_, currentApp, currentRunner)
    local spriteWinA = assert(currentRunner.clipboardPathSpriteWinA, "expected sprite window A")
    local spriteWinB = assert(currentRunner.clipboardPathSpriteWinB, "expected sprite window B")

    local liA = setActiveLayer(spriteWinA, 1)
    local layerA = assert(spriteWinA.layers and spriteWinA.layers[liA], "expected sprite layer A")
    assert(layerA.items and layerA.items[1], "expected sprite source in window A")
    layerA.selectedSpriteIndex = 1
    layerA.multiSpriteSelection = { [1] = true }
    layerA.multiSpriteSelectionOrder = { 1 }
    doClipboardAction(currentApp, spriteWinA, "copy", { layerIndex = liA })

    local liB = setActiveLayer(spriteWinB, 1)
    local beforeInterCopy = countSprites(spriteWinB, liB)
    doClipboardAction(currentApp, spriteWinB, "paste", { layerIndex = liB, anchorX = 24, anchorY = 16 })
    local afterInterCopy = countSprites(spriteWinB, liB)
    assert(afterInterCopy == beforeInterCopy + 1, "expected sprite inter-window copy/paste to add one sprite")

    local beforeAInterCut = countSprites(spriteWinA, liA)
    layerA.selectedSpriteIndex = 1
    layerA.multiSpriteSelection = { [1] = true }
    layerA.multiSpriteSelectionOrder = { 1 }
    doClipboardAction(currentApp, spriteWinA, "cut", { layerIndex = liA })
    local afterAInterCut = countSprites(spriteWinA, liA)
    assert(afterAInterCut == beforeAInterCut - 1, "expected sprite inter-window cut to remove from source")

    local beforeBInterCutPaste = countSprites(spriteWinB, liB)
    doClipboardAction(currentApp, spriteWinB, "paste", { layerIndex = liB, anchorX = 40, anchorY = 24 })
    local afterBInterCutPaste = countSprites(spriteWinB, liB)
    assert(afterBInterCutPaste == beforeBInterCutPaste + 1, "expected sprite inter-window cut/paste to add in destination")
  end)
  steps[#steps + 1] = pause("Observe sprite inter-window paths", 0.35)

  steps[#steps + 1] = call("Assert cross-type inter-window tile<->sprite paste paths", function(_, currentApp, currentRunner)
    local tileWinB = assert(currentRunner.clipboardPathTileWinB, "expected tile window B")
    local spriteWinB = assert(currentRunner.clipboardPathSpriteWinB, "expected sprite window B")

    local tileSource = assert(tileWinB:get(2, 1, 1), "expected tile source for tile->sprite path")
    selectTile(tileWinB, 2, 1, 1)
    doClipboardAction(currentApp, tileWinB, "copy", { layerIndex = 1 })

    local spriteLayerIdx = setActiveLayer(spriteWinB, 1)
    local beforeTileToSprite = countSprites(spriteWinB, spriteLayerIdx)
    doClipboardAction(currentApp, spriteWinB, "paste", { layerIndex = spriteLayerIdx, anchorX = 72, anchorY = 24 })
    local afterTileToSprite = countSprites(spriteWinB, spriteLayerIdx)
    assert(afterTileToSprite == beforeTileToSprite + 1, "expected tile->sprite inter-window paste to add one sprite")
    assert(tileSource ~= nil, "expected deterministic tile source for tile->sprite")

    local spriteLayer = assert(spriteWinB.layers and spriteWinB.layers[spriteLayerIdx], "expected sprite destination layer")
    local spriteIdx = 1
    assert(spriteLayer.items and spriteLayer.items[spriteIdx], "expected sprite source for sprite->tile path")
    spriteLayer.selectedSpriteIndex = spriteIdx
    spriteLayer.multiSpriteSelection = { [spriteIdx] = true }
    spriteLayer.multiSpriteSelectionOrder = { spriteIdx }
    doClipboardAction(currentApp, spriteWinB, "copy", { layerIndex = spriteLayerIdx })

    local beforeSpriteToTile = countTileItems(tileWinB)
    selectTile(tileWinB, 6, 2, 1)
    doClipboardAction(currentApp, tileWinB, "paste", { layerIndex = 1 })
    local afterSpriteToTile = countTileItems(tileWinB)
    assert(afterSpriteToTile == beforeSpriteToTile + 1, "expected sprite->tile inter-window paste to add one tile")
    assert(tileWinB:get(6, 2, 1) ~= nil, "expected sprite->tile paste destination to be populated")
  end)
  steps[#steps + 1] = pause("Observe cross-type inter-window paths", 0.35)

  steps[#steps + 1] = call("Assert CHR intra-window copy/cut/paste paths", function(_, currentApp, currentRunner)
    local srcWin = assert(currentRunner.clipboardPathSrcWin, "expected CHR source window")

    local sourceTile = assert(srcWin:get(0, 0, 1), "expected CHR source tile")
    local sourcePixels = cloneTilePixels(sourceTile)

    selectTile(srcWin, 0, 0, 1)
    doClipboardAction(currentApp, srcWin, "copy", { layerIndex = 1 })
    selectTile(srcWin, 1, 0, 1)
    doClipboardAction(currentApp, srcWin, "paste", { layerIndex = 1 })
    local copiedTarget = assert(srcWin:get(1, 0, 1), "expected CHR copy target")
    assert(pixelsEqual(cloneTilePixels(copiedTarget), sourcePixels), "expected CHR copy/paste target pixels to match source")

    selectTile(srcWin, 0, 0, 1)
    doClipboardAction(currentApp, srcWin, "cut", { layerIndex = 1 })
    local cutSourceAfter = assert(srcWin:get(0, 0, 1), "expected CHR source after cut")
    assert(pixelsAreZero(cloneTilePixels(cutSourceAfter)), "expected CHR cut to clear source pixels")

    selectTile(srcWin, 2, 0, 1)
    doClipboardAction(currentApp, srcWin, "paste", { layerIndex = 1 })
    local cutPasteTarget = assert(srcWin:get(2, 0, 1), "expected CHR cut/paste destination tile")
    assert(pixelsEqual(cloneTilePixels(cutPasteTarget), sourcePixels), "expected CHR cut/paste destination pixels to match pre-cut source")
  end)
  steps[#steps + 1] = pause("Observe CHR intra-window paths", 0.35)

  steps[#steps + 1] = call("Assert CHR destination inter-window paste remains blocked", function(_, currentApp, currentRunner)
    local srcWin = assert(currentRunner.clipboardPathSrcWin, "expected CHR source window")
    local tileWinB = assert(currentRunner.clipboardPathTileWinB, "expected tile window B")

    selectTile(tileWinB, 1, 1, 1)
    doClipboardAction(currentApp, tileWinB, "copy", { layerIndex = 1 })
    selectTile(srcWin, 3, 0, 1)
    local availability = KeyboardClipboardController.getActionAvailability(currentApp:_buildCtx(), srcWin, "paste", { layerIndex = 1 })
    assert(availability and availability.allowed == false, "expected CHR destination inter-window paste to be blocked")
    assert(
      tostring(availability.reason or ""):match("same window") ~= nil,
      string.format("expected CHR destination same-window restriction reason, got '%s'", tostring(availability.reason))
    )
  end)
  steps[#steps + 1] = pause("Observe CHR destination restriction", 0.45)
  steps[#steps + 1] = pause("Clipboard intra/inter paths complete", 0.7)

  return steps
end

return {
  clipboard_intra_inter_paths = {
    title = "Clipboard Intra/Inter Paths",
    build = buildClipboardIntraInterPathsScenario,
  },
}
