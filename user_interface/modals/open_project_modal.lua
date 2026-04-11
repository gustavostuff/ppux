local Button = require("user_interface.button")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")
local Panel = require("user_interface.panel")
local colors = require("app_colors")
local images = require("images")

local Dialog = {}
Dialog.__index = Dialog

local VISIBLE_FILE_SLOTS = 8
local SCROLLBAR_W = 4

local function isWindows()
  return package.config:sub(1, 1) == "\\"
end

local function trim(text)
  return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function detectWorkingDirectory()
  local command = isWindows() and "cd" or "pwd"
  local handle = io.popen(command)
  if not handle then
    return "."
  end
  local line = handle:read("*l")
  handle:close()
  line = trim((line or ""):gsub("\r", ""))
  if line == "" then
    return "."
  end
  return line
end

local function normalizePath(path)
  path = trim(path)
  if path == "" or path == "." then
    path = detectWorkingDirectory()
  end
  local sep = isWindows() and "\\" or "/"
  path = path:gsub("[/\\]", sep)
  if path == sep then
    return path
  end
  if path:match("^%a:[\\/]?$") then
    return path:sub(1, 2) .. sep
  end
  path = path:gsub("[/\\]+$", "")
  if path == "" then
    return sep
  end
  return path
end

local function pathJoin(dir, name)
  local sep = isWindows() and "\\" or "/"
  dir = normalizePath(dir)
  if dir == sep then
    return dir .. tostring(name or "")
  end
  if dir:sub(-1) == sep then
    return dir .. tostring(name or "")
  end
  return dir .. sep .. tostring(name or "")
end

local function pathParent(path)
  local sep = isWindows() and "\\" or "/"
  path = normalizePath(path)
  if path == sep then
    return nil
  end
  if isWindows() and path:match("^%a:[\\/]?$") then
    return nil
  end
  local normalized = path:gsub("[/\\]+$", "")
  local parent = normalized:match("^(.*)[/\\][^/\\]+$")
  if not parent or parent == "" then
    if isWindows() then
      local drive = normalized:match("^(%a:)")
      if drive then
        return drive .. "\\"
      end
    end
    return sep
  end
  return normalizePath(parent)
end

local function fileExt(name)
  local ext = tostring(name or ""):match("%.([^%.\\/]+)$")
  return ext and ext:lower() or ""
end

local function isProjectFileName(name)
  local ext = fileExt(name)
  return ext == "lua" or ext == "ppux"
end

local function shellQuotePosix(path)
  return "'" .. tostring(path or ""):gsub("'", "'\\''") .. "'"
end

local function shellQuoteWindows(path)
  local escaped = tostring(path or ""):gsub('"', '\\"')
  return '"' .. escaped .. '"'
end

