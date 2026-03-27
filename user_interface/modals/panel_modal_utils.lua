local colors = require("app_colors")
local Panel = require("user_interface.panel")

local M = {}

M.MODAL_BUTTON_H = 15
M.MODAL_ICON_BUTTON_SIZE = 15
M.MODAL_TEXT_OFFSET_Y = 1

M.DEFAULT_PANEL_STYLE = {
  padding = 2,
  rowGap = 2,
  colGap = 2,
  cellPaddingX = 0,
  cellPaddingY = 0,
  cellW = Panel.DEFAULT_CELL_W,
  cellH = M.MODAL_BUTTON_H,
  titleH = 18,
  bgColor = { 0.356, 0.424, 0.851 },
}

function M.centerPanel(panel, canvas)
  local cw = canvas:getWidth()
  local ch = canvas:getHeight()
  local x = math.floor((cw - panel.w) / 2)
  local y = math.floor((ch - panel.h) / 2)
  panel:setPosition(x, y)
  return x, y, panel.w, panel.h
end

function M.drawBackdrop(canvas)
  local cw = canvas:getWidth()
  local ch = canvas:getHeight()
  love.graphics.setColor(colors.black[1], colors.black[2], colors.black[3], 0.5)
  love.graphics.rectangle("fill", 0, 0, cw, ch)
  love.graphics.setColor(colors.white)
end

function M.applyPanelDefaults(target)
  target.padding = target.padding or M.DEFAULT_PANEL_STYLE.padding
  target.rowGap = target.rowGap or M.DEFAULT_PANEL_STYLE.rowGap
  target.colGap = target.colGap or M.DEFAULT_PANEL_STYLE.colGap
  target.cellPaddingX = target.cellPaddingX or M.DEFAULT_PANEL_STYLE.cellPaddingX
  target.cellPaddingY = target.cellPaddingY or M.DEFAULT_PANEL_STYLE.cellPaddingY
  target.cellW = target.cellW or M.DEFAULT_PANEL_STYLE.cellW
  target.cellH = target.cellH or M.DEFAULT_PANEL_STYLE.cellH
  target.rowH = target.rowH or target.cellH
  target.titleH = target.titleH or M.DEFAULT_PANEL_STYLE.titleH
  target.bgColor = target.bgColor or M.DEFAULT_PANEL_STYLE.bgColor
  target.textOffsetY = target.textOffsetY or M.MODAL_TEXT_OFFSET_Y
end

return M
