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
  self:updateActiveIcon()
end

-- Update the active button icon based on window's activePalette state
function PaletteToolbar:updateActiveIcon()
  if not self.activeButton or not self.window then return end
  
  if self.window.activePalette then
    self.activeButton.icon = images.icons.icon_selected
    self.activeButton.tooltip = "Active palette (click to deactivate)"
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

return PaletteToolbar
