local colors = require("app_colors")
local Text = require("utils.text_utils")

local M = {}

local PAD_X = 6
local RADIUS = 2
local RIGHT_PAD = 2
local PAD_Y = 2
local TILE_BG = { 0, 0.56, 0 }
local EDIT_BG = { 0.82, 0.64, 0.16 }

function M.install(Taskbar, Helpers)
  local function layout(self)
    local edit = self.app and self.app.mode == "edit"
    local label = edit and "Edit" or "Tile"
    local font = love.graphics.getFont()
    local tw = (font and font:getWidth(label)) or 0
    local th = (font and font:getHeight()) or 0
    local bw = math.max(24, tw + PAD_X * 2)
    local bh = math.max(0, self.h - PAD_Y * 2)
    local bx = math.floor(self.x + self.w - RIGHT_PAD - bw)
    local by = self.y + PAD_Y
    return {
      x = bx,
      y = by,
      w = bw,
      h = bh,
      label = label,
      bg = edit and EDIT_BG or TILE_BG,
      fg = edit and colors.black or colors.white,
      tw = tw,
      th = th,
    }
  end

  function Taskbar:_modeIndicatorContains(px, py)
    local L = layout(self)
    return Helpers.pointInRect(px, py, L.x, L.y, L.w, L.h)
  end

  function Taskbar:_toggleMode()
    local app = self and self.app
    if not app then
      return
    end
    if app._buildCtx then
      local ctx = app:_buildCtx()
      if ctx and ctx.getMode and ctx.setMode then
        local nextMode = (ctx.getMode() == "edit") and "tile" or "edit"
        ctx.setMode(nextMode)
        return
      end
    end
    app.mode = (app.mode == "edit") and "tile" or "edit"
  end

  function Taskbar:_drawModeIndicator()
    local L = layout(self)
    love.graphics.setColor(L.bg[1], L.bg[2], L.bg[3], 1)
    love.graphics.rectangle("fill", L.x, L.y, L.w, L.h, RADIUS, RADIUS)
    local tx = math.floor(L.x + (L.w - L.tw) * 0.5)
    local ty = math.floor(L.y + (L.h - L.th) * 0.5)
    Text.print(L.label, tx, ty, {
      color = { L.fg[1], L.fg[2], L.fg[3], 1 },
      literalColor = true,
    })
    love.graphics.setColor(colors.white)
  end
end

return M
