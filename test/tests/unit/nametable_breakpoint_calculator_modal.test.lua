local NametableBreakpointCalculatorModal = require("ui.modals.nametable_breakpoint_calculator_modal")
local NametableBreakpointMath = require("utils.nametable_breakpoint_math")

describe("nametable_breakpoint_calculator_modal.lua", function()
  it("calculates PPU address and A==#tile condition", function()
    local statuses = {}
    local modal = NametableBreakpointCalculatorModal.new()
    modal:show({
      statusCallback = function(msg)
        statuses[#statuses + 1] = msg
      end,
    })

    modal.colField:setText("8")
    modal.rowField:setText("10")
    modal.tileField:setText("A0")
    expect(modal:handleKey("return")).toBe(true)
    expect(modal.resultAddress).toBe("$2148")
    expect(modal.resultCondition).toBe("A == #A0")
    expect(modal.copyAddressButton.enabled).toBe(true)
    expect(#statuses).toBeGreaterThan(0)
  end)

  it("defaults NT base to $2000", function()
    local modal = NametableBreakpointCalculatorModal.new()
    modal:show({})
    expect(modal.ntBaseDropdown:getValue()).toBe(0x2000)
  end)

  it("hides on escape", function()
    local modal = NametableBreakpointCalculatorModal.new()
    modal:show({})
    expect(modal:isVisible()).toBe(true)
    expect(modal:handleKey("escape")).toBe(true)
    expect(modal:isVisible()).toBe(false)
  end)

  it("keeps the same Panel across draws", function()
    local modal = NametableBreakpointCalculatorModal.new()
    modal:show({})
    local panelBefore = modal.panel
    expect(panelBefore.cellWidths[2]).toBe(360)
    modal:draw({
      getWidth = function()
        return 640
      end,
      getHeight = function()
        return 360
      end,
    })
    expect(modal.panel).toBe(panelBefore)
    expect(modal.panel.w > 400).toBe(true)
  end)

  it("formats helpers match guide examples", function()
    expect(NametableBreakpointMath.formatPpuAddress(0x23BF)).toBe("$23BF")
  end)
end)
