local Button = require("user_interface.button")
local AppearanceSwatch = require("user_interface.modals.appearance_color_swatch")
local ModalTabBar = require("user_interface.modals.modal_tab_bar")
local Panel = require("user_interface.panel")
local colors = require("app_colors")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

-- Tab row + body rows + footer; minimum body rows fits current defaults + one extraRow; grows with General if needed.
local SETTINGS_TAB_ROW = 1
local SETTINGS_MIN_CONTENT_ROWS = 5

local function normalizeCanvasFilterKey(key)
  if key == "soft" then return "soft" end
  return "sharp"
end

local function normalizeThemeKey(key)
  if key == "light" then return "light" end
  return "dark"
end

local function makeButtonWidget(text)
  return Button.new({
    text = text,
    w = 0,
    h = 0,
    transparent = true,
  })
end

-- Appearance tab: column headers + row labels + six placeholder swatches (matches UI mock).
local function layoutAppearanceContent(self, contentStart, footerRow)
  local r = contentStart
  self.panel:setCell(1, r, {
    kind = "label",
    text = "",
    align = "left",
  })
  self.panel:setCell(2, r, {
    kind = "label",
    text = "Dark mode",
    align = "center",
  })
  self.panel:setCell(3, r, {
    kind = "label",
    text = "Light mode",
    align = "center",
  })
  r = r + 1

  local dataRows = {
    {
      label = "Focused",
      darkId = "dark_focused",
      lightId = "light_focused",
      darkC = colors.blue,
      lightC = colors.blue,
    },
    {
      label = "Non-focused",
      darkId = "dark_non_focused",
      lightId = "light_non_focused",
      darkC = colors.gray10,
      lightC = colors.gray75,
    },
    {
      label = "Text/Icons",
      darkId = "dark_text_icons",
      lightId = "light_text_icons",
      darkC = colors.white,
      lightC = colors.gray20,
    },
  }

  for _, spec in ipairs(dataRows) do
    self.panel:setCell(1, r, {
      kind = "label",
      text = spec.label,
      align = "right",
    })
    self.panel:setCell(2, r, {
      component = AppearanceSwatch.new({
        slotId = spec.darkId,
        color = spec.darkC,
      }),
    })
    self.panel:setCell(3, r, {
      component = AppearanceSwatch.new({
        slotId = spec.lightId,
        color = spec.lightC,
      }),
    })
    r = r + 1
  end

  while r < footerRow do
    self.panel:setCell(1, r, {
      kind = "label",
      text = "",
      colspan = 3,
      align = "left",
    })
    r = r + 1
  end
end

function Dialog:_rebuildPanelGrid()
  local bodyRows = math.max(SETTINGS_MIN_CONTENT_ROWS, self._generalContentRowCount or SETTINGS_MIN_CONTENT_ROWS)
  local footerRow = SETTINGS_TAB_ROW + bodyRows + 1
  local totalRows = footerRow
  self.panel = Panel.new({
    cols = 3,
    rows = totalRows,
    cellW = self.cellW,
    cellH = self.cellH,
    padding = self.padding,
    spacingX = self.colGap,
    spacingY = self.rowGap,
    cellPaddingX = self.cellPaddingX,
    cellPaddingY = self.cellPaddingY,
    visible = self.visible,
    title = self.title,
    titleH = self.titleH,
    bgColor = self.bgColor,
    titleBgColor = self.titleBgColor,
    _modalChromeOverBlue = self._modalChromeOverBlue == true,
  })

  self._tabBar:setActiveId(self._activeTabId)
  self.panel:setCell(1, SETTINGS_TAB_ROW, {
    colspan = 2,
    component = self._tabBar,
  })

  local contentStart = SETTINGS_TAB_ROW + 1

  if self._activeTabId == "appearance" then
    layoutAppearanceContent(self, contentStart, footerRow)
  else
    local rowIndex = contentStart
    for _, row in ipairs(self.rows or {}) do
      self.panel:setCell(1, rowIndex, {
        text = (row.label or "") .. ":",
        colspan = 2,
        align = "right",
      })
      if row.dropdown then
        self.panel:setCell(3, rowIndex, {
          component = row.dropdown,
        })
      elseif row.buttonEntry then
        self.panel:setCell(3, rowIndex, {
          component = row.buttonEntry.button,
        })
      elseif row.valueText and row.valueText ~= "" then
        self.panel:setCell(3, rowIndex, {
          text = row.valueText,
          textColor = colors.yellow,
        })
      end
      rowIndex = rowIndex + 1
    end
    while rowIndex < footerRow do
      self.panel:setCell(1, rowIndex, {
        kind = "label",
        text = "",
        colspan = 3,
        align = "left",
      })
      rowIndex = rowIndex + 1
    end
  end

  self.panel:setCell(1, footerRow, {
    text = self.footerText,
    colspan = 3,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Settings",
    padding = nil,
    rowGap = nil,
    colGap = nil,
    titleH = nil,
    cellW = nil,
    cellH = nil,
    footerText = "Esc) Close",
    rows = {},
    buttons = {},
    focusedButtonIndex = 1,
    pressedButton = nil,
    onSetScale = nil,
    onToggleFullscreen = nil,
    onToggleResizable = nil,
    onSetCanvasImageMode = nil,
    onSetCanvasFilter = nil,
    onSetTooltipsEnabled = nil,
    onSetTheme = nil,
    onSetPaletteLinks = nil,
    onSetSeparateToolbar = nil,
    getScale = nil,
    getFullscreen = nil,
    getResizable = nil,
    getCanvasImageMode = nil,
    getCanvasFilter = nil,
    getTooltipsEnabled = nil,
    getTheme = nil,
    getPaletteLinks = nil,
    getSeparateToolbar = nil,
    extraRows = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    panel = nil,
    _activeTabId = "general",
    _tabBar = nil,
    _generalContentRowCount = SETTINGS_MIN_CONTENT_ROWS,
  }, Dialog)

  ModalPanelUtils.applyPanelDefaults(self)
  self._tabBar = ModalTabBar.new({
    chromeOverBlue = true,
    tabs = {
      { id = "general", label = "General" },
      { id = "appearance", label = "Appearance" },
    },
    onSelect = function(id)
      if self._activeTabId ~= id then
        self._activeTabId = id
        self:_rebuildRows()
      end
    end,
  })
  self:_rebuildPanelGrid()
  return self
