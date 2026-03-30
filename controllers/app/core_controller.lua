local WindowController = require("controllers.window.window_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local BrushController = require("controllers.input_support.brush_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

local GenericActionsModal = require("user_interface.modals.generic_actions_modal")
local NewWindowModal = require("user_interface.modals.new_window_modal")
local RenameWindowModal = require("user_interface.modals.rename_window_modal")
local RomPaletteAddressModal = require("user_interface.modals.rom_palette_address_modal")
local SaveOptionsModal = require("user_interface.modals.save_options_modal")
local QuitConfirmModal = require("user_interface.modals.quit_confirm_modal")
local SettingsModal = require("user_interface.modals.settings_modal")
local SimpleLoadingScreen = require("controllers.app.simple_loading_screen")
local TooltipController = require("controllers.ui.tooltip_controller")
local ContextualMenuController = require("controllers.ui.contextual_menu_controller")
local UserInput = require("controllers.input")

local AppCoreController = {}
AppCoreController.__index = AppCoreController

local function anyModalVisible(app)
  return (app.quitConfirmModal and app.quitConfirmModal:isVisible())
    or (app.saveOptionsModal and app.saveOptionsModal:isVisible())
    or (app.genericActionsModal and app.genericActionsModal:isVisible())
    or (app.settingsModal and app.settingsModal:isVisible())
    or (app.newWindowModal and app.newWindowModal:isVisible())
    or (app.renameWindowModal and app.renameWindowModal:isVisible())
    or (app.romPaletteAddressModal and app.romPaletteAddressModal:isVisible())
end

local function getTopWindowTooltipCandidate(app, x, y)
  if not (app and app.wm and app.wm.getWindows) then return nil end

  local windows = app.wm:getWindows() or {}
  for i = #windows, 1, -1 do
    local w = windows[i]
    if w and not w._closed and not w._minimized then
      if not w._collapsed and w.specializedToolbar and w.specializedToolbar.contains then
        if w.specializedToolbar:contains(x, y) then
          if w.specializedToolbar.getTooltipAt then
            return w.specializedToolbar:getTooltipAt(x, y)
          end
          return nil
        end
      end

      if w.headerToolbar and w.headerToolbar.contains then
        if w.headerToolbar:contains(x, y) then
          if w.headerToolbar.getTooltipAt then
            return w.headerToolbar:getTooltipAt(x, y)
          end
          return nil
        end
      end

      if w.contains and w:contains(x, y) then
        return nil
      end
    end
  end

  return nil
end

local function getTopModalTooltipCandidate(app, x, y)
  local modals = {
    app.quitConfirmModal,
    app.saveOptionsModal,
    app.genericActionsModal,
    app.settingsModal,
    app.newWindowModal,
    app.renameWindowModal,
    app.romPaletteAddressModal,
  }

  for _, modal in ipairs(modals) do
    if modal and modal.isVisible and modal:isVisible() and modal.getTooltipAt then
      local candidate = modal:getTooltipAt(x, y)
      if candidate then
        return candidate
      end
    end
  end

  return nil
end

function AppCoreController.new()
  local self = setmetatable({}, AppCoreController)

  -- app state
  self.statusText = "Drop an .nes ROM with CHR data"
  self.lastEventText = self.statusText
  self.mode = "tile"
  self.isPainting = false
  self.currentColor = 1
  self.brushSize = 1
  self.editTool = "pencil"
  self.syncDuplicateTiles = false
  self.spaceHighlightActive = false
  self.showDebugInfo = false

  -- rom state
  self.appEditState = {
    romRaw = nil,
    romOriginalPath = nil,
    meta = nil,
    chrBanksBytes = nil,
    originalChrBanksBytes = nil,
    currentBank = 1,
    romPatches = nil,
    romSha1 = nil,
    tilesPool = {},
    chrBacking = nil,
  }

  -- edits
  self.edits = nil
  self.projectPath = nil
  self.encodedProjectPath = nil
  self.recentProjects = {}

  -- windows + manager
  self.wm = WindowController.new()
  self.winBank = nil

  self.genericActionsModal = GenericActionsModal.new()
  self.newWindowModal = NewWindowModal.new()
  self.renameWindowModal = RenameWindowModal.new()
  self.romPaletteAddressModal = RomPaletteAddressModal.new()
  self.saveOptionsModal = SaveOptionsModal.new()
  self.quitConfirmModal = QuitConfirmModal.new()
  self.settingsModal = SettingsModal.new()
  self.taskbar = nil
  self.windowHeaderContextMenu = ContextualMenuController.new({
    getBounds = function()
      local canvas = self.canvas
      return {
        w = canvas and canvas.getWidth and canvas:getWidth() or 0,
        h = canvas and canvas.getHeight and canvas:getHeight() or 0,
      }
    end,
    cellH = 15,
    padding = 0,
    colGap = 0,
    rowGap = 1,
    splitIconCell = false,
  })
  self.emptySpaceContextMenu = ContextualMenuController.new({
    getBounds = function()
      local canvas = self.canvas
      return {
        w = canvas and canvas.getWidth and canvas:getWidth() or 0,
        h = canvas and canvas.getHeight and canvas:getHeight() or 0,
      }
    end,
    cellH = 15,
    padding = 0,
    colGap = 0,
    rowGap = 1,
    splitIconCell = false,
  })
  self.tooltipsEnabled = true
  self.tooltipController = TooltipController.new({
    delaySeconds = 0.7,
  })
  self.toastController = nil
  self.splash = nil
  self._allowImmediateQuit = false
  self.unsavedChanges = false
  self.unsavedEvents = {}
  self.unsavedEventTypes = {
    pixel_edit = true,
    tile_move = true,
    sprite_move = true,
    palette_color_change = true,
    sprite_remove = true,
    window_close = true,
  }

  -- undo/redo
  self.undoRedo = UndoRedoController.new(50)
  self.undoRedo:setUnsavedTracker(function(eventType)
    self:markUnsaved(eventType)
  end)

  -- rendering
  self.canvas = nil
  self.font = nil
  self.emptyStateFont = nil
  self._windowSnapshot = nil
  self._windowSnapshotTimer = 0
  self.chrBankCanvasController = nil

  return self
end

function AppCoreController:hideAppContextMenus()
  if self.windowHeaderContextMenu then
    self.windowHeaderContextMenu:hide()
  end
  if self.emptySpaceContextMenu then
    self.emptySpaceContextMenu:hide()
  end
end

function AppCoreController:_hideAllContextMenus()
  self:hideAppContextMenus()
  if self.taskbar and self.taskbar.menuController then
    self.taskbar.menuController:hide()
  end
end

function AppCoreController:_buildNewWindowOptions()
  return {
    {
      text = "Static Art window (tiles)",
      callback = function(cols, rows, _, windowTitle)
        local win = self.wm:createTileWindow({
          animated = false,
          title    = windowTitle or "Static Art (tiles)",
          cols     = cols,
          rows     = rows,
        })
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "Static Art window (sprites)",
      callback = function(cols, rows, spriteMode, windowTitle)
        local win = self.wm:createSpriteWindow({
          animated = false,
          title = windowTitle or "Static Art (sprites)",
          spriteMode = spriteMode,
          cols = cols,
          rows = rows,
        })
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "Animation window  (tiles)",
      callback = function(cols, rows, _, windowTitle)
        local win = self.wm:createTileWindow({
          animated = true,
          title = windowTitle or "Animation (tiles)",
          numFrames = 3,
          cols = cols,
          rows = rows,
        })
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "Animation window  (sprites)",
      callback = function(cols, rows, spriteMode, windowTitle)
        local win = self.wm:createSpriteWindow({
          animated = true,
          title = windowTitle or "Animation (sprites)",
          numFrames = 3,
          spriteMode = spriteMode,
          cols = cols,
          rows = rows,
        })
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "Palette window",
      buttonText = "Palette window",
      callback = function(_, _, _, windowTitle)
        local win = self.wm:createPaletteWindow({
          title = windowTitle or "Palette",
        })
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "ROM Palette window",
      buttonText = "ROM Palette window",
      callback = function(_, _, _, windowTitle)
        local win = self.wm:createRomPaletteWindow({
          title = windowTitle or "ROM Palette",
        })
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "Pattern Table Builder",
      buttonText = "Pattern Table Builder",
      callback = function(_, _, _, windowTitle)
        local win = self.wm:createPatternTableBuilderWindow({
          title = windowTitle or "Pattern Table Builder",
        })
        self:setStatus(string.format("Created %s", win.title))
      end
    },
  }
end

function AppCoreController:showNewWindowModal()
  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before creating windows.")
    return false
  end

  self.newWindowModal:show("New Window", self:_buildNewWindowOptions())
  return true
end

function AppCoreController:_collapseAllWindowsFromMenu()
  local wm = self.wm
  local canvas = self.canvas
  if not (wm and wm.collapseAll and canvas) then
    return false
  end

  local taskbarTopY = (self.taskbar and self.taskbar.getTopY and self.taskbar:getTopY())
    or (self.taskbar and self.taskbar.y)
    or canvas:getHeight()

  wm:collapseAll({
    areaX = 30,
    areaY = 30,
    areaH = math.max(1, taskbarTopY - 38),
    gapX = 8,
    gapY = 2,
  })
  self:setStatus("Windows collapsed and stacked")
  return true
end

function AppCoreController:_buildWindowHeaderContextMenuItems(win)
  local collapseLabel = (win and win._collapsed == true) and "Expand" or "Collapse"
  return {
    {
      text = "Close",
      enabled = win ~= nil and win._closed ~= true,
      callback = function()
        self:hideAppContextMenus()
        local toolbar = win and win.headerToolbar or nil
        if toolbar and toolbar._onClose then
          toolbar:_onClose()
          return
        end
        if self.wm and self.wm.closeWindow and self.wm:closeWindow(win) then
          self:setStatus("Window closed")
        end
      end,
    },
    {
      text = collapseLabel,
      enabled = win ~= nil and win._closed ~= true and win._minimized ~= true,
      callback = function()
        self:hideAppContextMenus()
        local toolbar = win and win.headerToolbar or nil
        if toolbar and toolbar._onCollapse then
          toolbar:_onCollapse()
          return
        end
        if win then
          win._collapsed = not (win._collapsed == true)
          self:setStatus(win._collapsed and "Window collapsed" or "Window expanded")
        end
      end,
    },
    {
      text = "Minimize",
      enabled = win ~= nil and win._closed ~= true and win._minimized ~= true,
      callback = function()
        self:hideAppContextMenus()
        local toolbar = win and win.headerToolbar or nil
        if toolbar and toolbar._onMinimize then
          toolbar:_onMinimize()
          return
        end
        if self.wm and self.wm.minimizeWindow and self.wm:minimizeWindow(win) then
          self:setStatus("Window minimized")
        end
      end,
    },
  }
end

function AppCoreController:_buildEmptySpaceContextMenuItems()
  local hasRom = self:hasLoadedROM()
  local hasWindows = self.wm and self.wm.getWindows and #(self.wm:getWindows() or {}) > 0

  return {
    {
      text = "New Window",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        self:showNewWindowModal()
      end,
    },
    {
      text = "Minimize all",
      enabled = hasWindows,
      callback = function()
        self:hideAppContextMenus()
        if self.wm and self.wm.minimizeAll and self.wm:minimizeAll() then
          self:setStatus("Windows minimized")
        end
      end,
    },
    {
      text = "Collapse all",
      enabled = hasWindows,
      callback = function()
        self:hideAppContextMenus()
        self:_collapseAllWindowsFromMenu()
      end,
    },
  }
end

function AppCoreController:showWindowHeaderContextMenu(win, x, y)
  if not (self.windowHeaderContextMenu and win and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  self.windowHeaderContextMenu:showAt(x, y, self:_buildWindowHeaderContextMenuItems(win))
  return self.windowHeaderContextMenu:isVisible()
end

function AppCoreController:showEmptySpaceContextMenu(x, y)
  if not (self.emptySpaceContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  self.emptySpaceContextMenu:showAt(x, y, self:_buildEmptySpaceContextMenuItems())
  return self.emptySpaceContextMenu:isVisible()
end

function AppCoreController:rebuildBankWindowItems()
  if not self.winBank or self.winBank.kind ~= "chr" then return end
  BankViewController.rebuildBankWindowItems(
    self.winBank,
    self.appEditState,
    self.winBank.orderMode or "normal",
    function(txt) self:setStatus(txt) end
  )
end

function AppCoreController:paintAt(win, col, row, lx, ly, pickOnly)
  return BrushController.paintPixel(self, win, col, row, lx, ly, pickOnly)
end

function AppCoreController:setStatus(text)
  if text == nil then return end
  self.statusText = text
  self.lastEventText = text
end

function AppCoreController:hasLoadedROM()
  local state = self.appEditState or {}
  if type(state.romSha1) == "string" and state.romSha1 ~= "" then
    return true
  end
  return type(state.romRaw) == "string"
    and #state.romRaw > 0
    and type(state.romOriginalPath) == "string"
    and state.romOriginalPath ~= ""
end

function AppCoreController:showToast(kind, text, opts)
  if not self.toastController then return nil end
  return self.toastController:show(kind, text, opts)
end

function AppCoreController:beginSimpleLoading(message)
  self._simpleLoadingActive = true
  self._simpleLoadingMessage = message or "Loading..."
  return SimpleLoadingScreen.present(self._simpleLoadingMessage, self)
end

function AppCoreController:pulseSimpleLoading(message)
  if message and message ~= "" then
    self._simpleLoadingMessage = message
  end
  if self._simpleLoadingActive ~= true then
    return false
  end
  return SimpleLoadingScreen.present(self._simpleLoadingMessage or "Loading...", self)
end

function AppCoreController:endSimpleLoading()
  self._simpleLoadingActive = false
  self._simpleLoadingMessage = nil
end

function AppCoreController:getTooltipCandidateAt(x, y)
  if x == nil or y == nil then return nil end
  if self._getTooltipsEnabledForSettings and not self:_getTooltipsEnabledForSettings() then
    return nil
  end

  local modalOpen = anyModalVisible(self) or (self.splash and self.splash:isVisible())
  if modalOpen then
    local modalCandidate = getTopModalTooltipCandidate(self, x, y)
    if modalCandidate then
      return modalCandidate
    end
    return nil
  end

  if UserInput.getTooltipCandidate then
    local candidate = UserInput.getTooltipCandidate(x, y)
    if candidate then
      return candidate
    end
  end

  if self.taskbar and self.taskbar.getTooltipAt then
    local candidate = self.taskbar:getTooltipAt(x, y)
    if candidate then
      return candidate
    end
  end

  return getTopWindowTooltipCandidate(self, x, y)
end

local function parseHexAddress(text)
  local trimmed = tostring(text or ""):match("^%s*(.-)%s*$")
  if trimmed == "" then
    return nil, "Address is required"
  end

  local normalized = trimmed:upper():gsub("^0X", "")
  if not normalized:match("^[0-9A-F]+$") then
    return nil, "Address must be hexadecimal"
  end

  local value = tonumber(normalized, 16)
  if type(value) ~= "number" then
    return nil, "Address must be hexadecimal"
  end

  return math.floor(value)
end

function AppCoreController:showRenameWindowModal(win)
  if not (self.renameWindowModal and win and type(win) == "table") then
    return false
  end

  self.renameWindowModal:show({
    window = win,
    initialTitle = win.title or "",
    onConfirm = function(newTitle, targetWindow)
      if not targetWindow then return end
      targetWindow.title = newTitle
      self:setStatus(string.format("Renamed window to \"%s\"", newTitle))
    end,
  })

  return true
end

function AppCoreController:showRomPaletteAddressModal(win, col, row)
  if not (self.romPaletteAddressModal and win and type(win) == "table") then
    return false
  end

  local rowColors = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[(row or 0) + 1] or nil
  local existingAddr = rowColors and rowColors[(col or 0) + 1] or nil
  local initialAddress = type(existingAddr) == "number" and string.format("0x%06X", existingAddr) or ""

  self.romPaletteAddressModal:show({
    title = "Enter color address",
    window = win,
    col = col,
    row = row,
    initialAddress = initialAddress,
    onConfirm = function(addressText, targetWindow, targetCol, targetRow)
      local addr, parseErr = parseHexAddress(addressText)
      if not addr then
        self:setStatus(parseErr)
        self:showToast("error", parseErr)
        return false
      end

      local ok, err = targetWindow:setCellAddress(targetCol, targetRow, addr)
      if not ok then
        local message = err or "Failed to assign ROM palette address"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      self:setStatus(string.format("Assigned ROM palette cell (%d,%d) to 0x%X", targetCol, targetRow, addr))
      return true
    end,
  })

  return true
end

function AppCoreController:invalidateChrBankCanvas(bankIdx)
  if not self.chrBankCanvasController then
    return false
  end
  self.chrBankCanvasController:invalidateBank(bankIdx)
  return true
end

function AppCoreController:invalidateChrBankTileCanvas(bankIdx, tileIndex)
  if not self.chrBankCanvasController then
    return false
  end
  self.chrBankCanvasController:invalidateTile(bankIdx, tileIndex)
  return true
end

require("controllers.app.core_controller_save_settings")(AppCoreController)
require("controllers.app.core_controller_lifecycle")(AppCoreController)
require("controllers.app.core_controller_input")(AppCoreController)
require("controllers.app.core_controller_draw")(AppCoreController)

return AppCoreController
