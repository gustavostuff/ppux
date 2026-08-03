-- sketch_canvas_palette_controller.lua
-- Link sketch canvases to sketch-mode ROM palettes; attribute helpers.

local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

M.ATTR_BYTES = 64
M.GRID_COLS = 32
M.GRID_ROWS = 30

function M.isSketchModePalette(win)
  return WindowCaps.isRomPaletteWindow(win) and win.paletteRole == "sketch"
end

function M.ensureAttrBytes(sketchWin)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return nil
  end
  if type(sketchWin.nametableAttrBytes) ~= "table" or #sketchWin.nametableAttrBytes ~= M.ATTR_BYTES then
    local attrs = {}
    for i = 1, M.ATTR_BYTES do
      attrs[i] = 0
    end
    sketchWin.nametableAttrBytes = attrs
  end
  return sketchWin.nametableAttrBytes
end

--- Fill all attribute quadrants with NES palette index 0 (UI key 1).
function M.resetAttrsToPaletteRow0(sketchWin)
  local attrs = M.ensureAttrBytes(sketchWin)
  if not attrs then
    return false
  end
  for i = 1, M.ATTR_BYTES do
    attrs[i] = 0
  end
  return true
end

function M.getLinkedSketchPalette(sketchWin, wm)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return nil
  end
  local layer = sketchWin.layers and sketchWin.layers[1]
  local pd = layer and layer.paletteData
  local winId = pd and pd.winId
  if type(winId) ~= "string" or winId == "" then
    return nil
  end
  if not wm then
    local ctx = rawget(_G, "ctx")
    if ctx then
      if type(ctx.wm) == "function" then
        wm = ctx.wm()
      elseif ctx.app and ctx.app.wm then
        wm = ctx.app.wm
      end
    end
  end
  if not (wm and wm.findWindowById) then
    return nil
  end
  local pal = wm:findWindowById(winId)
  if M.isSketchModePalette(pal) and not pal._closed then
    return pal
  end
  return nil
end

--- Palette number 1-4 for tile col/row from attribute table (nil if no attrs).
function M.getTilePaletteNumber(sketchWin, col, row)
  local attrs = sketchWin and sketchWin.nametableAttrBytes
  if type(attrs) ~= "table" or #attrs < 1 then
    return nil
  end
  col = math.floor(tonumber(col) or 0)
  row = math.floor(tonumber(row) or 0)
  local cols = sketchWin.cols or M.GRID_COLS
  local attrCols = math.floor(cols / 4)
  if attrCols < 1 then
    attrCols = 8
  end
  local attrCol = math.floor(col / 4)
  local attrRow = math.floor(row / 4)
  local attrIndex = attrRow * attrCols + attrCol + 1
  local attrByte = math.floor(tonumber(attrs[attrIndex]) or 0) % 256
  local localCol = col % 4
  local localRow = row % 4
  local palIndex
  if localRow < 2 then
    if localCol < 2 then
      palIndex = attrByte % 4
    else
      palIndex = math.floor((attrByte % 16) / 4)
    end
  else
    if localCol < 2 then
      palIndex = math.floor((attrByte % 64) / 16)
    else
      palIndex = math.floor(attrByte / 64)
    end
  end
  return palIndex + 1
end

function M.onLinkedToPalette(sketchWin, paletteWin)
  if not WindowCaps.isSketchCanvas(sketchWin) then
    return false
  end
  if not M.isSketchModePalette(paletteWin) then
    return false, "Sketch canvases need a sketch-mode ROM palette"
  end
  M.resetAttrsToPaletteRow0(sketchWin)
  return true
end

--- Encode 32-byte NES palette blob from a sketch-mode ROM palette window.
--  BG rows from 4x4 codes. Sprite color-0 slots ($3F10/$14/$18/$1C) mirror
--  BG color 0 ($3F00), so they must match BG0 or a later write stomps the backdrop.
--  Other sprite colors stay 0F (unused in gallery BG slides).
--  Falls back to hardcoded gallery defaults when palette is missing.
function M.encodePaletteBlob32(paletteWin)
  local bg = {
    { "07", "17", "27", "36" },
    { "07", "17", "27", "36" },
    { "07", "17", "27", "36" },
    { "07", "17", "27", "36" },
  }
  if M.isSketchModePalette(paletteWin) and paletteWin.codes2D then
    for row = 0, 3 do
      local rowTbl = paletteWin.codes2D[row]
      if type(rowTbl) == "table" then
        for col = 0, 3 do
          local code = rowTbl[col]
          if type(code) == "string" and #code >= 2 then
            bg[row + 1][col + 1] = string.upper(code:sub(1, 2))
          end
        end
      end
    end
  end

  local bytes = {}
  for row = 1, 4 do
    for col = 1, 4 do
      bytes[#bytes + 1] = tonumber(bg[row][col], 16) or 0x0F
    end
  end
  -- Sprite rows: match BG0 on mirrored color-0 slots, then 0F fillers.
  local bg0 = bytes[1] or 0x07
  for _ = 1, 4 do
    bytes[#bytes + 1] = bg0
    bytes[#bytes + 1] = 0x0F
    bytes[#bytes + 1] = 0x0F
    bytes[#bytes + 1] = 0x0F
  end
  return bytes
end

function M.encodePaletteBlob32String(paletteWin)
  local bytes = M.encodePaletteBlob32(paletteWin)
  local chars = {}
  for i = 1, #bytes do
    chars[i] = string.char(bytes[i] % 256)
  end
  return table.concat(chars)
end

return M
