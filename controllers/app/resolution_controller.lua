local DebugController = require("controllers.dev.debug_controller")

local ResolutionController = {
  modes = {
    KEEP_ASPECT = 1,
    PIXEL_PERFECT = 2,
    STRETCH = 3,
  },
}

function ResolutionController:init(canvas)
  self.canvas = canvas
  self.canvasWidth = self.canvas:getWidth()
  self.canvasHeight = self.canvas:getHeight()
  self.canvasScaleX = 1
  self.canvasScaleY = 1
  self.defaultMode = self.modes.STRETCH
  self:setMode(self.defaultMode)

  self:recalculate()
end

function ResolutionController:setMode(mode)
  self.mode = mode
  self:recalculate()
end

function ResolutionController:normalizeScale()
  if self.canvasScaleX > self.canvasScaleY then
    self.canvasScaleX = self.canvasScaleY
  else
    self.canvasScaleY = self.canvasScaleX
  end
end

function ResolutionController:setCanvasPosition()
  local w = love.graphics.getWidth()
  local h = love.graphics.getHeight()
  self.canvasX = math.floor(w / 2 - self.canvas:getWidth() * self.canvasScaleX / 2)
  self.canvasY = math.floor(h / 2 - self.canvas:getHeight() * self.canvasScaleY / 2)
end

function ResolutionController:recalculate()
  local w = love.graphics.getWidth()
  local h = love.graphics.getHeight()

  if self.mode == self.modes.KEEP_ASPECT then
    self.canvasScaleX = w / self.canvasWidth
    self.canvasScaleY = h / self.canvasHeight
    self:normalizeScale()
  elseif self.mode == self.modes.PIXEL_PERFECT then
    self.canvasScaleX = math.floor(w / self.canvasWidth)
    self.canvasScaleY = math.floor(h / self.canvasHeight)
    self:normalizeScale()
  elseif self.mode == self.modes.STRETCH then
    self.canvasScaleX = w / self.canvasWidth
    self.canvasScaleY = h / self.canvasHeight
  end

  self:setCanvasPosition()
end

function ResolutionController:renderCanvas()
  love.graphics.draw(
    self.canvas,
    self.canvasX,
    self.canvasY,
    0,
    self.canvasScaleX,
    self.canvasScaleY
  )
end

function ResolutionController:getScaledMouse(asInteger, touchX, touchY)
  local x, y = love.mouse.getPosition()

  if touchX and touchY then
    x, y = touchX, touchY
  end

  if asInteger then
    return {
      x = math.floor((x - self.canvasX) / self.canvasScaleX),
      y = math.floor((y - self.canvasY) / self.canvasScaleY)
    }
  end

  return {
    x = ((x - self.canvasX) / self.canvasScaleX),
    y = ((y - self.canvasY) / self.canvasScaleY)
  }
end

return ResolutionController
