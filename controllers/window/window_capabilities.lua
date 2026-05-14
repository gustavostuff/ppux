-- window_capabilities.lua
-- Shared predicates for common window-kind checks.

local M = {}

function M.isChrLike(win)
  return win and win.kind == "chr"
end

function M.isAnimationLike(win)
  return win and (win.kind == "animation" or win.kind == "oam_animation")
end

function M.isStaticArt(win)
  return win and win.kind == "static_art"
end

function M.isPatternSketchCanvas(win)
  return win and win.kind == "pattern_sketch_canvas"
end

function M.isPatternTable(win)
  return win and win.kind == "pattern_table"
end

function M.isStaticOrAnimationArt(win)
  -- Includes pattern_table: tile-grid editor with same input/invalidation expectations as static art.
  return M.isStaticArt(win)
    or M.isPatternSketchCanvas(win)
    or M.isAnimationLike(win)
    or M.isPatternTable(win)
end

function M.isPpuFrame(win)
  return win and win.kind == "ppu_frame"
end

function M.isOamAnimation(win)
  return win and win.kind == "oam_animation"
end

function M.isStartAddrSpriteSyncWindow(win)
  return win and (win.kind == "oam_animation" or win.kind == "ppu_frame")
end

function M.isRomPaletteWindow(win)
  return win and win.kind == "rom_palette"
end

function M.isGlobalPaletteWindow(win)
  return win and win.kind == "palette"
end

function M.isAnyPaletteWindow(win)
  return win and (win.isPalette == true or win.kind == "palette" or win.kind == "rom_palette")
end

function M.isCrtLens(win)
  return win and win.kind == "crt_lens"
end

--- Windows that can supply CRT viz references: editable/layout canvases (not palettes or CHR/ROM banks).
function M.isCrtVizLayoutWindow(win)
  if not win or win._closed or win._minimized or win._groupHidden == true then
    return false
  end
  if M.isCrtLens(win) then
    return false
  end
  if M.isAnyPaletteWindow(win) then
    return false
  end
  if M.isChrLike(win) then
    return false
  end
  return true
end

return M
