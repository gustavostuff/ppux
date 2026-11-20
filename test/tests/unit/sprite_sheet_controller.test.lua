local SpriteSheet = require("controllers.sprite.sprite_sheet_controller")
local SpriteLayerDraw = require("ui.windows_system.sprite_layer_draw")
local ClipboardNative = require("utils.ppux_clipboard_native")

describe("sprite sheet export", function()
  it("lays sprite layers out at 1:1 and skips tile layers", function()
    local layout = SpriteSheet.sheetLayout({
      cols = 4,
      rows = 2,
      cellW = 8,
      cellH = 8,
      zoom = 3,
      layers = {
        { kind = "tile" },
        { kind = "sprite" },
        { kind = "sprite" },
      },
    })

    expect(layout.frameW).toBe(32)
    expect(layout.frameH).toBe(16)
    expect(layout.sheetW).toBe(64)
    expect(layout.sheetH).toBe(16)
    expect(#layout.indices).toBe(2)
    expect(layout.indices[1]).toBe(2)
    expect(layout.indices[2]).toBe(3)
  end)

  it("renders each sprite layer as a transparent 1:1 frame and encodes a PNG", function()
    local originalDraw = SpriteLayerDraw.drawSpriteLayerInContentSpace
    local originalSet = ClipboardNative.setPng
    SpriteLayerDraw.drawSpriteLayerInContentSpace = function(opts)
      local layerIndex = tonumber(opts.spriteLayerIndex) or 1
      if layerIndex == 1 then
        love.graphics.setColor(1, 0, 0, 1)
      else
        love.graphics.setColor(0, 0, 1, 1)
      end
      love.graphics.rectangle("fill", 0, 0, 1, 1)
    end

    local captured = nil
    ClipboardNative.setPng = function(bytes)
      captured = bytes
      return true
    end

    local win = {
      kind = "animation",
      cols = 2,
      rows = 1,
      cellW = 8,
      cellH = 8,
      zoom = 4,
      layers = {
        { kind = "sprite", opacity = 0.25, items = {} },
        { kind = "tile", items = {} },
        { kind = "sprite", items = {} },
      },
    }

    local ok, err = pcall(function()
      local copied, copyErr = SpriteSheet.copyWindowSpriteSheet(win, nil)
      expect(copied).toBe(true)
      expect(copyErr).toBeNil()
      expect(win.layers[1].opacity).toBe(0.25)
      expect(type(captured)).toBe("string")

      local fileData = love.filesystem.newFileData(captured, "sheet.png")
      local image = love.image.newImageData(fileData)
      expect(image:getWidth()).toBe(32)
      expect(image:getHeight()).toBe(8)

      local r, g, b, a = image:getPixel(0, 0)
      expect(r > 0.9 and g < 0.1 and b < 0.1 and a > 0.9).toBe(true)
      local r2, g2, b2, a2 = image:getPixel(16, 0)
      expect(r2 < 0.1 and g2 < 0.1 and b2 > 0.9 and a2 > 0.9).toBe(true)
      local _, _, _, clearA = image:getPixel(8, 0)
      expect(clearA < 0.01).toBe(true)
      image:release()
    end)

    SpriteLayerDraw.drawSpriteLayerInContentSpace = originalDraw
    ClipboardNative.setPng = originalSet
    if not ok then
      error(err, 0)
    end
  end)

  it("keeps palette index 0 transparent when drawing real sprite pixels", function()
    local indexed = love.image.newImageData(8, 8)
    for y = 0, 7 do
      for x = 0, 7 do
        local index = (x < 4) and 0 or 1
        indexed:setPixel(x, y, index / 3, 0, 0, 1)
      end
    end
    local image = love.graphics.newImage(indexed)
    image:setFilter("nearest", "nearest")
    local topRef = {
      draw = function(_, x, y, sx, sy)
        love.graphics.draw(image, x or 0, y or 0, 0, sx or 1, sy or 1)
      end,
    }

    local originalSet = ClipboardNative.setPng
    local captured = nil
    ClipboardNative.setPng = function(bytes)
      captured = bytes
      return true
    end

    local win = {
      kind = "oam_animation",
      cols = 2,
      rows = 1,
      cellW = 8,
      cellH = 8,
      layers = {
        {
          kind = "sprite",
          mode = "8x8",
          originX = 0,
          originY = 0,
          items = {
            { worldX = 0, worldY = 0, topRef = topRef },
          },
        },
      },
    }

    local ok, err = pcall(function()
      local copied = SpriteSheet.copyWindowSpriteSheet(win, nil)
      expect(copied).toBe(true)
      local decoded = love.image.newImageData(love.filesystem.newFileData(captured, "sheet.png"))
      expect(decoded:getWidth()).toBe(16)
      expect(decoded:getHeight()).toBe(8)
      local _, _, _, clearA = decoded:getPixel(0, 0)
      local _, _, _, inkA = decoded:getPixel(4, 0)
      expect(clearA < 0.01).toBe(true)
      expect(inkA > 0.9).toBe(true)
      decoded:release()
    end)

    ClipboardNative.setPng = originalSet
    image:release()
    if not ok then
      error(err, 0)
    end
  end)
end)
