-- toolbar_controller.lua
-- Manages creation and lifecycle of window toolbars

local HeaderToolbar = require("user_interface.toolbars.header_toolbar")
local ChrHeaderToolbar = require("user_interface.toolbars.chr_header_toolbar")
local AnimationToolbar = require("user_interface.toolbars.animation_toolbar")
local StaticArtToolbar = require("user_interface.toolbars.static_art_toolbar")
local PatternTableBuilderToolbar = require("user_interface.toolbars.pattern_table_builder_toolbar")
local PPUFrameToolbar = require("user_interface.toolbars.ppu_frame_toolbar")
local PaletteToolbar = require("user_interface.toolbars.palette_toolbar")
local RomPaletteToolbar = require("user_interface.toolbars.rom_palette_toolbar")
local ChrToolbar = require("user_interface.toolbars.chr_toolbar")
local DebugController = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local ToolbarController = {}
ToolbarController.__index = ToolbarController

-- Create header toolbar for a window
function ToolbarController.createHeaderToolbar(window, ctx, windowController)
  if not window then return nil end
  
  -- CHR windows get special header toolbar (no close button)
  if WindowCaps.isChrLike(window) then
    return ChrHeaderToolbar.new(window, ctx, windowController)
  else
    -- All other windows get standard header toolbar
    return HeaderToolbar.new(window, ctx, windowController)
  end
end

-- Create specialized toolbar for a window (based on window kind)
function ToolbarController.createSpecializedToolbar(window, ctx, windowController)
  if not window then return nil end

  if WindowCaps.isAnimationLike(window) then
    return AnimationToolbar.new(window, ctx, windowController)
  elseif WindowCaps.isPatternTableBuilder(window) then
    return PatternTableBuilderToolbar.new(window, ctx, windowController)
  elseif window.kind == "static_art" then
    return StaticArtToolbar.new(window, ctx, windowController)
  elseif WindowCaps.isChrLike(window) then
    return ChrToolbar.new(window, ctx, windowController)
  elseif WindowCaps.isPpuFrame(window) then
    return PPUFrameToolbar.new(window, ctx, windowController)
  elseif WindowCaps.isGlobalPaletteWindow(window) then
    return PaletteToolbar.new(window, ctx, windowController)
  elseif WindowCaps.isRomPaletteWindow(window) then
    return RomPaletteToolbar.new(window, ctx, windowController)
  end
  
  -- Other window types don't have specialized toolbars yet
  return nil
end

-- Create toolbars for a single window
function ToolbarController.createToolbarsForWindow(window, ctx, windowController)
  if not window or window._closed then return end
  
  ctx = ctx or _G.ctx
  if not ctx then 
    DebugController.log("warning", "UI", "ToolbarController.createToolbarsForWindow: no context available")
    return 
  end
  
  -- Create header toolbar if it doesn't exist
  if not window.headerToolbar then
    window.headerToolbar = ToolbarController.createHeaderToolbar(window, ctx, windowController)
  end
  
  -- Create specialized toolbar if it doesn't exist
  if not window.specializedToolbar then
    window.specializedToolbar = ToolbarController.createSpecializedToolbar(window, ctx, windowController)
  end
  
  -- Update header toolbar position and sync collapse icon with window state
  if window.headerToolbar then
    window.headerToolbar:updatePosition()
    window.headerToolbar.visible = true
    window.headerToolbar.enabled = true
    -- Update collapse icon to reflect current window collapsed state
    if window.headerToolbar.updateCollapseIcon then
      window.headerToolbar:updateCollapseIcon()
    end
  end
  
  -- Update specialized toolbar position
  if window.specializedToolbar then
    window.specializedToolbar:updatePosition()
    window.specializedToolbar.visible = true
    window.specializedToolbar.enabled = true
  end
end

-- Create toolbars for all windows
function ToolbarController.createToolbarsForWindows(app)
  if not app or not app.wm then return end
  
  local ctx = _G.ctx
  if not ctx then return end
  
  local windows = app.wm:getWindows()
  for _, win in ipairs(windows) do
    ToolbarController.createToolbarsForWindow(win, ctx, app.wm)
  end
end

return ToolbarController
