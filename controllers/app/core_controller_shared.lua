local TableUtils = require("utils.table_utils")

local M = {}

function M.parseHexAddress(text)
  local trimmed = tostring(text or ""):match("^%s*(.-)%s*$")
  if trimmed == "" then
    return nil, "Address is required"
  end

  local normalized = trimmed:upper():gsub("^0X", "")
  if not normalized:match("^[0-9A-F]+$") then
    return nil, "Address must be hexadecimal"
  end

  local value = tonumber(normalized, 16)
  if type(value) ~= "number" then
    return nil, "Address must be hexadecimal"
  end

  return math.floor(value)
end

function M.parseNonNegativeInteger(text, label)
  local trimmed = tostring(text or ""):match("^%s*(.-)%s*$")
  label = label or "Value"
  if trimmed == "" then
    return nil, string.format("%s is required", label)
  end

  local base = 10
  local normalized = trimmed
  if trimmed:match("^0[xX][0-9A-Fa-f]+$") then
    base = 16
    normalized = trimmed:sub(3)
  elseif not trimmed:match("^%d+$") then
    return nil, string.format("%s must be a whole number", label)
  end

  local value = tonumber(normalized, base)
  if type(value) ~= "number" then
    return nil, string.format("%s must be a whole number", label)
  end

  value = math.floor(value)
  if value < 0 then
    return nil, string.format("%s must be zero or greater", label)
  end

  return value
end

function M.parsePositiveDecimalInteger(text, label)
  local trimmed = tostring(text or ""):match("^%s*(.-)%s*$")
  label = label or "Value"
  if trimmed == "" then
    return nil, string.format("%s is required", label)
  end
  if not trimmed:match("^%d+$") then
    return nil, string.format("%s must be a decimal whole number", label)
  end

  local value = tonumber(trimmed, 10)
  if type(value) ~= "number" then
    return nil, string.format("%s must be a decimal whole number", label)
  end

  value = math.floor(value)
  if value < 1 then
    return nil, string.format("%s must be 1 or greater", label)
  end

  return value
end

function M.anyModalVisible(app)
  return (app.quitConfirmModal and app.quitConfirmModal:isVisible())
    or (app.saveOptionsModal and app.saveOptionsModal:isVisible())
    or (app.genericActionsModal and app.genericActionsModal:isVisible())
    or (app.settingsModal and app.settingsModal:isVisible())
    or (app.newWindowTypeModal and app.newWindowTypeModal:isVisible())
    or (app.newWindowModal and app.newWindowModal:isVisible())
    or (app.openProjectModal and app.openProjectModal:isVisible())
    or (app.renameWindowModal and app.renameWindowModal:isVisible())
    or (app.romPaletteAddressModal and app.romPaletteAddressModal:isVisible())
    or (app.ppuFrameSpriteLayerModeModal and app.ppuFrameSpriteLayerModeModal:isVisible())
    or (app.ppuFrameAddSpriteModal and app.ppuFrameAddSpriteModal:isVisible())
    or (app.ppuFrameRangeModal and app.ppuFrameRangeModal:isVisible())
    or (app.ppuFramePatternRangeModal and app.ppuFramePatternRangeModal:isVisible())
    or (app.textFieldDemoModal and app.textFieldDemoModal:isVisible())
end

function M.getTopWindowTooltipCandidate(app, x, y)
  if not (app and app.wm and app.wm.getWindows) then return nil end

  local windows = app.wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local w = windows[i]
    if w and not w._closed and not w._minimized then
      if not w._collapsed and w.specializedToolbar and w.specializedToolbar.contains then
        if w.specializedToolbar:contains(x, y) then
          if w.specializedToolbar.getTooltipAt then
            return w.specializedToolbar:getTooltipAt(x, y)
          end
          return nil
        end
      end

      if w.headerToolbar and w.headerToolbar.contains then
        if w.headerToolbar:contains(x, y) then
          if w.headerToolbar.getTooltipAt then
            return w.headerToolbar:getTooltipAt(x, y)
          end
          return nil
        end
      end

      if w.contains and w:contains(x, y) then
        return nil
      end
    end
  end

  return nil
