local Button = require("user_interface.button")
local Text = require("utils.text_utils")

local M = {}

M.STATUS_MAX_CHARS = 120
M.STATUS_TRUNCATION_SUFFIX = "..."
M.CONTROL_GAP = 6

local TASKBAR_KIND_SORT_RANK = {
  chr = 1,
  rom_window = 1,
  animated_sprite = 2,
  oam_animated = 2,
  animated_tile = 3,
  static_sprite = 4,
  static_tile = 5,
  ppu_frame = 6,
  palette = 7,
  rom_palette = 8,
  generic = 9,
}

function M.pointInRect(px, py, x, y, w, h)
  return px >= x and px <= (x + w) and py >= y and py <= (y + h)
end

function M.appHasLoadedRom(app)
  if app and type(app.hasLoadedROM) == "function" then
    return app:hasLoadedROM()
  end

  local state = app and app.appEditState or nil
  if not state then
    return false
  end
  if type(state.romSha1) == "string" and state.romSha1 ~= "" then
    return true
  end
  return type(state.romRaw) == "string"
    and #state.romRaw > 0
    and type(state.romOriginalPath) == "string"
    and state.romOriginalPath ~= ""
end

function M.splitPath(path)
  if type(path) ~= "string" then
    return "", ""
  end
  local dir, base = path:match("^(.*)[/\\]([^/\\]+)$")
  if not dir then
    return "", path
  end
  return dir, base
end

function M.baseName(path)
  if type(path) ~= "string" then
    return ""
  end
  return path:match("([^/\\]+)$") or path
end

local function getWindowVisualContentKind(win)
  if not (win and win.layers) then
    return nil
  end

  local layer = nil
  if win.getActiveLayerIndex then
    local activeIndex = win:getActiveLayerIndex() or 1
    layer = win.layers[activeIndex]
  end
  layer = layer or win.layers[1]
  return layer and layer.kind or nil
end

function M.getTaskbarIconKeyForWindow(win)
  local kind = win and win.kind or nil
  if kind == "chr" and win and win.isRomWindow == true then
    return "rom_window"
  end

  if kind == "static_art" then
    local contentKind = getWindowVisualContentKind(win)
    if contentKind == "sprite" then
      return "static_sprite"
    end
    return "static_tile"
  end

  if kind == "animation" or kind == "oam_animation" then
    if kind == "oam_animation" then
      return "oam_animated"
    end
    local contentKind = getWindowVisualContentKind(win)
    if contentKind == "tile" then
      return "animated_tile"
    end
    return "animated_sprite"
  end

  if kind == "chr" then return "chr" end
  if kind == "ppu_frame" then return "ppu_frame" end
  if kind == "palette" then return "palette" end
  if kind == "rom_palette" then return "rom_palette" end
  return "generic"
end

function M.getTaskbarSortRankForWindow(win)
  local iconKey = M.getTaskbarIconKeyForWindow(win)
  return TASKBAR_KIND_SORT_RANK[iconKey] or TASKBAR_KIND_SORT_RANK.generic
end

function M.newTaskbarButton(opts)
  opts = opts or {}
  opts.alwaysOpaqueContent = true
  return Button.new(opts)
end

function M.fitStatusText(text, maxWidth)
  if maxWidth <= 0 then return "" end
  local font = love.graphics.getFont()
  if not font or font:getWidth(text) <= maxWidth then
    return text
  end

  local ellipsis = M.STATUS_TRUNCATION_SUFFIX
  local ellipsisWidth = font:getWidth(ellipsis)
  if ellipsisWidth >= maxWidth then
    return ""
  end

  local trimmed = text
  while #trimmed > 0 and (font:getWidth(trimmed) + ellipsisWidth) > maxWidth do
    trimmed = trimmed:sub(1, -2)
  end
  return trimmed .. ellipsis
end

function M.formatStatusText(text)
  return Text.limitChars(
    "" .. tostring(text or ""),
    M.STATUS_MAX_CHARS
  )
end

function M.setLastEvent(app, text)
  if not (app and text) then return end
  app.statusText = text
  app.lastEventText = text
end

return M
