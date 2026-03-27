-- text_field.lua
-- Text input field component using love.textinput

local colors = require("app_colors")
local TextUtils = require("utils.text_utils")

local TextField = {}
TextField.__index = TextField

function TextField.new(opts)
  opts = opts or {}
  
  -- Default size spans 4 buttons (button size is typically toolbar height, usually around 15px)
  local defaultButtonSize = opts.buttonSize or 15
  local defaultWidth = (opts.width or (defaultButtonSize * 4))
  local defaultHeight = opts.height or defaultButtonSize
  
  local self = setmetatable({
    x = opts.x or 0,
    y = opts.y or 0,
    w = defaultWidth,
    h = defaultHeight,
    text = {},  -- Table of characters
    cursorPos = 1,  -- Cursor position (1-based index into text array)
    scrollOffset = 0,  -- Horizontal scroll offset (number of characters to skip when drawing)
    focused = false,
    visible = opts.visible ~= false,
    enabled = opts.enabled ~= false,
  }, TextField)
  
  return self
end

-- Get text as string
function TextField:getText()
  return table.concat(self.text, "")
end

-- Set text from string
function TextField:setText(str)
  str = str or ""
  self.text = {}
  for i = 1, #str do
    self.text[i] = str:sub(i, i)
  end
  self.cursorPos = math.min(#self.text + 1, #str + 1)
  self.scrollOffset = 0  -- Reset scroll when setting text
  self:_updateScroll()
end

-- Check if a point is inside the text field
function TextField:contains(px, py)
  if not self.visible then return false end
  return px >= self.x and px <= self.x + self.w and
         py >= self.y and py <= self.y + self.h
end

-- Handle text input (called from love.textinput)
function TextField:onTextInput(text)
  if not self.focused or not self.enabled then return false end
  
  -- Insert character at cursor position
  table.insert(self.text, self.cursorPos, text)
  self.cursorPos = self.cursorPos + 1
  self:_updateScroll()
  return true
end

-- Update scroll offset to ensure cursor is visible
function TextField:_updateScroll()
  if not self.focused then 
    self.scrollOffset = 0
    return 
  end
  
  local font = love.graphics.getFont()
  local padding = 2
  local visibleWidth = self.w - (padding * 2) - 1  -- -1 for cursor
  
  if visibleWidth <= 0 then
    self.scrollOffset = 0
    return
  end
  
  -- Calculate cursor position in pixels (from start of full text)
  local cursorPixelPos = 0
  if self.cursorPos > 1 and self.cursorPos <= #self.text + 1 then
    local textBeforeCursor = table.concat(self.text, "", 1, self.cursorPos - 1)
    cursorPixelPos = font:getWidth(textBeforeCursor)
  end
  
  -- Calculate current scroll position in pixels
  local scrollPixelPos = 0
  if self.scrollOffset > 0 and self.scrollOffset <= #self.text then
    local textBeforeScroll = table.concat(self.text, "", 1, self.scrollOffset)
    scrollPixelPos = font:getWidth(textBeforeScroll)
  end
  
  -- Check if cursor is outside visible range
  if cursorPixelPos < scrollPixelPos then
    -- Cursor is to the left - scroll to show cursor at left edge
    -- Find scroll offset that positions cursor at left edge
    self.scrollOffset = 0
    if self.cursorPos > 1 then
      for i = 1, self.cursorPos - 1 do
        local testText = table.concat(self.text, "", 1, i - 1)
        local testPixel = font:getWidth(testText)
        if testPixel <= cursorPixelPos then
          self.scrollOffset = i
        else
          break
        end
      end
    end
  elseif cursorPixelPos > scrollPixelPos + visibleWidth then
    -- Cursor is to the right - scroll to show cursor at right edge
    local targetPixelPos = cursorPixelPos - visibleWidth
    self.scrollOffset = 1
    for i = 1, #self.text do
      local testText = table.concat(self.text, "", 1, i - 1)
      local testPixel = font:getWidth(testText)
      if testPixel < targetPixelPos then
        self.scrollOffset = i
      else
        break
      end
    end
  end
end

-- Handle key presses (cursor movement, delete, backspace)
function TextField:onKeyPressed(key)
  if not self.focused or not self.enabled then return false end
  
  if key == "left" then
    -- Move cursor left
    if self.cursorPos > 1 then
      self.cursorPos = self.cursorPos - 1
      self:_updateScroll()
    end
    return true
  elseif key == "right" then
    -- Move cursor right
    if self.cursorPos <= #self.text then
      self.cursorPos = self.cursorPos + 1
      self:_updateScroll()
    end
    return true
  elseif key == "backspace" then
    -- Delete character before cursor
    if self.cursorPos > 1 then
      table.remove(self.text, self.cursorPos - 1)
      self.cursorPos = self.cursorPos - 1
      self:_updateScroll()
    end
    return true
  elseif key == "delete" then
    -- Delete character at cursor
    if self.cursorPos <= #self.text then
      table.remove(self.text, self.cursorPos)
      self:_updateScroll()
    end
    return true
  end
  
  return false
end

-- Set focus state
function TextField:setFocused(focused)
  self.focused = focused ~= false
end

-- Update button position
function TextField:setPosition(x, y)
  self.x = x or self.x
  self.y = y or self.y
end

-- Update button size
function TextField:setSize(w, h)
  self.w = w or self.w
  self.h = h or self.h
end

-- Draw the text field
function TextField:draw()
  if not self.visible then return end

  -- Draw background
  local bgColor = self.focused and colors.gray10 or colors.gray20
  love.graphics.setColor(bgColor)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

  -- Draw text (only visible portion)
  local font = love.graphics.getFont()
  local padding = 2
  local textX = self.x + padding
  local textY = self.y + (self.h - font:getHeight()) / 2
  local clipX = math.floor(self.x + padding)
  local clipY = math.floor(self.y)
  local clipW = math.max(0, math.floor(self.w - (padding * 2)))
  local clipH = math.max(0, math.floor(self.h))
  local prevScissor = { love.graphics.getScissor() }

  if clipW > 0 and clipH > 0 then
    love.graphics.setScissor(clipX, clipY, clipW, clipH)
  end

  if #self.text > 0 then
    -- Draw only the visible portion of text
    local visibleStart = math.max(1, self.scrollOffset + 1)
    local visibleText = {}
    for i = visibleStart, #self.text do
      table.insert(visibleText, self.text[i])
    end
    
    if #visibleText > 0 then
      local textStr = table.concat(visibleText, "")
      love.graphics.setColor(colors.white)

      love.graphics.print(textStr, textX, textY)
    end
    
    -- Draw cursor if focused
    if self.focused then
      self:_updateScroll()  -- Ensure scroll is up to date
      
      local cursorX = textX
      if self.cursorPos > 1 then
        local textBeforeCursor = table.concat(self.text, "", 1, self.cursorPos - 1)
        local cursorPixelPos = font:getWidth(textBeforeCursor)
        local scrollPixelPos = 0
        if self.scrollOffset > 0 then
          local textBeforeScroll = table.concat(self.text, "", 1, self.scrollOffset)
          scrollPixelPos = font:getWidth(textBeforeScroll)
        end
        cursorX = textX + (cursorPixelPos - scrollPixelPos)
      end
      
      -- Blinking cursor (simple toggle based on time)
      local time = love.timer.getTime()
      if math.floor(time * 2) % 2 == 0 then  -- Blink every 0.5 seconds
        love.graphics.setColor(colors.white)
        love.graphics.rectangle("fill", cursorX, textY, 1, font:getHeight())
      end
    end
  else
    -- Draw cursor at start if empty and focused
    if self.focused then
      local time = love.timer.getTime()
      if math.floor(time * 2) % 2 == 0 then
        love.graphics.setColor(colors.white)
        love.graphics.rectangle("fill", textX, textY, 1, font:getHeight())
      end
    end
  end

  if prevScissor[1] ~= nil then
    love.graphics.setScissor(prevScissor[1], prevScissor[2], prevScissor[3], prevScissor[4])
  else
    love.graphics.setScissor()
  end

  love.graphics.setColor(colors.white)
end

return TextField
