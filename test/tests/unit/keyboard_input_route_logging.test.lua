local KeyboardInput = require("controllers.input.keyboard_input")
local DebugController = require("controllers.dev.debug_controller")
local KeyboardArtActionsController = require("controllers.input.keyboard_art_actions_controller")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
local KeyboardWindowShortcutsController = require("controllers.input.keyboard_window_shortcuts_controller")
local KeyboardDebugController = require("controllers.input.keyboard_debug_controller")
local KeyboardEditToggleController = require("controllers.input.keyboard_edit_toggle_controller")
local KeyboardNavigationController = require("controllers.input.keyboard_navigation_controller")
local KeyboardSelectionActionsController = require("controllers.input.keyboard_selection_actions_controller")

describe("keyboard_input.lua - INPUT_ROUTE logging", function()
  local originalLog
  local originalDebugHandler
  local originalWindowScaling
  local originalCascade
  local originalFullscreen
  local originalModeSwitch
  local originalArtActions
  local originalClipboard
  local originalEditToggle
  local originalNavigation
  local originalSelectionActions
  local originalGetFocus
  local logCalls

  local function formatLogCall(call)
    local args = call.args or {}
    return string.format(call.message, unpack(args))
  end

  beforeEach(function()
    logCalls = {}
    originalLog = DebugController.log
    originalDebugHandler = KeyboardDebugController.handleDebugKeys
    originalWindowScaling = KeyboardWindowShortcutsController.handleWindowScaling
    originalCascade = KeyboardWindowShortcutsController.handleCascade
    originalFullscreen = KeyboardWindowShortcutsController.handleFullscreen
    originalModeSwitch = KeyboardWindowShortcutsController.handleModeSwitch
    originalArtActions = {
      pixelOffset = KeyboardArtActionsController.handlePixelOffset,
      tileRotation = KeyboardArtActionsController.handleTileRotation,
      paletteAssign = KeyboardArtActionsController.handlePaletteNumberAssignment,
    }
    originalClipboard = {
      copy = KeyboardClipboardController.handleCopySelection,
      paste = KeyboardClipboardController.handlePasteSelection,
      reset = KeyboardClipboardController.reset,
    }
    originalEditToggle = {
      editModeKeys = KeyboardEditToggleController.handleEditModeKeys,
      attrModeToggle = KeyboardEditToggleController.handleAttrModeToggle,
      shaderToggle = KeyboardEditToggleController.handleShaderToggle,
      undoRedo = KeyboardEditToggleController.handleUndoRedo,
    }
    originalNavigation = {
      inactiveOpacity = KeyboardNavigationController.handleInactiveLayerOpacity,
      animDelay = KeyboardNavigationController.handleAnimationDelayAdjust,
      paletteKeys = KeyboardNavigationController.handlePaletteKeys,
      tileNav = KeyboardNavigationController.handleTileSelectionNavigation,
      layerNav = KeyboardNavigationController.handleLayerNavigation,
      chrBank = KeyboardNavigationController.handleChrBankKeys,
      animKeys = KeyboardNavigationController.handleAnimationWindowKeys,
    }
    originalSelectionActions = {
      selectAll = KeyboardSelectionActionsController.handleSelectAll,
      mirror = KeyboardSelectionActionsController.handleSpriteMirror,
      deleteKey = KeyboardSelectionActionsController.handleDeleteKey,
    }

    DebugController.log = function(level, category, message, ...)
      logCalls[#logCalls + 1] = {
        level = level,
        category = category,
        message = message,
        args = { ... },
      }
    end

    KeyboardDebugController.handleDebugKeys = function() return false end
    KeyboardWindowShortcutsController.handleWindowScaling = function() return false end
    KeyboardWindowShortcutsController.handleCascade = function() return false end
    KeyboardWindowShortcutsController.handleFullscreen = function(_, _, key)
      return key == "f11"
    end
    KeyboardWindowShortcutsController.handleModeSwitch = function() return false end
    KeyboardWindowShortcutsController.handleWindowZoom = function() return false end
    KeyboardWindowShortcutsController.handleGridToggleInWindow = function() return false end
    KeyboardArtActionsController.handlePixelOffset = function() return false end
    KeyboardArtActionsController.handleTileRotation = function() return false end
    KeyboardArtActionsController.handlePaletteNumberAssignment = function() return false end
    KeyboardClipboardController.reset = function() end
    KeyboardClipboardController.handleCopySelection = function() return false end
    KeyboardClipboardController.handlePasteSelection = function() return false end
    KeyboardEditToggleController.handleEditModeKeys = function() return false end
    KeyboardEditToggleController.handleAttrModeToggle = function() return false end
    KeyboardEditToggleController.handleShaderToggle = function() return false end
    KeyboardEditToggleController.handleUndoRedo = function() return false end
    KeyboardNavigationController.handleInactiveLayerOpacity = function() return false end
    KeyboardNavigationController.handleAnimationDelayAdjust = function() return false end
    KeyboardNavigationController.handlePaletteKeys = function() return false end
    KeyboardNavigationController.handleTileSelectionNavigation = function() return false end
    KeyboardNavigationController.handleLayerNavigation = function() return false end
    KeyboardNavigationController.handleChrBankKeys = function() return false end
    KeyboardNavigationController.handleAnimationWindowKeys = function() return false end
    KeyboardSelectionActionsController.handleSelectAll = function() return false end
    KeyboardSelectionActionsController.handleSpriteMirror = function() return false end
    KeyboardSelectionActionsController.handleDeleteKey = function() return false end

    originalGetFocus = function()
      return { kind = "chr", _id = "bank" }
    end

    KeyboardInput.setup({
      getFocus = originalGetFocus,
    }, {})
  end)

  afterEach(function()
    DebugController.log = originalLog
    KeyboardDebugController.handleDebugKeys = originalDebugHandler
    KeyboardWindowShortcutsController.handleWindowScaling = originalWindowScaling
    KeyboardWindowShortcutsController.handleCascade = originalCascade
    KeyboardWindowShortcutsController.handleFullscreen = originalFullscreen
    KeyboardWindowShortcutsController.handleModeSwitch = originalModeSwitch
    KeyboardArtActionsController.handlePixelOffset = originalArtActions.pixelOffset
    KeyboardArtActionsController.handleTileRotation = originalArtActions.tileRotation
    KeyboardArtActionsController.handlePaletteNumberAssignment = originalArtActions.paletteAssign
    KeyboardClipboardController.handleCopySelection = originalClipboard.copy
    KeyboardClipboardController.handlePasteSelection = originalClipboard.paste
    KeyboardClipboardController.reset = originalClipboard.reset
    KeyboardEditToggleController.handleEditModeKeys = originalEditToggle.editModeKeys
    KeyboardEditToggleController.handleAttrModeToggle = originalEditToggle.attrModeToggle
    KeyboardEditToggleController.handleShaderToggle = originalEditToggle.shaderToggle
    KeyboardEditToggleController.handleUndoRedo = originalEditToggle.undoRedo
    KeyboardNavigationController.handleInactiveLayerOpacity = originalNavigation.inactiveOpacity
    KeyboardNavigationController.handleAnimationDelayAdjust = originalNavigation.animDelay
    KeyboardNavigationController.handlePaletteKeys = originalNavigation.paletteKeys
    KeyboardNavigationController.handleTileSelectionNavigation = originalNavigation.tileNav
    KeyboardNavigationController.handleLayerNavigation = originalNavigation.layerNav
    KeyboardNavigationController.handleChrBankKeys = originalNavigation.chrBank
    KeyboardNavigationController.handleAnimationWindowKeys = originalNavigation.animKeys
    KeyboardSelectionActionsController.handleSelectAll = originalSelectionActions.selectAll
    KeyboardSelectionActionsController.handleSpriteMirror = originalSelectionActions.mirror
    KeyboardSelectionActionsController.handleDeleteKey = originalSelectionActions.deleteKey
  end)

  it("logs matched handler name/group for handled keys", function()
    KeyboardInput.keypressed("f11", {})

    expect(#logCalls).toBeGreaterThan(0)
    local last = logCalls[#logCalls]
    expect(last.category).toBe("INPUT_ROUTE")
    local text = formatLogCall(last)
    expect(string.find(text, "group=global", 1, true)).toNotBe(nil)
    expect(string.find(text, "handler=fullscreen", 1, true)).toNotBe(nil)
    expect(string.find(text, "key=f11", 1, true)).toNotBe(nil)
  end)

  it("logs unhandled keys with focus info", function()
    KeyboardWindowShortcutsController.handleFullscreen = function() return false end

    KeyboardInput.keypressed("totally_unhandled_key", {})

    expect(#logCalls).toBeGreaterThan(0)
    local last = logCalls[#logCalls]
    expect(last.category).toBe("INPUT_ROUTE")
    local text = formatLogCall(last)
    expect(string.find(text, "route=unhandled", 1, true)).toNotBe(nil)
    expect(string.find(text, "focus=chr:bank", 1, true)).toNotBe(nil)
  end)
end)
