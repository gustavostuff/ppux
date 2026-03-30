local TextField = require("user_interface.text_field")

describe("text_field.lua", function()
  local originalGetTime
  local originalIsDown
  local now
  local keysDown

  beforeEach(function()
    originalGetTime = love.timer.getTime
    originalIsDown = love.keyboard.isDown
    now = 0
    keysDown = {}
    love.timer.getTime = function()
      return now
    end
    love.keyboard.isDown = function(key)
      return keysDown[key] == true
    end
  end)

  afterEach(function()
    love.timer.getTime = originalGetTime
    love.keyboard.isDown = originalIsDown
  end)

  it("repeats left and right cursor movement after a short hold delay", function()
    local field = TextField.new()
    field:setFocused(true)
    field:setText("ABCD")

    expect(field.cursorPos).toBe(5)

    keysDown.left = true
    expect(field:onKeyPressed("left")).toBe(true)
    expect(field.cursorPos).toBe(4)

    now = 0.49
    field:update()
    expect(field.cursorPos).toBe(4)

    now = 0.55
    field:update()
    expect(field.cursorPos).toBe(3)

    now = 0.60
    field:update()
    expect(field.cursorPos).toBe(2)

    keysDown.left = false
    field:update()

    keysDown.right = true
    expect(field:onKeyPressed("right")).toBe(true)
    expect(field.cursorPos).toBe(3)

    now = 1.15
    field:update()
    expect(field.cursorPos).toBe(4)

    now = 1.20
    field:update()
    expect(field.cursorPos).toBe(5)
  end)

  it("builds masked text with a literal 0x prefix and right-aligned hex input", function()
    local field = TextField.new({
      mask = "0x000000",
    })

    expect(field:getText()).toBe("0x000000")

    field:setText("3f10")
    expect(field:getText()).toBe("0x003F10")
  end)

  it("replaces masked symbols and skips literals when moving the cursor", function()
    local field = TextField.new({
      mask = "0x000000",
    })
    field:setFocused(true)

    expect(field.cursorPos).toBe(3)
    expect(field:onTextInput("a")).toBe(true)
    expect(field:getText()).toBe("0xA00000")
    expect(field.cursorPos).toBe(4)

    expect(field:onKeyPressed("left")).toBe(true)
    expect(field.cursorPos).toBe(3)

    expect(field:onKeyPressed("backspace")).toBe(true)
    expect(field:getText()).toBe("0x000000")
    expect(field.cursorPos).toBe(3)

    field:onTextInput("b")
    field:onTextInput("c")
    expect(field:getText()).toBe("0xBC0000")
    expect(field.cursorPos).toBe(5)

    field.cursorPos = 4
    expect(field:onKeyPressed("delete")).toBe(true)
    expect(field:getText()).toBe("0xB00000")
    expect(field.cursorPos).toBe(4)
  end)
end)
