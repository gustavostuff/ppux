local Button = require("user_interface.button")
local ContextualMenuController = require("controllers.ui.contextual_menu_controller")
local Text = require("utils.text_utils")
local Draw = require("utils.draw_utils")
local colors = require("app_colors")
local images = require("images")
local katsudo = require("lib.katsudo")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local ResolutionController = require("controllers.app.resolution_controller")

local Taskbar = {}
Taskbar.__index = Taskbar

local function appHasLoadedRom(app)
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
local STATUS_MAX_CHARS = 120
local STATUS_TRUNCATION_SUFFIX = "..."
local CONTROL_GAP = 6
local MINIMIZED_VISIBLE_MAX = 35
local MINIMIZED_SCROLLBAR_OPACITY_TIME = 1.5
local MINIMIZED_SCROLL_BUTTON_W = 10
local MINIMIZED_SCROLL_BUTTON_H = 15
local MODE_BADGE_TEXT_PAD_X = 6
local MODE_BADGE_ICON_GAP = 0
local MODE_BADGE_MARGIN_RIGHT = CONTROL_GAP
local MODE_BADGE_TILE_BG = { 0.0, 0.56, 0.0 }
local MODE_BADGE_EDIT_BG = { 0.82, 0.64, 0.16 }
local resolveBrushIndicatorColor
local buildVisibleToolbarButtons
local triggerMinimizedScrollbarFade

local function pointInRect(px, py, x, y, w, h)
  return px >= x and px <= (x + w) and py >= y and py <= (y + h)
end

local function splitPath(path)
  if type(path) ~= "string" then
    return "", ""
  end
  local dir, base = path:match("^(.*)[/\\]([^/\\]+)$")
  if not dir then
    return "", path
  end
  return dir, base
end

local function baseName(path)
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

local function getTaskbarIconKeyForWindow(win)
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

local function getTaskbarSortRankForWindow(win)
  local iconKey = getTaskbarIconKeyForWindow(win)
  return TASKBAR_KIND_SORT_RANK[iconKey] or TASKBAR_KIND_SORT_RANK.generic
end

local function newTaskbarButton(opts)
  opts = opts or {}
  opts.alwaysOpaqueContent = true
  return Button.new(opts)
end

local function getModeIndicatorData(self)
  local mode = (self.app and self.app.mode == "edit") and "edit" or "tile"
  local isEdit = (mode == "edit")
  return {
    mode = mode,
    label = isEdit and "Edit" or "Tile",
    bg = isEdit and MODE_BADGE_EDIT_BG or MODE_BADGE_TILE_BG,
    textColor = isEdit and colors.black or colors.white,
    icon = isEdit and self.modeEditIcon or self.modeTileIcon,
    useCursorShader = isEdit,
  }
end

local function getModeIndicatorLayout(self)
  local data = getModeIndicatorData(self)
  local font = love.graphics.getFont()
  local textW = (font and font:getWidth(data.label)) or 0
  local textH = (font and font:getHeight()) or 0
  local badgeW = math.max(24, textW + (MODE_BADGE_TEXT_PAD_X * 2))
  local badgeH = self.h
  local iconW = self.h
  local iconH = self.h
  local totalW = badgeW + MODE_BADGE_ICON_GAP + iconW

  local badgeX = math.floor((self.x + self.w) - MODE_BADGE_MARGIN_RIGHT - totalW)
  local badgeY = self.y
  local iconX = badgeX + badgeW + MODE_BADGE_ICON_GAP
  local iconY = self.y
  local icon = data.icon
  local iw = (icon and icon.getWidth and icon:getWidth()) or iconW
  local ih = (icon and icon.getHeight and icon:getHeight()) or iconH
  local drawX = iconX + math.floor((iconW - iw) * 0.5)
  if icon and self.app and self.app.canvas and self.app.canvas.getWidth and icon.getWidth then
    drawX = self.app.canvas:getWidth() - icon:getWidth()
  end
  local drawY = math.floor(iconY + (iconH - ih) * 0.5)

  return {
    data = data,
    badgeX = badgeX,
    badgeY = badgeY,
    badgeW = badgeW,
    badgeH = badgeH,
    iconDrawX = drawX,
    iconDrawY = drawY,
    iconDrawW = iw,
    iconDrawH = ih,
  }
end

local function modeIndicatorContains(self, x, y)
  local layout = getModeIndicatorLayout(self)
  if pointInRect(x, y, layout.badgeX, layout.badgeY, layout.badgeW, layout.badgeH) then
    return true
  end
  if pointInRect(x, y, layout.iconDrawX, layout.iconDrawY, layout.iconDrawW, layout.iconDrawH) then
    return true
  end
  return false
end

local function toggleMode(self)
  local app = self and self.app
  if not app then return end
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

local function drawModeIndicator(self)
  local layout = getModeIndicatorLayout(self)
  local data = layout.data
  local font = love.graphics.getFont()
  local textW = (font and font:getWidth(data.label)) or 0
  local textH = (font and font:getHeight()) or 0

  local bg = data.bg
  love.graphics.setColor(bg[1], bg[2], bg[3], 1)
  love.graphics.rectangle("fill", layout.badgeX, layout.badgeY, layout.badgeW, layout.badgeH)

  local tc = data.textColor
  local textX = math.floor(layout.badgeX + (layout.badgeW - textW) * 0.5)
  local textY = math.floor(layout.badgeY + (layout.badgeH - textH) * 0.5) + 1
  love.graphics.setColor(tc[1], tc[2], tc[3], 1)
  love.graphics.print(data.label, textX, textY)

  local icon = data.icon
  if icon then
    if data.useCursorShader then
      local shader = Draw.getCursorShader and Draw.getCursorShader() or nil
      if shader then
        local paint = resolveBrushIndicatorColor(self.app) or colors.white
        shader:send("u_paintColor", { paint[1] or 1, paint[2] or 1, paint[3] or 1 })
        local now = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
        shader:send("u_time", now)
        shader:send("u_applyPaint", true)
        love.graphics.setShader(shader)
      end
      love.graphics.setColor(colors.white)
      love.graphics.draw(icon, layout.iconDrawX, layout.iconDrawY)
      love.graphics.setShader()
    else
      love.graphics.setColor(colors.white)
      love.graphics.draw(icon, layout.iconDrawX, layout.iconDrawY)
    end
  end

  love.graphics.setColor(colors.white)
