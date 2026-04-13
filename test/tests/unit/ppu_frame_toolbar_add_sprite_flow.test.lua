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

describe("ppu_frame_toolbar.lua - sprite origin controls", function()
  it("enables origin guides control only when sprite layer is active", function()
    local win = makeWindow({
      { kind = "tile", items = {} },
      { kind = "sprite", items = {}, mode = "8x8", originX = 4, originY = 7 },
    }, 1)

    local toolbar = PPUFrameToolbar.new(win, { app = {} }, { getFocus = function() return win end })

    toolbar:updateOriginButtons()
    expect(toolbar.toggleOriginGuidesButton.enabled).toBe(false)

    win:setActiveLayerIndex(2)
    toolbar:updateOriginButtons()
    expect(toolbar.toggleOriginGuidesButton.enabled).toBe(true)
  end)

  it("toggles dotted origin guides and updates button style", function()
    local win = makeWindow({
      { kind = "tile", items = {} },
      { kind = "sprite", items = {}, mode = "8x8", originX = 0, originY = 0 },
    }, 2)

    local toolbar = PPUFrameToolbar.new(win, { app = {} }, { getFocus = function() return win end })

    toolbar:updateOriginButtons()
    expect(win.showSpriteOriginGuides).toNotBe(true)
    expect(toolbar.toggleOriginGuidesButton.bgColor).toBeTruthy()

    toolbar:_onToggleOriginGuides()
    toolbar:updateOriginButtons()
    expect(win.showSpriteOriginGuides).toBe(true)
    expect(toolbar.toggleOriginGuidesButton.bgColor).toBeNil()

    toolbar:_onToggleOriginGuides()
    toolbar:updateOriginButtons()
    expect(win.showSpriteOriginGuides).toBe(false)
    expect(toolbar.toggleOriginGuidesButton.bgColor).toBeTruthy()
  end)
end)

describe("ppu_frame_toolbar.lua - pattern layer toggle", function()
  it("toggles pattern layer solo mode when runtime layer exists", function()
    local statusText = nil
    local win = makeWindow({
      { kind = "tile", items = {} },
      { kind = "sprite", items = {} },
      { kind = "tile", items = {}, _runtimePatternTableRefLayer = true },
    }, 1)
    win.patternLayerSoloMode = false
    win.drawOnlyActiveLayer = false
    function win:findPatternReferenceLayerIndex()
      return 3
    end
    function win:setPatternLayerSoloMode(enabled)
      self.patternLayerSoloMode = (enabled == true)
      if self.patternLayerSoloMode then
        self.drawOnlyActiveLayer = true
        self.activeLayer = 3
      else
        self.drawOnlyActiveLayer = false
        self.activeLayer = 1
      end
      return true
    end

    local toolbar = PPUFrameToolbar.new(win, {
      app = {},
      setStatus = function(text) statusText = text end,
    }, { getFocus = function() return win end })

    toolbar:_onTogglePatternLayerSolo()
    expect(win.patternLayerSoloMode).toBe(true)
    expect(win.activeLayer).toBe(3)
    expect(statusText).toBe("Pattern layer mode: on")

    toolbar:_onTogglePatternLayerSolo()
    expect(win.patternLayerSoloMode).toBe(false)
    expect(win.activeLayer).toBe(1)
    expect(statusText).toBe("Pattern layer mode: off")
  end)

  it("shows warning when pattern layer solo mode is unavailable", function()
    local statusText = nil
    local toastKind = nil
    local toastText = nil
    local win = makeWindow({
      { kind = "tile", items = {} },
      { kind = "sprite", items = {} },
    }, 1)
    win.patternLayerSoloMode = false
    function win:findPatternReferenceLayerIndex()
      return nil
    end
    function win:setPatternLayerSoloMode()
      return false, "Pattern table layer is not available"
    end

    local toolbar = PPUFrameToolbar.new(win, {
      app = {},
      setStatus = function(text) statusText = text end,
      showToast = function(kind, text)
        toastKind = kind
        toastText = text
      end,
    }, { getFocus = function() return win end })

    toolbar:_onTogglePatternLayerSolo()
    expect(win.patternLayerSoloMode).toBe(false)
    expect(statusText).toBe("Pattern table layer is not available")
    expect(toastKind).toBe("warning")
    expect(toastText).toBe("Pattern table layer is not available")
  end)
end)
