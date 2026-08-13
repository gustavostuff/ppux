-- Shared helpers for link-interaction E2E scenarios (ROM palette + pattern table).
local P = require("test.e2e_visible.scenarios.prelude")

local pause, call, appendClick, appendDrag,
  windowHeaderCenter, rootMenuItemCenter, childMenuRowCenter,
  ppuToolbarButtonCenter
  = P.pause, P.call, P.appendClick, P.appendDrag,
  P.windowHeaderCenter, P.rootMenuItemCenter, P.childMenuRowCenter,
  P.ppuToolbarButtonCenter

local M = {}

function M.requireRunnerWindow(currentRunner, key)
  local win = currentRunner and currentRunner[key] or nil
  assert(win, "expected runner window: " .. tostring(key))
  return win
end

function M.activeLayerPaletteWinId(win)
  local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  local layer = win.layers and win.layers[li] or nil
  return layer and layer.paletteData and layer.paletteData.winId or nil
end

function M.layerPatternTableWinId(win, layerIndex)
  local layer = win.layers and win.layers[layerIndex] or nil
  return layer and layer.linkedPatternTableWindowId or nil
end

function M.findFirstLayerIndexByKind(win, kind)
  for i, layer in ipairs(win.layers or {}) do
    if layer and layer.kind == kind and layer._runtimePatternTableRefLayer ~= true then
      return i
    end
  end
  return nil
end

--- Logical pattern index -> { bank, page, tileByte } via the layer's current patternTable map.
function M.patternMapEntry(layer, logicalIndex)
  local PatternTableMapping = require("utils.pattern_table_mapping")
  local map = assert(PatternTableMapping.buildMap(layer and layer.patternTable), "expected pattern table map")
  local entry = map[math.floor(tonumber(logicalIndex) or 0)]
  assert(entry, "expected map entry for logical index " .. tostring(logicalIndex))
  return entry
end

function M.assertPatternMapBankAndTile(layer, logicalIndex, expectedBank, expectedTileByte)
  local entry = M.patternMapEntry(layer, logicalIndex)
  assert(
    tonumber(entry.bank) == tonumber(expectedBank),
    string.format(
      "expected logical %s -> bank %s, got bank %s",
      tostring(logicalIndex),
      tostring(expectedBank),
      tostring(entry.bank)
    )
  )
  assert(
    tonumber(entry.tileByte) == tonumber(expectedTileByte),
    string.format(
      "expected logical %s -> tileByte %s, got %s",
      tostring(logicalIndex),
      tostring(expectedTileByte),
      tostring(entry.tileByte)
    )
  )
  return entry
end

--- Hydrate PPU fixture nametable range (written by setupDeterministicPpuFixture).
--- Full ROM decode once; later calls only refresh CHR visuals from the current PT link.
function M.hydratePpuFixtureNametable(app, runner)
  local ppu = M.requireRunnerWindow(runner, "ppuFixtureWin")
  local bgIdx = assert(M.findFirstLayerIndexByKind(ppu, "tile"), "expected PPU tile layer")
  local layer = assert(ppu.layers[bgIdx], "expected bg layer")
  layer.nametableStartAddr = assert(runner.ppuFixtureRangeStart, "expected fixture range start")
  layer.nametableEndAddr = assert(runner.ppuFixtureRangeEnd, "expected fixture range end")
  local hasBytes = type(ppu.nametableBytes) == "table" and #ppu.nametableBytes > 0
  if not hasBytes then
    if app.hydrateNametableLayerIfReady then
      app:hydrateNametableLayerIfReady(ppu, layer, bgIdx)
    elseif ppu.refreshNametableVisuals and app.appEditState then
      ppu:refreshNametableVisuals(app.appEditState.tilesPool, bgIdx)
    end
  end
  return ppu, bgIdx, layer
end

