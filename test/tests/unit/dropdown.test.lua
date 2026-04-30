local Dropdown = require("user_interface.dropdown")

describe("user_interface/dropdown.lua", function()
  local function makeItems()
    return {
      { value = 10, text = "Alpha" },
      { value = 20, text = "Beta" },
      { value = 30, text = "Gamma" },
    }
  end

  it("selects the first item when default is omitted", function()
    local d = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 300 }
      end,
      items = makeItems(),
    })
    expect(d:getValue()).toBe(10)
    expect(d:getLabel()).toBe("Alpha")
    expect(d.trigger.text).toBe("Alpha")
  end)

  it("selects by numeric default matching value", function()
    local d = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 300 }
      end,
      default = 20,
      items = makeItems(),
    })
    expect(d:getValue()).toBe(20)
    expect(d:getLabel()).toBe("Beta")
  end)

  it("selects by string default matching label before value", function()
    local d = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 300 }
      end,
      default = "Gamma",
      items = makeItems(),
    })
    expect(d:getValue()).toBe(30)
    expect(d:getLabel()).toBe("Gamma")
  end)

  it("matches string default to value when label does not match", function()
    local d = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 300 }
      end,
      default = "20",
      items = {
        { value = 5, text = "X" },
        { value = 20, text = "Twenty" },
      },
    })
    expect(d:getValue()).toBe(20)
    expect(d:getLabel()).toBe("Twenty")
  end)

  it("errors when default does not match any item", function()
    local ok, err = pcall(function()
      Dropdown.new({
        getBounds = function()
          return { w = 400, h = 300 }
        end,
        default = 999,
        items = makeItems(),
      })
    end)
    expect(ok).toBe(false)
    expect(tostring(err)).toBeTruthy()
    expect(tostring(err):find("default", 1, true)).toBeTruthy()
  end)

  it("errors when item has non-numeric value", function()
    local ok = pcall(function()
      Dropdown.new({
        getBounds = function()
          return { w = 400, h = 300 }
        end,
        items = {
          { value = "nope", text = "A" },
        },
      })
    end)
    expect(ok).toBe(false)
  end)

  it("errors when item is missing text", function()
    local ok = pcall(function()
      Dropdown.new({
        getBounds = function()
          return { w = 400, h = 300 }
        end,
        items = {
          { value = 1 },
        },
      })
    end)
    expect(ok).toBe(false)
  end)

  it("clears selection when setItems is empty", function()
    local d = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 300 }
      end,
      items = makeItems(),
    })
    d:setItems({})
    expect(d:getValue()).toBeNil()
    expect(d:getLabel()).toBeNil()
    expect(d.trigger.text).toBe("")
  end)

  it("fires onPick and updates value when a menu item action runs", function()
    local picked = nil
    local d = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 300 }
      end,
      items = {
        { value = 1, text = "One" },
        {
          value = 2,
          text = "Two",
          onPick = function(entry)
            picked = entry
          end,
        },
      },
    })
    assert(d._menuItems and #d._menuItems == 2)
    d._menuItems[2].action()
    assert(picked ~= nil)
    assert(picked.value == 2)
    expect(d:getValue()).toBe(2)
    expect(d:getLabel()).toBe("Two")
  end)

  it("setGetBounds updates the contextual menu getBounds", function()
    local bounds = { w = 111, h = 222 }
    local d = Dropdown.new({
      getBounds = function()
        return { w = 1, h = 1 }
      end,
      items = makeItems(),
    })
    d:setGetBounds(function()
      return bounds
    end)
    expect(d.menu.getBounds()).toBe(bounds)
  end)

  it("embed item exposes component on synthesized menu row", function()
    local embed = {
      draw = function() end,
      contains = function() return false end,
      getWidth = function()
        return 40
      end,
      getHeight = function()
        return 30
      end,
    }
    local d = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 300 }
      end,
      menuCellH = 30,
      items = {
        { value = 1, text = "Picker", embed = embed },
      },
    })
    expect(d._menuItems[1].component).toBe(embed)
    expect(d._menuItems[1].menuWidthFromComponentOnly).toBe(true)
    expect(d._menuItems[1].action).toBeNil()
  end)

  it("closeMenuOnItemPick false sets keepMenuOpen on normal menu items", function()
    local d = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 300 }
      end,
      closeMenuOnItemPick = false,
      items = {
        { value = 1, text = "A" },
        { value = 2, text = "B" },
      },
    })
    expect(d._menuItems[1].keepMenuOpen).toBe(true)
    expect(d._menuItems[2].keepMenuOpen).toBe(true)
  end)

  it("allows empty item text when embed is set", function()
    local embed = {
      draw = function() end,
      contains = function()
        return false
      end,
      getWidth = function()
        return 4
      end,
      getHeight = function()
        return 4
      end,
    }
    local d = Dropdown.new({
      getBounds = function()
        return { w = 400, h = 300 }
      end,
      menuCellH = 8,
      items = {
        { value = 1, text = "", embed = embed },
      },
    })
    expect(d:getLabel()).toBe("")
  end)
end)
