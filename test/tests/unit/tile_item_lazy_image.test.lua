local Tile = require("user_interface.windows_system.tile_item")

describe("tile_item.lua - lazy image creation", function()
  it("defers image allocation until the tile is drawn", function()
    local oldNewImageData = love.image.newImageData
    local oldNewImage = love.graphics.newImage
    local oldDraw = love.graphics.draw
    local oldSetColor = love.graphics.setColor

    local imageDataCalls = 0
    local imageCalls = 0
    local drawCalls = 0

    love.image.newImageData = function()
      imageDataCalls = imageDataCalls + 1
      return {
        mapPixel = function() end,
        setPixel = function() end,
      }
    end

    love.graphics.newImage = function(imgData)
      imageCalls = imageCalls + 1
      return {
        setFilter = function() end,
        replacePixels = function() end,
      }
    end

    love.graphics.draw = function()
      drawCalls = drawCalls + 1
    end

    love.graphics.setColor = function() end

    local bankBytes = {}
    for i = 1, 16 do
      bankBytes[i] = 0
    end

    local tile = Tile.fromCHR(bankBytes, 0)

    expect(imageDataCalls).toBe(0)
    expect(imageCalls).toBe(0)

    tile:draw(0, 0, 1)

    love.image.newImageData = oldNewImageData
    love.graphics.newImage = oldNewImage
    love.graphics.draw = oldDraw
    love.graphics.setColor = oldSetColor

    expect(imageDataCalls).toBe(1)
    expect(imageCalls).toBe(1)
    expect(drawCalls).toBe(1)
  end)
end)
