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

local APPEARANCE_ROW_SLOTS = {
  { label = "Background", darkId = "dark_background", lightId = "light_background" },
  { label = "Focused", darkId = "dark_focused", lightId = "light_focused" },
  { label = "Non-focused", darkId = "dark_non_focused", lightId = "light_non_focused" },
  { label = "Text focused", darkId = "dark_text_icons_focused", lightId = "light_text_icons_focused" },
  { label = "Text non-focused", darkId = "dark_text_icons_non_focused", lightId = "light_text_icons_non_focused" },
}

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

--- Small read-only preview of window chrome (Appearance slots, including overrides).
local function newAppearanceChromeSample(modePrefix, stateKind)
  local bgSlot = modePrefix .. "_" .. stateKind
  local textSuffix = (stateKind == "focused") and "focused" or "non_focused"
  local textSlot = modePrefix .. "_text_icons_" .. textSuffix
  local sampleLabel = "Text"
  local icon = images.icons and images.icons.icon_clone or nil
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

local function anyAppearancePickerMenu(self, pred)
  local found = false
  forEachAppearancePicker(self, function(p)
    if pred(p) then
      found = true
    end
  end)
  return found
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

-- Appearance tab: column headers + row labels + eight color picker dropdowns.
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

  for _, spec in ipairs(APPEARANCE_ROW_SLOTS) do
    self.panel:setCell(1, r, {
      kind = "label",
      text = spec.label,
      align = "right",
    })
    self.panel:setCell(2, r, {
      component = self._appearancePickers[spec.darkId],
    })
    self.panel:setCell(3, r, {
      component = self._appearancePickers[spec.lightId],
    })
    r = r + 1
  end

  for _, sample in ipairs({
    { label = "Sample focused", kind = "focused" },
    { label = "Sample non-focused", kind = "non_focused" },
  }) do
    self.panel:setCell(1, r, {
      kind = "label",
      text = sample.label,
      align = "right",
    })
    self.panel:setCell(2, r, {
      component = newAppearanceChromeSample("dark", sample.kind),
    })
    self.panel:setCell(3, r, {
      component = newAppearanceChromeSample("light", sample.kind),
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
  ModalPanelUtils.refreshTargetMetrics(self)
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
    kind = "label",
    text = self.footerText,
    colspan = 2,
    align = "left",
  })
  self.panel:setCell(3, footerRow, {
    component = self._resetAllButton,
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
    _appearancePickers = {},
    _appearanceNeedsPickerSync = false,
    getAppearanceChromeRgb = nil,
    onAppearanceChromeChange = nil,
    onResetAll = nil,
    pressedResetAll = nil,
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
      { id = "appearance", label = "Colors" },
    },
    onSelect = function(id)
      if self._activeTabId ~= id then
        if id ~= "appearance" then
          forEachAppearancePicker(self, function(p)
            p:closeMenu()
          end)
        end
        if id == "appearance" then
          self._appearanceNeedsPickerSync = true
        end
        self._activeTabId = id
        self:_rebuildRows()
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
  if not self.visible or self._activeTabId ~= "appearance" then
    return false
  end
  for _, p in pairs(self._appearancePickers or {}) do
    if p and type(p.wantsHandCursorAt) == "function" and p:wantsHandCursorAt(px, py) then
      return true
    end
  end
  return false
end

function Dialog:hide()
  self.visible = false
  self.pressedButton = nil
  self.pressedResetAll = nil
  if self._resetAllButton then
    self._resetAllButton.pressed = false
  end
  forEachAppearancePicker(self, function(p)
    p:closeMenu()
  end)
  self.rows = {}
  self.buttons = {}
  self._activeTabId = "general"
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:_containsBox(x, y)
  if self._activeTabId == "appearance" then
    if anyAppearancePickerMenu(self, function(p)
      return p:isMenuVisible() and p.menu:contains(x, y)
    end) then
      return true
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
  if self._activeTabId == "appearance" then
    for _, p in pairs(self._appearancePickers or {}) do
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
  if self._activeTabId == "appearance" then
    for _, p in pairs(self._appearancePickers or {}) do
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
    self.getAppearanceChromeRgb = opts.getAppearanceChromeRgb
    self.onAppearanceChromeChange = opts.onAppearanceChromeChange
    self.onResetAll = opts.onResetAll
    self.visible = true
  self.pressedButton = nil
  self._activeTabId = "general"
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

  if self._activeTabId == "appearance" then
    for _, slotId in ipairs(APPEARANCE_PICKER_SLOT_IDS) do
      local p = self._appearancePickers and self._appearancePickers[slotId]
      if p and p:handleMousePressed(x, y, button) then
        return true
      end
    end
  end

  if self._tabBar:mousepressed(x, y, button) then
    return true
  end

  if self._resetAllButton and self._resetAllButton:contains(x, y) then
    self._resetAllButton.pressed = true
    self.pressedResetAll = true
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

  if self._activeTabId == "appearance" then
    for _, slotId in ipairs(APPEARANCE_PICKER_SLOT_IDS) do
      local p = self._appearancePickers and self._appearancePickers[slotId]
      if p and p:handleMouseReleased(x, y, button) then
        return true
      end
    end
  end

  local pressed = self.pressedButton
  self.pressedButton = nil
  for _, entry in ipairs(self.buttons or {}) do
    entry.button.pressed = false
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
  if self._activeTabId == "appearance" then
    forEachAppearancePicker(self, function(p)
      p:mousemoved(x, y)
    end)
  end
  self._tabBar:mousemoved(x, y)
  if self._resetAllButton then
    self._resetAllButton.hovered = self._resetAllButton:contains(x, y)
  end
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
  if self._activeTabId == "appearance" then
    forEachAppearancePicker(self, function(p)
      p:drawMenu()
    end)
  end
end

return Dialog
