local Panel = require("ui.panel")

describe("panel.lua", function()
  it("lays out arbitrary components with colspan and rowspan", function()
    local component = {
      setPosition = function(self, x, y)
        self.x = x
        self.y = y
      end,
      setSize = function(self, w, h)
        self.w = w
        self.h = h
      end,
    }

    local panel = Panel.new({
      x = 10,
      y = 20,
      cols = 3,
      rows = 2,
      cellW = 50,
      cellH = 10,
      padding = 2,
      spacingX = 3,
      spacingY = 4,
      visible = true,
    })

    panel:setCell(2, 1, {
      component = component,
      colspan = 2,
      rowspan = 2,
    })

    local cell = panel:getCell(2, 1)
    expect(cell).toBeTruthy()
    expect(panel:getCell(3, 1)).toBe(cell)
    expect(panel:getCell(2, 2)).toBe(cell)
    expect(panel:getCell(3, 2)).toBe(cell)

    expect(component.x).toBe(65)
    expect(component.y).toBe(22)
    expect(component.w).toBe(103)
    expect(component.h).toBe(24)
  end)

  it("honors per-column cellWidths from Panel.new", function()
    local panel = Panel.new({
      cols = 2,
      rows = 1,
      cellW = 50,
      cellH = 10,
      padding = 0,
      spacingX = 0,
      cellWidths = {
        [1] = 100,
        [2] = 250,
      },
      visible = true,
    })
    expect(panel.w).toBe(350)
    panel:setCell(1, 1, { text = "L" })
    panel:setCell(2, 1, { text = "R" })
    local left = panel:getCell(1, 1)
    local right = panel:getCell(2, 1)
    expect(left.w).toBe(100)
    expect(right.w).toBe(250)
  end)

  it("overwrites intersecting cells when a spanning cell covers them", function()
    local panel = Panel.new({
      cols = 3,
      rows = 2,
      cellW = 20,
      cellH = 10,
      visible = true,
    })

    panel:setCell(2, 1, { text = "B" })
    panel:setCell(3, 1, { text = "C" })
    panel:setCell(2, 1, {
      text = "Wide",
      colspan = 2,
      rowspan = 2,
    })

    local wide = panel:getCell(2, 1)
    expect(wide).toBeTruthy()
    expect(wide.text).toBe("Wide")
    expect(panel:getCell(3, 1)).toBe(wide)
    expect(panel:getCell(2, 2)).toBe(wide)
    expect(panel:getCell(3, 2)).toBe(wide)
  end)

  it("routes mouse and text input to focused generic components", function()
    local events = {}
    local component = {
      setPosition = function() end,
      setSize = function() end,
      contains = function() return true end,
      setFocused = function(self, focused)
        self.focused = focused
      end,
      mousepressed = function(self, x, y, button)
        events[#events + 1] = { "mousepressed", x, y, button }
        return true
      end,
      mousereleased = function(self, x, y, button)
        events[#events + 1] = { "mousereleased", x, y, button }
        return true
      end,
      onKeyPressed = function(self, key)
        events[#events + 1] = { "key", key }
        return true
      end,
      onTextInput = function(self, text)
        events[#events + 1] = { "text", text }
        return true
      end,
    }

    local panel = Panel.new({
      cols = 1,
      rows = 1,
      cellW = 60,
      cellH = 18,
      visible = true,
    })
    panel:setCell(1, 1, { component = component })

    expect(panel:mousepressed(5, 5, 1)).toBe(true)
    expect(component.focused).toBe(true)
    expect(panel:handleKey("a")).toBe(true)
    expect(panel:textinput("b")).toBe(true)
    expect(panel:mousereleased(5, 5, 1)).toBe(true)

    expect(events[1][1]).toBe("mousepressed")
    expect(events[2][1]).toBe("key")
    expect(events[3][1]).toBe("text")
    expect(events[4][1]).toBe("mousereleased")
  end)

  it("does not hover covered dropdown triggers while an open menu is under the cursor", function()
    local Dropdown = require("ui.dropdown")
    local items = {
      { value = 1, text = "One" },
      { value = 2, text = "Two" },
      { value = 3, text = "Three" },
    }
    local top = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 400 }
      end,
      items = items,
    })
    local bottom = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 400 }
      end,
      items = items,
    })

    local panel = Panel.new({
      x = 0,
      y = 0,
      cols = 1,
      rows = 2,
      cellW = 120,
      cellH = 20,
      padding = 0,
      spacingY = 0,
      visible = true,
    })
    panel:setCell(1, 1, { component = top })
    panel:setCell(1, 2, { component = bottom })

    expect(top:openMenu()).toBe(true)
    expect(top:isMenuVisible()).toBe(true)

    -- Menu hangs below the top trigger and covers the bottom trigger cell.
    local overBottom = {
      x = bottom.trigger.x + 4,
      y = bottom.trigger.y + 4,
    }
    expect(top.menu:contains(overBottom.x, overBottom.y)).toBe(true)
    expect(bottom.trigger:contains(overBottom.x, overBottom.y)).toBe(true)

    panel:mousemoved(overBottom.x, overBottom.y)

    expect(bottom.trigger.hovered).toBe(false)
    expect(bottom.hovered == true).toBe(false)
  end)
end)
