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

function M.isPatternTableBuilder(win)
  return win and win.kind == "pattern_table_builder"
end

function M.isStaticOrAnimationArt(win)
  return M.isStaticArt(win) or M.isPatternTableBuilder(win) or M.isAnimationLike(win)
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

return M
