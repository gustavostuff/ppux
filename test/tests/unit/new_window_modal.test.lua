local NewWindowModal = require("user_interface.modals.new_window_modal")

describe("new_window_modal.lua", function()
  it("passes selected sprite mode to option callback", function()
    local captured = nil
    local modal = NewWindowModal.new()

    modal:show("New Window", {
      {
        text = "Animation window (sprites)",
        callback = function(cols, rows, spriteMode, windowName)
          captured = { cols = cols, rows = rows, spriteMode = spriteMode, windowName = windowName }
        end,
      },
    })

    expect(modal:getSpriteMode()).toBe("8x8")
    modal:toggleSpriteMode()
    expect(modal:getSpriteMode()).toBe("8x16")

    local optionCell = modal.panel:getCell(1, 6)
    expect(optionCell).toBeTruthy()
    local clickX = optionCell.x + 4
    local clickY = optionCell.y + 4
    expect(modal:mousepressed(clickX, clickY, 1)).toBe(true)
    expect(modal:mousereleased(clickX, clickY, 1)).toBe(true)
    expect(captured).toBeTruthy()
    expect(captured.cols).toBe(8)
    expect(captured.rows).toBe(8)
    expect(captured.spriteMode).toBe("8x16")
    expect(captured.windowName).toBe("New Window")
    expect(modal:isVisible()).toBe(false)
  end)

  it("passes trimmed custom window name to option callback", function()
    local captured = nil
    local modal = NewWindowModal.new()

    modal:show("New Window", {
      {
        text = "Static Art window (tiles)",
        callback = function(cols, rows, spriteMode, windowName)
          captured = {
            cols = cols,
            rows = rows,
            spriteMode = spriteMode,
            windowName = windowName,
          }
        end,
      },
    })

    modal.nameField:setText("  Custom Name  ")
    local optionCell = modal.panel:getCell(1, 6)
    expect(optionCell).toBeTruthy()
    local clickX = optionCell.x + 4
    local clickY = optionCell.y + 4
    expect(modal:mousepressed(clickX, clickY, 1)).toBe(true)
    expect(modal:mousereleased(clickX, clickY, 1)).toBe(true)

    expect(captured).toBeTruthy()
    expect(captured.cols).toBe(8)
    expect(captured.rows).toBe(8)
    expect(captured.spriteMode).toBe("8x8")
    expect(captured.windowName).toBe("Custom Name")
  end)

  it("toggles sprite mode when mode button is clicked", function()
    local modal = NewWindowModal.new()
    modal:show("New Window", {})
    local modeCell = modal.panel:getCell(2, 2)
    expect(modeCell).toBeTruthy()

    expect(modal:getSpriteMode()).toBe("8x8")
    local clickX = modeCell.x + math.floor(modeCell.w * 0.5)
    local clickY = modeCell.y + math.floor(modeCell.h * 0.5)
    expect(modal:mousepressed(clickX, clickY, 1)).toBe(true)
    expect(modal:mousereleased(clickX, clickY, 1)).toBe(true)
    expect(modal:getSpriteMode()).toBe("8x16")
  end)

  it("shows the sprite mode toggle as a text button", function()
    local modal = NewWindowModal.new()
    modal:show("New Window", {})

    expect(modal.modeButton.text).toBe("8x8")
    modal:toggleSpriteMode()
    expect(modal.modeButton.text).toBe("8x16")
  end)

  it("handles textinput for the window name field when focused", function()
    local modal = NewWindowModal.new()
    modal:show("New Window", {})

    modal.nameField:setText("")
    expect(modal:textinput("A")).toBe(true)
    expect(modal:textinput("B")).toBe(true)

    expect(modal.nameField:getText()).toBe("AB")
  end)
end)
