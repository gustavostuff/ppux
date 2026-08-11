local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local Shared = require("controllers.app.core_controller_shared")

describe("modal right-drag", function()
  local function fakeCanvas(w, h)
    return {
      getWidth = function()
        return w
      end,
      getHeight = function()
        return h
      end,
    }
  end

  local function fakePanel(w, h)
    return {
      w = w,
      h = h,
      x = 0,
      y = 0,
      setPosition = function(self, x, y)
        self.x = x
        self.y = y
      end,
    }
  end

  it("centers until the user right-drags, then keeps the dragged position", function()
    local canvas = fakeCanvas(400, 300)
    local panel = fakePanel(100, 50)
    local modal = { panel = panel }

    local x, y = ModalPanelUtils.centerPanel(panel, canvas, modal)
    expect(x).toBe(150)
    expect(y).toBe(125)
    expect(modal._panelPosX).toBeNil()

    modal._boxX, modal._boxY, modal._boxW, modal._boxH = x, y, 100, 50
    expect(ModalPanelUtils.beginRightDrag(modal, 160, 130)).toBe(true)
    expect(modal._modalDragging).toBe(true)

    ModalPanelUtils.updateRightDrag(modal, 200, 170, canvas)
    expect(modal._panelPosX).toBe(190)
    expect(modal._panelPosY).toBe(165)
    expect(panel.x).toBe(190)
    expect(panel.y).toBe(165)

    ModalPanelUtils.endRightDrag(modal)
    expect(modal._modalDragging).toBe(false)

    local x2, y2 = ModalPanelUtils.centerPanel(panel, canvas, modal)
    expect(x2).toBe(190)
    expect(y2).toBe(165)
  end)

  it("does not start a drag when the pointer is outside the modal box", function()
    local modal = {
      panel = fakePanel(100, 50),
      _boxX = 150,
      _boxY = 125,
      _boxW = 100,
      _boxH = 50,
    }
    expect(ModalPanelUtils.beginRightDrag(modal, 10, 10)).toBe(false)
    expect(modal._modalDragging).toBeFalsy()
  end)

  it("dispatchTopModalMousePressed handles right-drag before modal mousepressed", function()
    local pressed = false
    local modal = {
      visible = true,
      isVisible = function()
        return true
      end,
      panel = fakePanel(80, 40),
      _boxX = 10,
      _boxY = 10,
      _boxW = 80,
      _boxH = 40,
      mousepressed = function()
        pressed = true
      end,
    }
    local app = { quitConfirmModal = modal }
    local handled = Shared.dispatchTopModalMousePressed(app, 20, 20, 2)
    expect(handled).toBe(true)
    expect(pressed).toBe(false)
    expect(modal._modalDragging).toBe(true)
    Shared.dispatchTopModalMouseReleased(app, 20, 20, 2)
    expect(modal._modalDragging).toBe(false)
  end)

  it("resetPanelPosition restores automatic centering", function()
    local canvas = fakeCanvas(200, 200)
    local panel = fakePanel(40, 20)
    local modal = { panel = panel, _panelPosX = 5, _panelPosY = 7 }
    ModalPanelUtils.resetPanelPosition(modal)
    local x, y = ModalPanelUtils.centerPanel(panel, canvas, modal)
    expect(x).toBe(80)
    expect(y).toBe(90)
  end)

  it("keeps dragged position across hide/show within the app session only", function()
    local canvas = fakeCanvas(400, 300)
    local panel = fakePanel(100, 50)
    local modal = { panel = panel, _boxX = 150, _boxY = 125, _boxW = 100, _boxH = 50 }
    ModalPanelUtils.beginRightDrag(modal, 160, 130)
    ModalPanelUtils.updateRightDrag(modal, 200, 170, canvas)
    ModalPanelUtils.endRightDrag(modal)
    local pinnedX, pinnedY = modal._panelPosX, modal._panelPosY

    -- Typical hide(): clears draw cache, not session position.
    modal._boxX, modal._boxY, modal._boxW, modal._boxH = nil, nil, nil, nil
    ModalPanelUtils.onModalHidden(modal)
    expect(modal._panelPosX).toBe(pinnedX)
    expect(modal._panelPosY).toBe(pinnedY)

    local x, y = ModalPanelUtils.centerPanel(panel, canvas, modal)
    expect(x).toBe(pinnedX)
    expect(y).toBe(pinnedY)
  end)
end)
