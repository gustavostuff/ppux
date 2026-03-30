local katsudo = require("lib.katsudo")
local colors = require("app_colors")
local images = require("images")
local ResolutionController = require("controllers.app.resolution_controller")

local M = {}

M.MINIMIZED_VISIBLE_MAX = 35
M.MINIMIZED_SCROLLBAR_OPACITY_TIME = 1.5
M.MINIMIZED_SCROLL_BUTTON_W = 10
M.MINIMIZED_SCROLL_BUTTON_H = 15

function M.install(Taskbar, Helpers)
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
    local maxOffset = math.max(0, #self.minimizedWindows - M.MINIMIZED_VISIBLE_MAX)
    self.minimizedScrollOffset = math.max(0, math.min(maxOffset, self.minimizedScrollOffset or 0))
  end

  local function canScrollMinimizedLeft(self)
    return (self.minimizedScrollOffset or 0) > 0
  end

  local function canScrollMinimizedRight(self)
    local maxOffset = math.max(0, #self.minimizedWindows - M.MINIMIZED_VISIBLE_MAX)
    return (self.minimizedScrollOffset or 0) < maxOffset
  end

  local function scrollMinimizedWindows(self, delta)
    if delta == 0 then return false end
    local before = self.minimizedScrollOffset or 0
    self.minimizedScrollOffset = before + delta
    clampMinimizedScroll(self)
    local changed = (self.minimizedScrollOffset or 0) ~= before
    if changed then
      self:_buildVisibleToolbarButtons()
      self:_triggerMinimizedScrollbarFade()
    end
    return changed
  end

  local function ensureTaskbarButtonForWindow(self, win)
    if not win or win._closed then return nil end
    local button = self.minimizedButtonsByWindow[win]
    if not button then
      button = Helpers.newTaskbarButton({
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
    self:_buildVisibleToolbarButtons()
    if self:_hasMinimizedOverflow() then
      self:_triggerMinimizedScrollbarFade()
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
    self:_buildVisibleToolbarButtons()
    if self:_hasMinimizedOverflow() then
      self:_triggerMinimizedScrollbarFade()
    end
    return true
  end

  function Taskbar:_initWindowControls()
    self.minimizedWindowButtonIcon = images.icons.icon_circle
    self.minimizedScrollLeftIcon = images.icons.icon_scroll_toolbar_left
    self.minimizedScrollRightIcon = images.icons.icon_scroll_toolbar_right
    self.minimizedScrollEmptyIcon = images.icons.icon_scroll_toolbar_empty or self.minimizedScrollLeftIcon or self.minimizedWindowButtonIcon
    self.modeTileIcon = images.icons.icon_ui_hand
    self.modeEditIcon = images.icons.icon_ui_pencil

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

    self.minimizedScrollLeftButton = Helpers.newTaskbarButton({
      icon = self.minimizedScrollLeftIcon,
      w = M.MINIMIZED_SCROLL_BUTTON_W,
      h = M.MINIMIZED_SCROLL_BUTTON_H,
      tooltip = "Scroll left",
      action = function()
        if not canScrollMinimizedLeft(self) then return end
        scrollMinimizedWindows(self, -1)
      end,
    })
    self.minimizedScrollLeftButton.isMinimizedScrollButton = true
    self.minimizedScrollLeftButton.scrollDirection = "left"
    self.minimizedScrollLeftButton.scrollEnabled = false

    self.minimizedScrollRightButton = Helpers.newTaskbarButton({
      icon = self.minimizedScrollRightIcon,
      w = M.MINIMIZED_SCROLL_BUTTON_W,
      h = M.MINIMIZED_SCROLL_BUTTON_H,
      tooltip = "Scroll right",
      action = function()
        if not canScrollMinimizedRight(self) then return end
        scrollMinimizedWindows(self, 1)
      end,
    })
    self.minimizedScrollRightButton.isMinimizedScrollButton = true
    self.minimizedScrollRightButton.scrollDirection = "right"
    self.minimizedScrollRightButton.scrollEnabled = false

    local sortAZIcon = images.icons.sort_a_z
    local sortZAIcon = images.icons.sort_z_a
    local sortKindAscIcon = images.icons.sort_kind_asc
    local sortKindDescIcon = images.icons.sort_kind_desc

    self.sortAlphaButton = Helpers.newTaskbarButton({
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
          Helpers.setLastEvent(self.app, descending and "Minimized windows sorted Z-A" or "Minimized windows sorted A-Z")
          if self._refreshMenuSortCells then
            self:_refreshMenuSortCells()
          end
        end
      end,
    })
    self.sortAlphaButton.fitIconWidth = true

    self.sortKindButton = Helpers.newTaskbarButton({
      icon = sortKindAscIcon,
      tooltip = "Sort by kind (asc)",
      action = function()
        local ascending = (self.sortKindAscending == true)
        local descending = not ascending
        local didSort = sortMinimizedWindows(self, function(a, b)
          local ar = Helpers.getTaskbarSortRankForWindow(a)
          local br = Helpers.getTaskbarSortRankForWindow(b)
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
          Helpers.setLastEvent(self.app, descending and "Minimized windows sorted by kind (desc)" or "Minimized windows sorted by type (asc)")
          if self._refreshMenuSortCells then
            self:_refreshMenuSortCells()
          end
        end
      end,
    })
    self.sortKindButton.fitIconWidth = true
  end

  function Taskbar:_buildVisibleToolbarButtons()
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
    local overflow = minimizedCount > M.MINIMIZED_VISIBLE_MAX
    local leftEnabled = overflow and canScrollMinimizedLeft(self)
    local rightEnabled = overflow and canScrollMinimizedRight(self)

    if showMinimizedStripControls and self.minimizedScrollLeftButton then
      self.minimizedScrollLeftButton.scrollEnabled = leftEnabled
      self.minimizedScrollLeftButton.icon = leftEnabled and self.minimizedScrollLeftIcon or self.minimizedScrollEmptyIcon
      buttons[#buttons + 1] = self.minimizedScrollLeftButton
    end

    local startIndex = 1 + (self.minimizedScrollOffset or 0)
    local endIndex = math.min(#self.minimizedWindows, startIndex + M.MINIMIZED_VISIBLE_MAX - 1)
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

  function Taskbar:_triggerMinimizedScrollbarFade()
    self.minimizedScrollbarOpacity = M.MINIMIZED_SCROLLBAR_OPACITY_TIME
  end

  function Taskbar:_hasMinimizedOverflow()
    return (#(self.minimizedWindows or {})) > M.MINIMIZED_VISIBLE_MAX
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
    return katsudo.new(sheet, 15, 15, frames, 0.1)
  end

  function Taskbar:getTaskbarIconForWindow(win)
    local iconKey = Helpers.getTaskbarIconKeyForWindow(win)
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
    self:_buildVisibleToolbarButtons()
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
    self:_buildVisibleToolbarButtons()
    if self:_hasMinimizedOverflow() then
      self:_triggerMinimizedScrollbarFade()
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
      self:_buildVisibleToolbarButtons()
      if self:_hasMinimizedOverflow() then
        self:_triggerMinimizedScrollbarFade()
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
    if #self.minimizedWindows <= M.MINIMIZED_VISIBLE_MAX then
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

  function Taskbar:_handleMinimizedDrag(x, y)
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
          end
        end
      end
    end
  end
end

return M
