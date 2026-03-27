local RenameWindowModal = require("user_interface.modals.rename_window_modal")

describe("rename_window_modal.lua", function()
  it("confirms renamed title on enter", function()
    local renamedTo = nil
    local targetWindow = { title = "Old" }
    local modal = RenameWindowModal.new()

    modal:show({
      window = targetWindow,
      onConfirm = function(newTitle, win)
        renamedTo = { title = newTitle, win = win }
      end,
    })

    modal.textField:setText("  New Name  ")
    expect(modal:handleKey("return")).toBe(true)

    expect(modal:isVisible()).toBe(false)
    expect(renamedTo).toBeTruthy()
    expect(renamedTo.title).toBe("New Name")
    expect(renamedTo.win).toBe(targetWindow)
  end)

  it("cancels on escape without confirming", function()
    local confirmCalls = 0
    local cancelCalls = 0
    local modal = RenameWindowModal.new()

    modal:show({
      onConfirm = function()
        confirmCalls = confirmCalls + 1
      end,
      onCancel = function()
        cancelCalls = cancelCalls + 1
      end,
    })

    expect(modal:handleKey("escape")).toBe(true)
    expect(confirmCalls).toBe(0)
    expect(cancelCalls).toBe(1)
    expect(modal:isVisible()).toBe(false)
  end)

  it("handles textinput only while visible", function()
    local modal = RenameWindowModal.new()

    expect(modal:textinput("A")).toBe(false)

    modal:show({ initialTitle = "Hi" })
    expect(modal:textinput("!")).toBe(true)
    expect(modal.textField:getText()).toBe("Hi!")
  end)

  it("ignores blank title confirmations", function()
    local confirmCalls = 0
    local modal = RenameWindowModal.new()

    modal:show({
      onConfirm = function()
        confirmCalls = confirmCalls + 1
      end,
    })

    modal.textField:setText("   ")
    expect(modal:handleKey("return")).toBe(true)
    expect(confirmCalls).toBe(0)
    expect(modal:isVisible()).toBe(true)
  end)
end)