end

local function setLastEvent(app, text)
  if not (app and text) then return end
  app.statusText = text
  app.lastEventText = text
end

local function clampBrushColorIndex(app)
  return math.max(1, math.min(4, ((app and app.currentColor) or 0) + 1))
end

resolveBrushIndicatorColor = function(app)
  local colorIndex = clampBrushColorIndex(app)
  local fallback = ShaderPaletteController.colorOfIndex(colorIndex) or colors.white
  if not app then return fallback end

  local wm = app.wm
  if not (wm and wm.windowAt and wm.getFocus) then
    return fallback
  end

  local mouse = ResolutionController:getScaledMouse(true)
  local win = wm:windowAt(mouse.x, mouse.y)
  if not win or win.isPalette then
    win = wm:getFocus()
  end
  if not win or win.isPalette then
    return fallback
  end

  local li = win.getActiveLayerIndex and win:getActiveLayerIndex() or 1
  local layer = win.layers and win.layers[li]
  if not layer then
    return fallback
  end

  local paletteNum
  if layer.kind == "sprite" then
    local spriteIdx = layer.hoverSpriteIndex or layer.selectedSpriteIndex
    local item = spriteIdx and layer.items and layer.items[spriteIdx] or nil
    paletteNum = item and item.paletteNumber or nil
  else
    local col, row
    if win.toGridCoords then
      local ok, c, r = win:toGridCoords(mouse.x, mouse.y)
      if ok then
        col, row = c, r
      end
    end
    if (not col or not row) and win.getSelected then
      local sc, sr, sl = win:getSelected()
      if sc and sr and (not sl or sl == li) then
        col, row = sc, sr
      end
    end
    if col and row then
      local idx = row * (win.cols or 1) + col
      if layer.paletteNumbers then
        paletteNum = layer.paletteNumbers[idx]
      end
    end
  end

  if not paletteNum then
    return fallback
  end

  local romRaw = app.appEditState and app.appEditState.romRaw
  local paletteColors = ShaderPaletteController.getPaletteColors(layer, paletteNum, romRaw)
  if paletteColors and paletteColors[colorIndex] then
    return paletteColors[colorIndex]
  end

  return fallback
end

local function fitStatusText(text, maxWidth)
  if maxWidth <= 0 then return "" end
  local font = love.graphics.getFont()
  if not font or font:getWidth(text) <= maxWidth then
    return text
  end

  local ellipsis = STATUS_TRUNCATION_SUFFIX
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

local function drawBrushIndicator(self, swatchX, swatchY, swatchSize)
  local brushColor = resolveBrushIndicatorColor(self.app)
  love.graphics.setColor(colors.black)
  love.graphics.rectangle("fill", swatchX - 1, swatchY - 1, swatchSize + 2, swatchSize + 2)
  love.graphics.setColor(brushColor[1] or 1, brushColor[2] or 1, brushColor[3] or 1, 1)
  love.graphics.rectangle("fill", swatchX, swatchY, swatchSize, swatchSize)
end

