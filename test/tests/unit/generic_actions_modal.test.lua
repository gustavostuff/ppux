local GenericActionsModal = require("ui.modals.generic_actions_modal")
local Checkbox = require("ui.checkbox")

describe("generic_actions_modal checkbox", function()
  it("toggles Don't ask again via Checkbox component and reports checked state", function()
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
    expect(checkboxCell.component).toBeTruthy()
    expect(getmetatable(checkboxCell.component)).toBe(getmetatable(Checkbox.new({})))
    expect(checkboxCell.component:isChecked()).toBe(false)
    expect(checkboxCell.component.text).toBe("Don't ask again")
    -- No button chrome: cell is a component, not a button with [ ] / [x] text.
    expect(checkboxCell.button).toBeNil()
    expect(checkboxCell.kind).toBe("component")
    expect(tostring(checkboxCell.text or "")).toBe("")

    checkboxCell.component.action()
    expect(modal:isCheckboxChecked()).toBe(true)
    expect(checkboxCell.component:isChecked()).toBe(true)
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

describe("ui.checkbox", function()
  it("toggles checked state and notifies onChange", function()
    local seen = nil
    local box = Checkbox.new({
      text = "Label",
      checked = false,
      iconSelected = { w = 8, h = 8 },
      iconNotSelected = { w = 8, h = 8 },
      onChange = function(checked)
        seen = checked
      end,
    })
    expect(box:isChecked()).toBe(false)
    box:toggle()
    expect(box:isChecked()).toBe(true)
    expect(seen).toBe(true)
    box:setChecked(false)
    expect(box:isChecked()).toBe(false)
    expect(seen).toBe(false)
  end)
end)