function M.assertPpuCellMatchesPatternMap(app, runner, col, row, logicalIndex)
  local ppu, bgIdx, layer = M.hydratePpuFixtureNametable(app, runner)
  if ppu.refreshNametableVisuals and app.appEditState then
    ppu:refreshNametableVisuals(app.appEditState.tilesPool, bgIdx)
  end
  local entry = M.patternMapEntry(layer, logicalIndex)
  local tile = assert(ppu:get(col, row, bgIdx), string.format("expected tile at %d,%d", col, row))
  local tileIndex = math.floor(tonumber(tile.index) or -1)
  local expectedIndex = math.floor(tonumber(entry.tileByte) or 0)
  if tonumber(entry.page) == 2 then
    expectedIndex = expectedIndex + 256
  end
  assert(
    tileIndex == expectedIndex or (tileIndex % 256) == tonumber(entry.tileByte),
    string.format(
      "expected NT %d,%d index ~%s (map tileByte %s page %s), got %s",
      col,
      row,
      tostring(expectedIndex),
      tostring(entry.tileByte),
      tostring(entry.page),
      tostring(tileIndex)
    )
  )
  assert(
    tonumber(tile._bankIndex) == tonumber(entry.bank),
    string.format(
      "expected NT %d,%d bank %s from pattern map, got %s",
      col,
      row,
      tostring(entry.bank),
      tostring(tile._bankIndex)
    )
  )
  local pool = app.appEditState and app.appEditState.tilesPool
  local bankTiles = pool and pool[entry.bank]
  local poolTile = bankTiles and bankTiles[tileIndex]
  if poolTile then
    assert(
      tile == poolTile or (tile.pixels and poolTile.pixels and tile.pixels == poolTile.pixels),
      "expected NT tile to resolve to the CHR bank tilesPool entry"
    )
  end
  return tile, entry
end

function M.layerPaletteCodes(layer, paletteNumber)
  local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
  return ShaderPaletteController.resolveLayerPaletteCodes(layer, paletteNumber or 1, nil)
end

--- Resolve linked palette row codes via wm (reliable in e2e without ctx.wm()).
function M.resolveLinkedPaletteCodes(app, layer, paletteNumber)
  local winId = layer and layer.paletteData and layer.paletteData.winId
  assert(type(winId) == "string" and winId ~= "", "expected layer.paletteData.winId")
  local win = assert(app.wm:findWindowById(winId), "expected linked palette window " .. tostring(winId))
  local rowIdx = (paletteNumber or 1) - 1
  local row = assert(win.codes2D and win.codes2D[rowIdx], "expected codes2D row on linked palette")
  return {
    row[0],
    row[1],
    row[2],
    row[3],
  }, win
end

function M.assertLayerPaletteCodesMatchWindow(app, layer, paletteWin, paletteNumber)
  assert(
    layer and layer.paletteData and layer.paletteData.winId == paletteWin._id,
    "expected layer linked to palette window"
  )
  local codes = assert(select(1, M.resolveLinkedPaletteCodes(app, layer, paletteNumber)))
  local rowIdx = (paletteNumber or 1) - 1
  local row = assert(paletteWin.codes2D and paletteWin.codes2D[rowIdx], "expected palette codes2D row")
  for col = 0, 3 do
    assert(
      codes[col + 1] == row[col],
      string.format(
        "expected consumer palette[%d][%d]=%s, got %s",
        rowIdx,
        col,
        tostring(row[col]),
        tostring(codes[col + 1])
      )
    )
  end
  return codes
end

function M.closeAllOpenWindows(app)
  for _, win in ipairs(app.wm:getWindows() or {}) do
    if win and not win._closed then
      win._closed = true
    end
  end
end

function M.paletteHandleCenterByKey(key, slot)
  return M.badgeCenterByKey(key, slot)
end

function M.windowHeaderCenterByKey(key)
  return windowHeaderCenter(function(_, currentRunner)
    return M.requireRunnerWindow(currentRunner, key)
  end)
end

local function defaultBadgeSlotForWindow(win)
  local WindowCaps = require("controllers.window.window_capabilities")
  if WindowCaps.isRomPaletteWindow(win) then
    return "palette_source"
  end
  if WindowCaps.isPatternTable(win) then
    return "pattern_source"
  end
  if WindowCaps.isPpuFrame(win) or WindowCaps.isSketchCanvas(win) then
    return "ppu_palette"
  end
  if WindowCaps.isOamAnimation(win) then
    return "layout_palette"
  end
  return "layout_palette"
end

