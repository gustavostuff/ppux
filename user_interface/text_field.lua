-- text_field.lua
-- Text input field component using love.textinput

local colors = require("app_colors")

local TextField = {}
TextField.__index = TextField

local KEY_REPEAT_DELAY_SECONDS = 0.5
local KEY_REPEAT_INTERVAL_SECONDS = 0.05
local KEY_REPEAT_EPSILON = 0.000001

local function getNowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function isKeyDown(key)
  return love
    and love.keyboard
    and love.keyboard.isDown
    and love.keyboard.isDown(key)
end

local function isHexChar(ch)
  return type(ch) == "string" and ch:match("^[0-9A-Fa-f]$") ~= nil
end

local function uppercaseOrNil(ch)
  if type(ch) ~= "string" then return nil end
  return string.upper(ch)
end

function TextField.new(opts)
  opts = opts or {}

  local defaultButtonSize = opts.buttonSize or 15
  local defaultWidth = (opts.width or (defaultButtonSize * 4))
  local defaultHeight = opts.height or defaultButtonSize
  local mask = opts.mask

  local self = setmetatable({
    x = opts.x or 0,
    y = opts.y or 0,
    w = defaultWidth,
    h = defaultHeight,
    text = {},
    cursorPos = 1,
    scrollOffset = 0,
    focused = false,
    visible = opts.visible ~= false,
    enabled = opts.enabled ~= false,
    mask = (type(mask) == "string" and mask ~= "") and mask or nil,
    keyRepeatDelay = opts.keyRepeatDelay or KEY_REPEAT_DELAY_SECONDS,
    keyRepeatInterval = opts.keyRepeatInterval or KEY_REPEAT_INTERVAL_SECONDS,
    _repeatKey = nil,
    _repeatStartedAt = nil,
    _repeatLastAt = nil,
  }, TextField)

  self:setText(opts.text or "")
  return self
end

function TextField:_hasMask()
  return type(self.mask) == "string" and self.mask ~= ""
end

function TextField:_maskChars()
  local chars = {}
  local mask = self.mask or ""
  for i = 1, #mask do
    chars[i] = mask:sub(i, i)
  end
  return chars
end

function TextField:_isMaskEditableIndex(index)
  if not self:_hasMask() then return false end
  local mask = self.mask or ""
  if index < 1 or index > #mask then return false end
  local ch = mask:sub(index, index)
  if ch ~= "0" then
    return false
  end
  if index == 1 and (mask:sub(2, 2) == "x" or mask:sub(2, 2) == "X") then
    return false
  end
  return true
end