local function readCommandLines(command)
  local handle = io.popen(command)
  if not handle then
    return {}
  end
  local lines = {}
  for line in handle:lines() do
    lines[#lines + 1] = trim(line:gsub("\r", ""))
  end
  handle:close()
  return lines
end

local function sortedEntries(entries)
  table.sort(entries, function(a, b)
    if a.isDir ~= b.isDir then
      return a.isDir == true
    end
    local an = tostring(a.name or ""):lower()
    local bn = tostring(b.name or ""):lower()
    if an == bn then
      return tostring(a.name or "") < tostring(b.name or "")
    end
    return an < bn
  end)
  return entries
end

local function listEntriesPosix(dir)
  local command = string.format("ls -1Ap %s 2>/dev/null", shellQuotePosix(dir))
  local lines = readCommandLines(command)
  local entries = {}
  for _, raw in ipairs(lines) do
    if raw ~= "" and raw ~= "." and raw ~= ".." then
      local isDir = raw:sub(-1) == "/"
      local name = isDir and raw:sub(1, -2) or raw
      if isDir or isProjectFileName(name) then
        entries[#entries + 1] = {
          name = name,
          path = pathJoin(dir, name),
          isDir = isDir,
        }
      end
    end
  end
  return sortedEntries(entries)
end

local function listEntriesWindows(dir)
  local quoted = shellQuoteWindows(dir)
  local dirLines = readCommandLines(string.format("cmd /d /c dir /b /ad %s 2>nul", quoted))
  local fileLines = readCommandLines(string.format("cmd /d /c dir /b /a-d %s 2>nul", quoted))
  local entries = {}
  for _, name in ipairs(dirLines) do
    if name ~= "" and name ~= "." and name ~= ".." then
      entries[#entries + 1] = {
        name = name,
        path = pathJoin(dir, name),
        isDir = true,
      }
    end
  end
  for _, name in ipairs(fileLines) do
    if name ~= "" and isProjectFileName(name) then
      entries[#entries + 1] = {
        name = name,
        path = pathJoin(dir, name),
        isDir = false,
      }
    end
  end
  return sortedEntries(entries)
end

local function listEntries(dir)
  if isWindows() then
    return listEntriesWindows(dir)
  end
  return listEntriesPosix(dir)
end

local function rebuildPanel(self)
  local leftInset = math.floor((self.cellH or 0) / 2)
  self.parentButton.contentPaddingX = leftInset
  for i = 1, VISIBLE_FILE_SLOTS do
    self.fileButtons[i].contentPaddingX = leftInset
  end

  local rows = 1 + VISIBLE_FILE_SLOTS + 1
  self.panel = Panel.new({
    cols = 4,
    rows = rows,
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
  })

  self.panel:setCell(1, 1, { component = self.parentButton, colspan = 2 })
  self.panel:setCell(3, 1, { text = "" })
  self.panel:setCell(4, 1, { text = "" })

  for i = 1, VISIBLE_FILE_SLOTS do
    self.panel:setCell(1, i + 1, {
      component = self.fileButtons[i],
      colspan = 4,
    })
  end

  self.panel:setCell(1, rows, {
    text = "Esc) Close",
    colspan = 4,
  })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Open Project",
    onOpen = nil,
    onCancel = nil,
    onDirectoryChanged = nil,
    currentDir = ".",
    entries = {},
    scrollOffset = 0,
    padding = nil,
    colGap = nil,
    rowGap = nil,
    cellW = nil,
    cellH = nil,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    panel = nil,
    _boxX = nil,
    _boxY = nil,
    _boxW = nil,
    _boxH = nil,
  }, Dialog)

  self.parentButton = Button.new({
    icon = images.icons.icon_up,
    text = "Parent",
    h = ModalPanelUtils.MODAL_BUTTON_H,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    action = function()
      self:_goUp()
    end,
  })

  self.fileButtons = {}
  for i = 1, VISIBLE_FILE_SLOTS do
    local idx = i
    self.fileButtons[i] = Button.new({
      text = "",
      h = ModalPanelUtils.MODAL_BUTTON_H,
      transparent = true,
      textAlign = "left",
      contentPaddingX = 4,
      enabled = false,
      action = function()
        self:_activateVisibleSlot(idx)
      end,
    })
  end

  ModalPanelUtils.applyPanelDefaults(self)
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible == true
end

function Dialog:_containsBox(x, y)
  if self.panel and self._boxX then
    return self.panel:contains(x, y)
  end
  return true
end

