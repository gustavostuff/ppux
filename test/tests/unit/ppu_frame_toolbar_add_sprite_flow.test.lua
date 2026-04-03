local PPUFrameToolbar = require("user_interface.toolbars.ppu_frame_toolbar")

local function makeWindow(layers, activeLayer)
  local win = {
    kind = "ppu_frame",
    layers = layers or {},
    activeLayer = activeLayer or 1,
  }

  function win:getHeaderRect()
    return 0, 0, 120, 15
  end

  function win:getActiveLayerIndex()
    return self.activeLayer
  end

  function win:setActiveLayerIndex(i)
    self.activeLayer = i
  end

  function win:getLayerCount()
    return #self.layers
  end

  function win:addLayer(opts)
    opts = opts or {}
    self.layers[#self.layers + 1] = {
      items = {},
      opacity = 1.0,
      name = opts.name,
      kind = opts.kind or "tile",
      mode = opts.mode,
      originX = opts.originX,
      originY = opts.originY,
    }
    return #self.layers
  end

  return win
end

describe("ppu_frame_toolbar.lua - add sprite flow", function()
  it("opens the sprite-layer mode modal when no sprite layer exists, then opens add-sprite modal afterwards", function()
    local statusText = nil
    local modeModalCalls = 0
    local addSpriteModalCalls = 0
    local capturedModeModalOpts = nil
    local capturedModeModalWindow = nil

    local win = makeWindow({
      { kind = "tile", items = {} },
    }, 1)

    local app = {
      showPpuFrameSpriteLayerModeModal = function(_, targetWindow, opts)
        modeModalCalls = modeModalCalls + 1
        capturedModeModalWindow = targetWindow
        capturedModeModalOpts = opts
        return true
      end,
      showPpuFrameAddSpriteModal = function(_, targetWindow)
        addSpriteModalCalls = addSpriteModalCalls + 1
        expect(targetWindow).toBe(win)
        return true
      end,
    }

    local ctx = {
      app = app,
      setStatus = function(text)
        statusText = text
      end,
    }

    local toolbar = PPUFrameToolbar.new(win, ctx, { getFocus = function() return win end })

    toolbar:_onAddSprite()
    expect(modeModalCalls).toBe(1)
    expect(addSpriteModalCalls).toBe(0)
    expect(capturedModeModalWindow).toBe(win)
    expect(type(capturedModeModalOpts.onConfirm)).toBe("function")

    local confirmed = capturedModeModalOpts.onConfirm("8x16", win)
    expect(confirmed).toBe(true)
    expect(#win.layers).toBe(2)
    expect(win.layers[2].kind).toBe("sprite")
    expect(win.layers[2].mode).toBe("8x16")
    expect(win.activeLayer).toBe(2)
    expect(statusText).toBe("Created sprite layer (8x16)")

    toolbar:_onAddSprite()
    expect(modeModalCalls).toBe(1)
    expect(addSpriteModalCalls).toBe(1)
  end)

  it("reuses existing sprite layer and opens add-sprite modal directly", function()
    local modeModalCalls = 0
    local addSpriteModalCalls = 0

    local win = makeWindow({
      { kind = "tile", items = {} },
      { kind = "sprite", items = {}, mode = "8x8" },
    }, 1)

    local app = {
      showPpuFrameSpriteLayerModeModal = function()
        modeModalCalls = modeModalCalls + 1
        return true
      end,
      showPpuFrameAddSpriteModal = function(_, targetWindow)
        addSpriteModalCalls = addSpriteModalCalls + 1
        expect(targetWindow).toBe(win)
        return true
      end,
    }

    local toolbar = PPUFrameToolbar.new(win, { app = app }, { getFocus = function() return win end })

    toolbar:_onAddSprite()
    expect(modeModalCalls).toBe(0)
    expect(addSpriteModalCalls).toBe(1)
    expect(win.activeLayer).toBe(2)
  end)
end)
