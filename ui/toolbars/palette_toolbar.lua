-- palette_toolbar.lua
-- Toolbar for palette windows: active palette toggle button

local ToolbarBase = require("ui.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local DebugController = require("controllers.dev.debug_controller")

local PaletteToolbar = {}
PaletteToolbar.__index = PaletteToolbar
setmetatable(PaletteToolbar, { __index = ToolbarBase })

function PaletteToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), PaletteToolbar)
  
  self.ctx = ctx
  self.windowController = windowController
  
  -- Get header dimensions
  local hx, hy, hw, hh = window:getHeaderRect()
  self.h = hh  -- Toolbar height matches header height

  self.prevButton = self:addButton(images.icons.actions.icon_left, function()
    self:_onNavigate(-1)
  end, "Previous palette")

  self.nextButton = self:addButton(images.icons.actions.icon_right, function()
    self:_onNavigate(1)
  end, "Next palette")

  self.compactButton = self:addButton(images.icons.chrome.icon_minus or images.icons.chrome.icon_down, function()
    -- Deactivated: compact is the only palette size (see FORCE_COMPACT_ONLY).
    self:_onToggleCompact()
  end, "Toggle compact palette view")
  self.compactButton.visible = false
  self.compactButton.enabled = false
  
  -- Active palette toggle button
  local activeBtn = self:addButton(images.icons.chrome.icon_not_selected, function()
    self:_onToggleActive()
  end, "Set as active palette")
  
  -- Store reference to the button so we can update its icon
  self.activeButton = activeBtn
  
  -- Update button icon based on current state
  self:updateActiveIcon()
  
  -- Update position
  self:updatePosition()

  return self
end

-- Override updateIcons to refresh the active button icon
function PaletteToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  self:updateGroupedNavigationButtons()
  self:updateCompactIcon()
  self:updateActiveIcon()
end

function PaletteToolbar:isGroupedPaletteMode()
  local app = self.ctx and self.ctx.app or nil
  return app and app.isGroupedPaletteWindowsEnabled and app:isGroupedPaletteWindowsEnabled() or false
end

function PaletteToolbar:updateGroupedNavigationButtons()
  local grouped = self:isGroupedPaletteMode()
  if self.prevButton then
    self.prevButton.visible = grouped
    self.prevButton.enabled = grouped
  end
  if self.nextButton then
    self.nextButton.visible = grouped
    self.nextButton.enabled = grouped
  end
end

function PaletteToolbar:updateCompactIcon()
  if not self.compactButton or not self.window then return end
  local supported = self.window.supportsCompactMode and self.window:supportsCompactMode()
  self.compactButton.visible = supported
  self.compactButton.enabled = supported
  if not supported then return end

  -- Inactive while supportsCompactMode() is false.
  if self.window.compactView then
    self.compactButton.icon = images.icons.chrome.icon_normal_mode or self.compactButton.icon
    self.compactButton.tooltip = "Switch to normal view"
  else
    self.compactButton.icon = images.icons.chrome.icon_compact_mode or self.compactButton.icon
    self.compactButton.tooltip = "Switch to compact view"
  end
end

-- Update the active button icon based on window's activePalette state
function PaletteToolbar:updateActiveIcon()
  if not self.activeButton or not self.window then return end
  
  if self.window.activePalette then
    self.activeButton.icon = images.icons.chrome.icon_selected
    self.activeButton.tooltip = "Active palette"
  else
    self.activeButton.icon = images.icons.chrome.icon_not_selected
    self.activeButton.tooltip = "Set as active palette"
  end
end

-- Handle toggle active palette
function PaletteToolbar:_onToggleActive()
  if not self.window then return end

  if self.window.activePalette then
    return
  end

  local app = self.ctx and self.ctx.app or nil
  if not app then return end

  local PaletteActivationController = require("controllers.palette.palette_activation_controller")
  PaletteActivationController.activateGlobalPalette(self.window, app)
end

function PaletteToolbar:_onToggleCompact()
  -- Deactivated while FORCE_COMPACT_ONLY: no-op if compact toggle unsupported.
  if not self.window or not self.window.setCompactMode then return end
  if self.window.supportsCompactMode and not self.window:supportsCompactMode() then
    return
  end
  local newVal = not self.window.compactView
  self.window:setCompactMode(newVal)
  self:updateCompactIcon()
end

function PaletteToolbar:_onNavigate(delta)
  if not self.window or not self.ctx or not self.ctx.app then return end
  local app = self.ctx.app
  if app.cycleGroupedPaletteWindow then
    app:cycleGroupedPaletteWindow(self.window, delta or 0)
  end
end

return PaletteToolbar
