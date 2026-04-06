local DebugController = require("controllers.dev.debug_controller")

local crtShaderLoadAttempted = false
local cachedCrtShader = nil

local function resolveCrtShader()
  if cachedCrtShader ~= nil or crtShaderLoadAttempted then
    return cachedCrtShader
  end

  crtShaderLoadAttempted = true
  local ok = pcall(require, "shaders")
  if not ok then
    return nil
  end

  cachedCrtShader = rawget(_G, "crtShader")
  return cachedCrtShader
end

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
  self.defaultMode = self.modes.KEEP_ASPECT
  self.canvasCrtShaderEnabled = (rawget(_G, "__PPUX_ENABLE_CRT_SHADER__") == true)
  self.canvasCrtFlat = (rawget(_G, "__PPUX_CRT_FLAT__") == true)
  self.canvasCrtDistortion = tonumber(rawget(_G, "__PPUX_CRT_DISTORTION__")) or 0.15
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
  local shaderApplied = false
  if self.canvasCrtShaderEnabled == true then
    local crtShader = resolveCrtShader()
    if crtShader then
      local canvasW = self.canvasWidth or self.canvas:getWidth()
      local canvasH = self.canvasHeight or self.canvas:getHeight()
      crtShader:send("inputSize", { canvasW, canvasH })
      crtShader:send("outputSize", { love.graphics.getWidth(), love.graphics.getHeight() })
      crtShader:send("textureSize", { canvasW, canvasH })
      local curve = self.canvasCrtFlat and 0 or (self.canvasCrtDistortion or 0.15)
      crtShader:send("distortion", curve)
      love.graphics.setShader(crtShader)
      shaderApplied = true
    end
  end

  love.graphics.draw(
    self.canvas,
    self.canvasX,
    self.canvasY,
    0,
    self.canvasScaleX,
    self.canvasScaleY
  )

  if shaderApplied then
    love.graphics.setShader()
  end
end

function ResolutionController:setCanvasCrtShaderEnabled(enabled)
  self.canvasCrtShaderEnabled = (enabled == true)
end

function ResolutionController:isCanvasCrtShaderEnabled()
  return self.canvasCrtShaderEnabled == true
end

function ResolutionController:setCanvasCrtFlat(flat)
  self.canvasCrtFlat = (flat == true)
end

function ResolutionController:setCanvasCrtDistortion(value)
  local n = tonumber(value)
  if not n then
    return false
  end
  self.canvasCrtDistortion = n
  return true
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
