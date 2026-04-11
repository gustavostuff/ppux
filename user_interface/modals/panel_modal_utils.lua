local colors = require("app_colors")
local Panel = require("user_interface.panel")
local UiScale = require("user_interface.ui_scale")

local M = {}

M.MODAL_BUTTON_H = UiScale.modalButtonHeight()
M.MODAL_ICON_BUTTON_SIZE = UiScale.modalButtonHeight()

M.DEFAULT_PANEL_STYLE = {}

local function copyColor(color)
  if type(color) ~= "table" then
    return color
  end
  return { color[1], color[2], color[3], color[4] }
end

local function setTrackedDefault(target, key, value)
  local marker = "_uses_modal_default_" .. key
  if target[key] == nil then
    target[key] = value
    target[marker] = true
    return
  end
  if target[marker] == true then
    target[key] = value
  end
end

function M.refreshMetrics()
  M.MODAL_BUTTON_H = UiScale.modalButtonHeight()
  M.MODAL_ICON_BUTTON_SIZE = UiScale.modalButtonHeight()

  M.DEFAULT_PANEL_STYLE.padding = 2
  M.DEFAULT_PANEL_STYLE.rowGap = 2
  M.DEFAULT_PANEL_STYLE.colGap = 2
  M.DEFAULT_PANEL_STYLE.cellPaddingX = 0
  M.DEFAULT_PANEL_STYLE.cellPaddingY = 0
  M.DEFAULT_PANEL_STYLE.cellW = Panel.DEFAULT_CELL_W
  M.DEFAULT_PANEL_STYLE.cellH = M.MODAL_BUTTON_H
  M.DEFAULT_PANEL_STYLE.titleH = M.DEFAULT_PANEL_STYLE.cellH
  M.DEFAULT_PANEL_STYLE.bgColor = { 0.356, 0.424, 0.851 }
  local titleBg = copyColor(colors.gray20)
  if type(titleBg) == "table" then
    titleBg[4] = 0.4
  end
  M.DEFAULT_PANEL_STYLE.titleBgColor = titleBg
end

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
  M.refreshMetrics()
  setTrackedDefault(target, "padding", M.DEFAULT_PANEL_STYLE.padding)
  setTrackedDefault(target, "rowGap", M.DEFAULT_PANEL_STYLE.rowGap)
  setTrackedDefault(target, "colGap", M.DEFAULT_PANEL_STYLE.colGap)
  setTrackedDefault(target, "cellPaddingX", M.DEFAULT_PANEL_STYLE.cellPaddingX)
  setTrackedDefault(target, "cellPaddingY", M.DEFAULT_PANEL_STYLE.cellPaddingY)
  setTrackedDefault(target, "cellW", M.DEFAULT_PANEL_STYLE.cellW)
  setTrackedDefault(target, "cellH", M.DEFAULT_PANEL_STYLE.cellH)
  if target.rowH == nil then
    target.rowH = target.cellH
    target._uses_modal_default_rowH = true
  elseif target._uses_modal_default_rowH == true then
    target.rowH = target.cellH
  end
  setTrackedDefault(target, "titleH", M.DEFAULT_PANEL_STYLE.titleH)
  setTrackedDefault(target, "bgColor", copyColor(M.DEFAULT_PANEL_STYLE.bgColor))
  setTrackedDefault(target, "titleBgColor", copyColor(M.DEFAULT_PANEL_STYLE.titleBgColor))
end

function M.refreshTargetMetrics(target)
  if not target then return end
  M.refreshMetrics()
  setTrackedDefault(target, "padding", M.DEFAULT_PANEL_STYLE.padding)
  setTrackedDefault(target, "rowGap", M.DEFAULT_PANEL_STYLE.rowGap)
  setTrackedDefault(target, "colGap", M.DEFAULT_PANEL_STYLE.colGap)
  setTrackedDefault(target, "cellPaddingX", M.DEFAULT_PANEL_STYLE.cellPaddingX)
  setTrackedDefault(target, "cellPaddingY", M.DEFAULT_PANEL_STYLE.cellPaddingY)
  setTrackedDefault(target, "cellW", M.DEFAULT_PANEL_STYLE.cellW)
  setTrackedDefault(target, "cellH", M.DEFAULT_PANEL_STYLE.cellH)
  if target._uses_modal_default_rowH == true then
    target.rowH = target.cellH
  end
  setTrackedDefault(target, "titleH", M.DEFAULT_PANEL_STYLE.titleH)
  if target._uses_modal_default_bgColor == true then
    target.bgColor = copyColor(M.DEFAULT_PANEL_STYLE.bgColor)
  end
  if target._uses_modal_default_titleBgColor == true then
    target.titleBgColor = copyColor(M.DEFAULT_PANEL_STYLE.titleBgColor)
  end
end

M.refreshMetrics()

return M
