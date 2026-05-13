local Button = require("user_interface.button")
local ColorPickerDropdown = require("user_interface.color_picker_dropdown")
local ModalTabBar = require("user_interface.modals.modal_tab_bar")
local Panel = require("user_interface.panel")
local Text = require("utils.text_utils")
local Draw = require("utils.draw_utils")
local images = require("images")
local colors = require("app_colors")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")

local Dialog = {}
Dialog.__index = Dialog

-- Tab row + body rows + footer; minimum body rows fits current defaults + Appearance sample rows + padding.
local SETTINGS_TAB_ROW = 1
local SETTINGS_MIN_CONTENT_ROWS = 8

local VALID_SETTINGS_TAB_IDS = {
  general = true,
  appearance = true,
  colors = true,
}

local function normalizeSettingsModalTabId(id)
  if type(id) ~= "string" or not VALID_SETTINGS_TAB_IDS[id] then
    return "general"
  end
  return id
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

local APPEARANCE_ROW_SLOTS = {
  { label = "Workspace background", darkId = "dark_background", lightId = "light_background" },
  { label = "Focused window chrome", darkId = "dark_focused", lightId = "light_focused" },
  { label = "Unfocused window chrome", darkId = "dark_non_focused", lightId = "light_non_focused" },
  { label = "Toolbar/menu text on hover", darkId = "dark_text_icons_focused", lightId = "light_text_icons_focused" },
  { label = "Toolbar/menu text (default)", darkId = "dark_text_icons_non_focused", lightId = "light_text_icons_non_focused" },
}

--- Chrome color pickers shown on the Colors tab for the active UI theme only.
local function chromePickerSlotIdsForTheme(themeKey)
  local t = normalizeThemeKey(themeKey)
  local ids = {}
  for _, spec in ipairs(APPEARANCE_ROW_SLOTS) do
    ids[#ids + 1] = (t == "light") and spec.lightId or spec.darkId
  end
  return ids
end

local APPEARANCE_PICKER_SLOT_IDS = {
  "dark_background",
  "light_background",
  "dark_focused",
  "light_focused",
  "dark_non_focused",
  "light_non_focused",
  "dark_text_icons_focused",
  "light_text_icons_focused",
  "dark_text_icons_non_focused",
  "light_text_icons_non_focused",
}

local function eachStandaloneSettingsComponent(self, fn)
  for _, row in ipairs(self.rows or {}) do
    if row.component and not row.buttonEntry and not row.dropdown then
      fn(row.component)
    end
  end
end

local function clearSettingsChromeHovers(self)
  if self._resetAllButton then
    self._resetAllButton.hovered = false
  end
  if self._tabBar then
    self._tabBar._hoverIndex = nil
  end
  for _, entry in ipairs(self.buttons or {}) do
    entry.button.hovered = false
  end
  for _, row in ipairs(self.rows or {}) do
    local dd = row.dropdown
    if dd and dd.trigger then
      dd.trigger.hovered = false
    end
  end
  if self._appearancePickers then
    for _, slotId in ipairs(APPEARANCE_PICKER_SLOT_IDS) do
      local p = self._appearancePickers[slotId]
      if p and p.trigger then
        p.trigger.hovered = false
      end
    end
  end
  eachStandaloneSettingsComponent(self, function(c)
    if type(c.hovered) == "boolean" then
      c.hovered = false
    end
  end)
end

local function findDraggingStandaloneComponent(self)
  local found = nil
  eachStandaloneSettingsComponent(self, function(c)
    if c.dragging then
      found = c
    end
  end)
  return found
end

--- Small read-only preview of window chrome (Appearance slots, including overrides).
local function newAppearanceChromeSample(modePrefix, stateKind)
  local bgSlot = modePrefix .. "_" .. stateKind
  local textSuffix = (stateKind == "focused") and "focused" or "non_focused"
  local textSlot = modePrefix .. "_text_icons_" .. textSuffix
  local sampleLabel = "Text"
  local icon = images.icons and images.icons.actions.icon_clone or nil
  return {
    contains = function()
      return false
    end,
    draw = function(self)
      local bg = colors:appearanceChromeResolved(bgSlot)
      local tc = colors:appearanceChromeResolved(textSlot)
      love.graphics.setColor(bg[1], bg[2], bg[3], 1)
      love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 2, 2)

      local font = love.graphics.getFont()
      local fh = font and font:getHeight() or 12
      local textY = math.floor(self.y + (self.h - fh) * 0.5)
      local pad = 4
      local gap = 4
      local textX = math.floor(self.x + pad)
      if icon and type(icon.getWidth) == "function" and type(icon.getHeight) == "function" then
        local iw = tonumber(icon:getWidth()) or 0
        local ih = tonumber(icon:getHeight()) or 0
        if iw > 0 and ih > 0 then
          local iconX = math.floor(self.x + pad)
          local iconY = math.floor(self.y + (self.h - ih) * 0.5)
          love.graphics.setColor(tc[1], tc[2], tc[3], tc[4] or 1)
          Draw.drawIcon(icon, iconX, iconY, { respectTheme = false })
          textX = iconX + iw + gap
        end
      end

      Text.print(sampleLabel, textX, textY, {
        color = tc,
        literalColor = true,
      })
      love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 1)
    end,
  }
