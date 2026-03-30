-- text_field.lua
-- Text input field component using love.textinput

local colors = require("app_colors")
local Selection = require("user_interface.text_field_selection")
local Editing = require("user_interface.text_field_editing")
local Rendering = require("user_interface.text_field_rendering")

local TextField = {}
TextField.__index = TextField

local KEY_REPEAT_DELAY_SECONDS = 0.5
local KEY_REPEAT_INTERVAL_SECONDS = 0.05
local KEY_REPEAT_EPSILON = 0.000001
local CURSOR_BLINK_HZ = 4
local SELECTION_BG_COLOR = colors.blue

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

local function concatTextRange(chars, startIndex, endIndex)
  if type(chars) ~= "table" then
    return ""
  end

  local startPos = math.max(1, math.floor(tonumber(startIndex) or 1))
  local endPos = tonumber(endIndex)
  if endPos == nil then
    endPos = #chars
  else
    endPos = math.floor(endPos)
  end

  if endPos < startPos then
    return ""
  end

  local out = {}
  for i = startPos, endPos do
    local ch = chars[i]
    out[#out + 1] = (type(ch) == "string") and ch or ""
  end
  return table.concat(out, "")
end

local shared = {
  colors = colors,
  getNowSeconds = getNowSeconds,
  isKeyDown = isKeyDown,
  isHexChar = isHexChar,
  uppercaseOrNil = uppercaseOrNil,
  concatTextRange = concatTextRange,
  KEY_REPEAT_EPSILON = KEY_REPEAT_EPSILON,
  CURSOR_BLINK_HZ = CURSOR_BLINK_HZ,
  SELECTION_BG_COLOR = SELECTION_BG_COLOR,
}

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
    selectionStart = nil,
    selectionEnd = nil,
    _selectionAnchor = nil,
    _dragSelecting = false,
    _keyboardSelectionAnchor = nil,
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
  if type(index) ~= "number" then return false end
  index = math.floor(index)
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

function TextField:getText()
  return concatTextRange(self.text)
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
  self:_clearSelection()
  self:_updateScroll()
end

function TextField:contains(px, py)
  if not self.visible then return false end
  return px >= self.x and px <= self.x + self.w
    and py >= self.y and py <= self.y + self.h
end

function TextField:setFocused(focused)
  self.focused = focused ~= false
  if self.focused then
    if self:_hasMask() and not self:_isMaskEditableIndex(self.cursorPos) then
      self.cursorPos = self:_firstEditableIndex()
    end
  else
    self:_clearRepeatKey()
    self:_clearSelection()
    self._dragSelecting = false
    self._selectionAnchor = nil
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

Selection.install(TextField, shared)
Editing.install(TextField, shared)
Rendering.install(TextField, shared)

return TextField
