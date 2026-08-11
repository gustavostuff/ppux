local colors = require("app_colors")
local Panel = require("ui.panel")
local UiScale = require("ui.ui_scale")
local ColorPickerMatrix = require("ui.color_picker_matrix")

local M = {}

--[[ Modal chrome feature flags — flip without ripping out call sites.
     MODAL_BACKDROP_ENABLED: translucent dim layer behind centered modals. ]]
M.MODAL_BACKDROP_ENABLED = true

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

--- Place the modal panel. With no remembered position, re-centers every call.
--- After a right-drag, `_panelPosX/Y` pin the panel for the rest of the app
--- session (survives hide/show). Never written to settings.lua or project files.
function M.centerPanel(panel, canvas, modal)
  local cw = canvas:getWidth()
  local ch = canvas:getHeight()
  local pw = panel.w or 0
  local ph = panel.h or 0
  local x, y
  local pinned = modal
    and type(modal._panelPosX) == "number"
    and type(modal._panelPosY) == "number"
  if pinned then
    x = math.floor(modal._panelPosX)
    y = math.floor(modal._panelPosY)
  else
    x = math.floor((cw - pw) / 2)
    y = math.floor((ch - ph) / 2)
  end
  -- Keep a sliver of the panel on-screen so it cannot be dragged away entirely.
  local margin = 16
  if cw > margin then
    x = math.max(margin - pw, math.min(x, cw - margin))
  end
  if ch > margin then
    y = math.max(margin - ph, math.min(y, ch - margin))
  end
  if pinned then
    modal._panelPosX = x
    modal._panelPosY = y
  end
  panel:setPosition(x, y)
  return x, y, pw, ph
end

--- True when (x,y) is over the modal panel box (uses last draw bounds when available).
function M.containsModalBox(modal, x, y)
  if not modal then
    return false
  end
  x = tonumber(x) or 0
  y = tonumber(y) or 0
  if type(modal._boxX) == "number" and type(modal._boxY) == "number"
      and type(modal._boxW) == "number" and type(modal._boxH) == "number" then
    return x >= modal._boxX and x < modal._boxX + modal._boxW
      and y >= modal._boxY and y < modal._boxY + modal._boxH
  end
  local panel = modal.panel
  if panel and type(panel.x) == "number" and type(panel.y) == "number" then
    local w = panel.w or 0
    local h = panel.h or 0
    return x >= panel.x and x < panel.x + w and y >= panel.y and y < panel.y + h
  end
  return false
end

function M.clearPanelDrag(modal)
  if not modal then
    return
  end
  modal._modalDragging = false
  modal._dragGrabX = nil
  modal._dragGrabY = nil
end

function M.resetPanelPosition(modal)
  M.clearPanelDrag(modal)
  if modal then
    modal._panelPosX = nil
    modal._panelPosY = nil
  end
end

--- Call from hide paths if needed: drop an in-progress drag, keep session position.
function M.onModalHidden(modal)
  M.clearPanelDrag(modal)
end

--- Start right-button drag of the whole modal. Returns true when a drag began.
function M.beginRightDrag(modal, x, y)
  if not modal or not M.containsModalBox(modal, x, y) then
    return false
  end
  local boxX = modal._boxX
  local boxY = modal._boxY
  if type(boxX) ~= "number" or type(boxY) ~= "number" then
    local panel = modal.panel
    if not panel then
      return false
    end
    boxX = panel.x or 0
    boxY = panel.y or 0
  end
  modal._modalDragging = true
  modal._dragGrabX = (tonumber(x) or 0) - boxX
  modal._dragGrabY = (tonumber(y) or 0) - boxY
  modal._panelPosX = boxX
  modal._panelPosY = boxY
  return true
end

--- Update an in-progress right-drag. `canvas` optional for clamping.
function M.updateRightDrag(modal, x, y, canvas)
  if not (modal and modal._modalDragging == true) then
    return false
  end
  local grabX = tonumber(modal._dragGrabX) or 0
  local grabY = tonumber(modal._dragGrabY) or 0
  modal._panelPosX = (tonumber(x) or 0) - grabX
  modal._panelPosY = (tonumber(y) or 0) - grabY
  local panel = modal.panel
  if panel and canvas then
    local bx, by, bw, bh = M.centerPanel(panel, canvas, modal)
    modal._boxX, modal._boxY, modal._boxW, modal._boxH = bx, by, bw, bh
  elseif panel then
    panel:setPosition(math.floor(modal._panelPosX), math.floor(modal._panelPosY))
    modal._boxX = modal._panelPosX
    modal._boxY = modal._panelPosY
    modal._boxW = panel.w
    modal._boxH = panel.h
  end
  return true
end

function M.endRightDrag(modal)
  if not modal then
    return false
  end
  local was = modal._modalDragging == true
  modal._modalDragging = false
  modal._dragGrabX = nil
  modal._dragGrabY = nil
  return was
end

function M.isRightDragging(modal)
  return modal ~= nil and modal._modalDragging == true
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
  M.centerPanel(panel, canvas, modal)
  local x, y, w, h = panel:chromeEnvelopeRectPx()
  if (w or 0) <= 0 or (h or 0) <= 0 then
    return nil
  end
  return x, y, w, h
end

local backgroundOverlayOpacity = 0.7
function M.drawBackdrop(canvas)
  if M.MODAL_BACKDROP_ENABLED ~= true then
    return
  end
  local cw = canvas:getWidth()
  local ch = canvas:getHeight()
  love.graphics.setColor(colors.black[1], colors.black[2], colors.black[3], backgroundOverlayOpacity)
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
    target._modalControlOutline = true
  end
  setTrackedDefault(target, "menuOutline", M.DEFAULT_PANEL_STYLE.menuOutline)
end

--- Keep live panel chrome flags aligned after metric refresh (draw paths that avoid rebuild).
function M.syncPanelChrome(panel, modal)
  if not (panel and modal) then
    return
  end
  panel._modalChromeOverBlue = modal._modalChromeOverBlue == true
  panel._modalControlOutline = modal._modalControlOutline == true
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
    app.relocationPointerCalculatorModal,
    app.nametableBreakpointCalculatorModal,
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