end

local function forEachAppearancePicker(self, fn)
  if not self._appearancePickers then
    return
  end
  for _, slotId in ipairs(APPEARANCE_PICKER_SLOT_IDS) do
    local p = self._appearancePickers[slotId]
    if p then
      fn(p)
    end
  end
end

--- First color picker whose dropdown menu is open (Colors tab: current theme only).
local function appearancePickerWithOpenMenu(self)
  for _, slotId in ipairs(chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)) do
    local p = self._appearancePickers and self._appearancePickers[slotId]
    if p and p:isMenuVisible() then
      return p
    end
  end
  return nil
end

--- Settings Appearance: only one color-picker menu at a time.
function Dialog:_closeOtherAppearancePickers(keepSlotId)
  for _, slotId in ipairs(APPEARANCE_PICKER_SLOT_IDS) do
    if slotId ~= keepSlotId then
      local p = self._appearancePickers[slotId]
      if p and p.closeMenu then
        p:closeMenu()
      end
    end
  end
end

--- Align each Appearance matrix + swatch with current chrome (saved overrides + builtins).
--- Safe before first `show()` (`getAppearanceChromeRgb` may be nil; uses `app_colors` directly).
function Dialog:syncAppearancePickersFromAppColors()
  if not self._appearancePickers then
    return
  end
  for _, slotId in ipairs(APPEARANCE_PICKER_SLOT_IDS) do
    local picker = self._appearancePickers[slotId]
    if picker and picker.setSelectedFromRgb then
      local rgb = self.getAppearanceChromeRgb and self.getAppearanceChromeRgb(slotId)
      if not rgb then
        local c = colors:appearanceChromeResolved(slotId)
        rgb = { r = c[1], g = c[2], b = c[3] }
      end
      local r = tonumber(rgb.r or rgb[1])
      local g = tonumber(rgb.g or rgb[2])
      local b = tonumber(rgb.b or rgb[3])
      if r and g and b then
        picker:setSelectedFromRgb(r, g, b, { silent = true })
      end
    end
  end
end

