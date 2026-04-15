local TableUtils = require("utils.table_utils")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}
M.__index = M

local function normalizeGroup(raw)
  raw = type(raw) == "table" and raw or {}
  return {
    activeSourceWindowId = type(raw.activeSourceWindowId) == "string" and raw.activeSourceWindowId or nil,
    activeIndex = tonumber(raw.activeIndex) or nil,
    logicalWindow = type(raw.logicalWindow) == "table" and TableUtils.deepcopy(raw.logicalWindow) or {},
  }
end

local function normalizeState(raw)
  raw = type(raw) == "table" and raw or {}
  return {
    version = 1,
    enabled = (raw.enabled == true),
    global = normalizeGroup(raw.global),
    rom = normalizeGroup(raw.rom),
  }
end

local function groupKeyFromWindow(win)
  if WindowCaps.isGlobalPaletteWindow(win) then
    return "global"
  end
  if WindowCaps.isRomPaletteWindow(win) then
    return "rom"
  end
  return nil
end

local function orderFieldForGroup(groupKey)
  if groupKey == "global" then
    return "_groupOrderGlobal"
  end
  if groupKey == "rom" then
    return "_groupOrderRom"
  end
  return "_groupOrder"
end

local function isSourcePaletteWindow(win)
  if not win then return false end
  if win._runtimeOnly == true then return false end
  if win._closed == true then return false end
  return groupKeyFromWindow(win) ~= nil
end

local function indexOfWindow(list, target)
  for i, win in ipairs(list or {}) do
    if win == target then
      return i
    end
  end
  return nil
end

local function clampIndex(i, count)
  if count <= 0 then return nil end
  if i < 1 then return 1 end
  if i > count then return count end
  return i
end

local function wrapIndex(i, count)
  if count <= 0 then return nil end
  return ((i - 1) % count) + 1
end

function M.new(app)
  return setmetatable({
    app = app,
    enabled = false,
    state = normalizeState(),
  }, M)
end

function M:setState(raw)
  self.state = normalizeState(raw)
  self.enabled = (self.state.enabled == true)
end

function M:getState()
  if self.enabled == true then
    -- Keep logical window geometry in sync with the currently visible grouped
    -- windows so project/layout saves persist the effective grouped position.
    for _, groupKey in ipairs({ "global", "rom" }) do
      local windows = self:_sourceWindowsForGroup(groupKey)
      if #windows > 0 then
        local active = self:_resolveActiveWindow(groupKey, windows)
        if active then
          local group = self.state[groupKey]
          group.logicalWindow = self:_extractLogicalLayout(active)
          group.activeSourceWindowId = active._id
          group.activeIndex = indexOfWindow(windows, active)
        end
      end
    end
  end
  self.state.enabled = (self.enabled == true)
  return TableUtils.deepcopy(self.state)
end