function Dialog:_maxScrollOffset()
  return math.max(0, #(self.entries or {}) - VISIBLE_FILE_SLOTS)
end

function Dialog:_setScrollOffset(offset)
  local maxOffset = self:_maxScrollOffset()
  offset = math.max(0, math.min(maxOffset, math.floor(tonumber(offset) or 0)))
  self.scrollOffset = offset
  self:_refreshFileButtons()
  return self.scrollOffset
end

function Dialog:_scrollBy(delta)
  delta = math.floor(tonumber(delta) or 0)
  if delta == 0 then
    return false
  end
  local before = self.scrollOffset
  self:_setScrollOffset(before + delta)
  return self.scrollOffset ~= before
end

function Dialog:_refreshNavButtons()
  local parent = pathParent(self.currentDir)
  self.parentButton.enabled = parent ~= nil and parent ~= self.currentDir
end

function Dialog:_refreshFileButtons()
  for i = 1, VISIBLE_FILE_SLOTS do
    local entryIndex = (self.scrollOffset or 0) + i
    local entry = self.entries and self.entries[entryIndex] or nil
    local button = self.fileButtons[i]
    if entry then
      if entry.isDir then
        button.icon = images.icons.icon_folder
        button.text = tostring(entry.name or "") .. "/"
      else
        button.icon = images.icons.icon_project
        button.text = tostring(entry.name or "")
      end
      button.tooltip = tostring(entry.path or "")
      button.enabled = true
    else
      button.icon = nil
      button.text = ""
      button.tooltip = ""
      button.enabled = false
    end
    button.pressed = false
    button.hovered = false
  end
end

function Dialog:_loadEntries(dir)
  self.entries = listEntries(dir)
end

function Dialog:_setDirectory(dir)
  local normalized = normalizePath(dir)
  if normalized == "" then
    normalized = "."
  end
  self.currentDir = normalized
  self:_loadEntries(normalized)
  self.scrollOffset = 0
  self:_refreshNavButtons()
  self:_refreshFileButtons()
  if self.onDirectoryChanged then
    self.onDirectoryChanged(normalized)
  end
end

function Dialog:_goUp()
  local parent = pathParent(self.currentDir)
  if not parent then
    return false
  end
  self:_setDirectory(parent)
  return true
end

function Dialog:_activateVisibleSlot(slotIndex)
  local absoluteIndex = (self.scrollOffset or 0) + tonumber(slotIndex or 0)
  local entry = self.entries and self.entries[absoluteIndex] or nil
  if not entry then
    return false
  end
  if entry.isDir then
    self:_setDirectory(entry.path)
    return true
  end
  if self.onOpen then
    self.onOpen(entry.path, entry)
  end
  self:hide()
  return true
end

function Dialog:getCurrentDir()
  return self.currentDir
end

function Dialog:getEntries()
  return self.entries
end

function Dialog:getVisibleEntries()
  local visible = {}
  for i = 1, VISIBLE_FILE_SLOTS do
    local idx = (self.scrollOffset or 0) + i
    visible[i] = self.entries and self.entries[idx] or nil
  end
  return visible
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Open Project"
  self.onOpen = opts.onOpen
  self.onCancel = opts.onCancel
  self.onDirectoryChanged = opts.onDirectoryChanged
  self.visible = true
  rebuildPanel(self)

  local initialDir = normalizePath(opts.initialDir or self.currentDir or ".")
  self:_setDirectory(initialDir)
  return true
end

function Dialog:hide()
  self.visible = false
  self.onOpen = nil
  self.onCancel = nil
  self.onDirectoryChanged = nil
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:_cancel()
  local cb = self.onCancel
  self:hide()
  if cb then
    cb()
  end
  return true
end

function Dialog:getTooltipAt(x, y)
  if not self.visible or not self.panel or not self:_containsBox(x, y) then
    return nil
  end
  return self.panel:getTooltipAt(x, y)
end

function Dialog:handleKey(key)
  if not self.visible then return false end
  if key == "escape" then
    self:_cancel()
    return true
  end
  if key == "backspace" then
    self:_goUp()
    return true
  end
  if key == "up" then
    self:_scrollBy(-1)
    return true
  end
  if key == "down" then
    self:_scrollBy(1)
    return true
  end
  if key == "pageup" then
    self:_scrollBy(-VISIBLE_FILE_SLOTS)
    return true
  end
  if key == "pagedown" then
    self:_scrollBy(VISIBLE_FILE_SLOTS)
    return true
  end
  if key == "home" then
    self:_setScrollOffset(0)
    return true
  end
  if key == "end" then
    self:_setScrollOffset(self:_maxScrollOffset())
    return true
  end
  if key == "return" or key == "kpenter" then
    self:_activateVisibleSlot(1)
    return true
  end
  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return false end
  if not self:_containsBox(x, y) then
    self:_cancel()
    return true
  end
  return self.panel and self.panel:mousepressed(x, y, button) or false
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  return self.panel and self.panel:mousereleased(x, y, button) or true
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end
  if self.panel then
    self.panel:mousemoved(x, y)
  end
  return true
end

function Dialog:wheelmoved(_, dy)
  if not self.visible then return false end
  if dy > 0 then
    self:_scrollBy(-1)
    return true
  end
  if dy < 0 then
    self:_scrollBy(1)
    return true
  end
  return false
end

function Dialog:draw(canvas)
  if not self.visible then return end
  ModalPanelUtils.drawBackdrop(canvas)
  self.panel:setVisible(true)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self.panel:draw()
  self:_drawScrollIndicator()
end

function Dialog:_drawScrollIndicator()
  if not self.panel then
    return
  end
  local total = #(self.entries or {})
  if total <= VISIBLE_FILE_SLOTS then
    return
  end
  local firstCell = self.panel:getCell(1, 2)
  local lastCell = self.panel:getCell(1, 1 + VISIBLE_FILE_SLOTS)
  if not firstCell or not lastCell then
    return
  end
  local trackTop = firstCell.y
  local trackBottom = lastCell.y + lastCell.h
  local trackH = math.max(1, trackBottom - trackTop)
  local trackX = firstCell.x + firstCell.w - SCROLLBAR_W - 1
  local maxOffset = self:_maxScrollOffset()
  local visibleFrac = VISIBLE_FILE_SLOTS / total
  local thumbH = math.max(1, math.floor(trackH * visibleFrac))
  local offsetFrac = (maxOffset > 0) and ((self.scrollOffset or 0) / maxOffset) or 0
  local thumbY = math.floor(trackTop + ((trackH - thumbH) * offsetFrac))

  local c = colors.white
  love.graphics.setColor(c[1], c[2], c[3], 1)
  love.graphics.rectangle("fill", trackX, thumbY, SCROLLBAR_W, thumbH)
  love.graphics.setColor(colors.white)
end

return Dialog