-- Colors tab: labels + chrome pickers for the active theme only (matches Appearance "Theme").
-- Fills rows from contentStart up to (but not including) spacerRow; caller adds spacer + footer.
local function layoutColorsTabContent(self, contentStart, spacerRow)
  local themeKey = normalizeThemeKey(self.getTheme and self.getTheme() or nil)
  local modePrefix = (themeKey == "light") and "light" or "dark"

  local r = contentStart

  for _, spec in ipairs(APPEARANCE_ROW_SLOTS) do
    local slotId = (themeKey == "light") and spec.lightId or spec.darkId
    self.panel:setCell(1, r, {
      text = spec.label .. ":",
      colspan = 2,
      align = "right",
    })
    self.panel:setCell(3, r, {
      component = self._appearancePickers[slotId],
    })
    r = r + 1
  end

  for _, sample in ipairs({
    { label = "Focused chrome preview", kind = "focused" },
    { label = "Unfocused chrome preview", kind = "non_focused" },
  }) do
    self.panel:setCell(1, r, {
      text = sample.label .. ":",
      colspan = 2,
      align = "right",
    })
    self.panel:setCell(3, r, {
      component = newAppearanceChromeSample(modePrefix, sample.kind),
    })
    r = r + 1
  end

  while r < spacerRow do
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
  ModalPanelUtils.refreshTargetMetrics(self)
  local bodyRows = math.max(SETTINGS_MIN_CONTENT_ROWS, self._generalContentRowCount or SETTINGS_MIN_CONTENT_ROWS)
  local contentEndRow = SETTINGS_TAB_ROW + bodyRows
  local spacerRow = contentEndRow + 1
  local footerRow = spacerRow + 1
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

  if self._activeTabId == "colors" then
    layoutColorsTabContent(self, contentStart, spacerRow)
    if self._appearanceNeedsPickerSync then
      self:syncAppearancePickersFromAppColors()
      self._appearanceNeedsPickerSync = false
    end
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
      elseif row.component then
        self.panel:setCell(3, rowIndex, {
          component = row.component,
        })
      elseif row.valueText and row.valueText ~= "" then
        self.panel:setCell(3, rowIndex, {
          text = row.valueText,
          textColor = colors.yellow,
        })
      end
      rowIndex = rowIndex + 1
    end
    while rowIndex <= contentEndRow do
      self.panel:setCell(1, rowIndex, {
        kind = "label",
        text = "",
        colspan = 3,
        align = "left",
      })
      rowIndex = rowIndex + 1
    end
  end

  self.panel:setCell(1, spacerRow, {
    kind = "label",
    text = "",
    colspan = 3,
    align = "left",
  })

  self.panel:setCell(1, footerRow, {
    kind = "label",
    text = self.footerText,
    colspan = 2,
    align = "left",
  })
  self.panel:setCell(3, footerRow, {
    component = self._resetAllButton,
  })

  self.panel._tabbedModalChrome = true
  self.panel._tabbedModalTabBar = self._tabBar
  self.panel._tabbedModalTabRow = SETTINGS_TAB_ROW
  self.panel._tabbedModalContentStartRow = SETTINGS_TAB_ROW + 1
  self.panel._tabbedModalFooterRow = footerRow
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
    onSetNeverShowResizeHandle = nil,
    getScale = nil,
    getFullscreen = nil,
    getResizable = nil,
    getCanvasImageMode = nil,
    getCanvasFilter = nil,
    getTooltipsEnabled = nil,
    getTheme = nil,
    getPaletteLinks = nil,
    getSeparateToolbar = nil,
    getNeverShowResizeHandle = nil,
    extraRows = nil,
    _getExtraRows = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    panel = nil,
    _activeTabId = "general",
    _tabBar = nil,
    _generalContentRowCount = SETTINGS_MIN_CONTENT_ROWS,
    _appearancePickers = {},
    _appearanceNeedsPickerSync = false,
    getAppearanceChromeRgb = nil,
    onAppearanceChromeChange = nil,
    onResetAll = nil,
    pressedResetAll = nil,
    _settingsTabbedChrome = true,
    _windowShadowBlurSlider = nil,
    _windowShadowStrengthSlider = nil,
    _canvasImageModeDropdown = nil,
    _canvasFilterDropdown = nil,
  }, Dialog)

  ModalPanelUtils.applyPanelDefaults(self)

  local stubBounds = function()
    local w, h = love.graphics.getDimensions()
    return { w = w, h = h }
  end

  local slotTooltips = {
    dark_background = "Dark mode: workspace background",
    light_background = "Light mode: workspace background",
    dark_focused = "Dark mode: focused window chrome",
    light_focused = "Light mode: focused window chrome",
    dark_non_focused = "Dark mode: unfocused window chrome",
    light_non_focused = "Light mode: unfocused window chrome",
    dark_text_icons_focused = "Dark mode: toolbar/menu text when hovered",
    light_text_icons_focused = "Light mode: toolbar/menu text when hovered",
    dark_text_icons_non_focused = "Dark mode: toolbar/menu text (default)",
    light_text_icons_non_focused = "Light mode: toolbar/menu text (default)",
  }

  for _, slotId in ipairs(APPEARANCE_PICKER_SLOT_IDS) do
    local sid = slotId
    self._appearancePickers[slotId] = ColorPickerDropdown.new({
      getBounds = stubBounds,
      closeMenuOnItemPick = false,
      menuBgColor = colors.transparent,
      tooltip = slotTooltips[slotId] or "Chrome color",
      onBeforeOpenMenu = function()
        self:_closeOtherAppearancePickers(sid)
      end,
      onChange = function(c)
        self:_onAppearanceChromeCommitted(sid, c)
      end,
    })
  end

  self._resetAllButton = makeButtonWidget("Reset all")

  self._tabBar = ModalTabBar.new({
    chromeOverBlue = true,
    tabs = {
      { id = "general", label = "General" },
      { id = "appearance", label = "Appearance" },
      { id = "colors", label = "Colors" },
    },
    onSelect = function(id)
      if self._activeTabId ~= id then
        if id ~= "colors" then
          forEachAppearancePicker(self, function(p)
            p:closeMenu()
          end)
        end
        if id == "colors" then
          self._appearanceNeedsPickerSync = true
        end
        self._activeTabId = id
        self:_rebuildRows()
      end
      if self.onActiveTabChange then
        self.onActiveTabChange(id)
      end
    end,
  })
  self:syncAppearancePickersFromAppColors()
  self:_rebuildPanelGrid()
  return self
