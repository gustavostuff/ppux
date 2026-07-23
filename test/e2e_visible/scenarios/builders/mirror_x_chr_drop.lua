-- Visible E2E: CHR multi-tile drop onto a layout window with Mirror X combinations.
-- Covers the integration gaps unit tests miss (focus during drag, real remap, final placement).
local P = require("test.e2e_visible.scenarios.prelude")
local BubbleExample, pause, call =
  P.BubbleExample, P.pause, P.call

local function setChrGappedSelection(srcWin, colA, colB, row)
  row = row or 0
  local layer = assert(srcWin.layers and srcWin.layers[1], "expected CHR tile layer")
  local cols = srcWin.cols or 16
  layer.multiTileSelection = {
    [(row * cols + colA) + 1] = true,
    [(row * cols + colB) + 1] = true,
  }
  if srcWin.setSelected then
    srcWin:setSelected(colA, row, 1)
  end
end

--- Screen point for a data cell, accounting for window Mirror X (visual flip).
local function cellCenterForDataCell(harness, win, col, row)
  local x, y = harness:windowCellCenter(win, col, row)
  if not (win and win._mirrorXPreview == true) then
    return x, y
  end
  local sx, _, sw
  if type(win.getInsetContentScreenRect) == "function" then
    sx, _, sw = win:getInsetContentScreenRect()
  end
  if not (type(x) == "number" and type(sx) == "number" and type(sw) == "number" and sw > 0) then
    return x, y
  end
  return sx + sw - (x - sx), y
end

local function tileIndexAt(win, col, row)
  local item = win.get and win:get(col, row, 1) or nil
  if item and type(item.index) == "number" then
    return item.index
  end
  return nil
end

