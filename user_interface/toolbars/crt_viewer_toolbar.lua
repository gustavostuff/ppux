-- Specialized toolbar for CRT layer visualizer: cycle referenced layers (refs), Shift+Up/Down matches other windows.

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local Slider = require("user_interface.slider")
local images = require("images")

local CrtViewerToolbar = {}
CrtViewerToolbar.__index = CrtViewerToolbar
setmetatable(CrtViewerToolbar, { __index = ToolbarBase })

function CrtViewerToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), CrtViewerToolbar)

  self.ctx = ctx
  self.windowController = windowController

  local _, _, _, hh = window:getHeaderRect()
  self.h = hh

  self.layerLabel = self:addLabel("", self.h * 3, function()
    if not self.window then
      return "Ref 0/0"
    end
    local total = self.window.getLayerCount and self.window:getLayerCount() or 0
    local current = self.window.getActiveLayerIndex and self.window:getActiveLayerIndex() or 1
    if total <= 0 then
      return "Ref 0/0"
    end
    current = math.max(1, math.min(current, total))
    return string.format("Ref %d/%d", current, total)
  end)
  self.layerLabel.renderInContent = true

  --- Reserve strip for distortion slider (labels lay out left of buttons).
  self.sliderAnchorLabel = self:addLabel("", 175, function()
    return ""
  end)

  self:addButton(images.icons.chrome.icon_down, function()
    self.window:prevLayer()
  end, "Previous reference layer", {})

  self:addButton(images.icons.chrome.icon_up, function()
    self.window:nextLayer()
  end, "Next reference layer", {})

  local rowH = hh
  local initDist = tonumber(window.crtVizDistortion)
  if not initDist then
    local app = ctx and ctx.app
    initDist = (type(app and app.crtDistortionSetting) == "number") and app.crtDistortionSetting or 0.1
  end

  self.distortionSlider = Slider.new({
    min = 0,
    max = 0.45,
    value = initDist,
    w = 130,
    h = math.max(rowH - 2, 18),
    tooltip = "CRT curve (barrel distortion) for this viewer",
    onChange = function(v)
      window.crtVizDistortion = v
    end,
    onCommit = function(v)
      window.crtVizDistortion = v
      local app = ctx and ctx.app
      if app and app._persistCrtLayerViz then
        app:_persistCrtLayerViz()
      end
    end,
  })

  self:updatePosition()

  return self
end

function CrtViewerToolbar:updatePosition()
  ToolbarBase.updatePosition(self)
  local sl = self.distortionSlider
  local anchor = self.sliderAnchorLabel
  if sl and anchor then
    local rowH = self:_getRowHeight(self.h)
    sl:setPosition(anchor.x + 2, anchor.y + math.floor((rowH - sl.h) / 2))
    if self.window then
      local v = tonumber(self.window.crtVizDistortion)
      if v then
        sl:setValue(v, { silent = true })
      end
    end
  end
end

function CrtViewerToolbar:contains(px, py)
  if ToolbarBase.contains(self, px, py) then
    return true
  end
  local sl = self.distortionSlider
  if not sl then
    return false
  end
  return sl:contains(px, py)
end

function CrtViewerToolbar:getTooltipAt(px, py)
  local sl = self.distortionSlider
  if sl and sl.enabled and sl:contains(px, py) then
    local tip = sl.tooltip or ""
    if tip ~= "" then
      return {
        text = tip,
        immediate = false,
        key = sl,
      }
    end
  end
  return ToolbarBase.getTooltipAt(self, px, py)
end

function CrtViewerToolbar:mousepressed(x, y, button)
  self:updateIcons()
  self:updatePosition()
  local sl = self.distortionSlider
  if sl and sl:mousepressed(x, y, button) then
    return true
  end
  return ToolbarBase.mousepressed(self, x, y, button)
end

function CrtViewerToolbar:mousereleased(x, y, button)
  local sl = self.distortionSlider
  if sl and sl:mousereleased(x, y, button) then
    return true
  end
  return ToolbarBase.mousereleased(self, x, y, button)
end

function CrtViewerToolbar:mousemoved(x, y)
  local sl = self.distortionSlider
  if sl then
    sl:mousemoved(x, y)
  end
  local overBtn = ToolbarBase.mousemoved(self, x, y)
  return overBtn or (sl and (sl.hovered or sl:isDragging()))
end

function CrtViewerToolbar:draw()
  ToolbarBase.draw(self)
  local sl = self.distortionSlider
  if not sl then
    return
  end
  if not self.visible then
    return
  end
  if not self.window or not self.windowController then
    return
  end
  if self.window ~= self.windowController:getFocus() then
    return
  end
  self:updatePosition()
  sl:draw()
end

return CrtViewerToolbar
