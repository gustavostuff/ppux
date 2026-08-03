local Button = require("user_interface.button")
local ModalPanelUtils = require("user_interface.modals.panel_modal_utils")
local Panel = require("user_interface.panel")
local TextField = require("user_interface.text_field")
local colors = require("app_colors")
local images = require("images")
local TU = require("utils.text_utils")

local Dialog = {}
Dialog.__index = Dialog

local MODAL_COLS = 3
local FILE_COLS = 3
local VISIBLE_FILE_ROWS = 8
local VISIBLE_FILE_SLOTS = FILE_COLS * VISIBLE_FILE_ROWS
local SCROLLBAR_W = 4

local function isWindows()
  return package.config:sub(1, 1) == "\\"
end

local function trim(text)
  return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function detectWorkingDirectory()
  -- Prefer LÖVE / Win32 APIs so Windows never shells out (io.popen flashes a console).
  local FilesystemPath = require("utils.filesystem_path")
  local dir = FilesystemPath.getWorkingDirectory()
  if type(dir) == "string" and trim(dir) ~= "" then
    return dir
  end
  if isWindows() then
    local okWin, WinFs = pcall(require, "utils.win_fs")
    if okWin and WinFs and WinFs.getCurrentDirectory then
      dir = WinFs.getCurrentDirectory()
      if type(dir) == "string" and trim(dir) ~= "" then
        return dir
      end
    end
    return "."
  end
  local handle = io.popen("pwd")
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

local function detectHomeDirectory()
  if isWindows() then
    local profile = trim(os.getenv("USERPROFILE") or "")
    if profile ~= "" then
      return profile
    end
    local homeDrive = trim(os.getenv("HOMEDRIVE") or "")
    local homePath = trim(os.getenv("HOMEPATH") or "")
    if homeDrive ~= "" and homePath ~= "" then
      return homeDrive .. homePath
    end
    return nil
  end

  local home = trim(os.getenv("HOME") or "")
  if home ~= "" then
    return home
  end
  return nil
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

local function fileAllowedByExt(name, allowedExt)
  if type(allowedExt) ~= "table" then
    return false
  end
  local ext = fileExt(name)
  return allowedExt[ext] == true
end

local function isHiddenName(name)
  name = tostring(name or "")
  return name:sub(1, 1) == "."
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

local function listEntriesPosix(dir, showHidden, allowedExt)
  local command = string.format("ls -1Ap %s 2>/dev/null", shellQuotePosix(dir))
  local lines = readCommandLines(command)
  local entries = {}
  for _, raw in ipairs(lines) do
    if raw ~= "" and raw ~= "." and raw ~= ".." then
      local isDir = raw:sub(-1) == "/"
      local name = isDir and raw:sub(1, -2) or raw
      if (showHidden or (not isHiddenName(name))) and (isDir or fileAllowedByExt(name, allowedExt)) then
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

local function listEntriesWindowsViaCmd(dir, showHidden, allowedExt)
  -- Fallback only: io.popen briefly flashes a console on Windows.
  local quoted = shellQuoteWindows(dir)
  local dirLines = readCommandLines(string.format("cmd /d /c dir /b /ad %s 2>nul", quoted))
  local fileLines = readCommandLines(string.format("cmd /d /c dir /b /a-d %s 2>nul", quoted))
  local entries = {}
  for _, name in ipairs(dirLines) do
    if name ~= "" and name ~= "." and name ~= ".." then
      if showHidden or (not isHiddenName(name)) then
        entries[#entries + 1] = {
          name = name,
          path = pathJoin(dir, name),
          isDir = true,
        }
      end
    end
  end
  for _, name in ipairs(fileLines) do
    if name ~= "" and fileAllowedByExt(name, allowedExt) and (showHidden or (not isHiddenName(name))) then
      entries[#entries + 1] = {
        name = name,
        path = pathJoin(dir, name),
        isDir = false,
      }
    end
  end
  return sortedEntries(entries)
end

local function listEntriesWindows(dir, showHidden, allowedExt)
  local okWin, WinFs = pcall(require, "utils.win_fs")
  local listed = okWin and WinFs and WinFs.listDirectory and WinFs.listDirectory(dir) or nil
  if type(listed) ~= "table" then
    return listEntriesWindowsViaCmd(dir, showHidden, allowedExt)
  end

  local entries = {}
  for _, item in ipairs(listed) do
    local name = item and item.name
    if type(name) == "string" and name ~= "" and name ~= "." and name ~= ".." then
      local isDir = item.isDir == true
      if showHidden or (not isHiddenName(name)) then
        if isDir or fileAllowedByExt(name, allowedExt) then
          entries[#entries + 1] = {
            name = name,
            path = pathJoin(dir, name),
            isDir = isDir,
          }
        end
      end
    end
  end
  return sortedEntries(entries)
