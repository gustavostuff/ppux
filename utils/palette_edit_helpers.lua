-- Shared helpers for palette_window and rom_palette_window.
local colors = require("app_colors")

local function clamp(n, a, b)
  if n < a then return a elseif n > b then return b else return n end
end

local function hex2(n)
  return string.format("%02X", n)
end

local function getLabelTextColor(rgb)
  rgb = rgb or colors.black
  local r, g, b = rgb[1] or 0, rgb[2] or 0, rgb[3] or 0
  local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
  local base = (luminance >= 0.5) and colors.black or colors.white
  return { base[1], base[2], base[3], 0.5 }
end

local function nibbleAdjust(code, dx, dy)
  local v = tonumber(code, 16) or 0
  local hi = math.floor(v / 16)
  local lo = v % 16
  hi = clamp(hi + (dy or 0), 0, 3)
  lo = clamp(lo + (dx or 0), 0, 15)
  return hex2(hi * 16 + lo)
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
  if app and app.invalidatePpuFrameLayersAffectedByPaletteWin then
    app:invalidatePpuFrameLayersAffectedByPaletteWin(paletteWin)
  end
end

return {
  clamp = clamp,
  hex2 = hex2,
  getLabelTextColor = getLabelTextColor,
  nibbleAdjust = nibbleAdjust,
  markPaletteUnsaved = markPaletteUnsaved,
  recordPaletteColorUndo = recordPaletteColorUndo,
  invalidateLinkedPpuFrames = invalidateLinkedPpuFrames,
}