end

function Dialog:isVisible()
  return self.visible
end

function Dialog:hide()
  self.visible = false
  self.pressedButton = nil
  self.rows = {}
  self.buttons = {}
  self._activeTabId = "general"
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:_containsBox(x, y)
  if self.panel and self._boxX then
    return self.panel:contains(x, y)
  end
  return true
end

function Dialog:getTooltipAt(x, y)
  if not self.visible or not self.panel or not self:_containsBox(x, y) then
    return nil
  end
  return self.panel:getTooltipAt(x, y)
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Settings"
  self.onSetScale = opts.onSetScale
  self.onToggleFullscreen = opts.onToggleFullscreen
  self.onToggleResizable = opts.onToggleResizable
  self.onSetCanvasImageMode = opts.onSetCanvasImageMode
  self.onSetCanvasFilter = opts.onSetCanvasFilter
  self.onSetTooltipsEnabled = opts.onSetTooltipsEnabled
  self.onSetTheme = opts.onSetTheme
  self.onSetPaletteLinks = opts.onSetPaletteLinks
  self.onSetSeparateToolbar = opts.onSetSeparateToolbar
  self.getScale = opts.getScale
  self.getFullscreen = opts.getFullscreen
  self.getResizable = opts.getResizable
  self.getCanvasImageMode = opts.getCanvasImageMode
  self.getCanvasFilter = opts.getCanvasFilter
  self.getTooltipsEnabled = opts.getTooltipsEnabled
  self.getTheme = opts.getTheme
  self.getPaletteLinks = opts.getPaletteLinks
  self.getSeparateToolbar = opts.getSeparateToolbar
  self.extraRows = opts.extraRows
  self.visible = true
  self.pressedButton = nil
  self._activeTabId = "general"
  self:_rebuildRows()
end

function Dialog:setExtraRows(rows)
  self.extraRows = rows
  if self.visible then
    self:_rebuildRows()
  end
end

function Dialog:_defaultRows()
  local canvasFilter = normalizeCanvasFilterKey(self.getCanvasFilter and self.getCanvasFilter() or nil)
  local tooltipsEnabled = not (self.getTooltipsEnabled and self.getTooltipsEnabled() == false)
  local theme = normalizeThemeKey(self.getTheme and self.getTheme() or nil)

  return {
    {
      id = "tooltips_enabled",
      label = "Tooltips",
      buttonSpec = {
        id = "tooltips_enabled_toggle",
        text = tooltipsEnabled and "On" or "Off",
        action = function()
          if self.onSetTooltipsEnabled then
            self.onSetTooltipsEnabled(not tooltipsEnabled)
          end
        end,
      },
    },
    {
      id = "theme",
      label = "Theme",
      buttonSpec = {
        id = "theme_toggle",
        text = (theme == "light") and "Light" or "Dark",
        action = function()
          if self.onSetTheme then
            self.onSetTheme((theme == "light") and "dark" or "light")
          end
        end,
      },
    },
    {
      id = "canvas_filter",
      label = "Canvas filter",
      buttonSpec = {
        id = "canvas_filter_toggle",
        text = (canvasFilter == "soft") and "Soft" or "Sharp",
        action = function()
          if self.onSetCanvasFilter then
            self.onSetCanvasFilter((canvasFilter == "soft") and "sharp" or "soft")
          end
        end,
      },
    },
    {
      id = "separate_toolbar",
      label = "Detached Window Toolbar",
      buttonSpec = {
        id = "separate_toolbar_toggle",
        text = (self.getSeparateToolbar and self.getSeparateToolbar() == true) and "On" or "Off",
        action = function()
          if self.onSetSeparateToolbar then
            self.onSetSeparateToolbar(not (self.getSeparateToolbar and self.getSeparateToolbar() == true))
          end
        end,
      },
    },
  }