function TextField:_editableIndices()
  local out = {}
  if not self:_hasMask() then return out end
  for i = 1, #(self.mask or "") do
    if self:_isMaskEditableIndex(i) then
      out[#out + 1] = i
    end
  end
  return out
end

function TextField:_firstEditableIndex()
  local indices = self:_editableIndices()
  return indices[1] or 1
end

function TextField:_lastEditableIndex()
  local indices = self:_editableIndices()
  return indices[#indices] or 1
end

function TextField:_nextEditableIndex(index)
  if not self:_hasMask() then return nil end
  for i = (index or 0) + 1, #(self.mask or "") do
    if self:_isMaskEditableIndex(i) then
      return i
    end
  end
  return nil
end

function TextField:_prevEditableIndex(index)
  if not self:_hasMask() then return nil end
  for i = (index or 0) - 1, 1, -1 do
    if self:_isMaskEditableIndex(i) then
      return i
    end
  end
  return nil
end

function TextField:_normalizeMaskedInputCharacters(str)
  local chars = {}
  str = tostring(str or "")
  for i = 1, #str do
    local ch = str:sub(i, i)
    if isHexChar(ch) then
      chars[#chars + 1] = uppercaseOrNil(ch)
    end
  end
  return chars
end

function TextField:_buildMaskedText(str)
  local chars = self:_maskChars()
  local editable = self:_editableIndices()
  local values = self:_normalizeMaskedInputCharacters(str)
  local start = math.max(1, (#editable - #values) + 1)

  for i = start, #editable do
    local valueIndex = i - start + 1
    chars[editable[i]] = values[valueIndex]
  end

  return chars
end

function TextField:_setRepeatKey(key)
  if key ~= "left" and key ~= "right" then
    self._repeatKey = nil
    self._repeatStartedAt = nil
    self._repeatLastAt = nil
    return
  end

  local now = getNowSeconds()
  self._repeatKey = key
  self._repeatStartedAt = now
  self._repeatLastAt = nil
end

function TextField:_clearRepeatKey(key)
  if key and self._repeatKey ~= key then return end
  self._repeatKey = nil
  self._repeatStartedAt = nil
  self._repeatLastAt = nil
end

function TextField:_moveCursorLeft()
  if self:_hasMask() then
    local prev = self:_prevEditableIndex(self.cursorPos)
    if prev then
      self.cursorPos = prev
      self:_updateScroll()
      return true
    end
    return false
  end

  if self.cursorPos > 1 then
    self.cursorPos = self.cursorPos - 1
    self:_updateScroll()
    return true
  end
  return false
end

function TextField:_moveCursorRight()
  if self:_hasMask() then
    local nextIndex = self:_nextEditableIndex(self.cursorPos)
    if nextIndex then
      self.cursorPos = nextIndex
      self:_updateScroll()
      return true
    end
    return false
  end

  if self.cursorPos <= #self.text then
    self.cursorPos = self.cursorPos + 1
    self:_updateScroll()
    return true
  end
  return false
end

function TextField:_processHeldArrowRepeat()
  if not (self.focused and self.enabled and self._repeatKey) then
    return false
  end
  if not isKeyDown(self._repeatKey) then
    self:_clearRepeatKey()
    return false
  end

  local now = getNowSeconds()
  local startedAt = self._repeatStartedAt or now
  if now + KEY_REPEAT_EPSILON < (startedAt + self.keyRepeatDelay) then
    return false
  end

  if type(self._repeatLastAt) ~= "number" then
    local changed = false
    if self._repeatKey == "left" then
      changed = self:_moveCursorLeft()
    elseif self._repeatKey == "right" then
      changed = self:_moveCursorRight()
    end
    self._repeatLastAt = now
    return changed
  end

  if now + KEY_REPEAT_EPSILON < (self._repeatLastAt + self.keyRepeatInterval) then
    return false
  end

  local changed = false
  if self._repeatKey == "left" then
    changed = self:_moveCursorLeft()
  elseif self._repeatKey == "right" then
    changed = self:_moveCursorRight()
  end

  self._repeatLastAt = now
  return changed
end

function TextField:getText()
  return table.concat(self.text, "")
end

function TextField:setText(str)
  if self:_hasMask() then
    self.text = self:_buildMaskedText(str)
    local values = self:_normalizeMaskedInputCharacters(str)
    if #values > 0 then
      local editable = self:_editableIndices()
      local idx = editable[#editable] or self:_firstEditableIndex()
      self.cursorPos = idx
    else
      self.cursorPos = self:_firstEditableIndex()
    end
  else
    str = str or ""
    self.text = {}
    for i = 1, #str do
      self.text[i] = str:sub(i, i)
    end
    self.cursorPos = math.min(#self.text + 1, #str + 1)
  end

  self.scrollOffset = 0
  self:_updateScroll()
end

function TextField:contains(px, py)
  if not self.visible then return false end
  return px >= self.x and px <= self.x + self.w and
         py >= self.y and py <= self.y + self.h
end

function TextField:onTextInput(text)
  if not self.focused or not self.enabled then return false end

  if self:_hasMask() then
    local inserted = false
    for i = 1, #(text or "") do
      local ch = uppercaseOrNil((text or ""):sub(i, i))
      if isHexChar(ch) and self:_isMaskEditableIndex(self.cursorPos) then
        self.text[self.cursorPos] = ch
        inserted = true
        local nextIndex = self:_nextEditableIndex(self.cursorPos)
        if nextIndex then
          self.cursorPos = nextIndex
        end
      end
    end
    if inserted then
      self:_updateScroll()
    end
    return inserted
  end

  table.insert(self.text, self.cursorPos, text)
  self.cursorPos = self.cursorPos + 1
  self:_updateScroll()
  return true
end

function TextField:_updateScroll()
  if not self.focused then
    self.scrollOffset = 0
    return
  end

  local font = love.graphics.getFont()
  local padding = 2
  local visibleWidth = self.w - (padding * 2) - 1

  if visibleWidth <= 0 then
    self.scrollOffset = 0
    return
  end

  local cursorPixelPos = 0
  if self:_hasMask() then
    if self.cursorPos > 1 and self.cursorPos <= #self.text then
      local textBeforeCursor = table.concat(self.text, "", 1, self.cursorPos - 1)
      cursorPixelPos = font:getWidth(textBeforeCursor)
    end
  elseif self.cursorPos > 1 and self.cursorPos <= #self.text + 1 then
    local textBeforeCursor = table.concat(self.text, "", 1, self.cursorPos - 1)
    cursorPixelPos = font:getWidth(textBeforeCursor)
  end

  local scrollPixelPos = 0
  if self.scrollOffset > 0 and self.scrollOffset <= #self.text then
    local textBeforeScroll = table.concat(self.text, "", 1, self.scrollOffset)
    scrollPixelPos = font:getWidth(textBeforeScroll)
  end

  if cursorPixelPos < scrollPixelPos then
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

function TextField:onKeyPressed(key)
  if not self.focused or not self.enabled then return false end

  if key == "left" then
    self:_moveCursorLeft()
    self:_setRepeatKey(key)
    return true
  elseif key == "right" then
    self:_moveCursorRight()
    self:_setRepeatKey(key)
    return true
  elseif key == "backspace" then
    self:_clearRepeatKey()
    if self:_hasMask() then
      local prev = self:_prevEditableIndex(self.cursorPos + 1) or self.cursorPos
      if self:_isMaskEditableIndex(prev) then
        self.cursorPos = prev
        self.text[self.cursorPos] = "0"
        self:_updateScroll()
      end
      return true
    end
    if self.cursorPos > 1 then
      table.remove(self.text, self.cursorPos - 1)
      self.cursorPos = self.cursorPos - 1
      self:_updateScroll()
    end
    return true
  elseif key == "delete" then
    self:_clearRepeatKey()
    if self:_hasMask() then
      if self:_isMaskEditableIndex(self.cursorPos) then
        self.text[self.cursorPos] = "0"
        self:_updateScroll()
      end
      return true
    end
    if self.cursorPos <= #self.text then
      table.remove(self.text, self.cursorPos)
      self:_updateScroll()
    end
    return true
  end

  self:_clearRepeatKey()
  return false
end

function TextField:setFocused(focused)
  self.focused = focused ~= false
  if self.focused then
    if self:_hasMask() and not self:_isMaskEditableIndex(self.cursorPos) then
      self.cursorPos = self:_firstEditableIndex()
    end
  else
    self:_clearRepeatKey()
  end
end

function TextField:setPosition(x, y)
  self.x = x or self.x
  self.y = y or self.y
end

function TextField:setSize(w, h)
  self.w = w or self.w
  self.h = h or self.h
end

function TextField:update()
  self:_processHeldArrowRepeat()
end

function TextField:draw()
  if not self.visible then return end

  self:update()

  local bgColor = self.focused and colors.gray10 or colors.gray20
  love.graphics.setColor(bgColor)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

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

  local visibleStart = math.max(1, self.scrollOffset + 1)
  local visibleText = {}
  for i = visibleStart, #self.text do
    visibleText[#visibleText + 1] = self.text[i]
  end
  local textStr = table.concat(visibleText, "")

  if textStr ~= "" then
    love.graphics.setColor(colors.white)
    love.graphics.print(textStr, textX, textY)
  end

  if self.focused then
    self:_updateScroll()
    local time = getNowSeconds()
    local blinkOn = math.floor(time * 2) % 2 == 0
    if blinkOn then
      local cursorX = textX
      if self.cursorPos > 1 then
        local textBeforeCursor = table.concat(self.text, "", 1, math.max(0, self.cursorPos - 1))
        local cursorPixelPos = font:getWidth(textBeforeCursor)
        local scrollPixelPos = 0
        if self.scrollOffset > 0 then
          local textBeforeScroll = table.concat(self.text, "", 1, self.scrollOffset)
          scrollPixelPos = font:getWidth(textBeforeScroll)
        end
        cursorX = textX + (cursorPixelPos - scrollPixelPos)
      end

      if self:_hasMask() and self:_isMaskEditableIndex(self.cursorPos) then
        local symbol = self.text[self.cursorPos] or "0"
        local symbolW = math.max(4, font:getWidth(symbol))
        love.graphics.setColor(colors.white)
        love.graphics.rectangle("fill", cursorX, textY, symbolW, font:getHeight())
        love.graphics.setColor(bgColor)
        love.graphics.print(symbol, cursorX, textY)
      else
        love.graphics.setColor(colors.white)
        love.graphics.rectangle("fill", cursorX, textY, 1, font:getHeight())
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