end

local function listEntries(dir, showHidden, allowedExt)
  if isWindows() then
    return listEntriesWindows(dir, showHidden, allowedExt)
  end
  return listEntriesPosix(dir, showHidden, allowedExt)
end

local function makeClippedFileButton(slotAction)
  local button = Button.new({
    text = "",
    h = ModalPanelUtils.MODAL_BUTTON_H,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    enabled = false,
    action = slotAction,
    iconTintColor = colors.white,
    iconRespectTheme = false,
    skipModalControlOutline = true,
  })

  function button:draw()
    local sx, sy, sw, sh = love.graphics.getScissor()
    love.graphics.setScissor(math.floor(self.x), math.floor(self.y), math.floor(self.w), math.floor(self.h))
    Button.draw(self)
    love.graphics.setScissor(sx, sy, sw, sh)
  end

  return button
end

local function rebuildPanel(self)
  local leftInset = math.floor((self.cellH or 0) / 2)
  self.parentButton.contentPaddingX = leftInset
  self.homeButton.contentPaddingX = leftInset
  if self.confirmButton then
    self.confirmButton.contentPaddingX = leftInset
    self.confirmButton.text = self._confirmLabel or "Use this folder"
    self.confirmButton.hidden = self._directoriesOnly ~= true
  end
  for i = 1, VISIBLE_FILE_SLOTS do
    self.fileButtons[i].contentPaddingX = leftInset
  end

  local nameRow = nil
  local footerRow = 1 + 1 + VISIBLE_FILE_ROWS + 1
  if self._directoriesOnly == true then
    nameRow = footerRow
    footerRow = footerRow + 1
  end
  local rows = footerRow

  self.panel = Panel.new({
    cols = MODAL_COLS,
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
    _modalChromeOverBlue = self._modalChromeOverBlue == true,
  })

  self.panel:setCell(1, 1, { component = self.parentButton })
  self.panel:setCell(2, 1, { component = self.homeButton })
  self.panel:setCell(3, 1, { text = "" })

  self.panel:setCell(1, 2, {
    component = self.pathLabelComponent,
    colspan = MODAL_COLS,
  })

  for row = 1, VISIBLE_FILE_ROWS do
    for col = 1, FILE_COLS do
      local slot = ((row - 1) * FILE_COLS) + col
      self.panel:setCell(col, row + 2, {
        component = self.fileButtons[slot],
      })
    end
  end

  if nameRow and self.nameField then
    self.panel:setCell(1, nameRow, {
      text = "Name:",
      preserveTrailingColon = true,
    })
    self.panel:setCell(2, nameRow, {
      component = self.nameField,
      colspan = 2,
    })
  end

  if self._directoriesOnly == true and self.confirmButton then
    self.panel:setCell(1, footerRow, {
      text = "Esc) Close",
      colspan = 2,
    })
    self.panel:setCell(3, footerRow, {
      component = self.confirmButton,
      colspan = 1,
    })
  else
    self.panel:setCell(1, footerRow, {
      text = "Esc) Close",
      colspan = MODAL_COLS,
    })
  end
end

local PRESETS = {
  project = {
    allowedExt = { lua = true, ppux = true, nes = true },
    defaultTitle = "Open Project",
  },
  png = {
    allowedExt = { png = true },
    defaultTitle = "Open PNG image",
  },
  -- Browse folders only; confirm current directory (used for no-ROM project save).
  saveProjectFolder = {
    allowedExt = {},
    directoriesOnly = true,
    defaultTitle = "Save Project Folder",
    confirmLabel = "Save here",
  },
}

