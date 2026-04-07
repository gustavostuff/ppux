-- oam_animation_window.lua
-- Animation window variant dedicated to ROM-backed OAM sprite layers.
-- Inherits behavior from AnimationWindow and enforces sprite-only layers.

local AnimationWindow = require("user_interface.windows_system.animation_window")

local OAMAnimationWindow = setmetatable({}, { __index = AnimationWindow })
OAMAnimationWindow.__index = OAMAnimationWindow

function OAMAnimationWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  local self = AnimationWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  setmetatable(self, OAMAnimationWindow)
  self.kind = "oam_animation"
  self.showSpriteOriginGuides = (data and data.showSpriteOriginGuides == true)
  return self
end

function OAMAnimationWindow:addLayerAfterActive(opts)
  opts = opts or {}
  local firstLayer = self.layers and self.layers[1] or nil
  local mode = opts.mode
  if mode == nil and firstLayer then
    mode = firstLayer.mode or "8x8"
  end

  return AnimationWindow.addLayerAfterActive(self, {
    opacity = opts.opacity,
    name = opts.name,
    kind = "sprite",
    mode = mode or "8x8",
    originX = opts.originX,
    originY = opts.originY,
  })
end

return OAMAnimationWindow