--- On-canvas link badge center (sources may be on the right).
--- @param winKey string
--- @param slot string|nil
--- @param opts table|nil { allowEmpty = bool } - empty badges are valid drag/menu targets
function M.badgeCenterByKey(winKey, slot, opts)
  opts = opts or {}
  return function(_, currentApp, currentRunner)
    local win = M.requireRunnerWindow(currentRunner, winKey)
    local LinkVisual = require("controllers.window.window_link_visual_controller")
    local state = assert(LinkVisual.prepareLinkDrawState(currentApp), "expected link draw state for badges")
    local byWin = assert(state.layouts and state.layouts[win], "expected badge layouts for " .. tostring(winKey))

    local resolvedSlot = slot
    if resolvedSlot == nil then
      resolvedSlot = defaultBadgeSlotForWindow(win)
    end
    local entry = byWin[resolvedSlot]
    assert(entry, string.format("expected badge slot %s on %s", tostring(resolvedSlot), tostring(winKey)))
    if slot ~= nil and opts.allowEmpty ~= true then
      assert(
        entry.pulseInner == true,
        string.format("expected linked badge for %s/%s", tostring(winKey), tostring(slot))
      )
    end
    local cx = entry.lineCx or entry.cx
    local cy = entry.lineCy or entry.cy
    assert(type(cx) == "number" and type(cy) == "number", "expected badge center for " .. tostring(winKey))
    return cx, cy
  end
end

function M.appendClickPaletteHandle(steps, label, key, slot)
  M.appendFocusWindow(steps, "Focus " .. tostring(key) .. " before badge menu", key)
  appendClick(steps, label, M.badgeCenterByKey(key, slot, { allowEmpty = true }), {
    button = 2,
    moveDuration = 0.08,
    prePressPause = 0.06,
    holdDuration = 0.05,
    postPause = 0.18,
  })
end

function M.appendBadgeDragLink(steps, label, fromKey, fromSlot, toKey, toSlot)
  M.appendFocusWindow(steps, "Focus " .. tostring(fromKey) .. " before badge drag", fromKey)
  appendDrag(steps, label, M.badgeCenterByKey(fromKey, fromSlot, { allowEmpty = true }), M.badgeCenterByKey(toKey, toSlot, { allowEmpty = true }), {
    button = 1,
    moveDuration = 0.08,
    prePressPause = 0.06,
    holdDuration = 0.05,
    dragDuration = 0.28,
    postPause = 0.28,
  })
end

--- Drag from a source badge onto a consumer window body (used when stacked destination
--- badges make badge-to-badge drops ambiguous; body resolve picks the only legal slot).
function M.appendBadgeDragToWindowBody(steps, label, fromKey, fromSlot, toKey, col, row)
  M.appendFocusWindow(steps, "Focus " .. tostring(fromKey) .. " before badge drag", fromKey)
  appendDrag(steps, label, M.badgeCenterByKey(fromKey, fromSlot, { allowEmpty = true }), function(h, _, currentRunner)
    local win = M.requireRunnerWindow(currentRunner, toKey)
    return h:windowCellCenter(win, col or 2, row or 2)
  end, {
    button = 1,
    moveDuration = 0.08,
    prePressPause = 0.06,
    holdDuration = 0.05,
    dragDuration = 0.28,
    postPause = 0.28,
  })
end

function M.appendRightDragPaletteLink(steps, label, fromKey, toKey)
  M.appendFocusWindow(steps, "Focus " .. tostring(fromKey) .. " before badge link drag", fromKey)
  appendDrag(steps, label, function(h, app, runner)
    local win = M.requireRunnerWindow(runner, fromKey)
    return M.badgeCenterByKey(fromKey, defaultBadgeSlotForWindow(win), { allowEmpty = true })(h, app, runner)
  end, function(h, app, runner)
    local win = M.requireRunnerWindow(runner, toKey)
    return M.badgeCenterByKey(toKey, defaultBadgeSlotForWindow(win), { allowEmpty = true })(h, app, runner)
  end, {
    button = 1,
    moveDuration = 0.08,
    prePressPause = 0.06,
    holdDuration = 0.05,
    dragDuration = 0.28,
    postPause = 0.28,
  })
end

