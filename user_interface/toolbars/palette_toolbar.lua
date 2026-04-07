-- palette_toolbar.lua
-- Toolbar for palette windows: active palette toggle button

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
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

  self.compactButton = self:addButton(images.icons.icon_minus or images.icons.icon_down, function()
    self:_onToggleCompact()
  end, "Toggle compact palette view")
  
  -- Active palette toggle button
  local activeBtn = self:addButton(images.icons.icon_not_selected, function()
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
  self:updateCompactIcon()
  self:updateActiveIcon()
end

function PaletteToolbar:updateCompactIcon()
  if not self.compactButton or not self.window then return end
  local supported = self.window.supportsCompactMode and self.window:supportsCompactMode()
  self.compactButton.visible = supported
  self.compactButton.enabled = supported
  if not supported then return end

  if self.window.compactView then
    self.compactButton.icon = images.icons.icon_normal_mode or self.compactButton.icon
    self.compactButton.tooltip = "Switch to normal view"
  else
    self.compactButton.icon = images.icons.icon_compact_mode or self.compactButton.icon
    self.compactButton.tooltip = "Switch to compact view"
  end
end

-- Update the active button icon based on window's activePalette state
function PaletteToolbar:updateActiveIcon()
  if not self.activeButton or not self.window then return end
  
  if self.window.activePalette then
    self.activeButton.icon = images.icons.icon_selected
    self.activeButton.tooltip = "Active palette"
  else
    self.activeButton.icon = images.icons.icon_not_selected
    self.activeButton.tooltip = "Set as active palette"
  end
end

-- Handle toggle active palette
function PaletteToolbar:_onToggleActive()
  if not self.window then return end
  
  local wm = self.windowController
  if not wm then return end
  
  -- Get all windows first (needed in both branches)
  local allWindows = wm:getWindows()
  
  -- Radio behavior: if already active, do nothing; otherwise activate this and deactivate others.
  if self.window.activePalette then
    return
  end

  for _, win in ipairs(allWindows) do
    if win.isPalette then
      win.activePalette = false
    end
  end
  
  self.window.activePalette = true
  
  if self.window.syncToGlobalPalette then
    self.window:syncToGlobalPalette()
  end
  if self.ctx and self.ctx.app and self.ctx.app.invalidatePpuFrameLayersAffectedByPaletteWin then
    self.ctx.app:invalidatePpuFrameLayersAffectedByPaletteWin(self.window)
  end
  
  if self.ctx and self.ctx.setStatus then
    local title = self.window.title or "Palette"
    self.ctx.setStatus(string.format("Active palette: %s", title))
  end
  
  -- Update all palette toolbar icons to reflect new state
  for _, win in ipairs(allWindows) do
    if win.isPalette and win.specializedToolbar and win.specializedToolbar.updateActiveIcon then
      win.specializedToolbar:updateActiveIcon()
    end
  end
end

function PaletteToolbar:_onToggleCompact()
  if not self.window or not self.window.setCompactMode then return end
  local newVal = not self.window.compactView
  self.window:setCompactMode(newVal)
  self:updateCompactIcon()
  if self.ctx and self.ctx.setStatus then
    self.ctx.setStatus(newVal and "Palette compact view" or "Palette full view")
  end
end

return PaletteToolbar
