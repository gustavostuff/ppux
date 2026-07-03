-- oam_animation_window.lua
-- Animation window variant dedicated to ROM-backed OAM sprite layers.
-- Inherits behavior from AnimationWindow and enforces sprite-only layers.

local AnimationWindow = require("user_interface.windows_system.animation_window")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local SpriteController = require("controllers.sprite.sprite_controller")

local OAMAnimationWindow = setmetatable({}, { __index = AnimationWindow })
OAMAnimationWindow.__index = OAMAnimationWindow

function OAMAnimationWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  local self = AnimationWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  setmetatable(self, OAMAnimationWindow)
  self.kind = "oam_animation"
  self.showSpriteOriginGuides = (data and data.showSpriteOriginGuides == true)
  self.multiRowToolbar = (data and data.multiRowToolbar == true)
  return self
end

--- Same CHR-mapping readiness rules as PPU sprite layers (256-entry pattern table).
function OAMAnimationWindow:isPatternTableInteractionLocked(layerIndex)
  local PatternLayerGate = require("controllers.window.pattern_layer_gate")
  return PatternLayerGate.isLayerInteractionLocked(self, layerIndex)
end

function OAMAnimationWindow:addLayerAfterActive(opts)
  opts = opts or {}
  local firstLayer = self.layers and self.layers[1] or nil
  local mode = opts.mode
  if mode == nil and firstLayer then
    mode = firstLayer.mode or "8x8"
  end

  local insertIdx = AnimationWindow.addLayerAfterActive(self, {
    opacity = opts.opacity,
    name = opts.name,
    kind = "sprite",
    mode = mode or "8x8",
    originX = opts.originX,
    originY = opts.originY,
  })

  if insertIdx and PatternTableDisplayController.syncOamAnimationSpriteLayerPatternTables(self) then
    local newLayer = self.layers and self.layers[insertIdx] or nil
    if newLayer then
      local ctx = rawget(_G, "ctx")
      local app = ctx and ctx.app
      local state = app and app.appEditState or {}
      SpriteController.hydrateSpriteLayer(newLayer, {
        romRaw = state.romRaw or "",
        tilesPool = state.tilesPool,
        appEditState = state,
      })
    end
  end

  return insertIdx
end

return OAMAnimationWindow