end

function Dialog:isVisible()
  return self.visible
end

function Dialog:_onAppearanceChromeCommitted(slotId, c)
  if not c or not self.onAppearanceChromeChange then
    return
  end
  self.onAppearanceChromeChange(slotId, { r = c.r, g = c.g, b = c.b })
end

function Dialog:isHoveringColorPickerSwatchAt(px, py)
  if not self.visible or self._activeTabId ~= "colors" then
    return false
  end
  local openPicker = appearancePickerWithOpenMenu(self)
  if openPicker and type(openPicker.wantsHandCursorAt) == "function" then
    return openPicker:wantsHandCursorAt(px, py)
  end
  for _, slotId in ipairs(chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)) do
    local p = self._appearancePickers and self._appearancePickers[slotId]
    if p and type(p.wantsHandCursorAt) == "function" and p:wantsHandCursorAt(px, py) then
      return true
    end
  end
  return false
end

--- Open appearance dropdown menus are not part of `self.panel` hit geometry; disabled swatch triggers too.
function Dialog:isHoveringDisabledAppearancePickerAt(px, py)
  if not self.visible or self._activeTabId ~= "colors" then
    return false
  end
  for _, slotId in ipairs(chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)) do
    local p = self._appearancePickers and self._appearancePickers[slotId]
    if p and p.trigger and p.trigger.enabled == false and p.trigger:contains(px, py) then
      return true
    end
    local m = p and p.menu
    if m and m.isVisible and m:isVisible() and m.contains and m:contains(px, py) then
      if m.isHoveringDisabledAt and m:isHoveringDisabledAt(px, py) then
        return true
      end
    end
  end
  return false
end

function Dialog:hide()
  self.visible = false
  self.pressedButton = nil
  self.pressedResetAll = nil
  eachStandaloneSettingsComponent(self, function(c)
    if type(c.dragging) == "boolean" then
      c.dragging = false
    end
  end)
  if self._resetAllButton then
    self._resetAllButton.pressed = false
  end
  forEachAppearancePicker(self, function(p)
    p:closeMenu()
  end)
  self.rows = {}
  self.buttons = {}
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:_containsBox(x, y)
  if self._activeTabId == "colors" then
    for _, slotId in ipairs(chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)) do
      local p = self._appearancePickers and self._appearancePickers[slotId]
      if p and p:isMenuVisible() and p.menu and p.menu:contains(x, y) then
        return true
      end
    end
  end
  if self._activeTabId == "general" or self._activeTabId == "appearance" then
    for _, row in ipairs(self.rows or {}) do
      local dd = row.dropdown
      if dd and dd:isMenuVisible() and dd.menu and dd.menu:contains(x, y) then
        return true
      end
    end
  end
  if self.panel and self._boxX then
    return self.panel:contains(x, y)
  end
  return true
