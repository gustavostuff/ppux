-- App core: window manager, modals, ROM/edit state, and wiring into feature modules.
-- Large method groups live in core_controller_*.lua (same pattern as save_settings / lifecycle / draw / input).

local WindowController = require("controllers.window.window_controller")
local UndoRedoController = require("controllers.input_support.undo_redo_controller")

local GenericActionsModal = require("user_interface.modals.generic_actions_modal")
local NewWindowTypeModal = require("user_interface.modals.new_window_type_modal")
local NewWindowModal = require("user_interface.modals.new_window_modal")
local OpenProjectModal = require("user_interface.modals.open_project_modal")
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
local TooltipController = require("controllers.ui.tooltip_controller")
local ContextualMenuController = require("controllers.ui.contextual_menu_controller")
local UiScale = require("user_interface.ui_scale")

local AppCoreController = {}
AppCoreController.__index = AppCoreController

function AppCoreController.new()
  local self = setmetatable({}, AppCoreController)

  -- app state
  self.statusText = "Drop an .nes ROM or open an existing project"
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

  self.chrCanvasOnlyWindow = nil
  self.chrCanvasOnlyScrollY = 0
  self.chrCanvasOnlyToolbarX = nil
  self.chrCanvasOnlyToolbarY = nil

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
  self.lastOpenProjectDir = nil
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
  self.openProjectModal = OpenProjectModal.new()
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
    animation_timeline_change = true,
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

require("controllers.app.core_controller_window_ops")(AppCoreController)
require("controllers.app.core_controller_ppu_chr_menus")(AppCoreController)
require("controllers.app.core_controller_status_tooltips")(AppCoreController)
require("controllers.app.core_controller_modals_input")(AppCoreController)
require("controllers.app.core_controller_ppu_frame")(AppCoreController)
require("controllers.app.core_controller_invalidation")(AppCoreController)

require("controllers.app.core_controller_save_settings")(AppCoreController)
require("controllers.app.core_controller_lifecycle")(AppCoreController)
require("controllers.app.core_controller_input")(AppCoreController)
require("controllers.app.core_controller_draw")(AppCoreController)

return AppCoreController
