local function install(Panel, utils)
  function Panel:mousepressed(x, y, button)
    if not self.visible then return false end
    if not self:contains(x, y) then return false end
    if button ~= 1 then return true end

    local target = self:getComponentAt(x, y)
    self.pressedButton = nil
    self.pressedComponent = nil

    if target then
      self:setFocusedComponent(target)
    else
      self:setFocusedComponent(nil)
    end

    if target and target.action then
      target.pressed = true
      self.pressedButton = target
      return true
    end

    if target then
      self.pressedComponent = target
      if utils.callIfPresent(target, "mousepressed", x, y, button) ~= false then
        return true
      end
    end

    return true
  end

  function Panel:mousereleased(x, y, button)
    if not self.visible then return false end

    local consumed = false
    if button == 1 and self.pressedButton then
      consumed = true
      local pressedBtn = self.pressedButton
      local releasedBtn = self:getButtonAt(x, y)
      if releasedBtn == pressedBtn and pressedBtn.action then
        pressedBtn.action()
      end
    elseif button == 1 and self.pressedComponent then
      consumed = true
      utils.callIfPresent(self.pressedComponent, "mousereleased", x, y, button)
    elseif self:contains(x, y) then
      consumed = true
    end

    for _, cell in ipairs(self:_iterCells()) do
      if cell.button then
        cell.button.pressed = false
      end
      if cell.component and cell.component.action then
        cell.component.pressed = false
      end
    end
    self.pressedButton = nil
    self.pressedComponent = nil

    return consumed
  end

  local function clearCellHover(cell)
    if cell.button then
      cell.button.hovered = false
    end
    local c = cell.component
    if not c then
      return
    end
    c.hovered = false
    if c.trigger then
      c.trigger.hovered = false
    end
  end

  --- Dropdown / color-picker list drawn above the panel; suppress hover on
  --- triggers and other controls sitting under the open menu.
  local function openMenuComponentAt(panel, x, y)
    for _, cell in ipairs(panel:_iterCells()) do
      local c = cell.component
      if c and c.enabled ~= false
        and type(c.isMenuVisible) == "function" and c:isMenuVisible()
        and c.menu and type(c.menu.contains) == "function" and c.menu:contains(x, y)
      then
        return c
      end
    end
    return nil
  end

  function Panel:mousemoved(x, y)
    if not self.visible then return end

    local openMenuComp = openMenuComponentAt(self, x, y)
    if openMenuComp then
      for _, cell in ipairs(self:_iterCells()) do
        clearCellHover(cell)
      end
      if type(openMenuComp.mousemoved) == "function" then
        openMenuComp:mousemoved(x, y)
      end
      return
    end

    local hovered = self:getButtonAt(x, y) or self:getComponentAt(x, y)
    for _, cell in ipairs(self:_iterCells()) do
      if cell.button then
        cell.button.hovered = (cell.button == hovered)
      end
      if cell.component then
        cell.component.hovered = (cell.component == hovered)
      end
      if cell.component and type(cell.component.mousemoved) == "function" then
        cell.component:mousemoved(x, y)
      end
    end
  end

  function Panel:handleKey(key)
    if not self.visible then return false end
    if self.focusedComponent and type(self.focusedComponent.onKeyPressed) == "function" then
      return self.focusedComponent:onKeyPressed(key) == true
    end
    if self.focusedComponent and type(self.focusedComponent.handleKey) == "function" then
      return self.focusedComponent:handleKey(key) == true
    end
    return false
  end

  function Panel:textinput(text)
    if not self.visible then return false end
    if self.focusedComponent and type(self.focusedComponent.onTextInput) == "function" then
      return self.focusedComponent:onTextInput(text) == true
    end
    if self.focusedComponent and type(self.focusedComponent.textinput) == "function" then
      return self.focusedComponent:textinput(text) == true
    end
    return false
  end
end

return {
  install = install,
}
