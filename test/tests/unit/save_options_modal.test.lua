local SaveOptionsModal = require("ui.modals.save_options_modal")

describe("save_options_modal.lua", function()
  it("renders vertical option buttons with numeric prefixes", function()
    local modal = SaveOptionsModal.new()
    modal:show("Save Options", {
      { text = "Save edited ROM", callback = function() end },
      { text = "Save Lua project", callback = function() end },
      { text = "Save *.ppux project", callback = function() end },
      { text = "All of the above", callback = function() end },
    })

    expect(modal.cols).toBe(2)
    expect(modal.optionColspan).toBe(2)

    local cell1 = modal.panel:getCell(1, 1)
    local cell2 = modal.panel:getCell(1, 2)
    local cell3 = modal.panel:getCell(1, 3)
    local cell4 = modal.panel:getCell(1, 4)

    expect(cell1.text).toBe("1) Save edited ROM")
    expect(cell2.text).toBe("2) Save Lua project")
    expect(cell3.text).toBe("3) Save *.ppux project")
    expect(cell4.text).toBe("4) All of the above")
  end)
end)
