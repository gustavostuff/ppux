-- Shared helpers for palette_window and rom_palette_window.
local colors = require("app_colors")

-- Known-problematic blacks when written to ROM / project → force to 0F.
local INVALID_BLACK_CODES = {
  ["0D"] = true, ["0E"] = true,
  ["1E"] = true, ["2E"] = true, ["3E"] = true,
  ["1F"] = true, ["2F"] = true, ["3F"] = true,
}

local function clamp(n, a, b)
  if n < a then return a elseif n > b then return b else return n end
end

local function hex2(n)
  return string.format("%02X", n)
end

local function isInvalidBlack(code)
  if type(code) ~= "string" then return false end
  return INVALID_BLACK_CODES[code:upper()] == true
end

--- Map invalid NES "black" codes to the canonical project black $0F.
local function normalizeInvalidBlack(code)
  if type(code) ~= "string" then return code end
  local upper = code:upper()
  if INVALID_BLACK_CODES[upper] then
    return "0F"
  end
  return upper
end

local function getLabelTextColor(rgb)
  rgb = rgb or colors.black
  local r, g, b = rgb[1] or 0, rgb[2] or 0, rgb[3] or 0
  local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
  local base = (luminance >= 0.5) and colors.black or colors.white
  return { base[1], base[2], base[3], 0.5 }
end

--- Step one nibble axis (dx/dy), skipping invalid blacks so navigation can leave $0F.
--- Selecting an invalid black elsewhere still normalizes to $0F on write/save.
local function nibbleAdjust(code, dx, dy)
  dx = math.floor(tonumber(dx) or 0)
  dy = math.floor(tonumber(dy) or 0)
  local start = type(code) == "string" and code:upper() or "0F"
  if dx == 0 and dy == 0 then
    return start
  end

  local v = tonumber(start, 16) or 0
  local hi = math.floor(v / 16)
  local lo = v % 16

  while true do
    local nhi = clamp(hi + dy, 0, 3)
    local nlo = clamp(lo + dx, 0, 15)
    if nhi == hi and nlo == lo then
      -- Hit the edge without a valid landing code — stay put.
      return start
    end
    hi, lo = nhi, nlo
    local candidate = hex2(hi * 16 + lo)
    if not isInvalidBlack(candidate) then
      return candidate
    end
  end
end

local function markPaletteUnsaved()
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  if app and app.markUnsaved then
    app:markUnsaved("palette_color_change")
  end
end

local function recordPaletteColorUndo(actions, paletteStates)
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  if not (app and app.undoRedo and app.undoRedo.addPaletteColorEvent) then
    return false
  end
  return app.undoRedo:addPaletteColorEvent({
    type = "palette_color",
    actions = actions,
    paletteStates = paletteStates or {},
  })
end

local function invalidateLinkedPpuFrames(paletteWin)
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  if app and app.invalidateConsumersOfPaletteWindow then
    app:invalidateConsumersOfPaletteWindow(paletteWin)
  elseif app and app.invalidatePpuFrameLayersAffectedByPaletteWin then
    app:invalidatePpuFrameLayersAffectedByPaletteWin(paletteWin)
  end
end

return {
  clamp = clamp,
  hex2 = hex2,
  INVALID_BLACK_CODES = INVALID_BLACK_CODES,
  isInvalidBlack = isInvalidBlack,
  normalizeInvalidBlack = normalizeInvalidBlack,
  getLabelTextColor = getLabelTextColor,
  nibbleAdjust = nibbleAdjust,
  markPaletteUnsaved = markPaletteUnsaved,
  recordPaletteColorUndo = recordPaletteColorUndo,
  invalidateLinkedPpuFrames = invalidateLinkedPpuFrames,
}
