-- CHR bank UX helpers: hover tooltip text, copy tile bytes as hex.

local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

function M.formatTileChrBytesHexSpaceSeparated(bankBytes, tileIndex)
  if not bankBytes then
    return nil
  end
  tileIndex = math.floor(tonumber(tileIndex) or 0)
  if tileIndex < 0 or tileIndex > 511 then
    return nil
  end
  local base = tileIndex * 16
  local parts = {}
  for i = 1, 16 do
    local b = tonumber(bankBytes[base + i]) or 0
    b = math.floor(b) % 256
    if b < 0 then
      b = 0
    end
    parts[i] = string.format("%02X", b)
  end
  return table.concat(parts, " ")
end

function M.setSystemClipboardText(text)
  if type(text) ~= "string" or text == "" then
    return false
  end
  if love and love.system and love.system.setClipboardText then
    love.system.setClipboardText(text)
    return true
  end
  return false
end

--- Copy 16 CHR bytes for `tileIndex` in `chrBanksBytes[bankIdx]` to the OS clipboard.
function M.copyChrTileHexToClipboard(app, bankIdx, tileIndex)
  if not app then
    return false, "Invalid app"
  end
  bankIdx = math.floor(tonumber(bankIdx) or 1)
  tileIndex = math.floor(tonumber(tileIndex) or -1)
  if tileIndex < 0 or tileIndex > 511 then
    return false, "Tile index out of range"
  end

  local state = app.appEditState
  local bank = state and state.chrBanksBytes and state.chrBanksBytes[bankIdx]
  if not bank then
    return false, "No CHR bank loaded"
  end

  local hex = M.formatTileChrBytesHexSpaceSeparated(bank, tileIndex)
  if not hex then
    return false, "Could not read tile bytes"
  end
  if not M.setSystemClipboardText(hex) then
    return false, ("Tile %d hex (clipboard unavailable): %s"):format(tileIndex, hex)
  end
  return true, ("Copied tile %d (0x%02X) bytes: %s"):format(tileIndex, tileIndex % 256, hex)
end

--- Copy 16 CHR bytes of the focused window's selected tile to the OS clipboard.
function M.copySelectedTileHexToClipboard(ctx, focus)
  if not (focus and WindowCaps.isChrLike(focus) and focus.getSelected and focus.getTileIndexAt) then
    return false, "CHR selection unavailable"
  end
  local col, row = focus:getSelected()
  if col == nil or row == nil then
    return false, "Select a CHR tile first"
  end
  local ti = focus:getTileIndexAt(col, row)
  if ti == nil then
    return false, "Could not resolve tile index"
  end

  local app = ctx and ctx.app
  local state = app and app.appEditState
  local bankIdx = tonumber(focus.currentBank) or tonumber(state and state.currentBank) or 1
  return M.copyChrTileHexToClipboard(app, bankIdx, ti)
end

function M.hoverTooltipCandidate(ctx, drag, mx, my)
  if drag and (drag.active or drag.pending) then
    return nil
  end
  if not (ctx and ctx.wm) then
    return nil
  end
  local wm = ctx.wm()
  local win = wm and wm:getFocus()
  if not (win and WindowCaps.isChrLike(win)) then
    return nil
  end
  if win._collapsed then
    return nil
  end
  if win.isInContentArea and not win:isInContentArea(mx, my) then
    return nil
  end
  local tb = win.specializedToolbar
  if tb and tb.contains and tb:contains(mx, my) then
    return nil
  end

  if not (win.toGridCoords and win.getTileIndexAt) then
    return nil
  end
  local ok, col, row = win:toGridCoords(mx, my)
  if not ok then
    return nil
  end
  local ti = win:getTileIndexAt(col, row)
  if ti == nil then
    return nil
  end
  ti = math.floor(tonumber(ti) or -1)
  if ti < 0 or ti > 511 then
    return nil
  end

  local text = ("Tile %d (0x%02X)\n(col %d, row %d)"):format(ti, ti % 256, col, row)
  return {
    text = text,
    immediate = false,
    key = table.concat({
      "chr_hover",
      tostring(win._id or win.title or ""),
      tostring(win.currentBank or 1),
      tostring(col),
      tostring(row),
      tostring(ti),
    }, "|"),
  }
end

return M
