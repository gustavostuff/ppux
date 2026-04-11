local WindowController = require("controllers.window.window_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local RevertTilePixelsController = require("controllers.chr.revert_tile_pixels_controller")
local BrushController = require("controllers.input_support.brush_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

local GenericActionsModal = require("user_interface.modals.generic_actions_modal")
local NewWindowTypeModal = require("user_interface.modals.new_window_type_modal")
local NewWindowModal = require("user_interface.modals.new_window_modal")
local PPUFrameAddSpriteModal = require("user_interface.modals.ppu_frame_add_sprite_modal")
local PPUFrameSpriteLayerModeModal = require("user_interface.modals.ppu_frame_sprite_layer_mode_modal")
local PPUFrameRangeModal = require("user_interface.modals.ppu_frame_range_modal")
local PPUFramePatternRangeModal = require("user_interface.modals.ppu_frame_pattern_range_modal")
local RenameWindowModal = require("user_interface.modals.rename_window_modal")
local RomPaletteAddressModal = require("user_interface.modals.rom_palette_address_modal")
local SaveOptionsModal = require("user_interface.modals.save_options_modal")
local QuitConfirmModal = require("user_interface.modals.quit_confirm_modal")
local SettingsModal = require("user_interface.modals.settings_modal")
local TextFieldDemoModal = require("user_interface.modals.text_field_demo_modal")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local SimpleLoadingScreen = require("controllers.app.simple_loading_screen")
local TooltipController = require("controllers.ui.tooltip_controller")
local ContextualMenuController = require("controllers.ui.contextual_menu_controller")
local UiScale = require("user_interface.ui_scale")
local images = require("images")
local katsudo = require("lib.katsudo")
local UserInput = require("controllers.input")
local TableUtils = require("utils.table_utils")
local PatternTableMapping = require("utils.pattern_table_mapping")

local AppCoreController = {}
AppCoreController.__index = AppCoreController
local snapshotPpuFrameRangeState
local didPpuFrameRangeSettingsChange
local parsePatternRangeBounds
local patternTableLogicalSize
local getPpuPatternTableTargetLayer
local buildPatternTableMapAllowPartial

local function anyModalVisible(app)
  return (app.quitConfirmModal and app.quitConfirmModal:isVisible())
    or (app.saveOptionsModal and app.saveOptionsModal:isVisible())
    or (app.genericActionsModal and app.genericActionsModal:isVisible())
    or (app.settingsModal and app.settingsModal:isVisible())
    or (app.newWindowTypeModal and app.newWindowTypeModal:isVisible())
    or (app.newWindowModal and app.newWindowModal:isVisible())
    or (app.renameWindowModal and app.renameWindowModal:isVisible())
    or (app.romPaletteAddressModal and app.romPaletteAddressModal:isVisible())
    or (app.ppuFrameSpriteLayerModeModal and app.ppuFrameSpriteLayerModeModal:isVisible())
    or (app.ppuFrameAddSpriteModal and app.ppuFrameAddSpriteModal:isVisible())
    or (app.ppuFrameRangeModal and app.ppuFrameRangeModal:isVisible())
    or (app.ppuFramePatternRangeModal and app.ppuFramePatternRangeModal:isVisible())
    or (app.textFieldDemoModal and app.textFieldDemoModal:isVisible())
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
    app.newWindowTypeModal,
    app.newWindowModal,
    app.renameWindowModal,
    app.romPaletteAddressModal,
    app.ppuFrameSpriteLayerModeModal,
    app.ppuFrameAddSpriteModal,
    app.ppuFrameRangeModal,
    app.ppuFramePatternRangeModal,
    app.textFieldDemoModal,
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

local function recordWindowCreateUndo(app, win, prevFocusedWin)
  if not (app and app.undoRedo and app.undoRedo.addWindowCreateEvent and win) then
    return false
  end
  return app.undoRedo:addWindowCreateEvent({
    type = "window_create",
    win = win,
    wm = app.wm,
    prevFocusedWin = prevFocusedWin,
  })
end

local function captureRomPaletteAddressUndoState(win)
  return {
    paletteData = TableUtils.deepcopy((win and win.paletteData) or {}),
    selected = {
      col = win and win.selected and win.selected.col or nil,
      row = win and win.selected and win.selected.row or nil,
    },
  }
end

local function clampByte(byteVal)
  local v = math.floor(tonumber(byteVal) or 0)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

local function ppuTileLinearIndex(win, col, row)
  return row * (win.cols or 0) + col + 1
end

local function normalizeTileIndex(item)
  local tileIndex = item and tonumber(item.index) or nil
  if type(tileIndex) ~= "number" then
    tileIndex = item and tonumber(item.tile) or nil
  end
  if type(tileIndex) ~= "number" and item and item.topRef then
    tileIndex = tonumber(item.topRef.index)
  end
  if type(tileIndex) ~= "number" then
    return nil
  end
  tileIndex = math.floor(tileIndex)
  if tileIndex < 0 then
    return nil
  end
  if tileIndex >= 512 then
    tileIndex = tileIndex % 512
  end
  return tileIndex
end

local function findChrWindowCellForTile(winBank, layerIndex, tileIndex)
  if not (winBank and winBank.getVirtualTileHandle and type(tileIndex) == "number") then
    return nil, nil
  end

  for row = 0, (winBank.rows or 0) - 1 do
    for col = 0, (winBank.cols or 0) - 1 do
      local handle = winBank:getVirtualTileHandle(col, row, layerIndex)
      if handle and tonumber(handle.index) == tileIndex then
        return col, row
      end
    end
  end

  return nil, nil
end

local function scrollChrWindowToCell(winBank, col, row)
  if not (winBank and type(col) == "number" and type(row) == "number") then
    return
  end

  local maxScrollCol = math.max(0, (winBank.cols or 0) - (winBank.visibleCols or winBank.cols or 1))
  local maxScrollRow = math.max(0, (winBank.rows or 0) - (winBank.visibleRows or winBank.rows or 1))
  local scrollCol = math.max(0, math.min(col, maxScrollCol))
  local scrollRow = math.max(0, math.min(row, maxScrollRow))

  if winBank.setScroll then
    winBank:setScroll(scrollCol, scrollRow)
    return
  end

  winBank.scrollCol = scrollCol
  winBank.scrollRow = scrollRow
end

function AppCoreController.new()
  local self = setmetatable({}, AppCoreController)

  -- app state
  self.statusText = "Drop an .nes ROM with CHR data"
  self.lastEventText = self.statusText
  self.crtModeEnabled = false
  self.mode = "tile"
  self.isPainting = false
  self.currentColor = 1
  self.brushSize = 1
  self.editTool = "pencil"
  self.syncDuplicateTiles = false
  self.spaceHighlightActive = false
  self.spaceHighlightSourceWin = nil
  self.showDebugInfo = false
  self.paletteLinkDrag = {
    active = false,
    sourceWin = nil,
    sourceWinId = nil,
    mode = nil,
    originContentWin = nil,
    originPaletteWin = nil,
    currentX = 0,
    currentY = 0,
  }

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
  self.groupedPaletteWindows = false
  self.paletteGroupState = nil
  self.groupedPaletteController = nil

  -- windows + manager
  self.wm = WindowController.new()
  self.winBank = nil

  self.genericActionsModal = GenericActionsModal.new()
  self.newWindowTypeModal = NewWindowTypeModal.new()
  self.newWindowModal = NewWindowModal.new()
  self.renameWindowModal = RenameWindowModal.new()
  self.romPaletteAddressModal = RomPaletteAddressModal.new()
  self.ppuFrameSpriteLayerModeModal = PPUFrameSpriteLayerModeModal.new()
  self.ppuFrameAddSpriteModal = PPUFrameAddSpriteModal.new()
  self.ppuFrameRangeModal = PPUFrameRangeModal.new()
  self.ppuFramePatternRangeModal = PPUFramePatternRangeModal.new()
  self.saveOptionsModal = SaveOptionsModal.new()
  self.quitConfirmModal = QuitConfirmModal.new()
  self.settingsModal = SettingsModal.new()
  self.textFieldDemoModal = TextFieldDemoModal.new()
  self.taskbar = nil
  self.windowHeaderContextMenu = ContextualMenuController.new({
    getBounds = function()
      local canvas = self.canvas
      return {
        w = canvas and canvas.getWidth and canvas:getWidth() or 0,
        h = canvas and canvas.getHeight and canvas:getHeight() or 0,
      }
    end,
    cellH = UiScale.menuCellSize(),
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
    cellH = UiScale.menuCellSize(),
    padding = 0,
    colGap = 0,
    rowGap = 1,
    splitIconCell = false,
  })
  self.ppuTileContextMenu = ContextualMenuController.new({
    getBounds = function()
      local canvas = self.canvas
      return {
        w = canvas and canvas.getWidth and canvas:getWidth() or 0,
        h = canvas and canvas.getHeight and canvas:getHeight() or 0,
      }
    end,
    cellH = UiScale.menuCellSize(),
    padding = 0,
    colGap = 0,
    rowGap = 1,
    splitIconCell = false,
  })
  self.paletteLinkContextMenu = ContextualMenuController.new({
    getBounds = function()
      local canvas = self.canvas
      return {
        w = canvas and canvas.getWidth and canvas:getWidth() or 0,
        h = canvas and canvas.getHeight and canvas:getHeight() or 0,
      }
    end,
    cellH = UiScale.menuCellSize(),
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
    rom_palette_address_change = true,
    sprite_remove = true,
    window_create = true,
    window_minimize = true,
    window_close = true,
    window_rename = true,
    palette_link_change = true,
    ppu_frame_range_change = true,
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
  if self.ppuTileContextMenu then
    self.ppuTileContextMenu:hide()
  end
  if self.paletteLinkContextMenu then
    self.paletteLinkContextMenu:hide()
  end
end

function AppCoreController:_hideAllContextMenus()
  self:hideAppContextMenus()
  if self.taskbar and self.taskbar.menuController then
    self.taskbar.menuController:hide()
  end
end

local _newWindowOptionIcons = {}
local NEW_WINDOW_ICON_SHEETS_BY_KEY = {
  static_tile = "icon_static_tile_window",
  static_sprite = "icon_static_sprite_window",
  animated_tile = "icon_animated_tile_window",
  animated_sprite = "icon_animated_sprite_window",
  oam_animated = "icon_oam_animated_window",
  ppu_frame = "icon_ppu_frame_window",
  palette = "icon_palette_window",
  rom_palette = "icon_rom_palette_window",
  generic = "icon_generic_window",
}

local function getNewWindowOptionIcon(iconKey)
  local key = tostring(iconKey or "generic")
  if _newWindowOptionIcons[key] ~= nil then
    return _newWindowOptionIcons[key]
  end

  local windowIcons = images.windows_icons or images.animated_icons or {}
  local sheet = windowIcons[NEW_WINDOW_ICON_SHEETS_BY_KEY[key] or NEW_WINDOW_ICON_SHEETS_BY_KEY.generic]
  local fallback = images.icons and images.icons.icon_circle or nil
  local icon = fallback

  if sheet and katsudo and type(katsudo.new) == "function"
    and type(sheet.getWidth) == "function"
    and type(sheet.getHeight) == "function"
  then
    local frameSize = UiScale.normalButtonSize()
    local iw = sheet:getWidth()
    local ih = sheet:getHeight()
    if ih == frameSize and iw >= frameSize and (iw % frameSize == 0) then
      local frames = math.max(1, math.floor(iw / frameSize))
      icon = katsudo.new(sheet, frameSize, frameSize, frames, 0.1) or icon
    end
  end

  _newWindowOptionIcons[key] = icon
  return icon
end

function AppCoreController:_buildNewWindowOptions()
  return {
    {
      text = "Static Art window (tiles)",
      icon = getNewWindowOptionIcon("static_tile"),
      buttonText = "Static Tiles window",
      callback = function(cols, rows, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createTileWindow({
          animated = false,
          title    = windowTitle or "Static Art (tiles)",
          cols     = cols,
          rows     = rows,
        })
        recordWindowCreateUndo(self, win, prevFocusedWin)
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "Static Art window (sprites)",
      icon = getNewWindowOptionIcon("static_sprite"),
      buttonText = "Static Sprites window",
      requiresSpriteMode = true,
      callback = function(cols, rows, spriteMode, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createSpriteWindow({
          animated = false,
          title = windowTitle or "Static Art (sprites)",
          spriteMode = spriteMode,
          cols = cols,
          rows = rows,
        })
        recordWindowCreateUndo(self, win, prevFocusedWin)
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "Animation window  (tiles)",
      icon = getNewWindowOptionIcon("animated_tile"),
      buttonText = "Animation Tiles window",
      callback = function(cols, rows, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createTileWindow({
          animated = true,
          title = windowTitle or "Animation (tiles)",
          numFrames = 3,
          cols = cols,
          rows = rows,
        })
        recordWindowCreateUndo(self, win, prevFocusedWin)
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "Animation window  (sprites)",
      icon = getNewWindowOptionIcon("animated_sprite"),
      buttonText = "Animation Sprites window",
      requiresSpriteMode = true,
      callback = function(cols, rows, spriteMode, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createSpriteWindow({
          animated = true,
          title = windowTitle or "Animation (sprites)",
          numFrames = 3,
          spriteMode = spriteMode,
          cols = cols,
          rows = rows,
        })
        recordWindowCreateUndo(self, win, prevFocusedWin)
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "Palette window",
      icon = getNewWindowOptionIcon("palette"),
      buttonText = "Palette window",
      skipSettingsModal = true,
      callback = function(_, _, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createPaletteWindow({
          title = windowTitle or "Palette",
        })
        recordWindowCreateUndo(self, win, prevFocusedWin)
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "ROM Palette window",
      icon = getNewWindowOptionIcon("rom_palette"),
      buttonText = "ROM Palette window",
      skipSettingsModal = true,
      callback = function(_, _, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createRomPaletteWindow({
          title = windowTitle or "ROM Palette",
        })
        recordWindowCreateUndo(self, win, prevFocusedWin)
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "PPU Frame window",
      icon = getNewWindowOptionIcon("ppu_frame"),
      buttonText = "PPU Frame window",
      skipSettingsModal = true,
      callback = function(_, _, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local currentBank = self.appEditState and self.appEditState.currentBank or 1
        local win = self.wm:createPPUFrameWindow({
          title = windowTitle or "PPU Frame",
          romRaw = self.appEditState and self.appEditState.romRaw or nil,
          bankIndex = currentBank,
          pageIndex = 1,
          codec = "konami",
        })
        recordWindowCreateUndo(self, win, prevFocusedWin)
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "OAM animation",
      icon = getNewWindowOptionIcon("oam_animated"),
      buttonText = "OAM animation",
      requiresSpriteMode = true,
      callback = function(cols, rows, spriteMode, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createSpriteWindow({
          animated = true,
          oamBacked = true,
          numFrames = 1,
          title = windowTitle or "OAM Animation",
          spriteMode = spriteMode,
          cols = cols,
          rows = rows,
        })
        recordWindowCreateUndo(self, win, prevFocusedWin)
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

  local options = self:_buildNewWindowOptions()
  local configTitle = "Window Settings"
  self.newWindowTypeModal:show("New Window", (function()
    local mapped = {}
    for _, option in ipairs(options) do
      mapped[#mapped + 1] = {
        text = option.text,
        buttonText = option.buttonText,
        icon = option.icon,
        callback = function()
          if option.skipSettingsModal == true then
            option.callback(nil, nil, nil, nil)
            return
          end

          self.newWindowModal:show({
            title = configTitle,
            option = option,
            initialName = "New Window",
            onConfirm = function(cols, rows, spriteMode, windowName, selectedOption)
              local targetOption = selectedOption or option
              if not (targetOption and targetOption.callback) then
                return false
              end
              targetOption.callback(cols, rows, spriteMode, windowName)
              return true
            end,
          })
        end,
      }
    end
    return mapped
  end)())
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
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.windowHeaderContextMenu:showAt(cx, cy, self:_buildWindowHeaderContextMenuItems(win))
  return self.windowHeaderContextMenu:isVisible()
end

function AppCoreController:showEmptySpaceContextMenu(x, y)
  if not (self.emptySpaceContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.emptySpaceContextMenu:showAt(cx, cy, self:_buildEmptySpaceContextMenuItems())
  return self.emptySpaceContextMenu:isVisible()
end

--- Mouse and window geometry use full canvas coordinates (including the top toolbar strip).
function AppCoreController:contentYToCanvasY(y)
  return y
end

function AppCoreController:contentPointToCanvasPoint(x, y)
  return x, y
end

local function setWindowActiveLayer(win, layerIndex)
  if not (win and type(layerIndex) == "number") then
    return
  end
  if win.setActiveLayerIndex then
    win:setActiveLayerIndex(layerIndex)
  else
    win.activeLayer = layerIndex
  end
end

function AppCoreController:_focusLinkedLayerTarget(win, layerIndex)
  if not win then
    return false
  end
  setWindowActiveLayer(win, layerIndex)
  if self.wm and self.wm.setFocus then
    self.wm:setFocus(win)
  end
  self:setStatus(string.format(
    "Focused %s layer %d",
    tostring(win.title or "window"),
    tonumber(layerIndex) or 1
  ))
  return true
end

function AppCoreController:_buildPaletteLinkSourceContextMenuItems(paletteWin)
  local targets = PaletteLinkController.getLinkedTargetsForPalette(self.wm, paletteWin)
  local items = {}

  items[#items + 1] = {
    text = "Jump to linked layer",
    children = function()
      if #targets == 0 then
        return {
          {
            text = "No linked layers",
            callback = function() end,
          },
        }
      end
      local childItems = {}
      for _, target in ipairs(targets) do
        childItems[#childItems + 1] = {
          text = string.format("%s / layer %d", tostring(target.win.title or "window"), target.layerIndex),
          callback = function()
            self:_focusLinkedLayerTarget(target.win, target.layerIndex)
          end,
        }
      end
      return childItems
    end,
  }

  items[#items + 1] = {
    text = "Remove all links",
    callback = function()
      PaletteLinkController.removeAllLinksForPalette(self.wm, paletteWin)
    end,
  }

  return items
end

function AppCoreController:_buildPaletteLinkDestinationContextMenuItems(contentWin)
  local layerIndex = (contentWin and contentWin.getActiveLayerIndex and contentWin:getActiveLayerIndex())
    or (contentWin and contentWin.activeLayer)
    or 1
  local linkedPalette = PaletteLinkController.getActiveLayerLinkedPaletteWindow(contentWin, self.wm)
  local paletteWindows = PaletteLinkController.getRomPaletteWindows(self.wm)
  local items = {}

  items[#items + 1] = {
      text = "Link To Palette",
      children = function()
        local childItems = {}
        for _, paletteWin in ipairs(paletteWindows) do
          childItems[#childItems + 1] = {
            text = tostring(paletteWin.title or "Palette"),
            callback = function()
              PaletteLinkController.linkLayerToPalette(contentWin, layerIndex, paletteWin)
            end,
          }
        end
        if #childItems == 0 then
          childItems[1] = {
            text = "No ROM palettes available",
            callback = function() end,
          }
        end
        return childItems
      end,
    }

  if linkedPalette then
    items[#items + 1] = {
      text = "Jump to linked palette",
      callback = function()
        if self.focusPaletteWindowWithGrouping then
          self:focusPaletteWindowWithGrouping(linkedPalette)
        elseif self.wm and self.wm.setFocus then
          self.wm:setFocus(linkedPalette)
        end
        self:setStatus(string.format("Focused %s", tostring(linkedPalette.title or "palette")))
      end,
    }
    items[#items + 1] = {
      text = "Remove this link",
      callback = function()
        PaletteLinkController.removeLinkForLayer(contentWin, layerIndex)
      end,
    }
  end

  return items
end

function AppCoreController:_resolveLinkedPaletteForLayer(win, layerIndex)
  if not (win and layerIndex and self.wm and self.wm.findWindowById) then
    return nil
  end
  local layer = (win.getLayer and win:getLayer(layerIndex)) or (win.layers and win.layers[layerIndex]) or nil
  local pd = layer and layer.paletteData or nil
  local winId = pd and pd.winId or nil
  if not winId then
    return nil
  end
  local paletteWin = self.wm:findWindowById(winId)
  if paletteWin and paletteWin._closed ~= true and paletteWin._minimized ~= true and paletteWin.kind == "rom_palette" then
    return paletteWin
  end
  return nil
end

function AppCoreController:_appendJumpToLinkedPaletteMenuItem(items, win, layerIndex)
  if type(items) ~= "table" then
    return items
  end
  local paletteWin = self:_resolveLinkedPaletteForLayer(win, layerIndex)
  if not paletteWin then
    return items
  end
  items[#items + 1] = {
    text = "Jump to linked palette",
    callback = function()
      if self.focusPaletteWindowWithGrouping then
        self:focusPaletteWindowWithGrouping(paletteWin)
      elseif self.wm and self.wm.setFocus then
        self.wm:setFocus(paletteWin)
      end
      self:setStatus(string.format("Focused %s", tostring(paletteWin.title or "ROM Palette")))
    end,
  }
  return items
end

function AppCoreController:showPaletteLinkSourceContextMenu(win, x, y)
  if not (self.paletteLinkContextMenu and win and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.paletteLinkContextMenu:showAt(cx, cy, self:_buildPaletteLinkSourceContextMenuItems(win))
  return self.paletteLinkContextMenu:isVisible()
end

function AppCoreController:showPaletteLinkDestinationContextMenu(win, x, y)
  if not (self.paletteLinkContextMenu and win and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.paletteLinkContextMenu:showAt(cx, cy, self:_buildPaletteLinkDestinationContextMenuItems(win))
  return self.paletteLinkContextMenu:isVisible()
end

function AppCoreController:_buildPpuTileContext(win, layerIndex, col, row)
  if not (win and win.kind == "ppu_frame" and type(col) == "number" and type(row) == "number") then
    return nil
  end

  local layer = win.getLayer and win:getLayer(layerIndex) or (win.layers and win.layers[layerIndex])
  if not (layer and layer.kind == "tile") then
    return nil
  end

  local idx = ppuTileLinearIndex(win, col, row)
  local byteVal = win.nametableBytes and win.nametableBytes[idx] or nil
  local item = win.get and win:get(col, row, layerIndex) or nil
  if type(byteVal) ~= "number" or not item then
    return nil
  end

  local sourceBank = tonumber(item._bankIndex)
  if not sourceBank and type(layer.patternTable) == "table" then
    local map = PatternTableMapping.buildMap(layer.patternTable)
    local entry = map and map[clampByte(byteVal)] or nil
    sourceBank = entry and tonumber(entry.bank) or nil
  end
  sourceBank = sourceBank or 1

  return {
    win = win,
    layerIndex = layerIndex,
    layer = layer,
    col = col,
    row = row,
    item = item,
    byteVal = clampByte(byteVal),
    tileIndex = normalizeTileIndex(item),
    sourceBank = sourceBank,
  }
end

function AppCoreController:_ensurePpuPatternTableReferenceLayer(context, opts)
  opts = opts or {}
  if not (context and context.win and context.layer) then
    return false
  end
  local layer = context.layer
  if type(layer.patternTable) ~= "table" then
    self:setStatus("This layer has no patternTable")
    return false
  end
  local map, mapErr = buildPatternTableMapAllowPartial(layer.patternTable)
  if not map then
    self:setStatus(tostring(mapErr or "Invalid patternTable mapping"))
    return false
  end

  local refLayer = nil
  local refLayerIndex = nil
  for i, L in ipairs(context.win.layers or {}) do
    if L
      and L._runtimePatternTableRefLayer == true
      and tonumber(L._runtimePatternTableRefTargetLayerIndex) == tonumber(context.layerIndex)
    then
      refLayer = L
      refLayerIndex = i
      break
    end
  end

  if not refLayer then
    if not (context.win and context.win.addLayer) then
      self:setStatus("Could not create pattern table reference layer")
      return false
    end
    refLayerIndex = context.win:addLayer({
      name = string.format("Pattern Table L%d", tonumber(context.layerIndex) or 1),
      kind = "tile",
      opacity = 1.0,
      items = {},
    })
    refLayer = context.win.layers and context.win.layers[refLayerIndex] or nil
    if not refLayer then
      self:setStatus("Could not create pattern table reference layer")
      return false
    end
  end

  refLayer._runtimeOnly = true
  refLayer._runtimePatternTableRefLayer = true
  refLayer._runtimePatternTableRefTargetLayerIndex = tonumber(context.layerIndex) or 1
  refLayer._runtimePatternTableRefTargetLayer = context.layer
  refLayer._runtimePatternTableRefTargetWin = context.win
  refLayer.items = {}
  refLayer._runtimePatternTableLogicalByCell = {}

  local tilesPool = self.appEditState and self.appEditState.tilesPool or nil
  if not tilesPool then
    self:setStatus("No tilesPool available for pattern table reference")
    return false
  end
  if self.appEditState and self.appEditState.chrBanksBytes and type(layer.patternTable.ranges) == "table" then
    for _, r in ipairs(layer.patternTable.ranges) do
      local bank = type(r) == "table" and tonumber(r.bank) or nil
      if bank and self.appEditState.chrBanksBytes[bank] then
        BankViewController.ensureBankTiles(self.appEditState, bank)
      end
    end
    tilesPool = self.appEditState.tilesPool or tilesPool
  end
  for logicalIndex = 0, 255 do
    local entry = map[logicalIndex]
    if entry then
      local bankTiles = tilesPool[entry.bank]
      local tileRef = bankTiles and bankTiles[entry.tileIndex] or nil
      local col = logicalIndex % 16
      local row = math.floor(logicalIndex / 16)
      local idx = (row * (context.win.cols or 32)) + col + 1
      refLayer.items[idx] = tileRef
      refLayer._runtimePatternTableLogicalByCell[idx] = logicalIndex
    end
  end

  if opts.keepActiveLayer ~= true then
    if context.win.setActiveLayerIndex then
      context.win:setActiveLayerIndex(refLayerIndex)
    else
      context.win.activeLayer = refLayerIndex
    end
  end
  if context.win.invalidateNametableLayerCanvas then
    context.win:invalidateNametableLayerCanvas(refLayerIndex)
  end
  local size = patternTableLogicalSize(layer.patternTable)
  self:setStatus(string.format("Prepared pattern table reference layer (%d/256 tiles)", tonumber(size) or 0))
  return true
end

function AppCoreController:_buildSelectInChrContext(win, layerIndex, col, row, itemIndex)
  if not (win and type(layerIndex) == "number") then
    return nil
  end

  local layer = win.getLayer and win:getLayer(layerIndex) or (win.layers and win.layers[layerIndex])
  if not layer then
    return nil
  end

  if layer.kind == "tile" then
    if not (type(col) == "number" and type(row) == "number") then
      return nil
    end

    local item = nil
    if win.getVirtualTileHandle then
      item = win:getVirtualTileHandle(col, row, layerIndex)
    end
    if not item and win.get then
      item = win:get(col, row, layerIndex)
    end
    if not item then
      return nil
    end

    local sourceBank = tonumber(item._bankIndex)
    if not sourceBank and win.kind == "ppu_frame" and win.nametableBytes then
      local idx = ppuTileLinearIndex(win, col, row)
      local byteVal = win.nametableBytes[idx]
      if type(byteVal) == "number" and type(layer.patternTable) == "table" then
        local map = PatternTableMapping.buildMap(layer.patternTable)
        local entry = map and map[clampByte(byteVal)] or nil
        sourceBank = entry and tonumber(entry.bank) or nil
      end
    end
    sourceBank = sourceBank or 1

    return {
      win = win,
      layerIndex = layerIndex,
      layer = layer,
      col = col,
      row = row,
      item = item,
      tileIndex = normalizeTileIndex(item),
      sourceBank = sourceBank,
      logicalIndex = (layer._runtimePatternTableRefLayer == true
        and layer._runtimePatternTableLogicalByCell
        and layer._runtimePatternTableLogicalByCell[((row * (win.cols or 32)) + col + 1)])
        or (row * (win.cols or 16)) + col,
    }
  end

  if layer.kind == "sprite" then
    if type(itemIndex) ~= "number" then
      return nil
    end
    local item = layer.items and layer.items[itemIndex] or nil
    if not item or item.removed == true then
      return nil
    end

    return {
      win = win,
      layerIndex = layerIndex,
      layer = layer,
      itemIndex = itemIndex,
      item = item,
      tileIndex = normalizeTileIndex(item),
      sourceBank = tonumber(item.bank)
        or tonumber(layer.bank)
        or tonumber(item.topRef and item.topRef._bankIndex)
        or 1,
    }
  end

  return nil
end

function AppCoreController:_selectPpuTileInChrWindow(context)
  if not context then
    return false
  end

  if type(context.tileIndex) ~= "number" then
    self:setStatus("This item has no CHR source selection to jump to")
    return false
  end

  local winBank = self.winBank
  if not (winBank and winBank.kind == "chr") then
    self:setStatus("No CHR/ROM bank window is available")
    return false
  end

  local sourceBank = tonumber(context.sourceBank) or 1
  if self.appEditState then
    self.appEditState.currentBank = sourceBank
  end

  if not (winBank.layers and winBank.layers[sourceBank]) and self.rebuildBankWindowItems then
    self:rebuildBankWindowItems()
  end

  if winBank.setCurrentBank then
    winBank:setCurrentBank(sourceBank)
  end

  local col, row = findChrWindowCellForTile(winBank, sourceBank, context.tileIndex)
  if (col == nil or row == nil) and self.rebuildBankWindowItems then
    self:rebuildBankWindowItems()
    if winBank.setCurrentBank then
      winBank:setCurrentBank(sourceBank)
    end
    col, row = findChrWindowCellForTile(winBank, sourceBank, context.tileIndex)
  end

  if col == nil or row == nil then
    self:setStatus(string.format("Tile %d was not found in CHR bank %d", context.tileIndex, sourceBank))
    return false
  end

  scrollChrWindowToCell(winBank, col, row)
  winBank:setSelected(col, row, sourceBank)
  if self.wm and self.wm.setFocus then
    self.wm:setFocus(winBank)
  end

  self:setStatus(string.format("Selected CHR tile %d in bank %d", context.tileIndex, sourceBank))
  return true
end

function AppCoreController:_buildPpuTileContextMenuItems(context)
  local items = {
    {
      text = "Build/refresh pattern table reference layer",
      enabled = context and context.layer and type(context.layer.patternTable) == "table",
      callback = function()
        self:_ensurePpuPatternTableReferenceLayer(context, { keepActiveLayer = false })
      end,
    },
    {
      text = "Undo pixel edits",
      enabled = RevertTilePixelsController.canRevertContext(self, context),
      callback = function()
        local ok, err = RevertTilePixelsController.revertForContext(self, context)
        if ok then
          self:setStatus("Reverted tile pixels to original CHR")
        else
          self:setStatus(tostring(err or "Could not revert tile pixels"))
        end
      end,
    },
    {
      text = "Select in CHR/ROM window",
      enabled = context and context.tileIndex ~= nil,
      callback = function()
        self:_selectPpuTileInChrWindow(context)
      end,
    },
  }
  if context and context.win and context.layerIndex then
    self:_appendJumpToLinkedPaletteMenuItem(items, context.win, context.layerIndex)
  end
  return items
end

function AppCoreController:_removePpuPatternRangeFromRuntimeReference(context)
  if not (context and context.layer and context.layer._runtimePatternTableRefLayer == true and type(context.logicalIndex) == "number") then
    return false
  end
  local targetWin = context.layer._runtimePatternTableRefTargetWin
  local targetLayerIndex = context.layer._runtimePatternTableRefTargetLayerIndex
  local targetLayer = context.layer._runtimePatternTableRefTargetLayer
  if not (targetWin and targetLayerIndex and targetLayer) then
    self:setStatus("Missing target PPU layer for runtime pattern table reference")
    return false
  end
  if targetWin.getLayer then
    targetLayer = targetWin:getLayer(targetLayerIndex) or targetLayer
  end
  if not targetLayer then
    self:setStatus("Target PPU tile layer is no longer available")
    return false
  end
  local patternTable = type(targetLayer.patternTable) == "table" and targetLayer.patternTable or nil
  local ranges = patternTable and patternTable.ranges
  if type(ranges) ~= "table" or #ranges == 0 then
    self:setStatus("No tile ranges to remove")
    return false
  end

  local beforeState = snapshotPpuFrameRangeState and snapshotPpuFrameRangeState(targetWin, targetLayerIndex) or nil
  local logicalIndex = math.max(0, math.floor(tonumber(context.logicalIndex) or 0))
  local cursor = 0
  local removeIndex = nil
  for i, range in ipairs(ranges) do
    local from, to = parsePatternRangeBounds(range)
    if from ~= nil and to ~= nil then
      local len = to - from + 1
      if logicalIndex >= cursor and logicalIndex < (cursor + len) then
        removeIndex = i
        break
      end
      cursor = cursor + len
    end
  end
  if not removeIndex then
    self:setStatus("Could not resolve a range at that logical tile")
    return false
  end

  table.remove(ranges, removeIndex)
  targetLayer.patternTable = patternTable

  local tilesPool = self.appEditState and self.appEditState.tilesPool or nil
  if targetWin.refreshNametableVisuals then
    targetWin:refreshNametableVisuals(tilesPool, targetLayerIndex)
  elseif targetWin.invalidateNametableLayerCanvas then
    targetWin:invalidateNametableLayerCanvas(targetLayerIndex)
  end
  self:_ensurePpuPatternTableReferenceLayer({
    win = targetWin,
    layerIndex = targetLayerIndex,
    layer = targetLayer,
  }, { keepActiveLayer = true })
  if targetWin.specializedToolbar and targetWin.specializedToolbar.updateIcons then
    targetWin.specializedToolbar:updateIcons()
  end

  local total = patternTableLogicalSize(patternTable)
  local afterState = snapshotPpuFrameRangeState and snapshotPpuFrameRangeState(targetWin, targetLayerIndex) or nil
  if self.undoRedo and self.undoRedo.addPpuFrameRangeEvent
    and didPpuFrameRangeSettingsChange(beforeState, afterState)
  then
    self.undoRedo:addPpuFrameRangeEvent({
      type = "ppu_frame_range",
      win = targetWin,
      layerIndex = targetLayerIndex,
      beforeState = beforeState,
      afterState = afterState,
    })
  end

  self:setStatus(string.format("Removed tile range #%d (%d/256 tiles)", removeIndex, tonumber(total) or 0))
  return true
end

function AppCoreController:_buildSelectInChrContextMenuItems(context)
  local items = {
    {
      text = "Undo pixel edits",
      enabled = RevertTilePixelsController.canRevertContext(self, context),
      callback = function()
        local ok, err = RevertTilePixelsController.revertForContext(self, context)
        if ok then
          self:setStatus("Reverted tile pixels to original CHR")
        else
          self:setStatus(tostring(err or "Could not revert tile pixels"))
        end
      end,
    },
    {
      text = "Select in CHR/ROM window",
      enabled = context and context.tileIndex ~= nil,
      callback = function()
        self:_selectPpuTileInChrWindow(context)
      end,
    },
  }
  if context and context.layer and context.layer._runtimePatternTableRefLayer == true then
    items[#items + 1] = {
      text = "Remove tile range at this tile",
      enabled = type(context.logicalIndex) == "number",
      callback = function()
        self:_removePpuPatternRangeFromRuntimeReference(context)
      end,
    }
  end
  if context and context.win and context.layerIndex then
    self:_appendJumpToLinkedPaletteMenuItem(items, context.win, context.layerIndex)
  end
  return items
end

function AppCoreController:_buildChrBankTileContext(win, col, row)
  if not (win and type(col) == "number" and type(row) == "number") then
    return nil
  end

  local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  local layer = win.getLayer and win:getLayer(li) or (win.layers and win.layers[li])
  if not (layer and layer.kind == "tile") then
    return nil
  end

  local item = win.get and win:get(col, row, li) or nil
  if not item then
    return nil
  end

  local bankIdx = tonumber(item._bankIndex) or tonumber(layer.bank) or tonumber(win.currentBank) or tonumber(li) or 1
  local logicalIndex = (row * (win.cols or 16)) + col

  return {
    win = win,
    layerIndex = li,
    layer = layer,
    col = col,
    row = row,
    item = item,
    sourceBank = bankIdx,
    tileIndex = normalizeTileIndex(item),
    logicalIndex = logicalIndex,
  }
end

function AppCoreController:_buildChrBankTileContextMenuItems(context)
  local items = {
    {
      text = "Undo pixel edits",
      enabled = RevertTilePixelsController.canRevertContext(self, context),
      callback = function()
        local ok, err = RevertTilePixelsController.revertForContext(self, context)
        if ok then
          self:setStatus("Reverted tile pixels to original CHR")
        else
          self:setStatus(tostring(err or "Could not revert tile pixels"))
        end
      end,
    },
  }
  return items
end

function AppCoreController:showPpuTileContextMenu(win, layerIndex, col, row, x, y)
  if not (self.ppuTileContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = self:_buildPpuTileContext(win, layerIndex, col, row)
  if not context then
    return false
  end

  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, self:_buildPpuTileContextMenuItems(context))
  return self.ppuTileContextMenu:isVisible()
end

function AppCoreController:showSelectInChrContextMenu(win, layerIndex, col, row, itemIndex, x, y)
  if not (self.ppuTileContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = self:_buildSelectInChrContext(win, layerIndex, col, row, itemIndex)
  if not context then
    return false
  end

  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, self:_buildSelectInChrContextMenuItems(context))
  return self.ppuTileContextMenu:isVisible()
end

function AppCoreController:showChrBankTileContextMenu(win, col, row, x, y)
  if not (self.ppuTileContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = self:_buildChrBankTileContext(win, col, row)
  if not context then
    return false
  end

  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, self:_buildChrBankTileContextMenuItems(context))
  return self.ppuTileContextMenu:isVisible()
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
  local message = tostring(text)
  self.statusText = message
  self.lastEventText = message
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

  local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
  local topBarCandidate = AppTopToolbarController.getTooltipAt(self, x, y)
  if topBarCandidate then
    return topBarCandidate
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

local function parseNonNegativeInteger(text, label)
  local trimmed = tostring(text or ""):match("^%s*(.-)%s*$")
  label = label or "Value"
  if trimmed == "" then
    return nil, string.format("%s is required", label)
  end

  local base = 10
  local normalized = trimmed
  if trimmed:match("^0[xX][0-9A-Fa-f]+$") then
    base = 16
    normalized = trimmed:sub(3)
  elseif not trimmed:match("^%d+$") then
    return nil, string.format("%s must be a whole number", label)
  end

  local value = tonumber(normalized, base)
  if type(value) ~= "number" then
    return nil, string.format("%s must be a whole number", label)
  end

  value = math.floor(value)
  if value < 0 then
    return nil, string.format("%s must be zero or greater", label)
  end

  return value
end

local function parsePositiveDecimalInteger(text, label)
  local trimmed = tostring(text or ""):match("^%s*(.-)%s*$")
  label = label or "Value"
  if trimmed == "" then
    return nil, string.format("%s is required", label)
  end
  if not trimmed:match("^%d+$") then
    return nil, string.format("%s must be a decimal whole number", label)
  end

  local value = tonumber(trimmed, 10)
  if type(value) ~= "number" then
    return nil, string.format("%s must be a decimal whole number", label)
  end

  value = math.floor(value)
  if value < 1 then
    return nil, string.format("%s must be 1 or greater", label)
  end

  return value
end

local function parsePageNumber(text)
  local value, err = parsePositiveDecimalInteger(text, "Page")
  if not value then
    return nil, err
  end
  if value ~= 1 and value ~= 2 then
    return nil, "Page must be 1 or 2"
  end
  return value
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
      local beforeTitle = targetWindow.title or ""
      targetWindow.title = newTitle
      if beforeTitle ~= newTitle and self.undoRedo and self.undoRedo.addWindowRenameEvent then
        self.undoRedo:addWindowRenameEvent({
          type = "window_rename",
          win = targetWindow,
          beforeTitle = beforeTitle,
          afterTitle = newTitle,
        })
      end
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
      local beforeState = captureRomPaletteAddressUndoState(targetWindow)
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
      if self.invalidatePpuFrameLayersAffectedByPaletteWin then
        self:invalidatePpuFrameLayersAffectedByPaletteWin(targetWindow)
      end
      if self.undoRedo and self.undoRedo.addRomPaletteAddressEvent then
        self.undoRedo:addRomPaletteAddressEvent({
          type = "rom_palette_address",
          win = targetWindow,
          beforeState = beforeState,
          afterState = captureRomPaletteAddressUndoState(targetWindow),
        })
      end
      return true
    end,
  })

  return true
end

local function getPpuNametableLayer(win)
  if not (win and win.layers) then return nil end
  local activeIndex = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  local activeLayer = win.layers[activeIndex]
  if activeLayer and activeLayer.kind ~= "sprite" then
    return activeLayer, activeIndex
  end
  for _, layer in ipairs(win.layers) do
    if layer and layer.kind ~= "sprite" then
      return layer
    end
  end
  return nil
end

parsePatternRangeBounds = function(range)
  if type(range) ~= "table" then
    return nil, nil
  end
  local tileRange = type(range.tileRange) == "table" and range.tileRange or nil
  local from = range.from
  local to = range.to
  if from == nil and tileRange then
    from = tileRange.from
  end
  if to == nil and tileRange then
    to = tileRange.to
  end
  from = math.floor(tonumber(from) or -1)
  to = math.floor(tonumber(to) or -1)
  if from < 0 or from > 255 or to < 0 or to > 255 or to < from then
    return nil, nil
  end
  return from, to
end

patternTableLogicalSize = function(patternTable)
  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
    return 0, "patternTable.ranges is missing"
  end
  local total = 0
  for i, range in ipairs(patternTable.ranges) do
    local from, to = parsePatternRangeBounds(range)
    if from == nil or to == nil then
      return total, string.format("patternTable.ranges[%d] has invalid from/to", i)
    end
    total = total + (to - from + 1)
  end
  return total, nil
end

local function isNametableLayerRenderReady(layer)
  if type(layer) ~= "table" then
    return false, "Missing nametable layer"
  end
  if type(layer.nametableStartAddr) ~= "number" then
    return false, "nametableStartAddr is not set"
  end
  if type(layer.nametableEndAddr) ~= "number" then
    return false, "nametableEndAddr is not set"
  end
  local total, err = patternTableLogicalSize(layer.patternTable)
  if err then
    return false, err
  end
  if total ~= 256 then
    return false, string.format("patternTable ranges must add up to 256 tiles (got %d)", total)
  end
  return true, nil
end

local function hydrateNametableLayerIfReady(app, win, layer, layerIndex)
  local ready, reason = isNametableLayerRenderReady(layer)
  if not ready then
    if layer then
      layer.items = {}
    end
    if win and win.invalidateNametableLayerCanvas then
      win:invalidateNametableLayerCanvas(layerIndex)
    end
    return false, reason
  end

  local state = app and app.appEditState or {}
  local romRaw = state.romRaw
  if type(romRaw) ~= "string" or romRaw == "" then
    return false, "Open a ROM before loading a PPU frame range"
  end

  if type(layer.userDefinedAttrs) ~= "string"
    and type(win.nametableAttrBytes) == "table"
    and #win.nametableAttrBytes >= 64
  then
    local hexParts = {}
    for i = 1, 64 do
      local byteVal = tonumber(win.nametableAttrBytes[i]) or 0x00
      if byteVal < 0 then byteVal = 0x00 elseif byteVal > 255 then byteVal = 255 end
      hexParts[i] = string.format("%02x", byteVal)
    end
    layer.userDefinedAttrs = table.concat(hexParts, "")
  end

  local tilesPool = state.tilesPool
  local ok, err = NametableTilesController.hydrateWindowNametable(win, layer, {
    romRaw = romRaw,
    tilesPool = tilesPool,
    ensureTiles = function(bank)
      if not (state.chrBanksBytes and state.chrBanksBytes[bank]) then
        return false
      end
      BankViewController.ensureBankTiles(state, bank)
      return true
    end,
    nametableStartAddr = layer.nametableStartAddr,
    nametableEndAddr = layer.nametableEndAddr,
    patternTable = layer.patternTable,
    tileSwaps = layer.tileSwaps,
    userDefinedAttrs = layer.userDefinedAttrs,
    codec = layer.codec,
    reportErrors = false,
  })
  if not ok then
    return false, err or "Failed to load PPU frame range"
  end
  return true, nil
end

getPpuPatternTableTargetLayer = function(win)
  if not (win and win.kind == "ppu_frame" and win.layers) then
    return nil, nil
  end
  local fallbackLayer, fallbackIndex = nil, nil
  for i, layer in ipairs(win.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      if not fallbackLayer then
        fallbackLayer, fallbackIndex = layer, i
      end
      if type(layer.nametableStartAddr) == "number" and type(layer.nametableEndAddr) == "number" then
        return layer, i
      end
    end
  end
  return fallbackLayer, fallbackIndex
end

buildPatternTableMapAllowPartial = function(patternTable)
  local map = {}

  if type(patternTable) ~= "table" or type(patternTable.ranges) ~= "table" then
    return map, nil
  end

  local logicalIndex = 0
  for i, range in ipairs(patternTable.ranges) do
    local from, to = parsePatternRangeBounds(range)
    if from == nil or to == nil then
      return nil, string.format("patternTable.ranges[%d] has invalid from/to", i)
    end
    local bank = math.max(1, math.floor(tonumber(range.bank) or -1))
    local page = math.floor(tonumber(range.page) or -1)
    if bank < 1 then
      return nil, string.format("patternTable.ranges[%d] is missing bank", i)
    end
    if page < 1 then
      return nil, string.format("patternTable.ranges[%d] is missing page", i)
    end
    if page < 1 then page = 1 elseif page > 2 then page = 2 end
    for src = from, to do
      if logicalIndex > 255 then
        return nil, "patternTable ranges exceed 256 tiles"
      end
      map[logicalIndex] = {
        bank = bank,
        page = page,
        tileByte = src,
        tileIndex = (page == 2) and (256 + src) or src,
      }
      logicalIndex = logicalIndex + 1
    end
  end
  return map, nil
end

local function copyNumberArray(values)
  local out = {}
  if type(values) ~= "table" then
    return out
  end
  for i = 1, #values do
    out[i] = values[i]
  end
  return out
end

snapshotPpuFrameRangeState = function(win, layerIndex)
  if not (win and win.kind == "ppu_frame") then
    return nil
  end

  local layer, resolvedLayerIndex = getPpuNametableLayer(win)
  local li = layerIndex or resolvedLayerIndex or 1
  layer = (win.getLayer and win:getLayer(li)) or layer
  if not layer then
    return nil
  end

  return {
    win = win,
    layerIndex = li,
    cols = win.cols,
    rows = win.rows,
    nametableStart = win.nametableStart,
    nametableBytes = copyNumberArray(win.nametableBytes),
    nametableAttrBytes = copyNumberArray(win.nametableAttrBytes),
    originalNametableBytes = copyNumberArray(win._originalNametableBytes),
    originalNametableAttrBytes = copyNumberArray(win._originalNametableAttrBytes),
    originalCompressedBytes = copyNumberArray(win._originalCompressedBytes),
    tileSwapsMap = TableUtils.deepcopy(win._tileSwaps),
    originalTotalByteNumber = win.originalTotalByteNumber,
    nametableOriginalSize = win._nametableOriginalSize,
    nametableCompressedSize = win._nametableCompressedSize,
    layerState = {
      kind = layer.kind,
      mode = layer.mode,
      codec = layer.codec,
      nametableStartAddr = layer.nametableStartAddr,
      nametableEndAddr = layer.nametableEndAddr,
      noOverflowSupported = layer.noOverflowSupported,
      patternTable = TableUtils.deepcopy(layer.patternTable),
      attrMode = layer.attrMode,
      tileSwaps = TableUtils.deepcopy(layer.tileSwaps),
    },
  }
end

didPpuFrameRangeSettingsChange = function(beforeState, afterState)
  local beforeLayer = beforeState and beforeState.layerState or nil
  local afterLayer = afterState and afterState.layerState or nil
  if not (beforeLayer and afterLayer) then
    return false
  end

  return beforeLayer.nametableStartAddr ~= afterLayer.nametableStartAddr
    or beforeLayer.nametableEndAddr ~= afterLayer.nametableEndAddr
end

local function getFirstPpuSpriteLayer(win)
  if not (win and win.getSpriteLayers) then return nil, nil end
  local spriteLayers = win:getSpriteLayers() or {}
  local first = spriteLayers[1]
  if not first then
    return nil, nil
  end
  return first.layer, first.index
end

local function getTargetSpriteLayerForAddSprite(win)
  if not win then
    return nil, nil
  end

  if win.kind == "ppu_frame" then
    return getFirstPpuSpriteLayer(win)
  end

  if win.kind == "oam_animation" then
    local activeIndex = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
    local activeLayer = win.layers and win.layers[activeIndex] or nil
    if activeLayer and activeLayer.kind == "sprite" then
      return activeLayer, activeIndex
    end

    if win.layers then
      for i, layer in ipairs(win.layers) do
        if layer and layer.kind == "sprite" then
          return layer, i
        end
      end
    end
  end

  return nil, nil
end

local function getInitialPpuSpriteModalValues(app)
  local state = app and app.appEditState or {}
  local bankWindow = app and app.winBank or nil
  local bankNumber = (bankWindow and bankWindow.currentBank) or state.currentBank or 1
  local tileNumber = 0

  if bankWindow and bankWindow.getSelected and bankWindow.get then
    local col, row, layerIndex = bankWindow:getSelected()
    if type(col) == "number" and type(row) == "number" then
      local selectedTile = bankWindow:get(col, row, layerIndex)
      if selectedTile and type(selectedTile.index) == "number" then
        tileNumber = math.max(0, math.floor(selectedTile.index))
      end
    end
  end

  return tostring(bankNumber), tostring(tileNumber), ""
end

function AppCoreController:showPpuFrameSpriteLayerModeModal(win, opts)
  if not (self.ppuFrameSpriteLayerModeModal and win and win.kind == "ppu_frame") then
    return false
  end

  opts = opts or {}
  self.ppuFrameSpriteLayerModeModal:show({
    title = opts.title or "Create sprite layer",
    window = win,
    initialMode = opts.initialMode or "8x8",
    onConfirm = opts.onConfirm,
    onCancel = opts.onCancel,
  })
  return true
end

function AppCoreController:showPpuFrameAddSpriteModal(win)
  if not (self.ppuFrameAddSpriteModal and win and (win.kind == "ppu_frame" or win.kind == "oam_animation")) then
    return false
  end

  local initialBank, initialTile, initialOamStart = getInitialPpuSpriteModalValues(self)

  self.ppuFrameAddSpriteModal:show({
    title = "Add sprite",
    window = win,
    initialBank = initialBank,
    initialTile = initialTile,
    initialOamStart = initialOamStart,
    onConfirm = function(bankText, tileText, oamStartText, targetWindow)
      local spriteLayer, spriteLayerIndex = getTargetSpriteLayerForAddSprite(targetWindow)
      if not spriteLayer then
        local message = "PPU frame window is missing a sprite layer"
        if targetWindow and targetWindow.kind == "oam_animation" then
          message = "OAM animation window is missing a sprite layer"
        end
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local bankNumber, bankErr = parseNonNegativeInteger(bankText, "Bank number")
      if not bankNumber then
        self:setStatus(bankErr)
        self:showToast("error", bankErr)
        return false
      end
      if bankNumber < 1 then
        local message = "Bank number must be 1 or greater"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local tileNumber, tileErr = parseNonNegativeInteger(tileText, "Tile number")
      if not tileNumber then
        self:setStatus(tileErr)
        self:showToast("error", tileErr)
        return false
      end

      local oamStart, oamErr = parseHexAddress(oamStartText)
      if not oamStart then
        self:setStatus(oamErr)
        self:showToast("error", oamErr)
        return false
      end

      local state = self.appEditState or {}
      local romRaw = state.romRaw
      local tilesPool = state.tilesPool
      if type(romRaw) ~= "string" or romRaw == "" then
        local message = "Open a ROM before adding an OAM-backed sprite"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      if not (tilesPool and tilesPool[bankNumber]) then
        local message = string.format("CHR bank %d is not available", bankNumber)
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      if not tilesPool[bankNumber][tileNumber] then
        local message = string.format("Tile %d is not available in CHR bank %d", tileNumber, bankNumber)
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      spriteLayer.items = spriteLayer.items or {}
      table.insert(spriteLayer.items, {
        bank = bankNumber,
        startAddr = oamStart,
        tile = tileNumber,
      })

      SpriteController.hydrateSpriteLayer(spriteLayer, {
        romRaw = romRaw,
        tilesPool = tilesPool,
        appEditState = state,
        keepWorld = false,
      })

      local itemIndex = #spriteLayer.items
      spriteLayer.selectedSpriteIndex = itemIndex
      spriteLayer.multiSpriteSelection = nil
      spriteLayer.multiSpriteSelectionOrder = nil
      spriteLayer.hoverSpriteIndex = nil

      if targetWindow.setActiveLayerIndex then
        targetWindow:setActiveLayerIndex(spriteLayerIndex)
      else
        targetWindow.activeLayer = spriteLayerIndex
      end

      self:markUnsaved("sprite_move")
      self:setStatus(string.format(
        "Added sprite from OAM 0x%06X on bank %d tile %d",
        oamStart,
        bankNumber,
        tileNumber
      ))
      return true
    end,
  })

  return true
end

function AppCoreController:_buildOamSpriteEmptySpaceContext(win, layerIndex)
  if not (win and win.kind == "oam_animation" and type(layerIndex) == "number") then
    return nil
  end

  local layer = win.getLayer and win:getLayer(layerIndex) or (win.layers and win.layers[layerIndex])
  if not (layer and layer.kind == "sprite") then
    return nil
  end

  return {
    win = win,
    layerIndex = layerIndex,
    layer = layer,
  }
end

function AppCoreController:_buildOamSpriteEmptySpaceContextMenuItems(context)
  return {
    {
      text = "Add new sprite",
      enabled = context ~= nil,
      callback = function()
        if not context then
          return false
        end
        return self:showPpuFrameAddSpriteModal(context.win)
      end,
    },
  }
end

function AppCoreController:showOamSpriteEmptySpaceContextMenu(win, layerIndex, x, y)
  if not (self.ppuTileContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end

  local context = self:_buildOamSpriteEmptySpaceContext(win, layerIndex)
  if not context then
    return false
  end

  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, self:_buildOamSpriteEmptySpaceContextMenuItems(context))
  return self.ppuTileContextMenu:isVisible()
end

function AppCoreController:showPpuFrameRangeModal(win)
  if not (self.ppuFrameRangeModal and win and win.kind == "ppu_frame") then
    return false
  end

  local layer = getPpuNametableLayer(win)
  local initialStart = (layer and type(layer.nametableStartAddr) == "number")
    and string.format("0x%06X", layer.nametableStartAddr) or ""
  local initialEnd = (layer and type(layer.nametableEndAddr) == "number")
    and string.format("0x%06X", layer.nametableEndAddr) or ""
  self.ppuFrameRangeModal:show({
    title = "Set tile range",
    window = win,
    initialStartAddress = initialStart,
    initialEndAddress = initialEnd,
    onConfirm = function(startText, endText, targetWindow)
      local startAddr, startErr = parseHexAddress(startText)
      if not startAddr then
        self:setStatus(startErr)
        self:showToast("error", startErr)
        return false
      end

      local endAddr, endErr = parseHexAddress(endText)
      if not endAddr then
        self:setStatus(endErr)
        self:showToast("error", endErr)
        return false
      end

      if endAddr < startAddr then
        local message = "End address must be greater than or equal to start address"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local targetLayer, targetLayerIndex = getPpuNametableLayer(targetWindow)
      if not targetLayer then
        local message = "PPU frame window is missing a tile layer"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      local beforeRangeState = snapshotPpuFrameRangeState(targetWindow, targetLayerIndex)

      targetLayer.codec = targetLayer.codec or "konami"
      targetLayer.nametableStartAddr = startAddr
      targetLayer.nametableEndAddr = endAddr
      local hydrated, hydrateErr = hydrateNametableLayerIfReady(self, targetWindow, targetLayer, targetLayerIndex)
      if not hydrated and targetWindow.invalidateNametableLayerCanvas then
        targetWindow:invalidateNametableLayerCanvas(targetLayerIndex)
      end
      if targetWindow.syncNametableLayerMetadata then
        targetWindow:syncNametableLayerMetadata()
      end
      if targetWindow.specializedToolbar and targetWindow.specializedToolbar.updateIcons then
        targetWindow.specializedToolbar:updateIcons()
      end
      local afterRangeState = snapshotPpuFrameRangeState(targetWindow, targetLayerIndex)
      if self.undoRedo and self.undoRedo.addPpuFrameRangeEvent
        and didPpuFrameRangeSettingsChange(beforeRangeState, afterRangeState)
      then
        self.undoRedo:addPpuFrameRangeEvent({
          type = "ppu_frame_range",
          win = targetWindow,
          layerIndex = targetLayerIndex,
          beforeState = beforeRangeState,
          afterState = afterRangeState,
        })
      end

      if hydrated then
        self:setStatus(string.format("Set nametable address range 0x%06X-0x%06X", startAddr, endAddr))
      else
        self:setStatus(string.format(
          "Set nametable address range 0x%06X-0x%06X (waiting: %s)",
          startAddr,
          endAddr,
          tostring(hydrateErr or "incomplete setup")
        ))
      end
      return true
    end,
  })

  return true
end

function AppCoreController:showPpuFramePatternRangeModal(win)
  if not (self.ppuFramePatternRangeModal and win and win.kind == "ppu_frame") then
    return false
  end

  local targetLayer = getPpuPatternTableTargetLayer(win)
  if not targetLayer then
    self:setStatus("PPU frame window is missing a target tile layer")
    self:showToast("error", "PPU frame window is missing a target tile layer")
    return false
  end
  local existingPatternTable = type(targetLayer.patternTable) == "table" and targetLayer.patternTable or {}
  local existingRanges = type(existingPatternTable.ranges) == "table" and existingPatternTable.ranges or {}

  local initialBank = "1"
  local initialPage = 1
  local initialFrom = "0"
  local initialTo = "255"
  local lastRange = existingRanges[#existingRanges]
  if type(lastRange) == "table" then
    initialBank = tostring(tonumber(lastRange.bank) or tonumber(initialBank) or 1)
    initialPage = tonumber(lastRange.page) or initialPage
    local lastFrom, lastTo = parsePatternRangeBounds(lastRange)
    if lastFrom ~= nil and lastTo ~= nil then
      initialFrom = tostring(lastFrom)
      initialTo = tostring(lastTo)
    end
  end

  self.ppuFramePatternRangeModal:show({
    title = "Add tile range",
    window = win,
    initialBank = initialBank,
    initialPage = initialPage,
    initialFrom = initialFrom,
    initialTo = initialTo,
    onConfirm = function(bankText, pageValue, fromText, toText, targetWindow)
      local layer, layerIndex = getPpuPatternTableTargetLayer(targetWindow)
      if not layer then
        local message = "PPU frame window is missing a target tile layer"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local bankIndex, bankErr = parsePositiveDecimalInteger(bankText, "Bank")
      if not bankIndex then
        self:setStatus(bankErr)
        self:showToast("error", bankErr)
        return false
      end
      local pageIndex = math.floor(tonumber(pageValue) or 1)
      if pageIndex ~= 1 and pageIndex ~= 2 then
        local message = "Page must be 1 or 2"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      local fromTile, fromErr = parseNonNegativeInteger(fromText, "From")
      if not fromTile then
        self:setStatus(fromErr)
        self:showToast("error", fromErr)
        return false
      end
      local toTile, toErr = parseNonNegativeInteger(toText, "To")
      if not toTile then
        self:setStatus(toErr)
        self:showToast("error", toErr)
        return false
      end
      if fromTile > 255 or toTile > 255 then
        local message = "From/To must be between 0 and 255"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      if toTile < fromTile then
        local message = "To must be greater than or equal to From"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local beforeState = snapshotPpuFrameRangeState and snapshotPpuFrameRangeState(targetWindow, layerIndex) or nil
      layer.patternTable = type(layer.patternTable) == "table" and layer.patternTable or {}
      layer.patternTable.ranges = type(layer.patternTable.ranges) == "table" and layer.patternTable.ranges or {}
      local currentTotal = patternTableLogicalSize(layer.patternTable) or 0
      local nextTotal = currentTotal + (toTile - fromTile + 1)
      if nextTotal > 256 then
        local message = string.format("Range exceeds 256 logical tiles (%d/256)", nextTotal)
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      layer.patternTable.ranges[#layer.patternTable.ranges + 1] = {
        bank = bankIndex,
        page = pageIndex,
        tileRange = {
          from = fromTile,
          to = toTile,
        },
      }
      local hydrated, hydrateErr = hydrateNametableLayerIfReady(self, targetWindow, layer, layerIndex)
      if not hydrated and targetWindow.invalidateNametableLayerCanvas then
        targetWindow:invalidateNametableLayerCanvas(layerIndex)
      end
      self:_ensurePpuPatternTableReferenceLayer({
        win = targetWindow,
        layer = layer,
        layerIndex = layerIndex,
      }, {
        keepActiveLayer = true,
      })

      local total = patternTableLogicalSize(layer.patternTable)
      if total == 256 then
        self:showToast("success", "Pattern table ranges complete (256/256).")
      end
      if targetWindow.specializedToolbar and targetWindow.specializedToolbar.updateIcons then
        targetWindow.specializedToolbar:updateIcons()
      end

      local afterState = snapshotPpuFrameRangeState and snapshotPpuFrameRangeState(targetWindow, layerIndex) or nil
      if self.undoRedo and self.undoRedo.addPpuFrameRangeEvent
        and didPpuFrameRangeSettingsChange(beforeState, afterState)
      then
        self.undoRedo:addPpuFrameRangeEvent({
          type = "ppu_frame_range",
          win = targetWindow,
          layerIndex = layerIndex,
          beforeState = beforeState,
          afterState = afterState,
        })
      end

      if hydrated then
        self:setStatus(string.format(
          "Added tile range [%d..%d] bank %d page %d (%d/256)",
          fromTile,
          toTile,
          bankIndex,
          pageIndex,
          tonumber(total) or 0
        ))
      else
        self:setStatus(string.format(
          "Added tile range [%d..%d] bank %d page %d (%d/256, waiting: %s)",
          fromTile,
          toTile,
          bankIndex,
          pageIndex,
          tonumber(total) or 0,
          tostring(hydrateErr or "incomplete setup")
        ))
      end
      return true
    end,
  })

  return true
end

function AppCoreController:applyPpuFrameRangeState(rangeState)
  if not (rangeState and rangeState.win and rangeState.win.kind == "ppu_frame") then
    return false
  end

  local win = rangeState.win
  local li = tonumber(rangeState.layerIndex) or select(2, getPpuNametableLayer(win)) or win.activeLayer or 1
  local layer = win.layers and win.layers[li] or nil
  local layerState = rangeState.layerState or nil
  if not (layer and layerState) then
    return false
  end

  win.cols = tonumber(rangeState.cols) or win.cols
  win.rows = tonumber(rangeState.rows) or win.rows
  win.nametableStart = rangeState.nametableStart
  win.nametableBytes = copyNumberArray(rangeState.nametableBytes)
  win.nametableAttrBytes = copyNumberArray(rangeState.nametableAttrBytes)
  win._originalNametableBytes = copyNumberArray(rangeState.originalNametableBytes)
  win._originalNametableAttrBytes = copyNumberArray(rangeState.originalNametableAttrBytes)
  win._originalCompressedBytes = copyNumberArray(rangeState.originalCompressedBytes)
  win._tileSwaps = TableUtils.deepcopy(rangeState.tileSwapsMap)
  win.originalTotalByteNumber = rangeState.originalTotalByteNumber
  win._nametableOriginalSize = rangeState.nametableOriginalSize
  win._nametableCompressedSize = rangeState.nametableCompressedSize

  layer.kind = layerState.kind
  layer.mode = layerState.mode
  layer.codec = layerState.codec
  layer.nametableStartAddr = layerState.nametableStartAddr
  layer.nametableEndAddr = layerState.nametableEndAddr
  layer.noOverflowSupported = layerState.noOverflowSupported
  layer.patternTable = TableUtils.deepcopy(layerState.patternTable)
  layer.attrMode = layerState.attrMode
  layer.tileSwaps = TableUtils.deepcopy(layerState.tileSwaps)
  layer.items = {}

  local state = self.appEditState or {}
  if state.chrBanksBytes and type(layer.patternTable) == "table" and type(layer.patternTable.ranges) == "table" then
    local ensuredBanks = {}
    for _, range in ipairs(layer.patternTable.ranges) do
      local bankIndex = type(range) == "table" and tonumber(range.bank) or nil
      if bankIndex and bankIndex >= 1 and not ensuredBanks[bankIndex] and state.chrBanksBytes[bankIndex] then
        ensuredBanks[bankIndex] = true
        BankViewController.ensureBankTiles(state, bankIndex)
      end
    end
  end

  if NametableTilesController.extractPaletteNumbersFromAttributes then
    NametableTilesController.extractPaletteNumbersFromAttributes(win, layer, win.cols, win.rows)
  end

  local hydrated, _ = hydrateNametableLayerIfReady(self, win, layer, li)
  if not hydrated and win.invalidateNametableLayerCanvas then
    win:invalidateNametableLayerCanvas(li)
  end

  if win.syncNametableLayerMetadata then
    win:syncNametableLayerMetadata()
  end
  if win.specializedToolbar and win.specializedToolbar.updateIcons then
    win.specializedToolbar:updateIcons()
  end

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

function AppCoreController:invalidatePpuFrameNametableTile(bankIdx, tileIndex)
  if not (self.wm and self.wm.getWindows) then
    return false
  end

  local bank = math.floor(tonumber(bankIdx) or -1)
  local tile = math.floor(tonumber(tileIndex) or -1)
  if bank < 1 or tile < 0 then
    return false
  end

  local touched = false
  local function layerMayReferenceBankTile(layer, targetBank, targetTileIndex)
    if type(layer) ~= "table" then
      return false
    end
    local pt = layer.patternTable
    if type(pt) ~= "table" or type(pt.ranges) ~= "table" then
      return false
    end

    local targetPage = (targetTileIndex >= 256) and 2 or 1
    local targetByte = targetTileIndex % 256
    for _, r in ipairs(pt.ranges) do
      if type(r) == "table" then
        local from = r.from
        local to = r.to
        local tr = r.tileRange
        if type(tr) == "table" then
          if from == nil then from = tr.from or tr.start end
          if to == nil then to = tr.to or tr["end"] end
        end
        if from == nil then from = r.start end
        if to == nil then to = r["end"] end
        from = math.floor(tonumber(from) or -1)
        to = math.floor(tonumber(to) or -1)
        local rangeBank = math.floor(tonumber(r.bank) or 1)
        local rangePage = math.floor(tonumber(r.page) or 1)
        if rangePage < 1 then rangePage = 1 elseif rangePage > 2 then rangePage = 2 end
        if rangeBank == targetBank and rangePage == targetPage and from >= 0 and to >= from and targetByte >= from and targetByte <= to then
          return true
        end
      end
    end
    return false
  end

  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win and win.kind == "ppu_frame" and win.layers and win.invalidateNametableLayerCanvas then
      for li, layer in ipairs(win.layers) do
        if layer and layer.kind ~= "sprite" and layer.items then
          local hitInItems = false
          for idx, item in pairs(layer.items) do
            if item and item.index == tile and tonumber(item._bankIndex) == bank then
              local z = (tonumber(idx) or 1) - 1
              local cols = win.cols or 32
              local col = z % cols
              local row = math.floor(z / cols)
              win:invalidateNametableLayerCanvas(li, col, row)
              touched = true
              hitInItems = true
            end
          end
          if not hitInItems and layerMayReferenceBankTile(layer, bank, tile) then
            -- Fallback for cached layers where edited tile currently has no item instances
            -- (for example after mapping changes or hidden/cleared cells); force full layer repaint.
            win:invalidateNametableLayerCanvas(li)
            touched = true
          end
        end
      end
    end
  end

  return touched
end

local function ppuLayerUsesPaletteWin(layer, paletteWin)
  if not (layer and layer.kind == "tile" and paletteWin) then
    return false
  end

  local pd = layer.paletteData
  if pd and pd.winId and paletteWin._id then
    return pd.winId == paletteWin._id
  end

  if paletteWin.kind == "palette" and paletteWin.activePalette == true then
    return not (pd and pd.items)
  end

  return false
end

function AppCoreController:invalidatePpuFramePaletteLayer(win, layerIndex)
  if not (win and win.kind == "ppu_frame" and win.layers and win.invalidateNametableLayerCanvas) then
    return false
  end

  local li = tonumber(layerIndex) or (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  local layer = win.layers[li]
  if not (layer and layer.kind == "tile") then
    return false
  end

  win:invalidateNametableLayerCanvas(li)
  return true
end

function AppCoreController:invalidatePpuFrameLayersAffectedByPaletteWin(paletteWin)
  if not (paletteWin and self.wm and self.wm.getWindows) then
    return false
  end

  local touched = false
  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win and win.kind == "ppu_frame" and win.layers and win.invalidateNametableLayerCanvas then
      for li, layer in ipairs(win.layers) do
        if ppuLayerUsesPaletteWin(layer, paletteWin) then
          win:invalidateNametableLayerCanvas(li)
          touched = true
        end
      end
    end
  end

  return touched
end

function AppCoreController:invalidateAllPpuFrameNametableCanvases()
  if not (self.wm and self.wm.getWindows) then
    return false
  end

  local touched = false
  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win and win.kind == "ppu_frame" and win.layers and win.invalidateNametableLayerCanvas then
      win._nametableLayerCanvas = {}
      for li, layer in ipairs(win.layers) do
        if layer and layer.kind == "tile" then
          win:invalidateNametableLayerCanvas(li)
          touched = true
        end
      end
    end
  end

  return touched
end

require("controllers.app.core_controller_save_settings")(AppCoreController)
require("controllers.app.core_controller_lifecycle")(AppCoreController)
require("controllers.app.core_controller_input")(AppCoreController)
require("controllers.app.core_controller_draw")(AppCoreController)

return AppCoreController
