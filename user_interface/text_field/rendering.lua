local function install(TextField, utils)
  function TextField:_getVisualCursorPos()
    return self.cursorPos
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
        local textBeforeCursor = utils.concatTextRange(self.text, 1, self.cursorPos - 1)
        cursorPixelPos = font:getWidth(textBeforeCursor)
      end
    elseif self.cursorPos > 1 and self.cursorPos <= #self.text + 1 then
      local textBeforeCursor = utils.concatTextRange(self.text, 1, self.cursorPos - 1)
      cursorPixelPos = font:getWidth(textBeforeCursor)
    end

    local scrollPixelPos = 0
    if self.scrollOffset > 0 and self.scrollOffset <= #self.text then
      local textBeforeScroll = utils.concatTextRange(self.text, 1, self.scrollOffset)
      scrollPixelPos = font:getWidth(textBeforeScroll)
    end

    if cursorPixelPos < scrollPixelPos then
      self.scrollOffset = 0
      if self.cursorPos > 1 then
        for i = 1, self.cursorPos - 1 do
          local testText = utils.concatTextRange(self.text, 1, i - 1)
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
        local testText = utils.concatTextRange(self.text, 1, i - 1)
        local testPixel = font:getWidth(testText)
        if testPixel < targetPixelPos then
          self.scrollOffset = i
        else
          break
        end
      end
    end
  end

  function TextField:draw()
    if not self.visible then return end

    self:update()

    local bgColor = self.focused and utils.colors.gray10 or utils.colors.gray20
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
    local textStr = utils.concatTextRange(self.text, visibleStart, #self.text)

    if textStr ~= "" then
      local selectionStart, selectionEnd = self:_selectionDisplayRange()
      if selectionStart and selectionEnd then
        local scrollPixelPos = self:_currentScrollPixelPos(font)
        local startPixel = font:getWidth(utils.concatTextRange(self.text, 1, selectionStart - 1)) - scrollPixelPos
        local endPixel = font:getWidth(utils.concatTextRange(self.text, 1, selectionEnd)) - scrollPixelPos
        local sel = utils.SELECTION_BG_COLOR
        love.graphics.setColor(sel[1], sel[2], sel[3], 0.75)
        love.graphics.rectangle("fill", textX + startPixel, textY, math.max(1, endPixel - startPixel), font:getHeight())
      end
      love.graphics.setColor(utils.colors.white)
      love.graphics.print(textStr, textX, textY)
    end

    if self.focused then
      self:_updateScroll()
      local time = utils.getNowSeconds()
      local blinkOn = math.floor(time * utils.CURSOR_BLINK_HZ) % 2 == 0
      if blinkOn then
        local cursorPos = self:_getVisualCursorPos()
        local cursorX = textX
        if cursorPos > 1 then
          local textBeforeCursor = utils.concatTextRange(self.text, 1, math.max(0, cursorPos - 1))
          local cursorPixelPos = font:getWidth(textBeforeCursor)
          local scrollPixelPos = 0
          if self.scrollOffset > 0 then
            local textBeforeScroll = utils.concatTextRange(self.text, 1, self.scrollOffset)
            scrollPixelPos = font:getWidth(textBeforeScroll)
          end
          cursorX = textX + (cursorPixelPos - scrollPixelPos)
        end

        if self:_hasMask() and self:_isMaskEditableIndex(cursorPos) then
          local symbol = self.text[cursorPos] or "0"
          local symbolW = math.max(4, font:getWidth(symbol))
          love.graphics.setColor(utils.colors.white)
          love.graphics.rectangle("fill", cursorX, textY, symbolW, font:getHeight())
          love.graphics.setColor(bgColor)
          love.graphics.print(symbol, cursorX, textY)
        else
          love.graphics.setColor(utils.colors.white)
          love.graphics.rectangle("fill", cursorX, textY, 1, font:getHeight())
        end
      end
    end

    if prevScissor[1] ~= nil then
      love.graphics.setScissor(prevScissor[1], prevScissor[2], prevScissor[3], prevScissor[4])
    else
      love.graphics.setScissor()
    end

    love.graphics.setColor(utils.colors.white)
  end
end

return {
  install = install,
}