end

function Dialog:getTooltipAt(x, y)
  if not self.visible or not self.panel or not self:_containsBox(x, y) then
    return nil
  end
  if self._activeTabId == "colors" then
    for _, slotId in ipairs(chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)) do
      local p = self._appearancePickers and self._appearancePickers[slotId]
      if p and p:isMenuVisible() then
        local tip = p.menu:getTooltipAt(x, y)
        if tip then
          return tip
        end
      end
    end
  end
  local tip = self.panel:getTooltipAt(x, y)
  if tip then
    return tip
  end
  if self._activeTabId == "colors" then
    for _, slotId in ipairs(chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)) do
      local p = self._appearancePickers and self._appearancePickers[slotId]
      if p and p.trigger and p.trigger.tooltip and p.trigger.tooltip ~= "" and p.trigger:contains(x, y) then
        return {
          text = p.trigger.tooltip,
          immediate = false,
          key = p.trigger,
        }
      end
    end
  end
  return nil
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
  self.onSetNeverShowResizeHandle = opts.onSetNeverShowResizeHandle
  self.getScale = opts.getScale
  self.getFullscreen = opts.getFullscreen
  self.getResizable = opts.getResizable
  self.getCanvasImageMode = opts.getCanvasImageMode
  self.getCanvasFilter = opts.getCanvasFilter
  self.getTooltipsEnabled = opts.getTooltipsEnabled
  self.getTheme = opts.getTheme
  self.getPaletteLinks = opts.getPaletteLinks
  self.getSeparateToolbar = opts.getSeparateToolbar
  self.getNeverShowResizeHandle = opts.getNeverShowResizeHandle
  self.extraRows = opts.extraRows
  self._getExtraRows = opts.getExtraRows
  self.getAppearanceChromeRgb = opts.getAppearanceChromeRgb
  self.onAppearanceChromeChange = opts.onAppearanceChromeChange
  self.onResetAll = opts.onResetAll
  self._windowShadowBlurSlider = opts.windowShadowBlurSlider
  self._windowShadowStrengthSlider = opts.windowShadowStrengthSlider
  self._canvasImageModeDropdown = opts.canvasImageModeDropdown
  self._canvasFilterDropdown = opts.canvasFilterDropdown
  self.onActiveTabChange = opts.onActiveTabChange
  self.visible = true
  self.pressedButton = nil
  local initialTab = normalizeSettingsModalTabId(opts.initialTabId)
  self._activeTabId = initialTab
  if self._tabBar then
    self._tabBar:setActiveId(self._activeTabId)
  end
  self._appearanceNeedsPickerSync = true
  self:syncAppearancePickersFromAppColors()
  local boundsFn = opts.getMenuBounds or function()
    local w, h = love.graphics.getDimensions()
    return { w = w, h = h }
  end
  forEachAppearancePicker(self, function(p)
    p:setGetBounds(boundsFn)
  end)
  self:_rebuildRows()
end

function Dialog:setExtraRows(rows)
  self.extraRows = rows
  self._getExtraRows = nil
  if self.visible then
    self:_rebuildRows()
  end
end

function Dialog:_generalTabRowSpecs()
  local tooltipsEnabled = not (self.getTooltipsEnabled and self.getTooltipsEnabled() == false)
  local rows = {
    {
      id = "fullscreen",
      label = "Full screen",
      buttonSpec = {
        id = "fullscreen_toggle",
        getText = function()
          return (self.getFullscreen and self.getFullscreen() == true) and "On" or "Off"
        end,
        action = function()
          if self.onToggleFullscreen then
            self.onToggleFullscreen()
          end
        end,
      },
    },
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
    {
      id = "never_show_resize_handle",
      label = "Never show resize handle",
      buttonSpec = {
        id = "never_show_resize_handle_toggle",
        text = (self.getNeverShowResizeHandle and self.getNeverShowResizeHandle() == true) and "On" or "Off",
        action = function()
          if self.onSetNeverShowResizeHandle then
            self.onSetNeverShowResizeHandle(not (self.getNeverShowResizeHandle and self.getNeverShowResizeHandle() == true))
          end
        end,
      },
    },
  }
  return rows
