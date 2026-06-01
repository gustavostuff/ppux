local colors = require("app_colors")
local Panel = require("user_interface.panel")
local UiScale = require("user_interface.ui_scale")
local ColorPickerMatrix = require("user_interface.color_picker_matrix")

local M = {}

--[[ Modal chrome feature flags — flip without ripping out call sites.
     MODAL_BACKDROP_ENABLED: translucent dim layer behind centered modals. ]]
M.MODAL_BACKDROP_ENABLED = false

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
  M.DEFAULT_PANEL_STYLE.bgCornerRadius = 2
  M.DEFAULT_PANEL_STYLE.titleCornerRadius = 2
  local styleColor = copyColor(colors:focusedChromeColor())
  M.DEFAULT_PANEL_STYLE.bgColor = copyColor(styleColor)
  M.DEFAULT_PANEL_STYLE.titleBgColor = copyColor(styleColor)
  M.DEFAULT_PANEL_STYLE.menuOutline = false
end

function M.centerPanel(panel, canvas)
  local cw = canvas:getWidth()
  local ch = canvas:getHeight()
  local x = math.floor((cw - panel.w) / 2)
  local y = math.floor((ch - panel.h) / 2)
  panel:setPosition(x, y)
  return x, y, panel.w, panel.h
end

--- Sync an existing modal panel from modal fields without rebuilding (safe for shadow-mask layout).
function M.syncLivePanelLayoutFromModal(modal)
  if not modal or not modal.panel then
    return
  end
  M.refreshTargetMetrics(modal)
  local panel = modal.panel
  if modal.cellW ~= nil then panel.cellW = modal.cellW end
  if modal.cellH ~= nil then panel.cellH = modal.cellH end
  if modal.padding ~= nil then panel.padding = modal.padding end
  local spacingX = modal.buttonGap or modal.colGap
  if spacingX ~= nil then panel.spacingX = spacingX end
  if modal.rowGap ~= nil then panel.spacingY = modal.rowGap end
  if modal.cellPaddingX ~= nil then panel.cellPaddingX = modal.cellPaddingX end
  if modal.cellPaddingY ~= nil then panel.cellPaddingY = modal.cellPaddingY end
  if modal.title ~= nil then panel.title = modal.title end
  if modal.titleH ~= nil then panel.titleH = modal.titleH end
  if modal.bgColor ~= nil then panel.bgColor = modal.bgColor end
  if modal.titleBgColor ~= nil then panel.titleBgColor = modal.titleBgColor end
  M.syncPanelChrome(panel, modal)
  if type(panel.updateLayout) == "function" then
    panel:updateLayout()
  end
end

--- Centered panel bounds in canvas space for drop-shadow masks (uses window shadow settings at draw time).
function M.modalPanelShadowRect(modal, canvas)
  if not modal or not modal.isVisible or not modal:isVisible() then
    return nil
  end
  local panel = modal.panel
  if not panel then
    return nil
  end
  M.syncLivePanelLayoutFromModal(modal)
  M.centerPanel(panel, canvas)
  local x, y, w, h = panel:chromeEnvelopeRectPx()
  if (w or 0) <= 0 or (h or 0) <= 0 then
    return nil
  end
  return x, y, w, h
end

function M.drawBackdrop(canvas)
  if M.MODAL_BACKDROP_ENABLED ~= true then
    return
  end
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
  setTrackedDefault(target, "bgCornerRadius", M.DEFAULT_PANEL_STYLE.bgCornerRadius)
  setTrackedDefault(target, "titleCornerRadius", M.DEFAULT_PANEL_STYLE.titleCornerRadius)
  setTrackedDefault(target, "bgColor", copyColor(M.DEFAULT_PANEL_STYLE.bgColor))
  setTrackedDefault(target, "titleBgColor", copyColor(M.DEFAULT_PANEL_STYLE.titleBgColor))
  if target._uses_modal_default_bgColor == true then
    target._modalChromeOverBlue = true
  end
  setTrackedDefault(target, "menuOutline", M.DEFAULT_PANEL_STYLE.menuOutline)
end

--- Keep live panel chrome flags aligned after metric refresh (draw paths that avoid rebuild).
function M.syncPanelChrome(panel, modal)
  if not (panel and modal) then
    return
  end
  panel._modalChromeOverBlue = modal._modalChromeOverBlue == true
  panel.menuOutline = modal.menuOutline == true
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
  setTrackedDefault(target, "bgCornerRadius", M.DEFAULT_PANEL_STYLE.bgCornerRadius)
  setTrackedDefault(target, "titleCornerRadius", M.DEFAULT_PANEL_STYLE.titleCornerRadius)
  if target._uses_modal_default_bgColor == true then
    target.bgColor = copyColor(M.DEFAULT_PANEL_STYLE.bgColor)
  end
  if target._uses_modal_default_titleBgColor == true then
    target.titleBgColor = copyColor(M.DEFAULT_PANEL_STYLE.titleBgColor)
  end
  if target._uses_modal_default_bgColor == true then
    target._modalChromeOverBlue = true
  end
  setTrackedDefault(target, "menuOutline", M.DEFAULT_PANEL_STYLE.menuOutline)
  if target._settingsTabbedChrome == true then
    local fc = colors:focusedChromeColor()
    local dr, dg, db = ColorPickerMatrix.adjustRgbLightnessByPickerSteps(fc[1], fc[2], fc[3], -1)
    target.bgColor = { dr, dg, db }
    target.titleBgColor = { dr, dg, db }
  end
end

--- After appearance chrome overrides change, resync modal panel fills from colors:focusedChromeColor().
function M.refreshModalChromeFromAppearanceChange(app)
  if not app then
    return
  end
  M.refreshMetrics()
  local modals = {
    app.quitConfirmModal,
    app.pressEscAgainExitModal,
    app.saveOptionsModal,
    app.genericActionsModal,
    app.settingsModal,
    app.newWindowModal,
    app.newWindowTypeModal,
    app.openProjectModal,
    app.openReferencePngModal,
    app.renameWindowModal,
    app.romPaletteAddressModal,
    app.ppuFrameSpriteLayerModeModal,
    app.ppuFrameRangeModal,
    app.ppuFramePatternRangeModal,
    app.ppuFrameAddSpriteModal,
    app.textFieldDemoModal,
  }
  for _, modal in ipairs(modals) do
    if modal and modal._uses_modal_default_bgColor == true then
      M.refreshTargetMetrics(modal)
    end
  end
  if colors.syncLoveGraphicsBackground then
    colors:syncLoveGraphicsBackground()
  end
end

M.refreshMetrics()

return M
