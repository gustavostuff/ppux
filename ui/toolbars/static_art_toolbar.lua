-- static_art_toolbar.lua
-- Static art windows use a single layer; palette links use on-canvas badges.

local ToolbarBase = require("ui.toolbars.toolbar_base")

local StaticArtToolbar = {}
StaticArtToolbar.__index = StaticArtToolbar
setmetatable(StaticArtToolbar, { __index = ToolbarBase })

function StaticArtToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), StaticArtToolbar)

  self.ctx = ctx
  self.windowController = windowController

  local _, _, _, hh = window:getHeaderRect()
  self.h = hh

  self:updatePosition()

  return self
end

function StaticArtToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
end

return StaticArtToolbar