function M:_sourceWindowsForGroup(groupKey)
  local wm = self.app and self.app.wm
  local out = {}
  if not (wm and wm.getWindows) then
    return out
  end
  local orderField = orderFieldForGroup(groupKey)
  local runningMaxOrder = 0
  for _, win in ipairs(wm:getWindows() or {}) do
    local existing = tonumber(win and win[orderField]) or 0
    if existing > runningMaxOrder then
      runningMaxOrder = existing
    end
  end

  for i, win in ipairs(wm:getWindows() or {}) do
    if isSourcePaletteWindow(win) and groupKeyFromWindow(win) == groupKey then
      if tonumber(win[orderField]) == nil then
        runningMaxOrder = runningMaxOrder + 1
        win[orderField] = runningMaxOrder
      end
      out[#out + 1] = win
    end
  end

  table.sort(out, function(a, b)
    local ao = tonumber(a and a[orderField]) or math.huge
    local bo = tonumber(b and b[orderField]) or math.huge
    if ao == bo then
      return tostring(a and a._id or "") < tostring(b and b._id or "")
    end
    return ao < bo
  end)

  return out
end

function M:_captureOriginalLayout(win)
  if not win then return end
  if type(win._groupOriginalLayout) == "table" then
    return
  end
  win._groupOriginalLayout = {
    x = win.x,
    y = win.y,
    collapsed = (win._collapsed == true),
    minimized = (win._minimized == true),
    compactView = (win.compactView == true),
  }
end

function M:_restoreOriginalLayout(win)
  if not (win and type(win._groupOriginalLayout) == "table") then
    return
  end
  local layout = win._groupOriginalLayout
  win.x = layout.x
  win.y = layout.y
  win._collapsed = (layout.collapsed == true)
  win._minimized = (layout.minimized == true)
  if win.setCompactMode then
    win:setCompactMode(layout.compactView == true)
  elseif layout.compactView ~= nil then
    win.compactView = (layout.compactView == true)
  end
end

function M:_extractLogicalLayout(win)
  if not win then
    return {}
  end
  return {
    x = win.x,
    y = win.y,
    z = win._z,
    collapsed = (win._collapsed == true),
    minimized = (win._minimized == true),
    compactView = (win.compactView == true),
  }
end

function M:_applyLogicalLayout(win, logicalLayout)
  if not win then return end
  logicalLayout = type(logicalLayout) == "table" and logicalLayout or {}
  if type(logicalLayout.x) == "number" then
    win.x = logicalLayout.x
  end
  if type(logicalLayout.y) == "number" then
    win.y = logicalLayout.y
  end
  if logicalLayout.collapsed ~= nil then
    win._collapsed = (logicalLayout.collapsed == true)
  end
  if logicalLayout.minimized ~= nil then
    win._minimized = (logicalLayout.minimized == true)
  end
  if logicalLayout.compactView ~= nil then
    if win.setCompactMode then
      win:setCompactMode(logicalLayout.compactView == true)
    else
      win.compactView = (logicalLayout.compactView == true)
    end
  end
end

function M:_resolveActiveWindow(groupKey, windows)
  local group = self.state[groupKey] or normalizeGroup(nil)
  local active = nil
  if group.activeSourceWindowId then
    for _, win in ipairs(windows) do
      if win._id == group.activeSourceWindowId then
        active = win
        break
      end
    end
  end
  if not active and group.activeIndex then
    local i = clampIndex(math.floor(group.activeIndex), #windows)
    active = i and windows[i] or nil
  end
  if not active then
    for _, win in ipairs(windows) do
      if win._groupHidden ~= true then
        active = win
        break
      end
    end
  end
  return active or windows[1]
end

function M:_syncGroup(groupKey)
  local windows = self:_sourceWindowsForGroup(groupKey)
  local group = self.state[groupKey]
  if #windows == 0 then
    group.activeSourceWindowId = nil
    group.activeIndex = nil
    return
  end

  for _, win in ipairs(windows) do
    self:_captureOriginalLayout(win)
  end

  local active = self:_resolveActiveWindow(groupKey, windows)
  local activeIndex = indexOfWindow(windows, active) or 1
  local logicalLayout = group.logicalWindow
  if next(logicalLayout) == nil then
    logicalLayout = self:_extractLogicalLayout(active)
    group.logicalWindow = logicalLayout
  end

  for _, win in ipairs(windows) do
    if win == active then
      self:_applyLogicalLayout(win, logicalLayout)
      win._groupHidden = false
    else
      self:_restoreOriginalLayout(win)
      win._groupHidden = true
    end
  end

  group.activeSourceWindowId = active._id
  group.activeIndex = activeIndex
end

function M:_clearGrouping()
  local wm = self.app and self.app.wm
  if not (wm and wm.getWindows) then
    return
  end
  for _, win in ipairs(wm:getWindows() or {}) do
    if isSourcePaletteWindow(win) then
      win._groupHidden = false
      self:_restoreOriginalLayout(win)
      win._groupOriginalLayout = nil
      win._groupOrderGlobal = nil
      win._groupOrderRom = nil
    end
  end
end

function M:refresh()
  if self.enabled ~= true then
    self:_clearGrouping()
    self.state.enabled = false
    return
  end
  self:_syncGroup("global")
  self:_syncGroup("rom")
  self.state.enabled = true

  local wm = self.app and self.app.wm
  if wm and wm.getFocus and wm.setFocus then
    local focused = wm:getFocus()
    if focused and focused._groupHidden == true then
      for _, win in ipairs(wm:getWindows() or {}) do
        if win and win._closed ~= true and win._minimized ~= true and win._groupHidden ~= true then
          wm:setFocus(win)
          break
        end
      end
    end
  end
end

function M:setEnabled(enabled, rawState)
  if rawState ~= nil then
    self:setState(rawState)
  end
  self.enabled = (enabled == true)
  self.state.enabled = self.enabled
  self:refresh()
end

function M:cycleWindow(window, delta)
  if self.enabled ~= true then
    return false
  end
  local groupKey = groupKeyFromWindow(window)
  if not groupKey then
    return false
  end

  local windows = self:_sourceWindowsForGroup(groupKey)
  if #windows <= 1 then
    return false
  end

  local group = self.state[groupKey]
  local current = self:_resolveActiveWindow(groupKey, windows)
  local currentIndex = indexOfWindow(windows, current) or 1
  local targetIndex = wrapIndex(currentIndex + (delta or 0), #windows)
  if not targetIndex or targetIndex == currentIndex then
    return false
  end

  local target = windows[targetIndex]
  group.logicalWindow = self:_extractLogicalLayout(current)

  self:_restoreOriginalLayout(current)
  current._groupHidden = true

  self:_applyLogicalLayout(target, group.logicalWindow)
  target._groupHidden = false

  group.activeSourceWindowId = target._id
  group.activeIndex = targetIndex

  local wm = self.app and self.app.wm
  if wm and wm.setFocus then
    wm:setFocus(target)
  end

  return true
end

function M:activateWindow(window)
  if self.enabled ~= true then
    return false
  end
  local groupKey = groupKeyFromWindow(window)
  if not groupKey then
    return false
  end

  local windows = self:_sourceWindowsForGroup(groupKey)
  local targetIndex = indexOfWindow(windows, window)
  if not targetIndex then
    return false
  end

  local group = self.state[groupKey]
  local current = self:_resolveActiveWindow(groupKey, windows)

  if current ~= window then
    group.logicalWindow = self:_extractLogicalLayout(current)

    self:_restoreOriginalLayout(current)
    current._groupHidden = true

    self:_applyLogicalLayout(window, group.logicalWindow)
    window._groupHidden = false
  end

  group.activeSourceWindowId = window._id
  group.activeIndex = targetIndex

  local wm = self.app and self.app.wm
  if wm and wm.setFocus then
    wm:setFocus(window)
  end

  return true
end

return M
