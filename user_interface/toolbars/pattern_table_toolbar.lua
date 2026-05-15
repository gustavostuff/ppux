-- pattern_table_toolbar.lua
-- Pattern table window toolbar (layout toggle; ranges via drag-drop for now).

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local images = require("images")

local PatternTableToolbar = {}
PatternTableToolbar.__index = PatternTableToolbar
setmetatable(PatternTableToolbar, { __index = ToolbarBase })

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

function PatternTableToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), PatternTableToolbar)
  self.ctx = ctx
  self.windowController = windowController

  local _, _, _, hh = window:getHeaderRect()
  self.h = hh

  self.modeButton = self:addButton(images.icons.actions.icon_8x8, function()
    self:_onToggleChrLayoutMode()
  end, "Tile layout 8×8 / 8×16 (Ctrl+M); M alone is mirror")
  self:updateModeIcon()

  self:updatePosition()

  return self
end

function PatternTableToolbar:_activeTileLayerIndex()
  local w = self.window
  if not w then
    return nil
  end
  return (w.getActiveLayerIndex and w:getActiveLayerIndex()) or w.activeLayer or 1
end

function PatternTableToolbar:updateModeIcon()
  if not self.window or not self.modeButton then
    return
  end
  local li = self:_activeTileLayerIndex()
  local layer = li and self.window.layers and self.window.layers[li]
  if not (layer and layer.kind == "tile") then
    self.modeButton.enabled = false
    return
  end
  self.modeButton.enabled = true
  if PpuRange.patternTableUses8x16TileLayout(layer) then
    self.modeButton.icon = images.icons.actions.icon_8x16 or self.modeButton.icon
  else
    self.modeButton.icon = images.icons.actions.icon_8x8 or self.modeButton.icon
  end
end

function PatternTableToolbar:_onToggleChrLayoutMode()
  local w = self.window
  local app = self.ctx and self.ctx.app
  if not w then
    return
  end
  local li = self:_activeTileLayerIndex()
  local layer = li and w.layers and w.layers[li]
  if not (layer and layer.kind == "tile") then
    return
  end
  local layoutLabel = PatternTableDisplayController.toggleTileLayerChrLayout(w, li, app)
    or ((layer.mode == "8x16") and "8x16 pairs" or "8x8")
  setStatus(self.ctx, "Pattern table layout: " .. layoutLabel .. " — Ctrl+M to toggle")
  self:updateModeIcon()
end

function PatternTableToolbar:updateIcons()
  self:updateModeIcon()
end

return PatternTableToolbar