function Dialog.new(config)
  config = config or PRESETS.project
  local allowedExt = config.allowedExt or PRESETS.project.allowedExt
  local self = setmetatable({
    _allowedExt = allowedExt,
    _directoriesOnly = config.directoriesOnly == true,
    _defaultTitle = config.defaultTitle or "Open file",
    _confirmLabel = config.confirmLabel or "Use this folder",
    visible = false,
    title = config.defaultTitle or "Open file",
    onOpen = nil,
    onCancel = nil,
    onDirectoryChanged = nil,
    showHidden = false,
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
    icon = images.icons.chrome.icon_up,
    text = "Parent",
    h = ModalPanelUtils.MODAL_BUTTON_H,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    -- Themed chrome ink for icon + label (no iconTintColor).
    iconRespectTheme = false,
    action = function()
      self:_goUp()
    end,
  })
  self.homeButton = Button.new({
    icon = images.icons.actions.icon_folder,
    text = "Home",
    h = ModalPanelUtils.MODAL_BUTTON_H,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    -- Folder glyph: theme chrome ink (no iconTintColor).
    iconRespectTheme = false,
    action = function()
      self:_goHome()
    end,
  })

  self.confirmButton = Button.new({
    text = self._confirmLabel,
    h = ModalPanelUtils.MODAL_BUTTON_H,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    iconRespectTheme = false,
    action = function()
      self:_confirmCurrentDirectory()
    end,
  })

  self.nameField = TextField.new({
    width = 220,
    height = ModalPanelUtils.MODAL_BUTTON_H,
  })

  self.fileButtons = {}
  for i = 1, VISIBLE_FILE_SLOTS do
    local idx = i
    self.fileButtons[i] = makeClippedFileButton(function()
      self:_activateVisibleSlot(idx)
    end)
  end

  self.pathLabelComponent = {
    draw = function(component)
      local font = love.graphics.getFont()
      local fh = font and font:getHeight() or 0
      local padX = math.floor(component.h / 2)
      local textY = component.y + math.floor((component.h - fh) / 2)
      local chromeWhite = self.panel and self.panel._modalChromeOverBlue == true
      local c = chromeWhite and colors:chromeTextIconsColorNonFocused() or (colors.textPrimary or colors.white)
      love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
      TU.drawScrollingText(
        self.currentDir or "",
        math.floor(component.x + padX),
        math.floor(textY),
        math.max(0, component.w - padX * 2),
        {}
      )
    end,
  }

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
  local totalRows = math.ceil((#(self.entries or {})) / FILE_COLS)
  return math.max(0, totalRows - VISIBLE_FILE_ROWS)
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
  local home = normalizePath(detectHomeDirectory() or "")
  self.homeButton.enabled = home ~= "" and home ~= self.currentDir
end

function Dialog:_refreshFileButtons()
  for i = 1, VISIBLE_FILE_SLOTS do
    local row = math.floor((i - 1) / FILE_COLS)
    local col = (i - 1) % FILE_COLS
    local entryIndex = ((self.scrollOffset or 0) + row) * FILE_COLS + col + 1
    local entry = self.entries and self.entries[entryIndex] or nil
    local button = self.fileButtons[i]
    if entry then
      if entry.isDir then
        button.icon = images.icons.actions.icon_folder
        button.text = tostring(entry.name or "") .. "/"
        -- Folder: match themed label ink (modal applies chrome colors). Files keep white glyph tint.
        button.iconTintColor = nil
      else
        local ext = fileExt(entry.name)
        local types = images.icons.image_types
        local windowIcons = images.windows_icons or images.animated_icons or {}
        if ext == "nes" then
          button.icon = windowIcons.icon_nes_rom or (images.icons.actions and images.icons.actions.icon_project)
        elseif ext == "png" then
          button.icon = types and types.icon_png or nil
        elseif ext == "jpg" or ext == "jpeg" then
          button.icon = types and types.icon_jpg or nil
        elseif ext == "bmp" then
          button.icon = types and types.icon_bpm or nil
        else
          button.icon = images.icons.actions.icon_project
        end
        button.text = tostring(entry.name or "")
        button.iconTintColor = colors.white
      end
      button.tooltip = tostring(entry.path or "")
      button.enabled = true
    else
      button.icon = nil
      button.text = ""
      button.tooltip = ""
      button.enabled = false
      button.iconTintColor = colors.white
    end
    button.pressed = false
    button.hovered = false
  end
end

function Dialog:_loadEntries(dir)
  local allowed = self._allowedExt
  if self._directoriesOnly == true then
    allowed = {}
  elseif type(allowed) ~= "table" then
    allowed = PRESETS.project.allowedExt
  end
  local entries = listEntries(dir, self.showHidden == true, allowed)
  if self._directoriesOnly == true then
    local dirsOnly = {}
    for _, entry in ipairs(entries) do
      if entry and entry.isDir then
        dirsOnly[#dirsOnly + 1] = entry
      end
    end
    self.entries = dirsOnly
  else
    self.entries = entries
  end
end

function Dialog:_sanitizeProjectName(raw)
  local name = trim(raw)
  if name == "" then
    return nil
  end
  -- Filename only: drop path separators and trailing extensions.
  name = name:gsub("[/\\]", "")
  name = name:gsub("%.lua$", ""):gsub("%.ppux$", ""):gsub("%.nes$", "")
  name = trim(name)
  if name == "" or name == "." or name == ".." then
    return nil
  end
  return name
end

function Dialog:getProjectName()
  if not self.nameField then
    return nil
  end
  return self:_sanitizeProjectName(self.nameField:getText())
end

function Dialog:_confirmCurrentDirectory()
  if self._directoriesOnly ~= true then
    return false
  end
  local dir = self.currentDir
  if type(dir) ~= "string" or trim(dir) == "" then
    return false
  end
  local projectName = self:getProjectName()
  if not projectName then
    if self.nameField then
      self.nameField:setFocused(true)
    end
    return false
  end
  local cb = self.onOpen
  self:hide()
  if cb then
    cb(dir, {
      name = projectName,
      path = dir,
      isDir = true,
      projectName = projectName,
    })
  end
  return true
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

function Dialog:_goHome()
  local home = detectHomeDirectory()
  if type(home) ~= "string" or trim(home) == "" then
    return false
  end
  self:_setDirectory(home)
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
    local row = math.floor((i - 1) / FILE_COLS)
    local col = (i - 1) % FILE_COLS
    local idx = ((self.scrollOffset or 0) + row) * FILE_COLS + col + 1
    visible[i] = self.entries and self.entries[idx] or nil
  end
  return visible
end

function Dialog:show(opts)
  opts = opts or {}
  if type(opts.allowedExt) == "table" then
    self._allowedExt = opts.allowedExt
  end
  if opts.directoriesOnly ~= nil then
    self._directoriesOnly = opts.directoriesOnly == true
  end
  if type(opts.confirmLabel) == "string" and opts.confirmLabel ~= "" then
    self._confirmLabel = opts.confirmLabel
  end
  self.title = opts.title or self._defaultTitle or "Open file"
  self.onOpen = opts.onOpen
  self.onCancel = opts.onCancel
  self.onDirectoryChanged = opts.onDirectoryChanged
  self.showHidden = opts.showHidden == true
  self.visible = true
  rebuildPanel(self)

  if self._directoriesOnly == true and self.nameField then
    local initialName = opts.initialProjectName
    if type(initialName) ~= "string" or trim(initialName) == "" then
      initialName = "untitled"
    end
    self.nameField:setText(self:_sanitizeProjectName(initialName) or "untitled")
    self.nameField:setFocused(true)
  elseif self.nameField then
    self.nameField:setFocused(false)
  end

  local initialDir = normalizePath(opts.initialDir or self.currentDir or ".")
  self:_setDirectory(initialDir)
  return true
end

function Dialog:hide()
  self.visible = false
  self.onOpen = nil
  self.onCancel = nil
  self.onDirectoryChanged = nil
  if self.nameField then
    self.nameField:setFocused(false)
  end
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
  if self._directoriesOnly == true and self.nameField and self.nameField.focused then
    if key == "return" or key == "kpenter" then
      self:_confirmCurrentDirectory()
      return true
    end
    if self.nameField:onKeyPressed(key) then
      return true
    end
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
    self:_scrollBy(-VISIBLE_FILE_ROWS)
    return true
  end
  if key == "pagedown" then
    self:_scrollBy(VISIBLE_FILE_ROWS)
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
    if self._directoriesOnly == true then
      self:_confirmCurrentDirectory()
    else
      self:_activateVisibleSlot(1)
    end
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  if self._directoriesOnly == true and self.nameField then
    return self.nameField:onTextInput(text)
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
  if self._directoriesOnly == true and self.nameField then
    local fieldFocused = self.nameField:contains(x, y)
    self.nameField:setFocused(fieldFocused)
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
  local totalRows = math.ceil(total / FILE_COLS)
  if totalRows <= VISIBLE_FILE_ROWS then
    return
  end
  local firstCell = self.panel:getCell(1, 3)
  local lastCell = self.panel:getCell(1, 2 + VISIBLE_FILE_ROWS)
  if not firstCell or not lastCell then
    return
  end
  local trackTop = firstCell.y
  local trackBottom = lastCell.y + lastCell.h
  local trackH = math.max(1, trackBottom - trackTop)
  local thirdCell = self.panel:getCell(MODAL_COLS, 3) or firstCell
  local trackX = thirdCell.x + thirdCell.w - SCROLLBAR_W - 1
  local maxOffset = self:_maxScrollOffset()
  local visibleFrac = VISIBLE_FILE_ROWS / math.max(1, totalRows)
  local thumbH = math.max(1, math.floor(trackH * visibleFrac))
  local offsetFrac = (maxOffset > 0) and ((self.scrollOffset or 0) / maxOffset) or 0
  local thumbY = math.floor(trackTop + ((trackH - thumbH) * offsetFrac))

  local chrome = self.panel and self.panel._modalChromeOverBlue == true
  local c = chrome and colors:chromeTextIconsColorNonFocused() or colors.white
  love.graphics.setColor(c[1], c[2], c[3], 1)
  love.graphics.rectangle("fill", trackX, thumbY, SCROLLBAR_W, thumbH)
  love.graphics.setColor(colors.white)
end

local M = {}
M.presets = PRESETS

function M.new(configOrPresetKey)
  local cfg = configOrPresetKey
  if type(cfg) == "string" then
    cfg = PRESETS[cfg] or PRESETS.project
  elseif type(cfg) ~= "table" then
    cfg = PRESETS.project
  end
  return Dialog.new(cfg)
end

return M