end

function Dialog:_normalizeRows(rowSpecs)
  local rows = {}
  local buttons = {}
  local preserveFocusId = nil

  if self.buttons and self.focusedButtonIndex and self.buttons[self.focusedButtonIndex] then
    preserveFocusId = self.buttons[self.focusedButtonIndex].id
  end

  for _, rowSpec in ipairs(rowSpecs or {}) do
    if rowSpec.dropdown then
      rows[#rows + 1] = {
        id = rowSpec.id,
        label = rowSpec.label or "",
        valueText = nil,
        buttonEntry = nil,
        dropdown = rowSpec.dropdown,
      }
    else
      local buttonEntry = nil
      if rowSpec.buttonSpec then
        buttonEntry = {
          id = rowSpec.buttonSpec.id,
          action = rowSpec.buttonSpec.action,
          button = makeButtonWidget(rowSpec.buttonSpec.text or ""),
        }
        buttons[#buttons + 1] = buttonEntry
      end

      rows[#rows + 1] = {
        id = rowSpec.id,
        label = rowSpec.label or "",
        valueText = rowSpec.valueText,
        buttonEntry = buttonEntry,
      }
    end
  end

  self.rows = rows
  self.buttons = buttons
  self._generalContentRowCount = math.max(SETTINGS_MIN_CONTENT_ROWS, #rows)

  if #self.buttons == 0 then
    self.focusedButtonIndex = 1
    self:_rebuildPanelGrid()
    return
  end

  local focusIndex = 1
  if preserveFocusId then
    for i, entry in ipairs(self.buttons) do
      if entry.id == preserveFocusId then
        focusIndex = i
        break
      end
    end
  end
  self.focusedButtonIndex = math.max(1, math.min(focusIndex, #self.buttons))
  self:_syncFocus()
  self:_rebuildPanelGrid()
end

function Dialog:_rebuildRows()
  if self._activeTabId == "appearance" then
    self.rows = {}
    self.buttons = {}
    self.focusedButtonIndex = 1
    self:_rebuildPanelGrid()
    return
  end

  local rowSpecs = self:_defaultRows()
  if self.extraRows then
    for _, row in ipairs(self.extraRows) do
      local spec = row.buttonSpec
      if spec and type(spec.getText) == "function" then
        spec.text = spec.getText()
      end
      rowSpecs[#rowSpecs + 1] = row
    end
  end
  self:_normalizeRows(rowSpecs)
end

function Dialog:_syncFocus()
  for i, entry in ipairs(self.buttons or {}) do
    entry.button.focused = (i == self.focusedButtonIndex)
  end
end

function Dialog:_focusNext(step)
  if not self.visible or not self.buttons or #self.buttons == 0 then
    return
  end
  step = step or 1
  local count = #self.buttons
  local idx = self.focusedButtonIndex or 1
  idx = ((idx - 1 + step) % count) + 1
  self.focusedButtonIndex = idx
  self:_syncFocus()
end

function Dialog:_activateButton(entry)
  if not entry or not entry.action then return false end
  entry.action()
  if self.visible then
    ModalPanelUtils.refreshTargetMetrics(self)
    self:_rebuildRows()
  end
  return true
end

function Dialog:_focusedEntry()
  return self.buttons and self.buttons[self.focusedButtonIndex] or nil
end

function Dialog:handleKey(key)
  if not self.visible then return false end
  if key == "escape" then
    self:hide()
    return true
  end
  if not self.buttons or #self.buttons == 0 then
    return false
  end
  if key == "tab" or key == "right" or key == "down" then
    self:_focusNext(1)
    return true
  end
  if key == "left" or key == "up" then
    self:_focusNext(-1)
    return true
  end
  if key == "return" or key == "kpenter" or key == "space" then
    return self:_activateButton(self:_focusedEntry())
  end
  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end

  if not self:_containsBox(x, y) then
    self:hide()
    return true
  end

  if self._tabBar:mousepressed(x, y, button) then
    return true
  end

  if self._activeTabId ~= "general" then
    return true
  end

  self.pressedButton = nil
  for i, entry in ipairs(self.buttons or {}) do
    if entry.button:contains(x, y) then
      self.focusedButtonIndex = i
      self:_syncFocus()
      entry.button.pressed = true
      self.pressedButton = entry
      return true
    end
  end

  return true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end

  local pressed = self.pressedButton
  self.pressedButton = nil
  for _, entry in ipairs(self.buttons or {}) do
    entry.button.pressed = false
  end

  if pressed and pressed.button:contains(x, y) then
    return self:_activateButton(pressed)
  end
  return true
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end
  self._tabBar:mousemoved(x, y)
  for _, entry in ipairs(self.buttons or {}) do
    entry.button.hovered = entry.button:contains(x, y)
  end
  return true
end

function Dialog:draw(canvas)
  if not self.visible then return end
  self:_rebuildPanelGrid()
  self.panel:setVisible(true)
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
end

return Dialog
