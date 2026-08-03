local GenericActionsModal = require("user_interface.modals.generic_actions_modal")

describe("generic_actions_modal checkbox", function()
  it("toggles Don't ask again and reports checked state", function()
    local modal = GenericActionsModal.new()
    modal:show("Overwrite file?", {
      { text = "Overwrite", callback = function() end },
      { text = "Cancel", callback = function() end },
    }, {
      checkbox = { text = "Don't ask again", checked = false },
    })

    expect(modal:isVisible()).toBe(true)
    expect(modal:isCheckboxChecked()).toBe(false)

    -- Checkbox is the row after the two options (row 3 in a full-row layout).
    local checkboxCell = modal.panel:getCell(1, 3)
    expect(checkboxCell).toBeTruthy()
    expect(checkboxCell.text).toBe("[ ] Don't ask again")
    checkboxCell.action()
    expect(modal:isCheckboxChecked()).toBe(true)
    expect(modal.panel:getCell(1, 3).text).toBe("[x] Don't ask again")
  end)

  it("omits the checkbox row when not requested", function()
    local modal = GenericActionsModal.new()
    modal:show("Quick Actions", {
      { text = "One", callback = function() end },
    })
    expect(modal.checkbox).toBeNil()
    expect(modal:isCheckboxChecked()).toBe(false)
    -- option + footer only
    expect(modal.panel.rows).toBe(2)
  end)
end)
