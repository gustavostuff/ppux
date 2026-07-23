local RelocationPointerCalculatorModal = require("user_interface.modals.relocation_pointer_calculator_modal")
local RelocationPointerMath = require("utils.relocation_pointer_math")

describe("relocation_pointer_calculator_modal.lua", function()
  it("calculates lo/hi on enter and enables copy", function()
    local statuses = {}
    local modal = RelocationPointerCalculatorModal.new()
    modal:show({
      statusCallback = function(msg)
        statuses[#statuses + 1] = msg
      end,
    })

    modal.offsetField:setText("13300")
    expect(modal:handleKey("return")).toBe(true)
    expect(modal.resultLo).toBe(0xF0)
    expect(modal.resultHi).toBe(0xB2)
    expect(modal.offsetField:getText()).toBe("0x013300")
    expect(modal.copyLoButton.enabled).toBe(true)
    expect(modal.resultBytesLabel).toBe("F0  B2  (lo, hi)")
    expect(#statuses).toBeGreaterThan(0)
  end)

  it("clears results on clear", function()
    local modal = RelocationPointerCalculatorModal.new()
    modal:show({})
    modal.offsetField:setText("0x013300")
    modal:calculate()
    expect(modal.resultLo).toBe(0xF0)

    modal:clear()
    expect(modal.resultLo).toBeNil()
    -- Masked hex field resets to the mask template, not a blank string.
    expect(modal.offsetField:getText()).toBe("0x000000")
    expect(modal.copyBothButton.enabled).toBe(false)
  end)

  it("hides on escape", function()
    local modal = RelocationPointerCalculatorModal.new()
    modal:show({})
    expect(modal:isVisible()).toBe(true)
    expect(modal:handleKey("escape")).toBe(true)
    expect(modal:isVisible()).toBe(false)
  end)

  it("keeps the same Panel across draws so focus and mouse press survive", function()
    local modal = RelocationPointerCalculatorModal.new()
    modal:show({})
    local panelBefore = modal.panel
    expect(panelBefore).toBeTruthy()
    expect(panelBefore.focusedComponent).toBe(modal.offsetField)

    modal:draw({
      getWidth = function()
        return 640
      end,
      getHeight = function()
        return 360
      end,
    })
    expect(modal.panel).toBe(panelBefore)
    expect(modal.panel.focusedComponent).toBe(modal.offsetField)
  end)

  it("defaults mapping dropdowns to Contra-style values", function()
    local modal = RelocationPointerCalculatorModal.new()
    modal:show({})
    local opts = modal:getMappingOpts()
    expect(opts.headerSize).toBe(0x10)
    expect(opts.bankSize).toBe(0x4000)
    expect(opts.cpuMapBase).toBe(0x8000)
    expect(modal.headerDropdown:getLabel()).toBe("0x10")
    expect(modal.bankDropdown:getLabel()).toBe("0x4000")
    expect(modal.cpuBaseDropdown:getLabel()).toBe("$8000")
  end)

  it("uses dropdown mapping when calculating", function()
    local modal = RelocationPointerCalculatorModal.new()
    modal:show({})
    modal.headerDropdown._defaultSpec = 0x00
    modal.headerDropdown:setItems({
      { value = 0x10, text = "0x10" },
      { value = 0x00, text = "0x00" },
    })
    modal.bankDropdown._defaultSpec = 0x8000
    modal.bankDropdown:setItems({
      { value = 0x2000, text = "0x2000" },
      { value = 0x4000, text = "0x4000" },
      { value = 0x8000, text = "0x8000" },
    })
    modal.cpuBaseDropdown._defaultSpec = 0x8000
    modal.cpuBaseDropdown:setItems({
      { value = 0x8000, text = "$8000" },
      { value = 0xA000, text = "$A000" },
      { value = 0xC000, text = "$C000" },
    })

    modal.offsetField:setText("0x000210")
    expect(modal:calculate()).toBe(true)
    expect(modal.resultLo).toBe(0x10)
    expect(modal.resultHi).toBe(0x82)
  end)

  it("formats pointer bytes via math helper", function()
    expect(RelocationPointerMath.formatByte(0xF0)).toBe("F0")
  end)
end)
