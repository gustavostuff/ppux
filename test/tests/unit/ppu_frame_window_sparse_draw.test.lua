local PPUFrameWindow = require("user_interface.windows_system.ppu_frame_window")

describe("ppu_frame_window.lua sparse tile rendering", function()
  local originalGraphics = {}

  local function makeTile(index)
    return {
      index = index,
      draw = function() end,
    }
  end

  local function makeTilesPool()
    return {
      [1] = {
        [0x00] = makeTile(0x00),
        [0x12] = makeTile(0x12),
        [0x34] = makeTile(0x34),
      },
    }
  end

  beforeEach(function()
    if not _G.love then _G.love = {} end
    love.graphics = love.graphics or {}

    originalGraphics.push = love.graphics.push
    originalGraphics.pop = love.graphics.pop
    originalGraphics.translate = love.graphics.translate
    originalGraphics.scale = love.graphics.scale
    originalGraphics.setLineWidth = love.graphics.setLineWidth
    originalGraphics.setLineStyle = love.graphics.setLineStyle
    originalGraphics.setScissor = love.graphics.setScissor
    originalGraphics.setColor = love.graphics.setColor

    love.graphics.push = function() end
    love.graphics.pop = function() end
    love.graphics.translate = function() end
    love.graphics.scale = function() end
    love.graphics.setLineWidth = function() end
    love.graphics.setLineStyle = function() end
    love.graphics.setScissor = function() end
    love.graphics.setColor = function() end
  end)

  afterEach(function()
    love.graphics.push = originalGraphics.push
    love.graphics.pop = originalGraphics.pop
    love.graphics.translate = originalGraphics.translate
    love.graphics.scale = originalGraphics.scale
    love.graphics.setLineWidth = originalGraphics.setLineWidth
    love.graphics.setLineStyle = originalGraphics.setLineStyle
    love.graphics.setScissor = originalGraphics.setScissor
    love.graphics.setColor = originalGraphics.setColor
  end)

  it("keeps glass/transparent bytes in the visual tile map", function()
    local win = PPUFrameWindow.new(0, 0, 1, { title = "PPU" })
    local layer = win.layers[1]
    layer.bank = 1
    layer.page = 1
    layer.glassTileByte = 0x00

    win.cols = 2
    win.rows = 1
    win.visibleCols = 2
    win.visibleRows = 1
    win.nametableBytes = { 0x12, 0x00 }
    win.updateCompressedBytesInROM = function() return true end

    local tilesPool = makeTilesPool()
    win:setNametableByteAt(0, 0, 0x12, tilesPool, 1)
    win:setNametableByteAt(1, 0, 0x00, tilesPool, 1)

    expect(win:get(0, 0, 1)).toBeTruthy()
    expect(win:get(1, 0, 1)).toBeTruthy()
  end)

  it("iterates all visible nametable cells including glass bytes", function()
    local win = PPUFrameWindow.new(0, 0, 1, { title = "PPU" })
    local layer = win.layers[1]
    layer.bank = 1
    layer.page = 1
    layer.glassTileByte = 0x00

    win.cols = 4
    win.rows = 1
    win.visibleCols = 4
    win.visibleRows = 1
    win.nametableBytes = { 0x12, 0x00, 0x34, 0x00 }
    win.updateCompressedBytesInROM = function() return true end

    local tilesPool = makeTilesPool()
    for col = 0, 3 do
      win:setNametableByteAt(col, 0, win.nametableBytes[col + 1], tilesPool, 1)
    end

    local visited = {}
    local handled = win:drawVisibleNametableCells(function(col, row, x, y, cw, ch, li, alpha, item, idx)
      visited[#visited + 1] = {
        col = col,
        row = row,
        idx = idx,
        itemIndex = item and item.index or nil,
      }
    end, 1)

    expect(handled).toBeTruthy()
    expect(#visited).toBe(4)
    expect(visited[1].col + visited[2].col + visited[3].col + visited[4].col).toBe(6)
    expect(visited[1].itemIndex + visited[2].itemIndex + visited[3].itemIndex + visited[4].itemIndex).toBe(0x12 + 0x00 + 0x34 + 0x00)
  end)
end)
