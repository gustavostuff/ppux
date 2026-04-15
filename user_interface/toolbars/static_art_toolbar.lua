-- static_art_toolbar.lua
-- Static art windows use a single layer; toolbar only exposes palette link handle.

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local PaletteLinkController = require("controllers.palette.palette_link_controller")

local StaticArtToolbar = {}
StaticArtToolbar.__index = StaticArtToolbar
setmetatable(StaticArtToolbar, { __index = ToolbarBase })

function StaticArtToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), StaticArtToolbar)

  self.ctx = ctx
  self.windowController = windowController

  local _, _, _, hh = window:getHeaderRect()
  self.h = hh

  self.linkButton = self:addButton(images.icons.icon_connect, nil, "Palette link handle; right-drag to a ROM palette to link; left-click for menu", {
    paletteLinkHandle = true,
  })

  self:updatePosition()

  return self
end

function StaticArtToolbar:getLinkHandleRect()
  if not self.linkButton or self.linkButton.hidden == true then
    return nil
  end
  self:updatePosition()
  return self.linkButton.x, self.linkButton.y, self.linkButton.w, self.linkButton.h
end

function StaticArtToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  if self.linkButton then
    self.linkButton.icon = images.icons.icon_connect or self.linkButton.icon
    local linkedPalette = PaletteLinkController.getActiveLayerLinkedPaletteWindow(self.window, self.windowController)
    self.linkButton.bgColor = linkedPalette and colors.green or colors.gray20
    if linkedPalette then
      self.linkButton.tooltip = string.format(
        "Linked to %s; right-drag to a ROM palette to change link; left-click for menu",
        tostring(linkedPalette.title or "palette")
      )
    else
      self.linkButton.tooltip = "No palette linked; right-drag to a ROM palette to link; left-click for menu"
    end
  end
end

return StaticArtToolbar
