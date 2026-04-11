-- rom_palette_toolbar.lua
-- Toolbar for ROM palette windows: compact/full toggle only

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local PaletteLinkController = require("controllers.palette.palette_link_controller")

local RomPaletteToolbar = {}
RomPaletteToolbar.__index = RomPaletteToolbar
setmetatable(RomPaletteToolbar, { __index = ToolbarBase })

function RomPaletteToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), RomPaletteToolbar)

  self.ctx = ctx
  self.windowController = windowController

  local hx, hy, hw, hh = window:getHeaderRect()
  self.h = hh

  self.prevButton = self:addButton(images.icons.icon_left, function()
    self:_onNavigate(-1)
  end, "Previous ROM palette")

  self.nextButton = self:addButton(images.icons.icon_right, function()
    self:_onNavigate(1)
  end, "Next ROM palette")

  self.linkButton = self:addButton(images.icons.icon_connect or images.icons.icon_pivot or images.icons.icon_empty or images.icons.icon_scroll_toolbar_empty, nil, "Palette link handle", {
    paletteLinkHandle = true,
  })

  self.compactButton = self:addButton(images.icons.icon_minus or images.icons.icon_down, function()
    self:_onToggleCompact()
  end, "Toggle compact palette view")

  self:updateCompactIcon()
  self:updatePosition()

  return self
end

function RomPaletteToolbar:getLinkHandleRect()
  if not self.linkButton or self.linkButton.hidden == true then return nil end
  self:updatePosition()
  return self.linkButton.x, self.linkButton.y, self.linkButton.w, self.linkButton.h
end

function RomPaletteToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  self:updateGroupedNavigationButtons()
  if self.linkButton then
    self.linkButton.icon = images.icons.icon_connect or images.icons.icon_pivot or self.linkButton.icon
    local targets = PaletteLinkController.getLinkedTargetsForPalette(self.windowController, self.window)
    local linkedCount = #(targets or {})
    self.linkButton.bgColor = linkedCount > 0 and colors.green or colors.gray20
    if linkedCount > 0 then
      self.linkButton.tooltip = string.format(
        "%d linked layer(s) (click for menu)",
        linkedCount
      )
    else
      self.linkButton.tooltip = "No linked layers (click for menu)"
    end
  end
  self:updateCompactIcon()
end

function RomPaletteToolbar:isGroupedPaletteMode()
  local app = self.ctx and self.ctx.app or nil
  return app and app.isGroupedPaletteWindowsEnabled and app:isGroupedPaletteWindowsEnabled() or false
end

function RomPaletteToolbar:updateGroupedNavigationButtons()
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

function RomPaletteToolbar:updateCompactIcon()
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

function RomPaletteToolbar:_onToggleCompact()
  if not self.window or not self.window.setCompactMode then return end
  local newVal = not self.window.compactView
  self.window:setCompactMode(newVal)
  self:updateCompactIcon()
  if self.ctx and self.ctx.app and self.ctx.app.setStatus then
    self.ctx.app:setStatus(newVal and "Palette compact view" or "Palette full view")
  end
end

function RomPaletteToolbar:_onNavigate(delta)
  if not self.window or not self.ctx or not self.ctx.app then return end
  local app = self.ctx.app
  if app.cycleGroupedPaletteWindow then
    app:cycleGroupedPaletteWindow(self.window, delta or 0)
  end
end

return RomPaletteToolbar