end

function Dialog:_appearanceTabRowSpecs()
  local theme = normalizeThemeKey(self.getTheme and self.getTheme() or nil)

  local rows = {
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
  }

  if self._canvasImageModeDropdown then
    rows[#rows + 1] = {
      id = "canvas_image_mode",
      label = "Canvas scale",
      dropdown = self._canvasImageModeDropdown,
    }
  end

  if self._canvasFilterDropdown then
    rows[#rows + 1] = {
      id = "canvas_filter",
      label = "Canvas filter",
      dropdown = self._canvasFilterDropdown,
    }
  end

  if self._windowShadowBlurSlider then
    rows[#rows + 1] = {
      id = "window_shadow_blur",
      label = "Window shadow blur",
      component = self._windowShadowBlurSlider,
    }
  end
  if self._windowShadowStrengthSlider then
    rows[#rows + 1] = {
      id = "window_shadow_strength",
      label = "Window shadow strength",
      component = self._windowShadowStrengthSlider,
    }
  end

  return rows
end

function Dialog:_rebuildRows()
  if self._activeTabId == "colors" then
    self.rows = {}
    self.buttons = {}
    self.focusedButtonIndex = 1
    self:_rebuildPanelGrid()
    return
  end

  if self._activeTabId == "appearance" then
    self:_normalizeRows(self:_appearanceTabRowSpecs())
    return
  end

  local rowSpecs = self:_generalTabRowSpecs()
  local extras = {}
  if type(self._getExtraRows) == "function" then
    extras = self._getExtraRows() or {}
  elseif self.extraRows then
    extras = self.extraRows
  end
  for _, row in ipairs(extras) do
    local spec = row.buttonSpec
    if spec and type(spec.getText) == "function" then
      spec.text = spec.getText()
    end
    rowSpecs[#rowSpecs + 1] = row
  end
  self:_normalizeRows(rowSpecs)
end

function Dialog:_normalizeRows(rowSpecs)
  for _, rowSpec in ipairs(rowSpecs or {}) do
    local spec = rowSpec.buttonSpec
    if spec and type(spec.getText) == "function" then
      spec.text = spec.getText()
    end
  end

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
        component = nil,
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
        component = rowSpec.component,
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

  if self._activeTabId == "colors" then
    local openPicker = appearancePickerWithOpenMenu(self)
    if openPicker then
      if openPicker:handleMousePressed(x, y, button) then
        return true
      end
    else
      for _, slotId in ipairs(chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)) do
        local p = self._appearancePickers and self._appearancePickers[slotId]
        if p and p:handleMousePressed(x, y, button) then
          return true
        end
      end
    end
  end

  if self._tabBar:mousepressed(x, y, button) then
    return true
  end

  -- Dropdown menus can extend over the footer; handle before Reset so menu picks win.
  if self._activeTabId == "general" or self._activeTabId == "appearance" then
    for _, row in ipairs(self.rows or {}) do
      if row.dropdown and row.dropdown:handleMousePressed(x, y, button) then
        return true
      end
    end
  end

  if self._resetAllButton and self._resetAllButton:contains(x, y) then
    self._resetAllButton.pressed = true
    self.pressedResetAll = true
    return true
  end

  if self._activeTabId == "colors" then
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

  local consumedComponent = false
  eachStandaloneSettingsComponent(self, function(c)
    if not consumedComponent and type(c.mousepressed) == "function" and c:mousepressed(x, y, button) then
      consumedComponent = true
    end
  end)
  if consumedComponent then
    return true
  end

  return true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end

  if self._activeTabId == "colors" then
    local openPicker = appearancePickerWithOpenMenu(self)
    if openPicker then
      if openPicker:handleMouseReleased(x, y, button) then
        return true
      end
    else
      for _, slotId in ipairs(chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)) do
        local p = self._appearancePickers and self._appearancePickers[slotId]
        if p and p:handleMouseReleased(x, y, button) then
          return true
        end
      end
    end
  end

  local pressed = self.pressedButton
  self.pressedButton = nil
  for _, entry in ipairs(self.buttons or {}) do
    entry.button.pressed = false
  end

  if self._activeTabId == "general" or self._activeTabId == "appearance" then
    for _, row in ipairs(self.rows or {}) do
      if row.dropdown and row.dropdown:handleMouseReleased(x, y, button) then
        return true
      end
    end
    eachStandaloneSettingsComponent(self, function(c)
      if type(c.mousereleased) == "function" then
        c:mousereleased(x, y, button)
      end
    end)
  end

  if self._resetAllButton then
    self._resetAllButton.pressed = false
  end

  if self.pressedResetAll and self._resetAllButton and self._resetAllButton:contains(x, y) then
    self.pressedResetAll = nil
    if self.onResetAll then
      self.onResetAll()
    end
    if self.visible then
      ModalPanelUtils.refreshTargetMetrics(self)
      self:_rebuildRows()
    end
    return true
  end
  self.pressedResetAll = nil

  if pressed and pressed.button:contains(x, y) then
    return self:_activateButton(pressed)
  end
  return true
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end

  local dragComp = findDraggingStandaloneComponent(self)
  if dragComp and type(dragComp.mousemoved) == "function" then
    clearSettingsChromeHovers(self)
    dragComp:mousemoved(x, y)
    return true
  end

  clearSettingsChromeHovers(self)

  -- Open menus paint above body/footer; only they should show hover while cursor is inside them.
  if self._activeTabId == "general" or self._activeTabId == "appearance" then
    for _, row in ipairs(self.rows or {}) do
      local dd = row.dropdown
      if dd and dd:isMenuVisible() and dd.menu then
        dd.menu:mousemoved(x, y)
        if dd.menu:contains(x, y) then
          return true
        end
      end
    end
  end

  if self._activeTabId == "colors" then
    local openPicker = appearancePickerWithOpenMenu(self)
    if openPicker and openPicker.menu then
      openPicker.menu:mousemoved(x, y)
      if openPicker.menu:contains(x, y) then
        return true
      end
    end
  end

  if self._tabBar and self._tabBar:contains(x, y) then
    self._tabBar:mousemoved(x, y)
    return true
  end

  if self._resetAllButton and self._resetAllButton:contains(x, y) then
    self._resetAllButton.hovered = true
    return true
  end

  if self._activeTabId == "general" or self._activeTabId == "appearance" then
    for _, row in ipairs(self.rows or {}) do
      local dd = row.dropdown
      if dd and dd.trigger and dd.trigger:contains(x, y) then
        dd.trigger.hovered = true
        return true
      end
    end
  end

  for i = #self.buttons, 1, -1 do
    local entry = self.buttons[i]
    if entry and entry.button:contains(x, y) then
      entry.button.hovered = true
      return true
    end
  end

  if self._activeTabId == "colors" then
    local visibleSlots = chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)
    for i = #visibleSlots, 1, -1 do
      local slotId = visibleSlots[i]
      local p = self._appearancePickers and self._appearancePickers[slotId]
      if p and p.trigger and p.trigger:contains(x, y) then
        p:mousemoved(x, y)
        return true
      end
    end
  end

  local standalone = {}
  eachStandaloneSettingsComponent(self, function(c)
    standalone[#standalone + 1] = c
  end)
  for i = #standalone, 1, -1 do
    local c = standalone[i]
    if type(c.mousemoved) == "function" and type(c.contains) == "function" and c:contains(x, y) then
      c:mousemoved(x, y)
      return true
    end
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
  if self._activeTabId == "colors" then
    for _, slotId in ipairs(chromePickerSlotIdsForTheme(self.getTheme and self.getTheme() or nil)) do
      local p = self._appearancePickers and self._appearancePickers[slotId]
      if p and p.drawMenu then
        p:drawMenu()
      end
    end
  elseif self._activeTabId == "general" or self._activeTabId == "appearance" then
    for _, row in ipairs(self.rows or {}) do
      if row.dropdown and row.dropdown.drawMenu then
        row.dropdown:drawMenu()
      end
    end
  end
end

return Dialog
