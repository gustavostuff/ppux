local function install(TextField, utils)
  function TextField:_clearSelection()
    self.selectionStart = nil
    self.selectionEnd = nil
  end

  function TextField:_hasSelection()
    return type(self.selectionStart) == "number"
      and type(self.selectionEnd) == "number"
      and self.selectionStart <= self.selectionEnd
  end

  function TextField:_getSelectionBounds()
    if not self:_hasSelection() then
      return nil, nil
    end
    return self.selectionStart, self.selectionEnd
  end

  function TextField:_setSelection(startIndex, endIndex)
    startIndex = math.floor(tonumber(startIndex) or 0)
    endIndex = math.floor(tonumber(endIndex) or 0)
    if startIndex > endIndex then
      startIndex, endIndex = endIndex, startIndex
    end
    if startIndex < 1 or endIndex < 1 then
      self:_clearSelection()
      return false
    end
    self.selectionStart = startIndex
    self.selectionEnd = math.min(#self.text, endIndex)
    if self.selectionStart > self.selectionEnd then
      self:_clearSelection()
      return false
    end
    return true
  end

  function TextField:selectAll()
    if #self.text == 0 then
      self:_clearSelection()
      return false
    end
    self:_setSelection(1, #self.text)
    if self:_hasMask() then
      self.cursorPos = self:_firstEditableIndex()
    else
      self.cursorPos = #self.text + 1
    end
    self:_updateScroll()
    return true
  end

  function TextField:_normalizeMaskCursor(index)
    if not self:_hasMask() then
      return index
    end
    if self:_isMaskEditableIndex(index) then
      return index
    end
    local nextIndex = self:_nextEditableIndex((index or 1) - 1)
    if nextIndex then
      return nextIndex
    end
    local prev = self:_prevEditableIndex((index or 1) + 1)
    if prev then
      return prev
    end
    return self:_firstEditableIndex()
  end

  function TextField:_maskedSelectionEditableIndices()
    local out = {}
    local startIndex, endIndex = self:_getSelectionBounds()
    if not (startIndex and endIndex) then
      return out
    end
    for i = startIndex, endIndex do
      if self:_isMaskEditableIndex(i) then
        out[#out + 1] = i
      end
    end
    return out
  end

  function TextField:_selectionDisplayRange()
    local startIndex, endIndex = self:_getSelectionBounds()
    if not (startIndex and endIndex) then
      return nil, nil
    end
    return startIndex, endIndex
  end

  function TextField:_currentScrollPixelPos(font)
    if self.scrollOffset > 0 then
      local textBeforeScroll = table.concat(self.text, "", 1, self.scrollOffset)
      return font:getWidth(textBeforeScroll)
    end
    return 0
  end

  function TextField:_cursorPosFromMouseX(px)
    local font = love.graphics.getFont()
    local padding = 2
    local localX = math.max(0, (px or 0) - (self.x + padding))
    local absoluteX = localX + self:_currentScrollPixelPos(font)

    if self:_hasMask() then
      if #self.text == 0 then
        return self:_firstEditableIndex()
      end
      for i = 1, #self.text do
        local before = font:getWidth(table.concat(self.text, "", 1, i - 1))
        local width = font:getWidth(self.text[i] or "")
        local mid = before + (width * 0.5)
        if absoluteX <= mid then
          return i
        end
      end
      return #self.text
    end

    for i = 1, #self.text do
      local before = font:getWidth(table.concat(self.text, "", 1, i - 1))
      local after = font:getWidth(table.concat(self.text, "", 1, i))
      local mid = before + ((after - before) * 0.5)
      if absoluteX <= mid then
        return i
      end
    end
    return #self.text + 1
  end

  function TextField:_updateMouseSelection(px)
    if not self._dragSelecting then return false end
    local anchor = self._selectionAnchor
    if type(anchor) ~= "number" then return false end

    local current = self:_cursorPosFromMouseX(px)
    if self:_hasMask() then
      self.cursorPos = self:_normalizeMaskCursor(current)
      if current == anchor then
        self:_clearSelection()
        return true
      end
      self:_setSelection(math.min(anchor, current), math.max(anchor, current))
      return true
    end

    self.cursorPos = current
    if current == anchor then
      self:_clearSelection()
      return true
    end
    local startIndex = math.min(anchor, current)
    local endIndex = math.max(anchor, current) - 1
    self:_setSelection(startIndex, endIndex)
    return true
  end

  function TextField:mousepressed(x, y, button)
    if not self.focused or not self.enabled or button ~= 1 then return false end
    self:_clearRepeatKey()
    self._dragSelecting = true
    self._selectionAnchor = self:_cursorPosFromMouseX(x)
    self:_clearSelection()
    if self:_hasMask() then
      self.cursorPos = self:_normalizeMaskCursor(self._selectionAnchor)
    else
      self.cursorPos = self._selectionAnchor
    end
    self:_updateScroll()
    return true
  end

  function TextField:mousereleased(x, y, button)
    if button ~= 1 then return false end
    if self._dragSelecting then
      self:_updateMouseSelection(x)
    end
    self._dragSelecting = false
    return true
  end

  function TextField:mousemoved(x, y)
    if not self._dragSelecting then return false end
    return self:_updateMouseSelection(x)
  end
end

return {
  install = install,
}