function M.appendFocusWindow(steps, label, key)
  steps[#steps + 1] = call(label, function(_, currentApp, currentRunner)
    currentApp.wm:setFocus(M.requireRunnerWindow(currentRunner, key))
  end)
  steps[#steps + 1] = pause("Observe focus: " .. tostring(key), 0.12)
end

function M.paletteLinkMenu(currentApp)
  local menu = currentApp and currentApp.paletteLinkContextMenu or nil
  assert(menu and menu:isVisible(), "expected visible palette/pattern link context menu")
  return menu
end

function M.paletteLinkMenuRowByText(itemText)
  return rootMenuItemCenter(function(currentApp)
    return M.paletteLinkMenu(currentApp)
  end, itemText)
end

function M.openPaletteLinkChildMenuByText(itemText)
  return function(_, currentApp)
    local menu = M.paletteLinkMenu(currentApp)
    local items = menu.visibleItems or {}
    local targetRow = nil
    for index, item in ipairs(items) do
      if item and item.text == itemText then
        targetRow = index
        break
      end
    end
    assert(targetRow, "expected link menu item: " .. tostring(itemText))
    assert(menu._openChildForRow, "expected link menu child opener")
    local opened = menu:_openChildForRow(targetRow)
    assert(opened == true, "expected link child menu to open for " .. tostring(itemText))
  end
end

function M.assertPaletteLinkMenuTexts(expectedTexts)
  return function(_, currentApp)
    local menu = M.paletteLinkMenu(currentApp)
    local actualTexts = {}
    for _, item in ipairs(menu.visibleItems or {}) do
      actualTexts[#actualTexts + 1] = tostring(item and item.text or "")
    end
    assert(#actualTexts == #expectedTexts, string.format(
      "expected %d link menu items, got %d (%s)",
      #expectedTexts,
      #actualTexts,
      table.concat(actualTexts, ", ")
    ))
    for index, expectedText in ipairs(expectedTexts) do
      assert(
        actualTexts[index] == expectedText,
        string.format(
          "expected link menu row %d to be %s, got %s",
          index,
          tostring(expectedText),
          tostring(actualTexts[index])
        )
      )
    end
  end
end

function M.paletteLinkChildMenuRow(row)
  return childMenuRowCenter(function(currentApp)
    return M.paletteLinkMenu(currentApp)
  end, row)
end

function M.paletteLinkChildMenuItemByText(textResolver)
  return function(_, currentApp, currentRunner)
    local expectedText = textResolver
    if type(textResolver) == "function" then
      expectedText = textResolver(currentRunner)
    end
    expectedText = tostring(expectedText or "")
    local menu = M.paletteLinkMenu(currentApp)
    local childMenu = assert(menu.childMenu, "expected visible link child menu")
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
    assert(targetRow, "expected link child menu item: " .. tostring(expectedText))
    return M.paletteLinkChildMenuRow(targetRow)(nil, currentApp, currentRunner)
  end
end

function M.assertPaletteLinks(expectedPaletteKeyByTargetKey)
  return function(_, _, currentRunner)
    for targetKey, expectedPaletteKey in pairs(expectedPaletteKeyByTargetKey) do
      local targetWin = M.requireRunnerWindow(currentRunner, targetKey)
      local actualWinId = M.activeLayerPaletteWinId(targetWin)
      local expectedWinId = nil
      if expectedPaletteKey ~= nil then
        expectedWinId = M.requireRunnerWindow(currentRunner, expectedPaletteKey)._id
      end
      assert(actualWinId == expectedWinId, string.format(
        "expected %s palette-linked to %s (winId=%s), got %s",
        tostring(targetKey),
        tostring(expectedPaletteKey),
        tostring(expectedWinId),
        tostring(actualWinId)
      ))
    end
  end
end

function M.assertFocusedWindow(expectedKey, expectedLayerIndex)
  return function(_, currentApp, currentRunner)
    local expectedWin = M.requireRunnerWindow(currentRunner, expectedKey)
    local focusedWin = currentApp.wm:getFocus()
    assert(focusedWin == expectedWin, string.format(
      "expected focused window %s, got %s",
      tostring(expectedKey),
      tostring(focusedWin and (focusedWin.title or focusedWin._id) or nil)
    ))
    if expectedLayerIndex ~= nil then
      local actualLayerIndex = (focusedWin.getActiveLayerIndex and focusedWin:getActiveLayerIndex())
        or focusedWin.activeLayer
        or 1
      assert(
        actualLayerIndex == expectedLayerIndex,
        string.format("expected focused layer %d, got %d", expectedLayerIndex, actualLayerIndex)
      )
    end
  end
end

function M.appendClickToolbarButton(steps, label, winKey, buttonResolver, opts)
  M.appendFocusWindow(steps, "Focus " .. tostring(winKey) .. " before toolbar button click", winKey)
  appendClick(steps, label, ppuToolbarButtonCenter(winKey, buttonResolver), opts or {
    moveDuration = 0.08,
    prePressPause = 0.06,
    holdDuration = 0.05,
    postPause = 0.2,
  })
end

function M.resetDoubleClickState()
  local PLC = require("controllers.palette.palette_link_controller")
  if PLC.resetDoubleClickState then
    PLC.resetDoubleClickState()
  end
end

--- On-canvas left-edge pivot handle center for a window link slot (not the toolbar handle).
--- @param winKey string runner window key
--- @param slot string|nil preferred slot; when nil, first pulsing (linked) slot is used
function M.pivotHandleCenterByKey(winKey, slot)
  return function(_, currentApp, currentRunner)
    local win = M.requireRunnerWindow(currentRunner, winKey)
    local LinkVisual = require("controllers.window.window_link_visual_controller")
    local state = assert(LinkVisual.prepareLinkDrawState(currentApp), "expected link draw state for pivot handles")
    local byWin = assert(state.layouts and state.layouts[win], "expected pivot layouts for " .. tostring(winKey))

    local entry = nil
    if slot ~= nil then
      entry = byWin[slot]
      assert(entry, string.format("expected pivot handle slot %s on %s", tostring(slot), tostring(winKey)))
    else
      for _, candidate in pairs(byWin) do
        if candidate and candidate.pulseInner == true and candidate.cx and candidate.cy then
          entry = candidate
          break
        end
      end
      assert(entry, "expected a linked (pulsing) pivot handle on " .. tostring(winKey))
    end

    assert(
      type(entry.cx) == "number" and type(entry.cy) == "number",
      "expected pivot handle center for " .. tostring(winKey)
    )
    -- Prefer linked handles; empty chrome handles do not focus partners.
    if slot ~= nil then
      assert(
        entry.pulseInner == true,
        string.format("expected linked pivot handle for %s/%s", tostring(winKey), tostring(slot))
      )
    end
    return entry.cx, entry.cy
  end
end

function M.appendClickPivotHandle(steps, label, winKey, slot, opts)
  appendClick(steps, label, M.pivotHandleCenterByKey(winKey, slot), opts or {
    button = 1,
    moveDuration = 0.08,
    prePressPause = 0.06,
    holdDuration = 0.05,
    postPause = 0.24,
  })
end

function M.minimizeWindowByKey(key, opts)
  return function(_, currentApp, currentRunner)
    local win = M.requireRunnerWindow(currentRunner, key)
    local wm = assert(currentApp.wm, "expected window manager")
    assert(wm.minimizeWindow, "expected minimizeWindow")
    local ok = wm:minimizeWindow(win, opts or { recordUndo = false })
    assert(ok == true, "expected minimize to succeed for " .. tostring(key))
    assert(win._minimized == true, "expected " .. tostring(key) .. " minimized")
  end
end

function M.bringWindowToFrontByKey(key)
  return function(_, currentApp, currentRunner)
    local win = M.requireRunnerWindow(currentRunner, key)
    local wm = assert(currentApp.wm, "expected window manager")
    if wm.bringToFront then
      wm:bringToFront(win)
    end
    if wm.setFocus then
      wm:setFocus(win)
    end
  end
end

function M.assertWindowMinimized(key, expectedMinimized)
  return function(_, _, currentRunner)
    local win = M.requireRunnerWindow(currentRunner, key)
    local actual = win._minimized == true
    assert(
      actual == (expectedMinimized == true),
      string.format(
        "expected %s minimized=%s, got %s",
        tostring(key),
        tostring(expectedMinimized == true),
        tostring(actual)
      )
    )
  end
end

function M.assertWindowFrontmost(key)
  return function(_, currentApp, currentRunner)
    local expectedWin = M.requireRunnerWindow(currentRunner, key)
    local windows = currentApp.wm and currentApp.wm.windows or {}
    local frontmost = nil
    for i = #windows, 1, -1 do
      local win = windows[i]
      if win and win._closed ~= true and win._minimized ~= true and win._groupHidden ~= true then
        frontmost = win
        break
      end
    end
    assert(frontmost == expectedWin, string.format(
      "expected frontmost window %s, got %s",
      tostring(key),
      tostring(frontmost and (frontmost.title or frontmost._id) or nil)
    ))
  end
end

function M.assertWindowsMinimized(expectedByKey)
  return function(_, _, currentRunner)
    for key, expectedMinimized in pairs(expectedByKey) do
      local win = M.requireRunnerWindow(currentRunner, key)
      local actual = win._minimized == true
      assert(
        actual == (expectedMinimized == true),
        string.format(
          "expected %s minimized=%s, got %s",
          tostring(key),
          tostring(expectedMinimized == true),
          tostring(actual)
        )
      )
    end
  end
end

function M.windowHeaderMenu(currentApp)
  local menu = currentApp and currentApp.windowHeaderContextMenu or nil
  assert(menu and menu:isVisible(), "expected visible window header context menu")
  return menu
end

function M.windowHeaderMenuRowByText(itemText)
  return rootMenuItemCenter(function(currentApp)
    return M.windowHeaderMenu(currentApp)
  end, itemText)
end

--- Open header context menu at the window title (API show; menu item clicks stay mouse-driven).
function M.appendOpenWindowHeaderMenu(steps, label, winKey)
  steps[#steps + 1] = call(label, function(_, currentApp, currentRunner)
    local win = M.requireRunnerWindow(currentRunner, winKey)
    assert(win.getHeaderRect, "expected header rect")
    local hx, hy, hw, hh = win:getHeaderRect()
    local cx = hx + math.floor((tonumber(hw) or 0) * 0.5)
    local cy = hy + math.floor((tonumber(hh) or 0) * 0.5)
    assert(currentApp.showWindowHeaderContextMenu, "expected showWindowHeaderContextMenu")
    assert(
      currentApp:showWindowHeaderContextMenu(win, cx, cy) == true,
      "expected window header context menu to open for " .. tostring(winKey)
    )
  end)
  steps[#steps + 1] = pause("Observe header menu: " .. tostring(winKey), 0.14)
end

function M.headerMinimizeButtonCenterByKey(winKey)
  return function(_, currentApp, currentRunner)
    local win = M.requireRunnerWindow(currentRunner, winKey)
    local toolbar = assert(win.headerToolbar, "expected header toolbar for " .. tostring(winKey))
    if toolbar.updatePosition then
      toolbar:updatePosition()
    end
    local target = nil
    for _, button in ipairs(toolbar.buttons or {}) do
      local tip = button and tostring(button.tooltip or "") or ""
      if tip:find("Minimize", 1, true) then
        target = button
        break
      end
    end
    assert(target, "expected header minimize button on " .. tostring(winKey))
    assert(type(target.x) == "number" and type(target.y) == "number", "expected minimize button position")
    return target.x + math.floor((tonumber(target.w) or 0) * 0.5),
      target.y + math.floor((tonumber(target.h) or 0) * 0.5)
  end
end

function M.appendClickHeaderMinimize(steps, label, winKey, opts)
  M.appendFocusWindow(steps, "Focus " .. tostring(winKey) .. " before header minimize", winKey)
  appendClick(steps, label, M.headerMinimizeButtonCenterByKey(winKey), opts or {
    moveDuration = 0.08,
    prePressPause = 0.06,
    holdDuration = 0.05,
    postPause = 0.22,
  })
end

function M.taskbarWindowButtonCenterByKey(winKey)
  return function(_, currentApp, currentRunner)
    local win = M.requireRunnerWindow(currentRunner, winKey)
    local taskbar = assert(currentApp.taskbar or (currentApp.wm and currentApp.wm.taskbar), "expected taskbar")
    if taskbar.updateLayout and currentApp.canvas and currentApp.canvas.getWidth then
      taskbar:updateLayout(currentApp.canvas:getWidth(), currentApp.canvas:getHeight())
    end
    local button = taskbar.minimizedButtonsByWindow and taskbar.minimizedButtonsByWindow[win]
    assert(button, "expected taskbar button for " .. tostring(winKey))
    assert(type(button.x) == "number" and type(button.y) == "number", "expected taskbar button position")
    assert((tonumber(button.w) or 0) > 0 and (tonumber(button.h) or 0) > 0, "expected laid-out taskbar button")
    return button.x + math.floor(button.w * 0.5), button.y + math.floor(button.h * 0.5)
  end
end

function M.appendClickTaskbarWindowButton(steps, label, winKey, opts)
  appendClick(steps, label, M.taskbarWindowButtonCenterByKey(winKey), opts or {
    moveDuration = 0.08,
    prePressPause = 0.06,
    holdDuration = 0.05,
    postPause = 0.24,
  })
end

return M
