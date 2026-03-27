local GameArtController = require("controllers.game_art.game_art_controller")

describe("game_art_controller.lua - db lookup", function()
  it("finds DB layouts even when the SHA-1 is lowercase", function()
    local sha = "376836361f404c815d404e1d5903d5d11f4eff0e"
    local layout = GameArtController.getLayout(sha)

    expect(GameArtController.hasLayout(sha)).toBe(true)
    expect(layout).toBeTruthy()
    expect(layout.kind).toBe("project")
    expect(#(layout.windows or {})).toBeGreaterThan(0)
  end)
end)