end

function M.getTopModalTooltipCandidate(app, x, y)
  local modals = {
    app.quitConfirmModal,
    app.saveOptionsModal,
    app.genericActionsModal,
    app.settingsModal,
    app.newWindowTypeModal,
    app.newWindowModal,
    app.openProjectModal,
    app.renameWindowModal,
    app.romPaletteAddressModal,
    app.ppuFrameSpriteLayerModeModal,
    app.ppuFrameAddSpriteModal,
    app.ppuFrameRangeModal,
    app.ppuFramePatternRangeModal,
    app.textFieldDemoModal,
  }

  for _, modal in ipairs(modals) do
    if modal and modal.isVisible and modal:isVisible() and modal.getTooltipAt then
      local candidate = modal:getTooltipAt(x, y)
      if candidate then
        return candidate
      end
    end
  end

  return nil
end

function M.recordWindowCreateUndo(app, win, prevFocusedWin)
  if not (app and app.undoRedo and app.undoRedo.addWindowCreateEvent and win) then
    return false
  end
  return app.undoRedo:addWindowCreateEvent({
    type = "window_create",
    win = win,
    wm = app.wm,
    prevFocusedWin = prevFocusedWin,
  })
end

function M.allocateCloneWindowId(wm, entryKind)
  local base = tostring(entryKind or "window"):gsub("[^%w_]+", "_")
  if base == "" then
    base = "window"
  end
  local n = 1
  local candidate
  repeat
    candidate = string.format("%s_%d", base, n)
    n = n + 1
  until not wm:findWindowById(candidate)
  return candidate
end

function M.deriveCloneWindowTitle(title)
  title = tostring(title or "Window")
  if title:sub(-7) == " (copy)" then
    return title
  end
  return title .. " (copy)"
end

function M.captureRomPaletteAddressUndoState(win)
  return {
    paletteData = TableUtils.deepcopy((win and win.paletteData) or {}),
    selected = {
      col = win and win.selected and win.selected.col or nil,
      row = win and win.selected and win.selected.row or nil,
    },
  }
end

function M.clampByte(byteVal)
  local v = math.floor(tonumber(byteVal) or 0)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

function M.ppuTileLinearIndex(win, col, row)
  return row * (win.cols or 0) + col + 1
end

function M.normalizeTileIndex(item)
  local tileIndex = item and tonumber(item.index) or nil
  if type(tileIndex) ~= "number" then
    tileIndex = item and tonumber(item.tile) or nil
  end
  if type(tileIndex) ~= "number" and item and item.topRef then
    tileIndex = tonumber(item.topRef.index)
  end
  if type(tileIndex) ~= "number" then
    return nil
  end
  tileIndex = math.floor(tileIndex)
  if tileIndex < 0 then
    return nil
  end
  if tileIndex >= 512 then
    tileIndex = tileIndex % 512
  end
  return tileIndex
end

function M.findChrWindowCellForTile(winBank, layerIndex, tileIndex)
  if not (winBank and winBank.getVirtualTileHandle and type(tileIndex) == "number") then
    return nil, nil
  end

  for row = 0, (winBank.rows or 0) - 1 do
    for col = 0, (winBank.cols or 0) - 1 do
      local handle = winBank:getVirtualTileHandle(col, row, layerIndex)
      if handle and tonumber(handle.index) == tileIndex then
        return col, row
      end
    end
  end

  return nil, nil
end

function M.scrollChrWindowToCell(winBank, col, row)
  if not (winBank and type(col) == "number" and type(row) == "number") then
    return
  end

  local maxScrollCol = math.max(0, (winBank.cols or 0) - (winBank.visibleCols or winBank.cols or 1))
  local maxScrollRow = math.max(0, (winBank.rows or 0) - (winBank.visibleRows or winBank.rows or 1))
  local scrollCol = math.max(0, math.min(col, maxScrollCol))
  local scrollRow = math.max(0, math.min(row, maxScrollRow))

  if winBank.setScroll then
    winBank:setScroll(scrollCol, scrollRow)
    return
  end

  winBank.scrollCol = scrollCol
  winBank.scrollRow = scrollRow
end

return M
