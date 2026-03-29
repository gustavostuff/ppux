-- ============================================================================
-- Keyboard Input Handler
-- ============================================================================

local DebugController = require("controllers.dev.debug_controller")
local KeyboardArtActionsController = require("controllers.input.keyboard_art_actions_controller")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
local KeyboardDebugController = require("controllers.input.keyboard_debug_controller")
local KeyboardEditToggleController = require("controllers.input.keyboard_edit_toggle_controller")
local KeyboardModifierHintController = require("controllers.input.keyboard_modifier_hint_controller")
local KeyboardWindowShortcutsController = require("controllers.input.keyboard_window_shortcuts_controller")
local KeyboardNavigationController = require("controllers.input.keyboard_navigation_controller")
local KeyboardSelectionActionsController = require("controllers.input.keyboard_selection_actions_controller")

local M = {}

local ctx
local utils = {}

local globalShortcutHandlers = {
  { name = "window_scaling", fn = function(key, _, appCoreControllerRef) return KeyboardWindowShortcutsController.handleWindowScaling(ctx, utils, key, appCoreControllerRef) end },
  { name = "cascade", fn = function(key) return KeyboardWindowShortcutsController.handleCascade(ctx, utils, key) end },
  { name = "fullscreen", fn = function(key) return KeyboardWindowShortcutsController.handleFullscreen(ctx, utils, key) end },
  { name = "mode_switch", fn = function(key) return KeyboardWindowShortcutsController.handleModeSwitch(ctx, key) end },
  { name = "space_highlight_toggle", fn = function(key) return KeyboardWindowShortcutsController.handleSpaceHighlightToggle(ctx, utils, key) end },
}

local focusHandlers = {
  { name = "pixel_offset", fn = function(key, focus) return KeyboardArtActionsController.handlePixelOffset(ctx, utils, key, focus) end },
  { name = "inactive_layer_opacity", fn = function(key, focus) return KeyboardNavigationController.handleInactiveLayerOpacity(ctx, utils, key, focus) end },
  { name = "window_zoom", fn = function(key) return KeyboardWindowShortcutsController.handleWindowZoom(ctx, utils, key) end },
  { name = "grid_toggle", fn = function(key, focus) return KeyboardWindowShortcutsController.handleGridToggleInWindow(ctx, utils, key, focus) end },
  { name = "animation_delay_adjust", fn = function(key, focus) return KeyboardNavigationController.handleAnimationDelayAdjust(ctx, utils, key, focus) end },
  { name = "tile_rotation", fn = function(key, focus) return KeyboardArtActionsController.handleTileRotation(ctx, utils, key, focus) end }, -- before palette keys
  { name = "palette_keys", fn = function(key, focus) return KeyboardNavigationController.handlePaletteKeys(ctx, utils, key, focus) end },
  { name = "tile_selection_navigation", fn = function(key, focus) return KeyboardNavigationController.handleTileSelectionNavigation(ctx, utils, key, focus) end },
  { name = "layer_navigation", fn = function(key, focus) return KeyboardNavigationController.handleLayerNavigation(ctx, utils, key, focus) end },
  { name = "chr_bank_keys", fn = function(key, focus) return KeyboardNavigationController.handleChrBankKeys(ctx, utils, key, focus) end },
  { name = "animation_window_keys", fn = function(key, focus) return KeyboardNavigationController.handleAnimationWindowKeys(ctx, key, focus) end },
  { name = "edit_mode_keys", fn = function(key) return KeyboardEditToggleController.handleEditModeKeys(ctx, utils, key) end },
  { name = "copy_selection", fn = function(key, focus) return KeyboardClipboardController.handleCopySelection(ctx, utils, key, focus) end },
  { name = "paste_selection", fn = function(key, focus) return KeyboardClipboardController.handlePasteSelection(ctx, utils, key, focus) end },
  { name = "select_all", fn = function(key, focus) return KeyboardSelectionActionsController.handleSelectAll(ctx, utils, key, focus) end },
  { name = "palette_number_assignment", fn = function(key, focus, appCoreControllerRef) return KeyboardArtActionsController.handlePaletteNumberAssignment(ctx, key, focus, appCoreControllerRef.appEditState) end },
  { name = "attr_mode_toggle", fn = function(key, focus) return KeyboardEditToggleController.handleAttrModeToggle(ctx, key, focus) end },
  { name = "shader_toggle", fn = function(key, focus) return KeyboardEditToggleController.handleShaderToggle(ctx, key, focus) end },
  { name = "sprite_mirror", fn = function(key, focus) return KeyboardSelectionActionsController.handleSpriteMirror(ctx, key, focus) end },
  { name = "delete_key", fn = function(key, focus) return KeyboardSelectionActionsController.handleDeleteKey(ctx, key, focus) end },
  { name = "undo_redo", fn = function(key) return KeyboardEditToggleController.handleUndoRedo(ctx, utils, key) end },
}

local function fmtFocus(focus)
  if not focus then return "nil" end
  return string.format("%s:%s", tostring(focus.kind or "?"), tostring(focus._id or focus.title or "?"))
end

local function runFirstTrue(groupName, handlers, key, focus, appCoreControllerRef)
  for i = 1, #handlers do
    local h = handlers[i]
    if h.fn(key, focus, appCoreControllerRef) then
      DebugController.log("debug", "INPUT_ROUTE", "key=%s group=%s handler=%s focus=%s", tostring(key), tostring(groupName), tostring(h.name), fmtFocus(focus))
      return true
    end
  end
  return false
end

function M.setup(context, utilities)
  ctx = context
  utils = utilities or {}
  KeyboardClipboardController.reset()
  KeyboardModifierHintController.reset()
end

-- ===== Keyboard =====
function M.keypressed(key, AppCoreControllerRef)
  if KeyboardModifierHintController.isModifierKey(key) then
    DebugController.log("debug", "INPUT_ROUTE", "key=%s route=modifier_hint", tostring(key))
    KeyboardModifierHintController.updateStatus(ctx, utils)
    local mode = ctx and ctx.getMode and ctx.getMode() or "tile"
    local isEditToolHoldKey = (key == "f" or key == "g")
    if (not isEditToolHoldKey) or mode == "edit" then
      return
    end
  end

  if key == "escape" then
    DebugController.log("debug", "INPUT_ROUTE", "key=%s route=escape_quit", tostring(key))
    love.event.quit()
    return
  end

  if KeyboardDebugController.handleDebugKeys(ctx, utils, key) then
    DebugController.log("debug", "INPUT_ROUTE", "key=%s route=debug_keys", tostring(key))
    return
  end

  if runFirstTrue("global", globalShortcutHandlers, key, nil, AppCoreControllerRef) then
    return
  end

  local focus = ctx.getFocus()
  if runFirstTrue("focus", focusHandlers, key, focus, AppCoreControllerRef) then
    return
  end

  DebugController.log("debug", "INPUT_ROUTE", "key=%s route=unhandled focus=%s", tostring(key), fmtFocus(focus))
end

function M.keyreleased(key, AppCoreControllerRef)
  if KeyboardModifierHintController.isModifierKey(key) then
    DebugController.log("debug", "INPUT_ROUTE", "key=%s route=modifier_release", tostring(key))
    KeyboardModifierHintController.updateStatus(ctx, utils)
  end
end

return M
