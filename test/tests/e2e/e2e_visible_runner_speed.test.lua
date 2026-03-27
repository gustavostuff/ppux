local VisibleE2ERunner = require("test.e2e_visible_runner")

describe("e2e_visible_runner.lua - speed multiplier", function()
  it("normalizes invalid multipliers to 1", function()
    expect(VisibleE2ERunner._normalizeSpeedMultiplier(nil)).toBe(1)
    expect(VisibleE2ERunner._normalizeSpeedMultiplier("bad")).toBe(1)
    expect(VisibleE2ERunner._normalizeSpeedMultiplier(0)).toBe(1)
    expect(VisibleE2ERunner._normalizeSpeedMultiplier(-2)).toBe(1)
  end)

  it("supports fractional and larger multipliers", function()
    expect(VisibleE2ERunner._normalizeSpeedMultiplier(0.5)).toBe(0.5)
    expect(VisibleE2ERunner._normalizeSpeedMultiplier(2)).toBe(2)
    expect(VisibleE2ERunner._normalizeSpeedMultiplier("4")).toBe(4)
  end)

  it("scales timing steps without mutating originals", function()
    local original = {
      { kind = "pause", duration = 0.4 },
      { kind = "move", duration = 0.2 },
      { kind = "assert_delay", expected = 0.1, tolerance = 0.02 },
      { kind = "mouse_down" },
    }

    local scaled = VisibleE2ERunner._applySpeedMultiplierToSteps(original, 2)

    expect(original[1].duration).toBe(0.4)
    expect(original[2].duration).toBe(0.2)
    expect(original[3].expected).toBe(0.1)
    expect(original[3].tolerance).toBe(0.02)

    expect(scaled[1].duration).toBe(0.2)
    expect(scaled[2].duration).toBe(0.1)
    expect(scaled[3].expected).toBe(0.05)
    expect(scaled[3].tolerance).toBe(0.01)
    expect(scaled[4].kind).toBe("mouse_down")
  end)

  it("slows timeline when multiplier is below 1", function()
    local scaled = VisibleE2ERunner._applySpeedMultiplierToSteps({
      { kind = "pause", duration = 0.1 },
    }, 0.5)

    expect(scaled[1].duration).toBe(0.2)
  end)
end)
