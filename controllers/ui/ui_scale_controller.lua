local UiScale = require("user_interface.ui_scale")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local M = {}

local function applyButtonScale(button)
  if not button then return end
  if type(button.applyUiScale) == "function" then
    button:applyUiScale()
    return
  end

  local w = tonumber(button.w)
  local h = tonumber(button.h)
  if UiScale.isScalableButtonSquare(w, h) then
    local size = UiScale.buttonSize()
    if type(button.setSize) == "function" then
      button:setSize(size, size)
    else
      button.w = size
      button.h = size
    end
  end
end

local function applyToolbarScale(toolbar)
  if not toolbar then return end

  if UiScale.isKnownWindowHeaderHeight(toolbar.h) then
    toolbar.h = UiScale.windowHeaderHeight()
  end

  for _, button in ipairs(toolbar.buttons or {}) do
    applyButtonScale(button)
  end

  if type(toolbar.updatePosition) == "function" then
    toolbar:updatePosition()
  elseif type(toolbar._layoutButtons) == "function" then
    toolbar:_layoutButtons()
  end
end

local function applyMenuScale(menu)
  if not menu then return end
  local cell = UiScale.menuCellSize()
  if type(menu.setCellSize) == "function" then
    menu:setCellSize(cell, cell)
    return
  end
  menu.cellW = cell
  menu.cellH = cell
  if type(menu.setItems) == "function" then
    menu:setItems(menu.items or {})
  end
end

local function applyWindowScale(win)
  if not win then return end
  if win.headerH == nil or UiScale.isKnownWindowHeaderHeight(win.headerH) then
    win.headerH = UiScale.windowHeaderHeight()
  end
  applyToolbarScale(win.headerToolbar)
  applyToolbarScale(win.specializedToolbar)
end

local function refreshModal(modal)
  if not modal then return end
  ModalPanelUtils.refreshTargetMetrics(modal)

  local buttonFields = {
    "yesButton",
    "noButton",
    "modeButton",
  }
  for _, key in ipairs(buttonFields) do
    applyButtonScale(modal[key])
  end

  if modal.colsSpinner and type(modal.colsSpinner.applyUiScale) == "function" then
    modal.colsSpinner:applyUiScale()
  end
  if modal.rowsSpinner and type(modal.rowsSpinner.applyUiScale) == "function" then
    modal.rowsSpinner:applyUiScale()
  end
  if modal.nameField and type(modal.nameField.applyUiScale) == "function" then
    modal.nameField:applyUiScale()
  end

  if modal.panel then
    if modal.panel.cellW and modal.cellW then
      modal.panel.cellW = modal.cellW
    end
    if modal.panel.cellH then
      modal.panel.cellH = modal.rowH or modal.cellH or modal.panel.cellH
    end
    if modal.panel.titleH and modal.titleH then
      modal.panel.titleH = modal.titleH
    end
    if modal.panel.textOffsetY ~= nil and modal.textOffsetY ~= nil then
      modal.panel.textOffsetY = modal.textOffsetY
    end
    if type(modal.panel.updateLayout) == "function" then
      modal.panel:updateLayout()
    end
  end
end

local function refreshModalMetrics(app)
  if not app then return end
  local modals = {
    app.quitConfirmModal,
    app.saveOptionsModal,
    app.genericActionsModal,
    app.settingsModal,
    app.newWindowModal,
    app.renameWindowModal,
    app.romPaletteAddressModal,
    app.ppuFrameSpriteLayerModeModal,
    app.ppuFrameRangeModal,
    app.textFieldDemoModal,
  }
  for _, modal in ipairs(modals) do
    refreshModal(modal)
  end
end

function M.applyForCrtMode(app, enabled)
  UiScale.setCompactMode(enabled == true)
  ModalPanelUtils.refreshMetrics()

  if app then
    applyMenuScale(app.windowHeaderContextMenu)
    applyMenuScale(app.emptySpaceContextMenu)

    if app.taskbar then
      app.taskbar.h = UiScale.taskbarHeight()
      if app.taskbar.minimizedScrollLeftButton then
        app.taskbar.minimizedScrollLeftButton.h = UiScale.buttonSize()
      end
      if app.taskbar.minimizedScrollRightButton then
        app.taskbar.minimizedScrollRightButton.h = UiScale.buttonSize()
      end
      for _, button in ipairs(app.taskbar.buttons or {}) do
        applyButtonScale(button)
      end
      applyMenuScale(app.taskbar.menuController)
      if app.canvas and app.taskbar.updateLayout then
        app.taskbar:updateLayout(app.canvas:getWidth(), app.canvas:getHeight())
      end
    end

    if app.wm and app.wm.getWindows then
      for _, win in ipairs(app.wm:getWindows() or {}) do
        applyWindowScale(win)
      end
    end

    refreshModalMetrics(app)
  end

  return UiScale.isCompactMode()
end

return M
