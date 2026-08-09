-- ui/ui_font.lua
-- App UI typeface selection. Fonts live under ui/fonts/.
--
-- Flip UI_FONT_FAMILY to switch the whole app between Proggy Tiny and Aseprite.

local M = {}

--- Preferred UI font family: "proggy_tiny" (default) or "aseprite".
M.UI_FONT_FAMILY = "aseprite"

local FAMILY_PATHS = {
  proggy_tiny = {
    "ui/fonts/proggy-tiny.ttf",
    "../ui/fonts/proggy-tiny.ttf",
  },
  aseprite = {
    "ui/fonts/AsepriteFont.ttf",
    "../ui/fonts/AsepriteFont.ttf",
  },
}

local FALLBACK_PATHS = {
  "ui/fonts/proggy-tiny.ttf",
  "../ui/fonts/proggy-tiny.ttf",
  "ui/fonts/AsepriteFont.ttf",
  "../ui/fonts/AsepriteFont.ttf",
  "ui/fonts/proggy-clean-sz.ttf",
  "../ui/fonts/proggy-clean-sz.ttf",
  "ui/fonts/Tiny5-Regular.ttf",
}

local function appendUnique(dst, paths)
  local seen = {}
  for _, p in ipairs(dst) do
    seen[p] = true
  end
  for _, p in ipairs(paths or {}) do
    if not seen[p] then
      seen[p] = true
      dst[#dst + 1] = p
    end
  end
end

--- Ordered font file candidates for the active family, then shared fallbacks.
function M.candidatePaths(family)
  family = family or M.UI_FONT_FAMILY
  local out = {}
  appendUnique(out, FAMILY_PATHS[family] or FAMILY_PATHS.proggy_tiny)
  appendUnique(out, FALLBACK_PATHS)
  return out
end

--- Load a Love font at `size` using the active (or given) family.
--  Returns a Font, or nil if Love graphics is unavailable.
function M.load(size, family)
  size = tonumber(size) or 16
  if not (love and love.graphics and love.graphics.newFont) then
    return nil
  end
  for _, path in ipairs(M.candidatePaths(family)) do
    local ok, font = pcall(love.graphics.newFont, path, size)
    if ok and font then
      return font
    end
  end
  return love.graphics.newFont(size)
end

return M
