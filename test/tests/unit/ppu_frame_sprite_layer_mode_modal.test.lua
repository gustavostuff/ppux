local PPUFrameSpriteLayerModeModal = require("user_interface.modals.ppu_frame_sprite_layer_mode_modal")

describe("ppu_frame_sprite_layer_mode_modal.lua", function()
  it("renders the sprite mode label and toggles the mode button text", function()
    local modal = PPUFrameSpriteLayerModeModal.new()
    modal:show({})

    local modeLabelCell = modal.panel:getCell(1, 1)
    expect(modeLabelCell and modeLabelCell.text).toBe("Sprite mode")
    expect(modal.modeButton.text).toBe("8x8")

    modal:toggleSpriteMode()
    expect(modal.modeButton.text).toBe("8x16")
  end)

  it("passes the selected mode and target window to onConfirm", function()
    local modal = PPUFrameSpriteLayerModeModal.new()
    local calledMode = nil
    local calledWindow = nil
    local targetWindow = { kind = "ppu_frame" }

    modal:show({
      window = targetWindow,
      onConfirm = function(mode, win)
        calledMode = mode
        calledWindow = win
        return true
      end,
    })

    modal:toggleSpriteMode()
    expect(modal:handleKey("return")).toBe(true)
    expect(calledMode).toBe("8x16")
    expect(calledWindow).toBe(targetWindow)
    expect(modal:isVisible()).toBe(false)
  end)
end)
