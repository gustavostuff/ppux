local KeyboardDebugController = require("controllers.input.keyboard_debug_controller")
local DebugController = require("controllers.dev.debug_controller")

describe("keyboard_debug_controller.lua", function()
  local originals
  local statusMessages

  beforeEach(function()
    statusMessages = {}
    originals = {
      isEnabled = DebugController.isEnabled,
      cycleHudMode = DebugController.cycleHudMode,
      getHudModeLabel = DebugController.getHudModeLabel,
      clear = DebugController.clear,
    }
  end)

  afterEach(function()
    DebugController.isEnabled = originals.isEnabled
    DebugController.cycleHudMode = originals.cycleHudMode
    DebugController.getHudModeLabel = originals.getHudModeLabel
    DebugController.clear = originals.clear
  end)

  it("cycles dev hud mode on f8", function()
    local cycled = 0
    DebugController.cycleHudMode = function()
      cycled = cycled + 1
      return "perf+debug"
    end
    DebugController.getHudModeLabel = function(mode)
      return "debug+perf"
    end

    local handled = KeyboardDebugController.handleDebugKeys({
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
    }, {}, "f8")

    expect(handled).toBeTruthy()
    expect(cycled).toBe(1)
    expect(statusMessages[#statusMessages]).toBe("Dev HUD mode: debug+perf")
  end)

  it("reports disabled state when cycle returns off", function()
    DebugController.cycleHudMode = function()
      return "off"
    end

    local handled = KeyboardDebugController.handleDebugKeys({
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
    }, {}, "f8")

    expect(handled).toBeTruthy()
    expect(statusMessages[#statusMessages]).toBe("Dev HUD disabled")
  end)

  it("keeps f9 as an alias for the unified dev hud", function()
    local cycled = 0
    DebugController.cycleHudMode = function()
      cycled = cycled + 1
      return "perf"
    end
    DebugController.getHudModeLabel = function(mode)
      return tostring(mode)
    end

    local handled = KeyboardDebugController.handleDebugKeys({
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
    }, {}, "f9")

    expect(handled).toBeTruthy()
    expect(cycled).toBe(1)
    expect(statusMessages[#statusMessages]).toBe("Dev HUD mode: perf")
  end)

  it("handles f7 and clears only when debug is enabled", function()
    local cleared = 0
    DebugController.clear = function() cleared = cleared + 1 end

    DebugController.isEnabled = function() return false end
    expect(KeyboardDebugController.handleDebugKeys({
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
    }, {}, "f7")).toBeTruthy()
    expect(cleared).toBe(0)
    expect(#statusMessages).toBe(0)

    DebugController.isEnabled = function() return true end
    expect(KeyboardDebugController.handleDebugKeys({
      setStatus = function(text)
        statusMessages[#statusMessages + 1] = text
      end,
    }, {}, "f7")).toBeTruthy()
    expect(cleared).toBe(1)
    expect(statusMessages[#statusMessages]).toBe("Debug log cleared")
  end)

  it("consumes key 9 and ignores unrelated keys", function()
    expect(KeyboardDebugController.handleDebugKeys({}, {}, "9")).toBeTruthy()
    expect(KeyboardDebugController.handleDebugKeys({}, {}, "x")).toBeFalsy()
  end)
end)