local function drawStatusWithBrushIndicator(self, eventText, opts)
  opts = opts or {}
  local drawStatusText = (opts.drawStatusText ~= false)
  local drawBrush = (opts.drawBrush ~= false)
  local status = Text.limitChars(
    "" .. tostring(eventText or ""),
    STATUS_MAX_CHARS
  )
  local margin = CONTROL_GAP

  local swatchSize = math.max(6, self.h - 6)
  local controlsEndX = self.x + self.paddingX
  if #self.buttons > 0 then
    local last = self.buttons[#self.buttons]
    controlsEndX = last.x + last.w
  end
  local swatchX = math.floor(controlsEndX + margin)
  local swatchY = math.floor(self.y + (self.h - swatchSize) * 0.5)
  if drawBrush then
    drawBrushIndicator(self, swatchX, swatchY, swatchSize)
  end

  local leftAfterControls = swatchX + swatchSize + margin

  local textX = leftAfterControls
  local textRight = self.x + self.w - margin
  local maxTextWidth = math.max(0, textRight - textX)
  local statusDisplay = fitStatusText(status, maxTextWidth)
  local font = love.graphics.getFont()
  local statusW = (font and font:getWidth(statusDisplay)) or 0
  local drawX = math.max(textX, textRight - statusW)

  if drawStatusText then
    love.graphics.setColor(colors.white)
    Text.print(statusDisplay, drawX, self.y + 3, { shadowColor = colors.transparent })
  end
end

local function removeMinimizedWindowAt(self, idx)
  local win = self.minimizedWindows[idx]
  if not win then return end
  table.remove(self.minimizedWindows, idx)
  self.minimizedButtonsByWindow[win] = nil
end

local function pruneMinimizedWindows(self)
  for i = #self.minimizedWindows, 1, -1 do
    local win = self.minimizedWindows[i]
    if (not win) or win._closed then
      removeMinimizedWindowAt(self, i)
    end
  end
end

local function clampMinimizedScroll(self)
  local maxOffset = math.max(0, #self.minimizedWindows - MINIMIZED_VISIBLE_MAX)
  self.minimizedScrollOffset = math.max(0, math.min(maxOffset, self.minimizedScrollOffset or 0))
end

local function canScrollMinimizedLeft(self)
  return (self.minimizedScrollOffset or 0) > 0
end

local function canScrollMinimizedRight(self)
  local maxOffset = math.max(0, #self.minimizedWindows - MINIMIZED_VISIBLE_MAX)
  return (self.minimizedScrollOffset or 0) < maxOffset
end

local function scrollMinimizedWindows(self, delta)
  if delta == 0 then return false end
  local before = self.minimizedScrollOffset or 0
  self.minimizedScrollOffset = before + delta
  clampMinimizedScroll(self)
  local changed = (self.minimizedScrollOffset or 0) ~= before
  if changed then
    buildVisibleToolbarButtons(self)
    triggerMinimizedScrollbarFade(self)
  end
  return changed
end

local function ensureTaskbarButtonForWindow(self, win)
  if not win or win._closed then return nil end
  local button = self.minimizedButtonsByWindow[win]
  if not button then
    button = newTaskbarButton({
      icon = self:getTaskbarIconForWindow(win),
      text = nil,
      tooltip = string.format("Window %s", tostring(win.title or "window")),
      action = function()
        local wm = self.app and self.app.wm
        if not wm or win._closed then return end
        if win._minimized then
          if wm.restoreMinimizedWindow then wm:restoreMinimizedWindow(win) end
          return
        end
        if wm.getFocus and wm:getFocus() == win then
          if wm.minimizeWindow then wm:minimizeWindow(win) end
          return
        end
        if wm.setFocus then
          wm:setFocus(win)
        end
      end,
    })
    button.isMinimizedWindowButton = true
    button.minimizedWindow = win
    self.minimizedButtonsByWindow[win] = button
  else
    button.icon = self:getTaskbarIconForWindow(win)
    button.text = nil
    button.minimizedWindow = win
  end

  local wm = self.app and self.app.wm
  local focused = wm and wm.getFocus and wm:getFocus() or nil
  button.focused = (focused == win)
  button.bgColor = (focused == win) and colors.blue or nil
  if win._minimized then
    button.tooltip = string.format("Restore %s", tostring(win.title or "window"))
  elseif focused == win then
    button.tooltip = string.format("Minimize %s", tostring(win.title or "window"))
  else
    button.tooltip = string.format("Focus %s", tostring(win.title or "window"))
  end
  return button
end

local function syncTaskbarWindowsFromWM(self)
  local wm = self.app and self.app.wm
  if not (wm and wm.getWindows) then return end

  pruneMinimizedWindows(self)

  local present = {}
  for _, win in ipairs(self.minimizedWindows) do
    present[win] = true
    ensureTaskbarButtonForWindow(self, win)
  end

  for _, win in ipairs(wm:getWindows() or {}) do
    if win and not win._closed then
      if not present[win] then
        self.minimizedWindows[#self.minimizedWindows + 1] = win
        present[win] = true
      end
      ensureTaskbarButtonForWindow(self, win)
    end
  end
end

buildVisibleToolbarButtons = function(self)
  local buttons = {}
  if self.menuButton then
    buttons[#buttons + 1] = self.menuButton
  end

  if self.showSortButtons and self.sortAlphaButton then
    buttons[#buttons + 1] = self.sortAlphaButton
  end
  if self.showSortButtons and self.sortKindButton then
    buttons[#buttons + 1] = self.sortKindButton
  end

  syncTaskbarWindowsFromWM(self)
  clampMinimizedScroll(self)
  local minimizedCount = #(self.minimizedWindows or {})
  local showMinimizedStripControls = minimizedCount > 0
  local overflow = minimizedCount > MINIMIZED_VISIBLE_MAX
  local leftEnabled = overflow and canScrollMinimizedLeft(self)
  local rightEnabled = overflow and canScrollMinimizedRight(self)

  if showMinimizedStripControls and self.minimizedScrollLeftButton then
    self.minimizedScrollLeftButton.scrollEnabled = leftEnabled
    self.minimizedScrollLeftButton.icon = leftEnabled and self.minimizedScrollLeftIcon or self.minimizedScrollEmptyIcon
    buttons[#buttons + 1] = self.minimizedScrollLeftButton
  end

  local startIndex = 1 + (self.minimizedScrollOffset or 0)
  local endIndex = math.min(#self.minimizedWindows, startIndex + MINIMIZED_VISIBLE_MAX - 1)
  for i = startIndex, endIndex do
    local win = self.minimizedWindows[i]
    local btn = win and self.minimizedButtonsByWindow[win] or nil
    if btn then
      ensureTaskbarButtonForWindow(self, win)
      buttons[#buttons + 1] = btn
    end
  end

  if showMinimizedStripControls and self.minimizedScrollRightButton then
    self.minimizedScrollRightButton.scrollEnabled = rightEnabled
    self.minimizedScrollRightButton.icon = rightEnabled and self.minimizedScrollRightIcon or self.minimizedScrollEmptyIcon
    buttons[#buttons + 1] = self.minimizedScrollRightButton
  end

  self.buttons = buttons
end

triggerMinimizedScrollbarFade = function(self)
  self.minimizedScrollbarOpacity = MINIMIZED_SCROLLBAR_OPACITY_TIME
end

local function hasMinimizedOverflow(self)
  return (#(self.minimizedWindows or {})) > MINIMIZED_VISIBLE_MAX
end

local function findMinimizedWindowIndex(self, win)
  for i, w in ipairs(self.minimizedWindows or {}) do
    if w == win then return i end
  end
  return nil
end

local function moveMinimizedWindow(self, fromIdx, toIdx)
  if not fromIdx or not toIdx or fromIdx == toIdx then return false end
  local list = self.minimizedWindows or {}
  if fromIdx < 1 or fromIdx > #list or toIdx < 1 or toIdx > #list then return false end
  local win = table.remove(list, fromIdx)
  if not win then return false end
  table.insert(list, toIdx, win)
  buildVisibleToolbarButtons(self)
  if hasMinimizedOverflow(self) then
    triggerMinimizedScrollbarFade(self)
  end
  return true
end

local function sortMinimizedWindows(self, cmp)
  pruneMinimizedWindows(self)
  if #self.minimizedWindows <= 1 then
    return false
  end

  local originalIndex = {}
  for i, win in ipairs(self.minimizedWindows) do
    originalIndex[win] = i
  end

  table.sort(self.minimizedWindows, function(a, b)
    local res = cmp(a, b)
    if res == nil then
      return (originalIndex[a] or 0) < (originalIndex[b] or 0)
    end
    return res
  end)

  clampMinimizedScroll(self)
  buildVisibleToolbarButtons(self)
  if hasMinimizedOverflow(self) then
    triggerMinimizedScrollbarFade(self)
  end
  return true
end

function Taskbar:drawBrushIndicatorTopRight()
  local margin = CONTROL_GAP
  local swatchSize = math.max(6, self.h - 6)
  local swatchX = math.floor(self.x + self.w - margin - swatchSize)
  local swatchY = math.floor(margin)
  drawBrushIndicator(self, swatchX, swatchY, swatchSize)
  love.graphics.setColor(colors.white)
end

function Taskbar.new(app, data)
  data = data or {}
  local self = setmetatable({
    app = app,
    x = 0,
    y = 0,
    w = 0,
    h = data.h or 15,
    paddingX = 0,
    paddingY = 0,
    spacing = 0,
    pressedButton = nil,
    buttons = {},
    minimizedWindows = {},
    minimizedButtonsByWindow = {},
    minimizedScrollOffset = 0,
    menuController = nil,
    menuButton = nil,
    sortAlphaAscending = true,
    sortKindAscending = true,
    sortAlphaButton = nil,
    sortKindButton = nil,
    minimizedScrollLeftButton = nil,
    minimizedScrollRightButton = nil,
    showSortButtons = false,
    minimizedScrollbarOpacity = 0,
    visibleMinimizedButtons = {},
    minimizedStripX = nil,
    minimizedStripW = 0,
    minimizedDrag = {
      button = nil,
      win = nil,
      startX = 0,
      startY = 0,
      active = false,
      reordered = false,
    },
    modeIndicatorPressed = false,
  }, Taskbar)

  local menuIcon = images.menu_button
  local saveIcon = images.icons.save
  local settingsIcon = images.icons.settings
  local windowsMenuIcon = images.icons.icon_windows
  local closeProjectIcon = images.icons.icon_x
  local quitIcon = images.icons.icon_quit
  local recentProjectsIcon = images.icons.icon_clock
  local expandAllIcon = images.icons.icon_cascade_all
  local collapseAllIcon = images.icons.icon_collapse_all
  local minimizeAllIcon = images.icons.min_all
  local maximizeAllIcon = images.icons.max_all
  local minimizedWindowIcon = images.icons.icon_circle
  local scrollLeftIcon = images.icons.icon_scroll_toolbar_left
  local scrollRightIcon = images.icons.icon_scroll_toolbar_right
  local scrollEmptyIcon = images.icons.icon_scroll_toolbar_empty or scrollLeftIcon or minimizedWindowIcon
  local modeTileIcon = images.icons.icon_ui_hand
  local modeEditIcon = images.icons.icon_ui_pencil
  local sortAZIcon = images.icons.sort_a_z
  local sortZAIcon = images.icons.sort_z_a
  local sortKindAscIcon = images.icons.sort_kind_asc
  local sortKindDescIcon = images.icons.sort_kind_desc
  local newWindowIcon = images.icons.icon_new_window
  local menuTextOffsetY = 1
  local menuButton = newTaskbarButton({
    icon = menuIcon,
    tooltip = "Menu",
    action = function()
      self:toggleMenu()
    end,
  })
  menuButton.fitIconWidth = true
  self.menuButton = menuButton
  self.minimizedWindowButtonIcon = minimizedWindowIcon
  self.minimizedScrollLeftIcon = scrollLeftIcon
  self.minimizedScrollRightIcon = scrollRightIcon
  self.minimizedScrollEmptyIcon = scrollEmptyIcon
  self.modeTileIcon = modeTileIcon
  self.modeEditIcon = modeEditIcon
  local windowIcons = images.windows_icons or images.animated_icons or {}
  self.taskbarAnimatedSheetsByKind = {
    static_tile = windowIcons.icon_static_tile_window or nil,
    static_sprite = windowIcons.icon_static_sprite_window or nil,
    animated_tile = windowIcons.icon_animated_tile_window or nil,
    animated_sprite = windowIcons.icon_animated_sprite_window or nil,
    oam_animated = windowIcons.icon_oam_animated_window or nil,
    chr = windowIcons.icon_chr_window or nil,
    rom_window = windowIcons.icon_rom_window or nil,
    ppu_frame = windowIcons.icon_ppu_frame_window or nil,
    palette = windowIcons.icon_palette_window or nil,
    rom_palette = windowIcons.icon_rom_palette_window or nil,
    generic = windowIcons.icon_generic_window or nil,
  }
  self.taskbarAnimatedIconByKind = {}

  self.minimizedScrollLeftButton = newTaskbarButton({
    icon = scrollLeftIcon,
    w = MINIMIZED_SCROLL_BUTTON_W,
    h = MINIMIZED_SCROLL_BUTTON_H,
    tooltip = "Scroll left",
    action = function()
      if not canScrollMinimizedLeft(self) then return end
      scrollMinimizedWindows(self, -1)
    end,
  })
  self.minimizedScrollLeftButton.isMinimizedScrollButton = true
  self.minimizedScrollLeftButton.scrollDirection = "left"
  self.minimizedScrollLeftButton.scrollEnabled = false

  self.minimizedScrollRightButton = newTaskbarButton({
    icon = scrollRightIcon,
    w = MINIMIZED_SCROLL_BUTTON_W,
    h = MINIMIZED_SCROLL_BUTTON_H,
    tooltip = "Scroll right",
    action = function()
      if not canScrollMinimizedRight(self) then return end
      scrollMinimizedWindows(self, 1)
    end,
  })
  self.minimizedScrollRightButton.isMinimizedScrollButton = true
  self.minimizedScrollRightButton.scrollDirection = "right"
  self.minimizedScrollRightButton.scrollEnabled = false

  self.sortAlphaButton = newTaskbarButton({
    icon = sortAZIcon,
    tooltip = "Sort alphabetically (A-Z)",
    action = function()
      local ascending = (self.sortAlphaAscending == true)
      local descending = not ascending
      local didSort = sortMinimizedWindows(self, function(a, b)
        local at = string.lower(tostring(a and a.title or ""))
        local bt = string.lower(tostring(b and b.title or ""))
        if at ~= bt then
          if descending then
            return at > bt
          end
          return at < bt
        end
        return nil
      end)
      if didSort then
        self.sortAlphaAscending = not ascending
        self.sortAlphaButton.icon = self.sortAlphaAscending and sortAZIcon or sortZAIcon
        self.sortAlphaButton.tooltip = self.sortAlphaAscending and "Sort alphabetically (A-Z)" or "Sort alphabetically (Z-A)"
        setLastEvent(self.app, descending and "Minimized windows sorted Z-A" or "Minimized windows sorted A-Z")
        if self._refreshMenuSortCells then
          self:_refreshMenuSortCells()
        end
      end
    end,
  })
  self.sortAlphaButton.fitIconWidth = true

  self.sortKindButton = newTaskbarButton({
    icon = sortKindAscIcon,
    tooltip = "Sort by kind (asc)",
    action = function()
      local ascending = (self.sortKindAscending == true)
      local descending = not ascending
      local didSort = sortMinimizedWindows(self, function(a, b)
        local ar = getTaskbarSortRankForWindow(a)
        local br = getTaskbarSortRankForWindow(b)
        if ar ~= br then
          if descending then
            return ar > br
          end
          return ar < br
        end
        local at = string.lower(tostring(a and a.title or ""))
        local bt = string.lower(tostring(b and b.title or ""))
        if at ~= bt then
          if descending then
            return at > bt
          end
          return at < bt
        end
        return nil
      end)
      if didSort then
        self.sortKindAscending = not ascending
        self.sortKindButton.icon = self.sortKindAscending and sortKindAscIcon or sortKindDescIcon
        self.sortKindButton.tooltip = self.sortKindAscending and "Sort by kind (asc)" or "Sort by kind (desc)"
        setLastEvent(self.app, descending and "Minimized windows sorted by kind (desc)" or "Minimized windows sorted by type (asc)")
        if self._refreshMenuSortCells then
          self:_refreshMenuSortCells()
        end
      end
    end,
  })
  self.sortKindButton.fitIconWidth = true

  self.menuController = ContextualMenuController.new({
    getBounds = function()
      return {
        w = self.x + self.w,
        h = self.y + self.h,
      }
    end,
    cols = 8,
    cellW = 15,
    cellH = 15,
    padding = 0,
    colGap = 0,
    rowGap = 1,
    splitIconCell = true,
  })

  local function closeMenu()
    if self.menuController then
      self.menuController:hide()
    end
  end

  local function actionSave()
    closeMenu()
    if self.app and self.app.showSaveOptionsModal and self.app:showSaveOptionsModal() then
      setLastEvent(self.app, "Opened save options")
    end
  end

  local function actionNewWindow()
    closeMenu()
    if self.app and self.app.showNewWindowModal and self.app:showNewWindowModal() then
      setLastEvent(self.app, "Opened new window modal")
    end
  end

  local function actionSettings()
    closeMenu()
    if self.app and self.app.showSettingsModal then
      self.app:showSettingsModal()
      setLastEvent(self.app, "Opened settings")
    end
  end

  local function actionCloseProject()
    closeMenu()
    if self.app and self.app.requestCloseProject then
      self.app:requestCloseProject()
      setLastEvent(self.app, "Closed project")
    end
  end

  local function actionQuit()
    closeMenu()
    if not self.app then return end
    if self.app.handleQuitRequest and self.app:handleQuitRequest() then
      setLastEvent(self.app, "Opened quit confirmation")
      return
    end
    love.event.quit()
  end

  local function actionCollapseAll()
    closeMenu()
    local wm = self.app and self.app.wm
    local canvas = self.app and self.app.canvas
    if wm and wm.collapseAll and canvas then
      local areaX = 30
      local areaY = 30
      local areaH = math.max(1, self.y - areaY - 8)
      wm:collapseAll({
        areaX = areaX,
        areaY = areaY,
        areaH = areaH,
        gapX = 8,
        gapY = 2,
      })
      setLastEvent(self.app, "Windows collapsed and stacked")
    end
  end

  local function actionExpandAll()
    closeMenu()
    local wm = self.app and self.app.wm
    if wm and wm.expandAll and wm:expandAll() then
      setLastEvent(self.app, "Windows expanded")
    end
  end

  local function actionSortByTitle()
    closeMenu()
    if self.sortAlphaButton and self.sortAlphaButton.action then
      self.sortAlphaButton.action()
    end
  end

  local function actionSortByType()
    closeMenu()
    if self.sortKindButton and self.sortKindButton.action then
      self.sortKindButton.action()
    end
  end

  local function actionMinimizeAll()
    closeMenu()
    local wm = self.app and self.app.wm
    if wm and wm.minimizeAll and wm:minimizeAll() then
      setLastEvent(self.app, "Windows minimized")
    end
  end

  local function actionMaximizeAll()
    closeMenu()
    local wm = self.app and self.app.wm
    if wm and wm.maximizeAll and wm:maximizeAll() then
      setLastEvent(self.app, "Windows restored")
    end
  end

  self.buttons = {
    menuButton,
    self.sortAlphaButton,
    self.sortKindButton,
  }
  self._menuActions = {
    expandAll = actionExpandAll,
    collapseAll = actionCollapseAll,
    sortByTitle = actionSortByTitle,
    sortByType = actionSortByType,
    minimizeAll = actionMinimizeAll,
    maximizeAll = actionMaximizeAll,
    newWindow = actionNewWindow,
    save = actionSave,
    settings = actionSettings,
    closeProject = actionCloseProject,
    quit = actionQuit,
  }
  self._menuIcons = {
    expandAll = expandAllIcon,
    collapseAll = collapseAllIcon,
    minimizeAll = minimizeAllIcon,
    maximizeAll = maximizeAllIcon,
    newWindow = newWindowIcon,
    save = saveIcon,
    settings = settingsIcon,
    windows = windowsMenuIcon,
    recentProjects = recentProjectsIcon,
    closeProject = closeProjectIcon,
    quit = quitIcon,
  }
  self:_refreshMenuItems()
  return self
end

function Taskbar:resetWindowButtons()
  self.pressedButton = nil
  self.minimizedWindows = {}
  self.minimizedButtonsByWindow = {}
  self.minimizedScrollOffset = 0
  self.visibleMinimizedButtons = {}
  self.minimizedStripX = nil
  self.minimizedStripW = 0
  self.minimizedScrollbarOpacity = 0
  self.minimizedDrag = {
    button = nil,
    win = nil,
    startX = 0,
    startY = 0,
    active = false,
    reordered = false,
  }
  buildVisibleToolbarButtons(self)
end

function Taskbar:_getMenuAnchor()
  local menuH = (self.menuController and self.menuController.panel and self.menuController.panel.h) or 0
  local menuW = (self.menuController and self.menuController.panel and self.menuController.panel.w) or 0
  local panelX = self.menuButton and self.menuButton.x or self.x
  local panelY = self.y - menuH
  if panelY < 0 then
    panelY = 0
  end
  if panelX + menuW > self.x + self.w then
    panelX = math.max(self.x, self.x + self.w - menuW)
  end
  return panelX, panelY
end

function Taskbar:_buildRecentProjectMenuItems()
  local recent = (self.app and self.app.getRecentProjects and self.app:getRecentProjects()) or {}
  local entries = {}
  local stemCounts = {}

  for _, path in ipairs(recent) do
    local _, stem = splitPath(path)
    stemCounts[stem] = (stemCounts[stem] or 0) + 1
  end

  for _, path in ipairs(recent) do
    local dir, stem = splitPath(path)
    local label = stem
    if (stemCounts[stem] or 0) > 1 then
      local folder = baseName(dir)
      label = ((folder ~= "" and folder) or dir or "?") .. "/" .. stem
    end
    entries[#entries + 1] = {
      text = label,
      callback = function()
        if self.app and self.app.openRecentProject then
          self.app:openRecentProject(path)
        end
      end,
    }
  end

  return entries
end

function Taskbar:_buildMainMenuItems()
  local hasRom = appHasLoadedRom(self.app)
  local recentItems = self:_buildRecentProjectMenuItems()
  local windowsItems = {
    {
      icon = self._menuIcons and self._menuIcons.expandAll or nil,
      text = "Expand all",
      enabled = hasRom,
      callback = self._menuActions and self._menuActions.expandAll or nil,
    },
    {
      icon = self._menuIcons and self._menuIcons.collapseAll or nil,
      text = "Collapse all",
      enabled = hasRom,
      callback = self._menuActions and self._menuActions.collapseAll or nil,
    },
    {
      icon = self.sortAlphaButton and self.sortAlphaButton.icon or nil,
      text = "Sort by title",
      enabled = hasRom,
      callback = self._menuActions and self._menuActions.sortByTitle or nil,
    },
    {
      icon = self.sortKindButton and self.sortKindButton.icon or nil,
      text = "Sort by kind",
      enabled = hasRom,
      callback = self._menuActions and self._menuActions.sortByType or nil,
    },
    {
      icon = self._menuIcons and self._menuIcons.minimizeAll or nil,
      text = "Minimize all",
      enabled = hasRom,
      callback = self._menuActions and self._menuActions.minimizeAll or nil,
    },
    {
      icon = self._menuIcons and self._menuIcons.maximizeAll or nil,
      text = "Maximize all",
      enabled = hasRom,
      callback = self._menuActions and self._menuActions.maximizeAll or nil,
    },
  }

  return {
    {
      icon = self._menuIcons and self._menuIcons.recentProjects or nil,
      text = "Recent Projects",
      enabled = #recentItems > 0,
      children = (#recentItems > 0) and function()
        return self:_buildRecentProjectMenuItems()
      end or nil,
    },
    {
      icon = self._menuIcons and self._menuIcons.windows or nil,
      text = "Windows",
      enabled = hasRom,
      children = hasRom and function()
        return windowsItems
      end or nil,
    },
    {
      icon = self._menuIcons and self._menuIcons.quit or nil,
      text = "Quit",
      enabled = true,
      callback = self._menuActions and self._menuActions.quit or nil,
    },
    {
      icon = self._menuIcons and self._menuIcons.closeProject or nil,
      text = "Close Project",
      enabled = hasRom,
      callback = self._menuActions and self._menuActions.closeProject or nil,
    },
    {
      icon = self._menuIcons and self._menuIcons.settings or nil,
      text = "Settings",
      enabled = true,
      callback = self._menuActions and self._menuActions.settings or nil,
    },
    {
      icon = self._menuIcons and self._menuIcons.newWindow or nil,
      text = "New Window",
      enabled = hasRom,
      callback = self._menuActions and self._menuActions.newWindow or nil,
    },
    {
      icon = self._menuIcons and self._menuIcons.save or nil,
      text = "Save",
      enabled = hasRom,
      callback = self._menuActions and self._menuActions.save or nil,
    },
  }
end

function Taskbar:_refreshMenuItems()
  if not self.menuController then
    return
  end
  self.menuController:setItems(self:_buildMainMenuItems())
  if self.menuController:isVisible() then
    local panelX, panelY = self:_getMenuAnchor()
    self.menuController:setPosition(panelX, panelY)
  end
end

function Taskbar:_refreshMenuAvailability()
  self:_refreshMenuItems()
end

function Taskbar:_refreshMenuSortCells()
  self:_refreshMenuItems()
end

function Taskbar:toggleMenu()
  if not self.menuController then
    return false
  end
  self:_refreshMenuItems()
  local panelX, panelY = self:_getMenuAnchor()
  return self.menuController:toggleAt(panelX, panelY, self:_buildMainMenuItems())
end

function Taskbar:_createTaskbarAnimatedIcon(sheet)
  if not sheet or type(sheet.getWidth) ~= "function" or type(sheet.getHeight) ~= "function" then
    return nil
  end
  local iw = sheet:getWidth()
  local ih = sheet:getHeight()
  if ih ~= 15 or iw < 15 or (iw % 15 ~= 0) then
    return nil
  end
  local frames = math.max(1, math.floor(iw / 15))
  local anim = katsudo.new(sheet, 15, 15, frames, 0.1)
  -- if #anim.items > 2 then
  --   anim:setDelay(0.2, #anim.items - 2)
  --   anim:setDelay(0.15, #anim.items - 1 )
  --   anim:setDelay(0.3, #anim.items)
  -- end
  return anim
end

function Taskbar:getTaskbarIconForWindow(win)
  local iconKey = getTaskbarIconKeyForWindow(win)
  local sheet = iconKey and self.taskbarAnimatedSheetsByKind and self.taskbarAnimatedSheetsByKind[iconKey] or nil
  if not sheet then
    return self.minimizedWindowButtonIcon
  end

  local cached = self.taskbarAnimatedIconByKind[iconKey]
  if cached == nil then
    cached = self:_createTaskbarAnimatedIcon(sheet)
    self.taskbarAnimatedIconByKind[iconKey] = cached or false
  end

  if cached and cached ~= false then
    return cached
  end
  return self.minimizedWindowButtonIcon
end

function Taskbar:addMinimizedWindow(win)
  if not win or win._closed then return false end

  pruneMinimizedWindows(self)

  local existingIndex = nil
  for i = 1, #self.minimizedWindows do
    if self.minimizedWindows[i] == win then
      existingIndex = i
      break
    end
  end

  ensureTaskbarButtonForWindow(self, win)

  if not existingIndex then
    self.minimizedWindows[#self.minimizedWindows + 1] = win
  end
  clampMinimizedScroll(self)
  buildVisibleToolbarButtons(self)
  if hasMinimizedOverflow(self) then
    triggerMinimizedScrollbarFade(self)
  end
  return true
end

function Taskbar:addWindowButton(win)
  return self:addMinimizedWindow(win)
end

function Taskbar:removeMinimizedWindow(win)
  if not win then return false end
  local removedButton = self.minimizedButtonsByWindow[win]
  local changed = false
  if win._closed then
    for i = #self.minimizedWindows, 1, -1 do
      if self.minimizedWindows[i] == win then
        removeMinimizedWindowAt(self, i)
        changed = true
      end
    end
  else
    ensureTaskbarButtonForWindow(self, win)
    changed = true
  end
  if changed then
    if self.pressedButton and self.pressedButton == removedButton then
      self.pressedButton = nil
    end
    clampMinimizedScroll(self)
    buildVisibleToolbarButtons(self)
    if hasMinimizedOverflow(self) then
      triggerMinimizedScrollbarFade(self)
    end
  end
  return changed
end

function Taskbar:wheelmoved(dx, dy)
  local mouse = ResolutionController:getScaledMouse(true)
  if not mouse then
    return false
  end
  local hoveredButton = self:getButtonAt(mouse.x, mouse.y)
  local overMinimizedButton = hoveredButton and hoveredButton.isMinimizedWindowButton == true
  if not overMinimizedButton then
    return false
  end

  pruneMinimizedWindows(self)
  if #self.minimizedWindows <= MINIMIZED_VISIBLE_MAX then
    return true
  end

  if dy < 0 then
    scrollMinimizedWindows(self, 1)
  elseif dy > 0 then
    scrollMinimizedWindows(self, -1)
  else
    return true
  end
  return true
end

function Taskbar:update(dt)
  if type(dt) ~= "number" then return end
  self.minimizedScrollbarOpacity = math.max(0.0, math.min(1.0, (self.minimizedScrollbarOpacity or 0) - dt))
end

function Taskbar:updateLayout(canvasW, canvasH)
  self.w = canvasW or self.w
  self.y = canvasH - self.h
  if not (self.menuController and (self.menuController:isVisible() or self.menuController:hasPressedButton())) then
    self:_refreshMenuAvailability()
  end

  buildVisibleToolbarButtons(self)

  local buttonSize = self.h
  local x = self.x + self.paddingX
  local y = self.y + self.paddingY
  self.visibleMinimizedButtons = {}
  self.minimizedStripX = nil
  self.minimizedStripW = 0
  for _, button in ipairs(self.buttons) do
    local isMinimizedButton = (button.isMinimizedWindowButton == true)
    local isIconOnly = (button.icon ~= nil) and (button.text == nil)
    local buttonW = buttonSize
    local buttonH = buttonSize
    if isIconOnly then
      if button._explicitW then
        buttonW = button.w
      elseif button.icon and button.icon.getWidth then
        buttonW = button.icon:getWidth()
      end
      if button._explicitH then
        buttonH = button.h
      elseif button.icon and button.icon.getHeight then
        buttonH = button.icon:getHeight()
      end
    elseif button.fitIconWidth and button.icon and button.icon.getWidth then
      buttonW = math.max(buttonSize, button.icon:getWidth())
    end
    button:setSize(buttonW, buttonH)
    button:setPosition(x, y)
    if isMinimizedButton then
      self.visibleMinimizedButtons[#self.visibleMinimizedButtons + 1] = button
      if not self.minimizedStripX then
        self.minimizedStripX = x
      end
      self.minimizedStripW = (x + buttonW) - (self.minimizedStripX or x)
    end
    x = x + buttonW + self.spacing
  end

  for _, btn in pairs(self.minimizedButtonsByWindow) do
    local isVisible = false
    for _, visibleBtn in ipairs(self.buttons) do
      if visibleBtn == btn then
        isVisible = true
        break
      end
    end
    if not isVisible then
      btn.hovered = false
      btn.pressed = false
    end
  end

  if self.menuController and self.menuController:isVisible() then
    local panelX, panelY = self:_getMenuAnchor()
    self.menuController:setPosition(panelX, panelY)
  end
end

function Taskbar:getTopY()
  return self.y
end

function Taskbar:contains(px, py)
  local inBar = px >= self.x and px <= self.x + self.w and
    py >= self.y and py <= self.y + self.h
  if inBar then return true end
  if self.menuController and self.menuController:isVisible() and self.menuController:contains(px, py) then
    return true
  end
  return false
end

function Taskbar:getButtonAt(px, py)
  for _, button in ipairs(self.buttons) do
    if button.isMinimizedScrollButton and button.scrollEnabled == false then
      goto continue
    end
    if button:contains(px, py) then
      return button
    end
    ::continue::
  end
  return nil
end

function Taskbar:getTooltipAt(px, py)
  if self.menuController and self.menuController:isVisible() and self.menuController:contains(px, py) then
    local panelBtn = self.menuController:getButtonAt(px, py)
    if panelBtn and panelBtn.tooltip and panelBtn.tooltip ~= "" then
      return {
        text = panelBtn.tooltip,
        immediate = (panelBtn.tooltipImmediate == true),
        key = panelBtn,
      }
    end
  end

  local btn = self:getButtonAt(px, py)
  if not btn or not btn.tooltip or btn.tooltip == "" then
    return nil
  end

  local text = btn.tooltip
  local immediate = (btn.tooltipImmediate == true)
  if btn.isMinimizedWindowButton then
    local win = btn.minimizedWindow
    if win and win.title and tostring(win.title) ~= "" then
      text = tostring(win.title)
    end
    immediate = true
  end

  return {
    text = text,
    immediate = immediate,
    key = btn,
  }
end

function Taskbar:isInteractiveAt(px, py)
  if self.menuController and self.menuController:isVisible() and self.menuController:contains(px, py) then
    return self.menuController:getButtonAt(px, py) ~= nil
  end

  if self:getButtonAt(px, py) then
    return true
  end

  return modeIndicatorContains(self, px, py)
end

function Taskbar:mousepressed(x, y, button)
  if self.menuController and self.menuController:isVisible() and self.menuController:contains(x, y) then
    return self.menuController:mousepressed(x, y, button)
  end

  if (not self:contains(x, y)) then
    if self.menuController and self.menuController:isVisible() and button == 1 then
      self.menuController:hide()
    end
    return false
  end

  if button == 1 then
    local btn = self:getButtonAt(x, y)
    if btn then
      self.modeIndicatorPressed = false
      btn.pressed = true
      self.pressedButton = btn
      if btn.isMinimizedWindowButton then
        self.minimizedDrag = {
          button = btn,
          win = btn.minimizedWindow,
          startX = x,
          startY = y,
          active = false,
          reordered = false,
        }
      else
        self.minimizedDrag = {
          button = nil, win = nil, startX = 0, startY = 0, active = false, reordered = false
        }
      end
    else
      self.pressedButton = nil
      self.modeIndicatorPressed = modeIndicatorContains(self, x, y)
      self.minimizedDrag = {
        button = nil, win = nil, startX = 0, startY = 0, active = false, reordered = false
      }
    end
  end

  return true
end

function Taskbar:mousereleased(x, y, button)
  if self.menuController and self.menuController:isVisible()
    and (self.menuController:contains(x, y) or self.menuController:hasPressedButton()) then
    return self.menuController:mousereleased(x, y, button)
  end

  local consumed = false
  local dragState = self.minimizedDrag or {}
  local modeIndicatorClicked = false

  if button == 1 and self.pressedButton then
    consumed = true
    local pressedBtn = self.pressedButton
    local releasedBtn = self:getButtonAt(x, y)
    local cancelClick = (dragState.button == pressedBtn) and (dragState.active or dragState.reordered)
    if (not cancelClick) and releasedBtn == pressedBtn and pressedBtn.action then
      pressedBtn.action()
    end
  elseif button == 1 and self.modeIndicatorPressed then
    consumed = true
    modeIndicatorClicked = modeIndicatorContains(self, x, y)
  elseif self:contains(x, y) then
    consumed = true
  end

  for _, b in ipairs(self.buttons) do
    b.pressed = false
  end
  self.pressedButton = nil
  self.modeIndicatorPressed = false
  self.minimizedDrag = {
    button = nil, win = nil, startX = 0, startY = 0, active = false, reordered = false
  }
  if modeIndicatorClicked then
    toggleMode(self)
  end

  return consumed
end

function Taskbar:mousemoved(x, y)
  local dragState = self.minimizedDrag
  if dragState and dragState.button and self.pressedButton == dragState.button then
    local moved = math.abs(x - (dragState.startX or 0)) + math.abs(y - (dragState.startY or 0))
    if moved >= 3 then
      dragState.active = true
    end
    if dragState.active and dragState.win then
      local hovered = self:getButtonAt(x, y)
      if hovered and hovered.isMinimizedWindowButton and hovered ~= dragState.button and hovered.minimizedWindow then
        local fromIdx = findMinimizedWindowIndex(self, dragState.win)
        local toIdx = findMinimizedWindowIndex(self, hovered.minimizedWindow)
        if moveMinimizedWindow(self, fromIdx, toIdx) then
          dragState.reordered = true
          -- keep pressedButton pointing to the dragged minimized button object (same object after rebuild)
        end
      end
    end
  end

  local inBar = self:contains(x, y)
  local hovered = inBar and self:getButtonAt(x, y) or nil
  for _, b in ipairs(self.buttons) do
    b.hovered = (b == hovered)
  end
  if self.menuController then
    self.menuController:mousemoved(x, y)
  end
end

function Taskbar:draw(eventText)
  local c = colors.gray20
  love.graphics.setColor(c[1], c[2], c[3], 1)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

  for _, b in ipairs(self.buttons) do
    b:draw()
  end

  drawModeIndicator(self)

  if hasMinimizedOverflow(self) and (self.minimizedScrollbarOpacity or 0) > 0 and (self.minimizedStripX and self.minimizedStripW and self.minimizedStripW > 0) then
    local total = #self.minimizedWindows
    local visible = math.min(MINIMIZED_VISIBLE_MAX, total)
    local maxScroll = math.max(1, total - visible)
    local frac = visible / total
    local trackX = self.minimizedStripX
    local trackW = self.minimizedStripW
    local thumbW = math.max(2, math.floor(trackW * frac))
    local posFrac = (self.minimizedScrollOffset or 0) / maxScroll
    local thumbX = math.floor(trackX + posFrac * math.max(0, trackW - thumbW))
    local thumbY = self.y + self.h - 2
    local c = colors.white
    love.graphics.setColor(c[1], c[2], c[3], self.minimizedScrollbarOpacity or 0)
    love.graphics.rectangle("fill", thumbX, thumbY, thumbW, 2)
    love.graphics.setColor(colors.white)
  end

  if self.menuController then
    if self.menuController.update then
      self.menuController:update()
    end
    self.menuController:draw()
  end

  -- Keep status rendering code available, but disconnect the bottom status text and swatch for now.
  drawStatusWithBrushIndicator(self, eventText, { drawStatusText = false, drawBrush = false })
  love.graphics.setColor(colors.white)
end

return Taskbar
