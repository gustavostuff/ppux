local colors = require("app_colors")
local Text = require("utils.text_utils")

local TooltipController = {}
TooltipController.__index = TooltipController

local DEFAULT_DELAY_SECONDS = 0.7
local OFFSET_X = 10
local OFFSET_Y = 10
local PADDING_X = 4
local PADDING_Y = 2

function TooltipController.new(opts)
  opts = opts or {}
  local self = setmetatable({
    delaySeconds = tonumber(opts.delaySeconds) or DEFAULT_DELAY_SECONDS,
    lastMouseX = nil,
    lastMouseY = nil,
    stillSeconds = 0,
    candidateKey = nil,
    candidateText = nil,
    candidateImmediate = false,
    visible = false,
    mouseX = 0,
    mouseY = 0,
  }, TooltipController)
  return self
end

local function normalizeCandidate(candidate)
  if not candidate then return nil end
  local text = candidate.text
  if text == nil then return nil end
  text = tostring(text)
  if text == "" then return nil end
  return {
    text = text,
    immediate = (candidate.immediate == true),
    key = candidate.key or text,
  }
end

function TooltipController:update(dt, mouseX, mouseY, candidate)
  dt = tonumber(dt) or 0
  local cx = tonumber(mouseX) or 0
  local cy = tonumber(mouseY) or 0

  local moved = (self.lastMouseX ~= cx) or (self.lastMouseY ~= cy)
  self.lastMouseX = cx
  self.lastMouseY = cy
  self.mouseX = cx
  self.mouseY = cy

  local normalized = normalizeCandidate(candidate)
  local nextKey = normalized and normalized.key or nil
  if nextKey ~= self.candidateKey then
    self.candidateKey = nextKey
    self.stillSeconds = 0
  elseif moved then
    self.stillSeconds = 0
  else
    self.stillSeconds = self.stillSeconds + dt
  end

  if not normalized then
    self.candidateText = nil
    self.candidateImmediate = false
    self.visible = false
    return
  end

  self.candidateText = normalized.text
  self.candidateImmediate = normalized.immediate
  if self.candidateImmediate then
    self.visible = true
    return
  end
  self.visible = self.stillSeconds >= self.delaySeconds
end

function TooltipController:draw(canvasW, canvasH)
  if not self.visible then return end
  if not self.candidateText or self.candidateText == "" then return end

  local font = love.graphics.getFont()
  if not font then return end

  local text = self.candidateText
  local textW = font:getWidth(text)
  local textH = font:getHeight()
  local boxW = textW + (PADDING_X * 2)
  local boxH = textH + (PADDING_Y * 2)

  local maxW = tonumber(canvasW) or love.graphics.getWidth()
  local maxH = tonumber(canvasH) or love.graphics.getHeight()

  local x = self.mouseX + OFFSET_X
  local y = self.mouseY + OFFSET_Y

  local rightX = self.mouseX + OFFSET_X
  local leftX = self.mouseX - boxW - OFFSET_X
  local bottomY = self.mouseY + OFFSET_Y
  local topY = self.mouseY - boxH - OFFSET_Y

  local hasRight = (rightX + boxW) <= maxW
  local hasLeft = leftX >= 0
  local hasBottom = (bottomY + boxH) <= maxH
  local hasTop = topY >= 0

  -- Horizontal side: prefer right, then left, then whichever side has more room.
  if hasRight then
    x = rightX
  elseif hasLeft then
    x = leftX
  else
    local rightRoom = maxW - self.mouseX
    local leftRoom = self.mouseX
    x = (rightRoom >= leftRoom) and rightX or leftX
  end

  -- Vertical side: prefer bottom, then top, then whichever side has more room.
  if hasBottom then
    y = bottomY
  elseif hasTop then
    y = topY
  else
    local bottomRoom = maxH - self.mouseY
    local topRoom = self.mouseY
    y = (bottomRoom >= topRoom) and bottomY or topY
  end

  -- Final safety clamp.
  if x < 0 then x = 0 end
  if y < 0 then y = 0 end
  if x + boxW > maxW then x = maxW - boxW end
  if y + boxH > maxH then y = maxH - boxH end

  local bg = colors.tooltipBg or { 1.0, 0.98, 0.75 }
  local fg = colors.black or { 0, 0, 0 }

  love.graphics.setColor(bg[1], bg[2], bg[3], 1)
  love.graphics.rectangle("fill", x, y, boxW, boxH)
  Text.print(text, math.floor(x + PADDING_X), math.floor(y + PADDING_Y), {
    color = { fg[1], fg[2], fg[3], 1 },
  })
  love.graphics.setColor(colors.white)
end

return TooltipController
