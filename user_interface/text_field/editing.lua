local function install(TextField, utils)
  function TextField:_clearKeyboardSelectionAnchor()
    self._keyboardSelectionAnchor = nil
  end

  function TextField:_cursorLeftStepFrom(pos)
    pos = math.floor(tonumber(pos) or self.cursorPos or 1)
    if self:_hasMask() then
      return self:_prevEditableIndex(pos)
    end
    if pos > 1 then
      return pos - 1
    end
    return nil
  end

  function TextField:_cursorRightStepFrom(pos)
    pos = math.floor(tonumber(pos) or self.cursorPos or 1)
    if self:_hasMask() then
      return self:_nextEditableIndex(pos)
    end
    if pos <= #self.text then
      return pos + 1
    end
    return nil
  end

  function TextField:_setRepeatKey(key)
    if key ~= "left" and key ~= "right" and key ~= "backspace" then
      self._repeatKey = nil
      self._repeatStartedAt = nil
      self._repeatLastAt = nil
      return
    end

    local now = utils.getNowSeconds()
    self._repeatKey = key
    self._repeatStartedAt = now
    self._repeatLastAt = nil
  end

  function TextField:_clearRepeatKey(key)
    if key and self._repeatKey ~= key then return end
    self._repeatKey = nil
    self._repeatStartedAt = nil
    self._repeatLastAt = nil
    self:_clearKeyboardSelectionAnchor()
  end

  function TextField:_moveCursorLeftStep()
    local prev = self:_cursorLeftStepFrom(self.cursorPos)
    if prev then
      self.cursorPos = prev
      self:_updateScroll()
      return true
    end
    return false
  end

  function TextField:_moveCursorRightStep()
    local nextIndex = self:_cursorRightStepFrom(self.cursorPos)
    if nextIndex then
      self.cursorPos = nextIndex
      self:_updateScroll()
      return true
    end
    return false
  end

  function TextField:_replaceSelectionWithText(text)
    self:_clearKeyboardSelectionAnchor()
    if self:_hasMask() then
      local targets = {}
      if self:_hasSelection() then
        targets = self:_maskedSelectionEditableIndices()
        for _, idx in ipairs(targets) do
          self.text[idx] = "0"
        end
      elseif self:_isMaskEditableIndex(self.cursorPos) then
        local idx = self.cursorPos
        while idx do
          targets[#targets + 1] = idx
          idx = self:_nextEditableIndex(idx)
        end
      end

      if #targets == 0 then
        self:_clearSelection()
        return false
      end

      local inserted = false
      local writeIndex = 1
      local values = self:_normalizeMaskedInputCharacters(text or "")
      for i = 1, #values do
        local ch = values[i]
        if utils.isHexChar(ch) and targets[writeIndex] then
          local idx = targets[writeIndex]
          self.text[idx] = ch
          self.cursorPos = idx
          writeIndex = writeIndex + 1
          inserted = true
        end
      end

      local nextIndex = self:_nextEditableIndex(self.cursorPos)
      if inserted and nextIndex then
        self.cursorPos = nextIndex
      end
      self:_clearSelection()
      self:_updateScroll()
      return inserted
    end

    local startIndex, endIndex = self:_getSelectionBounds()
    if startIndex and endIndex then
      for _ = endIndex, startIndex, -1 do
        table.remove(self.text, startIndex)
      end
      self.cursorPos = startIndex
      self:_clearSelection()
    end

    local insertedCount = 0
    for i = 1, #(text or "") do
      table.insert(self.text, self.cursorPos + insertedCount, text:sub(i, i))
      insertedCount = insertedCount + 1
    end
    self.cursorPos = self.cursorPos + insertedCount
    self:_updateScroll()
    return insertedCount > 0
  end

  function TextField:_deleteSelection()
    self:_clearKeyboardSelectionAnchor()
    local startIndex, endIndex = self:_getSelectionBounds()
    if not (startIndex and endIndex) then
      return false
    end

    if self:_hasMask() then
      for i = startIndex, endIndex do
        if self:_isMaskEditableIndex(i) then
          self.text[i] = "0"
        end
      end
      self.cursorPos = self:_normalizeMaskCursor(startIndex)
    else
      for _ = endIndex, startIndex, -1 do
        table.remove(self.text, startIndex)
      end
      self.cursorPos = startIndex
    end

    self:_clearSelection()
    self:_updateScroll()
    return true
  end

  function TextField:_deleteBackward()
    self:_clearKeyboardSelectionAnchor()
    if self:_hasSelection() then
      return self:_deleteSelection()
    end

    if self:_hasMask() then
      local prev = self:_prevEditableIndex(self.cursorPos)
      if self:_isMaskEditableIndex(prev) then
        self.cursorPos = prev
        self.text[self.cursorPos] = "0"
        self:_updateScroll()
        return true
      end
      return false
    end

    if self.cursorPos > 1 then
      table.remove(self.text, self.cursorPos - 1)
      self.cursorPos = self.cursorPos - 1
      self:_updateScroll()
      return true
    end
    return false
  end

  function TextField:_deleteForward()
    self:_clearKeyboardSelectionAnchor()
    if self:_hasSelection() then
      return self:_deleteSelection()
    end

    if self:_hasMask() then
      if self:_isMaskEditableIndex(self.cursorPos) then
        self.text[self.cursorPos] = "0"
        self:_updateScroll()
        return true
      end
      return false
    end

    if self.cursorPos <= #self.text then
      table.remove(self.text, self.cursorPos)
      self:_updateScroll()
      return true
    end
    return false
  end

  function TextField:_moveCursorLeft()
    self:_clearKeyboardSelectionAnchor()
    if self:_hasSelection() then
      local startIndex = self.selectionStart
      self:_clearSelection()
      if self:_hasMask() then
        self.cursorPos = self:_normalizeMaskCursor(startIndex)
      else
        self.cursorPos = startIndex
      end
      self:_updateScroll()
      return true
    end

    return self:_moveCursorLeftStep()
  end

  function TextField:_moveCursorRight()
    self:_clearKeyboardSelectionAnchor()
    if self:_hasSelection() then
      local endIndex = self.selectionEnd
      self:_clearSelection()
      if self:_hasMask() then
        local nextIndex = self:_nextEditableIndex(endIndex)
        self.cursorPos = nextIndex or self:_lastEditableIndex()
      else
        self.cursorPos = endIndex + 1
      end
      self:_updateScroll()
      return true
    end

    return self:_moveCursorRightStep()
  end

  function TextField:_processHeldKeyRepeat()
    if not (self.focused and self.enabled and self._repeatKey) then
      return false
    end
    if not utils.isKeyDown(self._repeatKey) then
      self:_clearRepeatKey()
      return false
    end

    local now = utils.getNowSeconds()
    local startedAt = self._repeatStartedAt or now
    if now + utils.KEY_REPEAT_EPSILON < (startedAt + self.keyRepeatDelay) then
      return false
    end

    if type(self._repeatLastAt) ~= "number" then
      local changed = false
      if self._repeatKey == "left" then
        changed = self:_moveCursorLeft()
      elseif self._repeatKey == "right" then
        changed = self:_moveCursorRight()
      elseif self._repeatKey == "backspace" then
        changed = self:_deleteBackward()
      end
      self._repeatLastAt = now
      return changed
    end

    if now + utils.KEY_REPEAT_EPSILON < (self._repeatLastAt + self.keyRepeatInterval) then
      return false
    end

    local changed = false
    if self._repeatKey == "left" then
      changed = self:_moveCursorLeft()
    elseif self._repeatKey == "right" then
      changed = self:_moveCursorRight()
    elseif self._repeatKey == "backspace" then
      changed = self:_deleteBackward()
    end

    self._repeatLastAt = now
    return changed
  end

  function TextField:onTextInput(text)
    if not self.focused or not self.enabled then return false end
    self:_clearRepeatKey()
    return self:_replaceSelectionWithText(text)
  end

  function TextField:onKeyPressed(key)
    if not self.focused or not self.enabled then return false end

    local ctrlDown = utils.isKeyDown("lctrl") or utils.isKeyDown("rctrl")
    local guiDown = utils.isKeyDown("lgui") or utils.isKeyDown("rgui")
    local shortcutDown = ctrlDown or guiDown

    if key == "left" then
      self:_moveCursorLeft()
      self:_setRepeatKey(key)
      return true
    elseif key == "right" then
      self:_moveCursorRight()
      self:_setRepeatKey(key)
      return true
    elseif key == "backspace" then
      self:_deleteBackward()
      self:_setRepeatKey(key)
      return true
    elseif key == "delete" then
      self:_clearRepeatKey()
      self:_deleteForward()
      return true
    elseif key == "a" and shortcutDown then
      self:_clearRepeatKey()
      return self:selectAll()
    elseif key == "v" and shortcutDown then
      self:_clearRepeatKey()
      local text = utils.getClipboardText and utils.getClipboardText() or nil
      if type(text) ~= "string" or text == "" then
        return false
      end
      return self:_replaceSelectionWithText(text)
    end

    self:_clearRepeatKey()
    return false
  end

  function TextField:update()
    self:_processHeldKeyRepeat()
  end
end

return {
  install = install,
}