local function findTileCellsByIndex(win, indexA, indexB)
  local found = {}
  local cols = win.cols or 0
  local rows = win.rows or 0
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local idx = tileIndexAt(win, col, row)
      if idx == indexA or idx == indexB then
        found[#found + 1] = { col = col, row = row, index = idx }
      end
    end
  end
  return found
end

local function assertGappedPairOffsets(win, indexAnchor, indexGap, expectedGapDelta, label)
  local cells = findTileCellsByIndex(win, indexAnchor, indexGap)
  assert(#cells == 2, string.format("%s: expected 2 placed tiles, found %d", label, #cells))
  local anchorCell, gapCell
  for _, cell in ipairs(cells) do
    if cell.index == indexAnchor then
      anchorCell = cell
    else
      gapCell = cell
    end
  end
  assert(anchorCell and gapCell, string.format("%s: missing anchor/gap tile cells", label))
  assert(anchorCell.row == gapCell.row, string.format("%s: expected same row for gapped pair", label))
  assert(
    gapCell.col == anchorCell.col + expectedGapDelta,
    string.format(
      "%s: expected gap tile at anchorCol%+d (%d), got anchor=%d gap=%d",
      label,
      expectedGapDelta,
      anchorCell.col + expectedGapDelta,
      anchorCell.col,
      gapCell.col
    )
  )
end

local function clearDestTiles(win)
  BubbleExample.clearStaticWindow(win)
end

local function setWindowMirror(app, win, enabled)
  app.wm:setFocus(win)
  win._mirrorXPreview = enabled == true
end

local function buildMirrorXChrGroupDropScenario(harness, app, runner)
  harness:loadROM(BubbleExample.getLoadPath())
  local srcWin = BubbleExample.prepareBankWindow(
    assert(BubbleExample.findBankWindow(app), "expected CHR bank window")
  )
  local dstWin = assert(BubbleExample.findStaticWindow(app), "expected static art window")
  BubbleExample.clearStaticWindow(dstWin)

  -- Prefer a roomy destination so remapped anchors keep source-relative offsets in-bounds.
  if dstWin.setZoomLevel then
    dstWin:setZoomLevel(2)
  else
    dstWin.zoom = 2
  end
  if app.canvas and app.wm and app.wm.setFocus then
    local zoom = (dstWin.getZoomLevel and dstWin:getZoomLevel()) or dstWin.zoom or 1
    local contentW = (dstWin.visibleCols or dstWin.cols or 8) * (dstWin.cellW or 8) * zoom
    local contentH = (dstWin.visibleRows or dstWin.rows or 8) * (dstWin.cellH or 8) * zoom
    dstWin.x = math.floor((app.canvas:getWidth() - contentW) * 0.55)
    dstWin.y = math.floor((app.canvas:getHeight() - contentH) * 0.25)
    srcWin.x = 24
    srcWin.y = 48
    app.wm:setFocus(srcWin)
  end

  local colA, colB, row = 0, 2, 0
  local dropCol, dropRow = 2, 2

  local steps = {
    pause("Start - Mirror X CHR group drop", 0.4),
    call("Cache source tile indices for gapped pair", function(_, _, currentRunner)
      local a = srcWin.get and srcWin:get(colA, row, 1) or nil
      local b = srcWin.get and srcWin:get(colB, row, 1) or nil
      assert(a and type(a.index) == "number", "expected CHR tile at (0,0)")
      assert(b and type(b.index) == "number", "expected CHR tile at (2,0)")
      assert(a.index ~= b.index, "expected distinct tile indices for gapped pair")
      currentRunner.mirrorDropIndexA = a.index
      currentRunner.mirrorDropIndexB = b.index
      currentRunner.mirrorDropSrcWin = srcWin
      currentRunner.mirrorDropDstWin = dstWin
    end),

    -- ---------------------------------------------------------------------
    -- Scenario 1: source not mirrored, destination mirrored
    -- ---------------------------------------------------------------------
    call("Enable Mirror X on destination only", function(_, currentApp, currentRunner)
      setWindowMirror(currentApp, currentRunner.mirrorDropDstWin, true)
      setWindowMirror(currentApp, currentRunner.mirrorDropSrcWin, false)
      clearDestTiles(currentRunner.mirrorDropDstWin)
      assert(currentRunner.mirrorDropDstWin._mirrorXPreview == true, "expected destination Mirror X on")
      assert(currentRunner.mirrorDropSrcWin._mirrorXPreview ~= true, "expected source Mirror X off")
    end),
    pause("Observe destination Mirror X", 0.45),
    call("Select gapped CHR pair and drag onto mirrored destination", function(currentHarness, currentApp, currentRunner)
      local src = currentRunner.mirrorDropSrcWin
      local dst = currentRunner.mirrorDropDstWin
      currentApp.wm:setFocus(src)
      setChrGappedSelection(src, colA, colB, row)

      local fromX, fromY = cellCenterForDataCell(currentHarness, src, colA, row)
      -- Aim at the geometric cell; dest Mirror X remaps this to the opposite data column.
      local toX, toY = currentHarness:windowCellCenter(dst, dropCol, dropRow)
      -- Keep focus on CHR while dragging so remap must work without dest focus.
      currentHarness:drag(fromX, fromY, toX, toY, {
        wait = false,
        steps = 10,
        dt = currentHarness.stepDt,
      })
    end),
    pause("Observe dest-mirrored group drop", 0.55),
    call("Assert dest-mirrored drop remapped without flipping group offsets", function(_, _, currentRunner)
      local dst = currentRunner.mirrorDropDstWin
      -- Static tile dest: Mirror X remaps drop only; source offsets stay 0 and +2.
      assertGappedPairOffsets(
        dst,
        currentRunner.mirrorDropIndexA,
        currentRunner.mirrorDropIndexB,
        2,
        "dest-mirrored"
      )
      -- Drop was aimed at a leftish visual cell; remapped data should land toward the right.
      local cells = findTileCellsByIndex(dst, currentRunner.mirrorDropIndexA, currentRunner.mirrorDropIndexB)
      local maxCol = 0
      for _, cell in ipairs(cells) do
        if cell.col > maxCol then
          maxCol = cell.col
        end
      end
      local mid = math.floor(((dst.cols or 8) - 1) * 0.5)
      assert(
        maxCol >= mid,
        string.format("dest-mirrored: expected remapped group on right half (maxCol=%d mid=%d)", maxCol, mid)
      )
    end),

    -- ---------------------------------------------------------------------
    -- Scenario 2: source mirrored, destination not
    -- ---------------------------------------------------------------------
    call("Enable Mirror X on source only", function(_, currentApp, currentRunner)
      clearDestTiles(currentRunner.mirrorDropDstWin)
      setWindowMirror(currentApp, currentRunner.mirrorDropSrcWin, true)
      setWindowMirror(currentApp, currentRunner.mirrorDropDstWin, false)
      assert(currentRunner.mirrorDropSrcWin._mirrorXPreview == true, "expected source Mirror X on")
      assert(currentRunner.mirrorDropDstWin._mirrorXPreview ~= true, "expected destination Mirror X off")
    end),
    pause("Observe source Mirror X", 0.45),
    call("Select gapped CHR pair and drag onto unmirrored destination", function(currentHarness, currentApp, currentRunner)
      local src = currentRunner.mirrorDropSrcWin
      local dst = currentRunner.mirrorDropDstWin
      currentApp.wm:setFocus(src)
      setChrGappedSelection(src, colA, colB, row)

      local fromX, fromY = cellCenterForDataCell(currentHarness, src, colA, row)
      local toX, toY = currentHarness:windowCellCenter(dst, dropCol, dropRow)
      currentHarness:drag(fromX, fromY, toX, toY, {
        wait = false,
        steps = 10,
        dt = currentHarness.stepDt,
      })
    end),
    pause("Observe source-mirrored group drop", 0.55),
    call("Assert source-mirrored drop used flipped group layout at unmirrored drop cell", function(_, _, currentRunner)
      local dst = currentRunner.mirrorDropDstWin
      assertGappedPairOffsets(
        dst,
        currentRunner.mirrorDropIndexA,
        currentRunner.mirrorDropIndexB,
        -2,
        "source-mirrored"
      )
      local cells = findTileCellsByIndex(dst, currentRunner.mirrorDropIndexA, currentRunner.mirrorDropIndexB)
      local anchorCell
      for _, cell in ipairs(cells) do
        if cell.index == currentRunner.mirrorDropIndexA then
          anchorCell = cell
        end
      end
      assert(anchorCell, "source-mirrored: missing anchor cell")
      -- Destination not mirrored: drop cell should match the aimed grid cell.
      assert(
        anchorCell.col == dropCol and anchorCell.row == dropRow,
        string.format(
          "source-mirrored: expected anchor at drop cell (%d,%d), got (%d,%d)",
          dropCol,
          dropRow,
          anchorCell.col,
          anchorCell.row
        )
      )
    end),
    pause("Done - Mirror X CHR group drop", 0.5),
  }

  return steps
end

return {
  mirror_x_chr_group_drop = {
    title = "Mirror X CHR group drop",
    build = buildMirrorXChrGroupDropScenario,
  },
}
