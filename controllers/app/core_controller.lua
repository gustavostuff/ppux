local WindowController = require("controllers.window.window_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local BrushController = require("controllers.input_support.brush_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

local GenericActionsModal = require("user_interface.modals.generic_actions_modal")
local NewWindowModal = require("user_interface.modals.new_window_modal")
local PPUFrameAddSpriteModal = require("user_interface.modals.ppu_frame_add_sprite_modal")
local PPUFrameSpriteLayerModeModal = require("user_interface.modals.ppu_frame_sprite_layer_mode_modal")
local PPUFrameRangeModal = require("user_interface.modals.ppu_frame_range_modal")
local RenameWindowModal = require("user_interface.modals.rename_window_modal")
local RomPaletteAddressModal = require("user_interface.modals.rom_palette_address_modal")
local SaveOptionsModal = require("user_interface.modals.save_options_modal")
local QuitConfirmModal = require("user_interface.modals.quit_confirm_modal")
local SettingsModal = require("user_interface.modals.settings_modal")
local TextFieldDemoModal = require("user_interface.modals.text_field_demo_modal")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local SimpleLoadingScreen = require("controllers.app.simple_loading_screen")
local TooltipController = require("controllers.ui.tooltip_controller")
local ContextualMenuController = require("controllers.ui.contextual_menu_controller")
local UiScale = require("user_interface.ui_scale")
local UserInput = require("controllers.input")
local TableUtils = require("utils.table_utils")

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
    or (app.ppuFrameSpriteLayerModeModal and app.ppuFrameSpriteLayerModeModal:isVisible())
    or (app.ppuFrameAddSpriteModal and app.ppuFrameAddSpriteModal:isVisible())
    or (app.ppuFrameRangeModal and app.ppuFrameRangeModal:isVisible())
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
    app.newWindowModal,
    app.renameWindowModal,
    app.romPaletteAddressModal,
    app.ppuFrameSpriteLayerModeModal,
    app.ppuFrameAddSpriteModal,
    app.ppuFrameRangeModal,
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

  -- windows + manager
  self.wm = WindowController.new()
  self.winBank = nil

  self.genericActionsModal = GenericActionsModal.new()
  self.newWindowModal = NewWindowModal.new()
  self.renameWindowModal = RenameWindowModal.new()
  self.romPaletteAddressModal = RomPaletteAddressModal.new()
  self.ppuFrameSpriteLayerModeModal = PPUFrameSpriteLayerModeModal.new()
  self.ppuFrameAddSpriteModal = PPUFrameAddSpriteModal.new()
  self.ppuFrameRangeModal = PPUFrameRangeModal.new()
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
      buttonText = "Palette window",
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
      buttonText = "ROM Palette window",
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
      buttonText = "PPU Frame window",
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
      text = "Pattern Table Builder",
      buttonText = "Pattern Table Builder",
      callback = function(_, _, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createPatternTableBuilderWindow({
          title = windowTitle or "Pattern Table Builder",
        })
        recordWindowCreateUndo(self, win, prevFocusedWin)
        self:setStatus(string.format("Created %s", win.title))
      end
    },
    {
      text = "OAM animation",
      buttonText = "OAM animation",
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

  local sourceBank = tonumber(layer.bank) or tonumber(item._bankIndex) or 1

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

    return {
      win = win,
      layerIndex = layerIndex,
      layer = layer,
      col = col,
      row = row,
      item = item,
      tileIndex = normalizeTileIndex(item),
      sourceBank = tonumber(layer.bank) or tonumber(item._bankIndex) or 1,
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

function AppCoreController:_markPpuTileByteAsGlass(context)
  if not context then
    return false
  end

  local tilesPool = self.appEditState and self.appEditState.tilesPool or nil
  local win = context.win
  if win and win.setGlassTileByte then
    win:setGlassTileByte(context.byteVal, tilesPool, context.layerIndex)
  else
    context.layer.glassTileByte = context.byteVal
    context.layer.transparentTileByte = nil
  end

  self:setStatus(string.format("Marked nametable byte 0x%02X as glass tile", context.byteVal))
  return true
end

function AppCoreController:_clearPpuTileGlassByte(context)
  if not context then
    return false
  end

  local tilesPool = self.appEditState and self.appEditState.tilesPool or nil
  local win = context.win
  if win and win.clearGlassTileByte then
    win:clearGlassTileByte(tilesPool, context.layerIndex)
  else
    context.layer.glassTileByte = nil
    context.layer.transparentTileByte = nil
  end

  self:setStatus("Cleared glass tile byte")
  return true
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
  local currentGlassByte = nil
  if context and context.layer then
    if context.layer.glassTileByte ~= nil then
      currentGlassByte = clampByte(context.layer.glassTileByte)
    elseif context.layer.transparentTileByte ~= nil then
      currentGlassByte = clampByte(context.layer.transparentTileByte)
    end
  end

  return {
    {
      text = string.format("Mark 0x%02X as glass tile", context.byteVal or 0),
      enabled = context ~= nil,
      callback = function()
        self:_markPpuTileByteAsGlass(context)
      end,
    },
    {
      text = currentGlassByte and string.format("Clear glass tile (0x%02X)", currentGlassByte) or "Clear glass tile",
      enabled = currentGlassByte ~= nil,
      callback = function()
        self:_clearPpuTileGlassByte(context)
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
end

function AppCoreController:_buildSelectInChrContextMenuItems(context)
  return {
    {
      text = "Select in CHR/ROM window",
      enabled = context and context.tileIndex ~= nil,
      callback = function()
        self:_selectPpuTileInChrWindow(context)
      end,
    },
  }
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
  self.ppuTileContextMenu:showAt(x, y, self:_buildPpuTileContextMenuItems(context))
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
  self.ppuTileContextMenu:showAt(x, y, self:_buildSelectInChrContextMenuItems(context))
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

local function snapshotPpuFrameRangeState(win, layerIndex)
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
      bank = layer.bank,
      page = layer.page,
      nametableStartAddr = layer.nametableStartAddr,
      nametableEndAddr = layer.nametableEndAddr,
      noOverflowSupported = layer.noOverflowSupported,
      glassTileByte = layer.glassTileByte,
      transparentTileByte = layer.transparentTileByte,
      attrMode = layer.attrMode,
      tileSwaps = TableUtils.deepcopy(layer.tileSwaps),
    },
  }
end

local function didPpuFrameRangeSettingsChange(beforeState, afterState)
  local beforeLayer = beforeState and beforeState.layerState or nil
  local afterLayer = afterState and afterState.layerState or nil
  if not (beforeLayer and afterLayer) then
    return false
  end

  return beforeLayer.nametableStartAddr ~= afterLayer.nametableStartAddr
    or beforeLayer.nametableEndAddr ~= afterLayer.nametableEndAddr
    or beforeLayer.bank ~= afterLayer.bank
    or beforeLayer.page ~= afterLayer.page
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
  self.ppuTileContextMenu:showAt(x, y, self:_buildOamSpriteEmptySpaceContextMenuItems(context))
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
  local initialBank = tostring((layer and tonumber(layer.bank)) or 1)
  local initialPage = tostring((layer and tonumber(layer.page)) or 1)

  self.ppuFrameRangeModal:show({
    title = "Set tile range",
    window = win,
    initialStartAddress = initialStart,
    initialEndAddress = initialEnd,
    initialBank = initialBank,
    initialPage = initialPage,
    onConfirm = function(startText, endText, bankText, pageText, targetWindow)
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

      local bankIndex, bankErr = parsePositiveDecimalInteger(bankText, "Bank")
      if not bankIndex then
        self:setStatus(bankErr)
        self:showToast("error", bankErr)
        return false
      end

      local pageIndex, pageErr = parsePageNumber(pageText)
      if not pageIndex then
        self:setStatus(pageErr)
        self:showToast("error", pageErr)
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

      local state = self.appEditState or {}
      local tilesPool = state.tilesPool
      local romRaw = state.romRaw
      if type(romRaw) ~= "string" or romRaw == "" then
        local message = "Open a ROM before loading a PPU frame range"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      if not (state.chrBanksBytes and state.chrBanksBytes[bankIndex]) then
        local message = string.format("CHR bank %d is not available", bankIndex)
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      local currentBankIndex = bankIndex
      BankViewController.ensureBankTiles(state, currentBankIndex)
      targetLayer.codec = targetLayer.codec or "konami"
      local ok, err = NametableTilesController.hydrateWindowNametable(targetWindow, targetLayer, {
        romRaw = romRaw,
        tilesPool = tilesPool,
        ensureTiles = function(bank)
          if not (state.chrBanksBytes and state.chrBanksBytes[bank]) then
            return false
          end
          BankViewController.ensureBankTiles(state, bank)
          return true
        end,
        nametableStartAddr = startAddr,
        nametableEndAddr = endAddr,
        bankIndex = currentBankIndex,
        pageIndex = pageIndex,
        codec = targetLayer.codec,
        reportErrors = false,
      })
      if not ok then
        local message = err or "Failed to load PPU frame range"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end

      targetLayer.nametableStartAddr = startAddr
      targetLayer.nametableEndAddr = endAddr
      targetLayer.bank = currentBankIndex
      targetLayer.page = pageIndex
      if targetWindow.setBankPage then
        targetWindow:setBankPage(currentBankIndex, pageIndex, tilesPool)
      elseif targetWindow.refreshNametableVisuals then
        targetWindow:refreshNametableVisuals(tilesPool, targetLayerIndex)
      elseif targetWindow.invalidateNametableLayerCanvas then
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

      self:setStatus(string.format(
        "Loaded tile range 0x%06X-0x%06X (bank %d, page %d)",
        startAddr,
        endAddr,
        currentBankIndex,
        pageIndex
      ))
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
  layer.bank = layerState.bank
  layer.page = layerState.page
  layer.nametableStartAddr = layerState.nametableStartAddr
  layer.nametableEndAddr = layerState.nametableEndAddr
  layer.noOverflowSupported = layerState.noOverflowSupported
  layer.glassTileByte = layerState.glassTileByte
  layer.transparentTileByte = layerState.transparentTileByte
  layer.attrMode = layerState.attrMode
  layer.tileSwaps = TableUtils.deepcopy(layerState.tileSwaps)
  layer.items = {}

  local state = self.appEditState or {}
  local bankIndex = tonumber(layer.bank)
  if bankIndex and state.chrBanksBytes and state.chrBanksBytes[bankIndex] then
    BankViewController.ensureBankTiles(state, bankIndex)
  end

  if NametableTilesController.extractPaletteNumbersFromAttributes then
    NametableTilesController.extractPaletteNumbersFromAttributes(win, layer, win.cols, win.rows)
  end

  local tilesPool = state.tilesPool
  if win.refreshNametableVisuals then
    win:refreshNametableVisuals(tilesPool, li)
  elseif win.invalidateNametableLayerCanvas then
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
  for _, win in ipairs(self.wm:getWindows() or {}) do
    if win and win.kind == "ppu_frame" and win.layers and win.invalidateNametableLayerCanvas then
      for li, layer in ipairs(win.layers) do
        if layer and layer.kind ~= "sprite" and tonumber(layer.bank) == bank and layer.items then
          for idx, item in pairs(layer.items) do
            if item and item.index == tile and tonumber(item._bankIndex) == bank then
              local z = (tonumber(idx) or 1) - 1
              local cols = win.cols or 32
              local col = z % cols
              local row = math.floor(z / cols)
              win:invalidateNametableLayerCanvas(li, col, row)
              touched = true
            end
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
