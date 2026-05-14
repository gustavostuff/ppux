-- pattern_table_toolbar.lua
-- ROM-backed pattern table window: add tile ranges only (for now).

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")

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

  self.addTileRangeButton = self:addButton(images.icons.chrome.icon_plus, function()
    self:_onAddTileRange()
  end, "Add tile range")

  self:updatePatternRangeButton()
  self:updatePosition()

  return self
end

function PatternTableToolbar:_onAddTileRange()
  local app = self.ctx and self.ctx.app
  if not app or not app.showPpuFramePatternRangeModal then
    setStatus(self.ctx, "Add tile range is not available")
    return
  end
  app:showPpuFramePatternRangeModal(self.window)
end

function PatternTableToolbar:updatePatternRangeButton()
  local button = self.addTileRangeButton
  if not (button and self.window) then
    return
  end
  local layer = self.window.layers and self.window.layers[1]
  local ranges = layer and layer.patternTable and layer.patternTable.ranges
  local rangeCount = type(ranges) == "table" and #ranges or 0
  if rangeCount > 0 then
    button.bgColor = nil
    button.contentColor = colors.white
  else
    button.bgColor = colors.yellow
    button.contentColor = colors.black
  end
  button.tooltip = "Add tile range"
end

function PatternTableToolbar:updateIcons()
  self:updatePatternRangeButton()
end

return PatternTableToolbar
