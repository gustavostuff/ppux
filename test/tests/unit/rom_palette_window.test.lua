local RomPaletteWindow = require("user_interface.windows_system.rom_palette_window")
local Window = require("user_interface.windows_system.window")
local colors = require("app_colors")
local chr = require("chr")

describe("rom_palette_window.lua - locked cells", function()
  local function makePaletteData()
    return {
      romColors = {
        [1] = { [1] = false, [2] = 0, [3] = 1, [4] = 2 },
        [2] = { [1] = false, [2] = 3, [3] = 4, [4] = 5 },
        [3] = { [1] = false, [2] = 6, [3] = 7, [4] = 8 },
        [4] = { [1] = false, [2] = 9, [3] = 10, [4] = 11 },
      },
      userDefinedCode = {
        { row = 0, col = 0, code = "2A" }, -- must be ignored (locked cell)
        { row = 0, col = 1, code = "09" },
      },
    }
  end

  local function makeWindow()
    return RomPaletteWindow.new(0, 0, 1, "smooth_fbx", 4, 4, {
      title = "ROM Palette Test",
      paletteData = makePaletteData(),
      romRaw = string.rep(string.char(0x07), 64),
    })
  end

  local function makeEditablePaletteData()
    return {
      romColors = {
        [1] = { [1] = 0, [2] = 1, [3] = 2, [4] = 3 },
        [2] = { [1] = 4, [2] = 5, [3] = 6, [4] = 7 },
        [3] = { [1] = 8, [2] = 9, [3] = 10, [4] = 11 },
        [4] = { [1] = 12, [2] = 13, [3] = 14, [4] = 15 },
      },
      userDefinedCode = {},
    }
  end

  it("blocks selection and edits on cells marked as false", function()
    local win = makeWindow()

    expect(win:isCellEditable(0, 0)).toBe(false)
    expect(win:isCellEditable(1, 0)).toBe(true)
    expect(win.codes2D[0][0]).toBe("0F") -- locked cell ignores user-defined value

    win:setSelected(0, 0)
    expect(win.selected).toBeNil()

    win:setSelected(1, 0)
    local col, row = win:getSelected()
    expect(col).toBe(1)
    expect(row).toBe(0)

    local oldEditable = win.codes2D[0][1]
    win:adjustSelectedByArrows(1, 0)
    expect(win.codes2D[0][1]).toNotBe(oldEditable)

    -- Force a locked selection to verify keyboard/mouse-wheel edits are blocked.
    Window.setSelected(win, 0, 0)
    local oldLocked = win.codes2D[0][0]
    win:adjustSelectedByArrows(1, 0)
    expect(win.codes2D[0][0]).toBe(oldLocked)
  end)

  it("moves selection with arrows and skips locked cells", function()
    local win = makeWindow()

    win:setSelected(2, 1)
    local moved = win:moveSelectedByArrows(-1, 0)
    local col, row = win:getSelected()
    expect(moved).toBe(true)
    expect(col).toBe(1)
    expect(row).toBe(1)

    -- Next left step would cross locked column 0 and hit wall, so selection stays.
    moved = win:moveSelectedByArrows(-1, 0)
    col, row = win:getSelected()
    expect(moved).toBe(false)
    expect(col).toBe(1)
    expect(row).toBe(1)
  end)

  it("renders locked cells using gray50", function()
    local win = makeWindow()

    local originalSetColor = love.graphics.setColor
    local originalRectangle = love.graphics.rectangle

    local currentColor = nil
    local firstFillColor = nil

    love.graphics.setColor = function(r, g, b, a)
      currentColor = { r, g, b, a }
      return originalSetColor(r, g, b, a)
    end

    love.graphics.rectangle = function(mode, x, y, w, h)
      if mode == "fill" and not firstFillColor and currentColor then
        firstFillColor = { currentColor[1], currentColor[2], currentColor[3] }
      end
      return originalRectangle(mode, x, y, w, h)
    end

    local ok, err = pcall(function()
      win:drawGrid()
    end)
    love.graphics.setColor = originalSetColor
    love.graphics.rectangle = originalRectangle
    if not ok then
      error(err)
    end

    expect(firstFillColor).toBeTruthy()
    expect(firstFillColor[1]).toBe(colors.gray50[1])
    expect(firstFillColor[2]).toBe(colors.gray50[2])
    expect(firstFillColor[3]).toBe(colors.gray50[3])
  end)

  it("parses string userDefinedCode and ignores locked-cell overrides", function()
    local win = RomPaletteWindow.new(0, 0, 1, "smooth_fbx", 4, 4, {
      title = "ROM Palette String Codes",
      paletteData = {
        romColors = {
          [1] = { [1] = false, [2] = 0, [3] = 1, [4] = 2 },
          [2] = { [1] = false, [2] = 3, [3] = 4, [4] = 5 },
          [3] = { [1] = false, [2] = 6, [3] = 7, [4] = 8 },
          [4] = { [1] = false, [2] = 9, [3] = 10, [4] = 11 },
        },
        userDefinedCode = "2A,0,0;09,1,0;0B,2,1",
      },
      romRaw = string.rep(string.char(0x07), 64),
    })

    expect(type(win.paletteData.userDefinedCode)).toBe("table")
    expect(win.codes2D[0][0]).toBe("0F") -- locked cell must stay locked/default
    expect(win.codes2D[0][1]).toBe("09")
    expect(win.codes2D[1][2]).toBe("0B")
  end)

  it("syncs color edits to every cell that shares the same ROM address", function()
    local previousCtx = rawget(_G, "ctx")
    local markUnsavedCalls = 0
    local sharedAddr = 0
    local paletteData = {
      romColors = {
        [1] = { [1] = sharedAddr, [2] = 1, [3] = 2, [4] = 3 },
        [2] = { [1] = sharedAddr, [2] = 5, [3] = 6, [4] = 7 },
        [3] = { [1] = sharedAddr, [2] = 9, [3] = 10, [4] = 11 },
        [4] = { [1] = sharedAddr, [2] = 13, [3] = 14, [4] = 15 },
      },
      userDefinedCode = {},
    }
    _G.ctx = {
      app = {
        markUnsaved = function(_, reason)
          markUnsavedCalls = markUnsavedCalls + 1
          expect(reason).toBe("palette_color_change")
        end,
        wm = {
          getWindowsOfKind = function()
            return {}
          end,
        },
      },
    }

    local win = RomPaletteWindow.new(0, 0, 1, "smooth_fbx", 4, 4, {
      title = "ROM Palette shared address",
      paletteData = paletteData,
      romRaw = string.rep(string.char(0x07), 64),
    })

    local ok, err = pcall(function()
      win:setSelected(0, 2)
      win:adjustSelectedByArrows(1, 0) -- 07 -> 08
    end)
    _G.ctx = previousCtx
    if not ok then error(err) end

    for row = 0, 3 do
      expect(win.codes2D[row][0]).toBe("08")
    end

    expect(chr.readByteFromAddress(win.romRaw, sharedAddr)).toBe(0x08)
    expect(chr.readByteFromAddress(win.romRaw, 4)).toBe(0x07)

    expect(#win.paletteData.userDefinedCode).toBe(4)
    expect(win.paletteData.userDefinedCode[1].row).toBe(0)
    expect(win.paletteData.userDefinedCode[1].col).toBe(0)
    expect(win.paletteData.userDefinedCode[4].row).toBe(3)
    expect(win.paletteData.userDefinedCode[4].col).toBe(0)
    expect(markUnsavedCalls).toBe(1)
  end)

  it("syncs color edits across ROM palette windows that share a ROM address", function()
    local previousCtx = rawget(_G, "ctx")
    local sharedAddr = 2
    local romRaw = string.rep(string.char(0x11), 64)
    local winA = RomPaletteWindow.new(0, 0, 1, "smooth_fbx", 4, 4, {
      title = "ROM A",
      paletteData = {
        romColors = {
          [1] = { [1] = false, [2] = sharedAddr, [3] = 3, [4] = 4 },
          [2] = { [1] = false, [2] = 5, [3] = 6, [4] = 7 },
          [3] = { [1] = false, [2] = 8, [3] = 9, [4] = 10 },
          [4] = { [1] = false, [2] = 11, [3] = 12, [4] = 13 },
        },
        userDefinedCode = {},
      },
      romRaw = romRaw,
    })
    local winB = RomPaletteWindow.new(0, 0, 1, "smooth_fbx", 4, 4, {
      title = "ROM B",
      paletteData = {
        romColors = {
          [1] = { [1] = false, [2] = 20, [3] = 21, [4] = 22 },
          [2] = { [1] = false, [2] = sharedAddr, [3] = 24, [4] = 25 },
          [3] = { [1] = false, [2] = 26, [3] = 27, [4] = 28 },
          [4] = { [1] = false, [2] = 29, [3] = 30, [4] = 31 },
        },
        userDefinedCode = {},
      },
      romRaw = romRaw,
    })
    _G.ctx = {
      app = {
        wm = {
          getWindowsOfKind = function()
            return { winA, winB }
          end,
        },
      },
    }

    local ok, err = pcall(function()
      winA:setSelected(1, 0)
      winA:adjustSelectedByArrows(1, 0) -- 11 -> 12
    end)
    _G.ctx = previousCtx
    if not ok then error(err) end

    expect(winA.codes2D[0][1]).toBe("12")
    expect(winB.codes2D[1][1]).toBe("12")
    expect(chr.readByteFromAddress(winA.romRaw, sharedAddr)).toBe(0x12)
  end)

  it("normalizes invalid black codes when writing to ROM and triggers update callback", function()
    local win = RomPaletteWindow.new(0, 0, 1, "smooth_fbx", 4, 4, {
      title = "ROM Palette Write",
      paletteData = makeEditablePaletteData(),
      romRaw = string.rep(string.char(0x07), 64),
    })

    local callbackRom = nil
    win._updateRomRawCallback = function(newRom)
      callbackRom = newRom
    end

    local wrote = win:writeColorToROM(0, 1, "1E") -- invalid black -> normalized to 0F
    expect(wrote).toBe(true)
    expect(chr.readByteFromAddress(win.romRaw, 1)).toBe(0x0F)
    expect(callbackRom).toBe(win.romRaw)
  end)

  it("updates existing user-defined entries and keeps them sorted", function()
    local win = makeWindow()
    win.paletteData.userDefinedCode = {
      { row = 3, col = 2, code = "22" },
      { row = 1, col = 2, code = "12" },
    }

    win:saveUserDefinedCode(2, 1, "0D") -- normalized to 0F
    win:saveUserDefinedCode(1, 2, "1A") -- update existing (row=1,col=2)

    expect(#win.paletteData.userDefinedCode).toBe(3)
    expect(win.paletteData.userDefinedCode[1].row).toBe(1)
    expect(win.paletteData.userDefinedCode[1].col).toBe(2)
    expect(win.paletteData.userDefinedCode[1].code).toBe("1A")
    expect(win.paletteData.userDefinedCode[2].row).toBe(2)
    expect(win.paletteData.userDefinedCode[2].col).toBe(1)
    expect(win.paletteData.userDefinedCode[2].code).toBe("0F")
    expect(win.paletteData.userDefinedCode[3].row).toBe(3)
    expect(win.paletteData.userDefinedCode[3].col).toBe(2)
  end)

  it("clearRomCellBinding locks the cell and drops user-defined overrides", function()
    local win = makeWindow()
    win:setSelected(1, 0)
    expect(win:isCellEditable(1, 0)).toBe(true)

    local cleared = win:clearRomCellBinding(1, 0)
    expect(cleared).toBe(true)
    expect(win:isCellEditable(1, 0)).toBe(false)
    expect(win.codes2D[0][1]).toBe("0F")
    expect(win.paletteData.romColors[1][2]).toBe(false)
    local hasUser = false
    for _, item in ipairs(win.paletteData.userDefinedCode or {}) do
      if item.row == 0 and item.col == 1 then
        hasUser = true
        break
      end
    end
    expect(hasUser).toBe(false)
  end)

  it("assigns a ROM address to a locked cell and loads its current code", function()
    local win = makeWindow()
    win.paletteData.userDefinedCode = {
      { row = 0, col = 0, code = "2A" },
    }

    local ok, codeOrErr = win:setCellAddress(0, 0, 5)

    expect(ok).toBe(true)
    expect(codeOrErr).toBe("07")
    expect(win:isCellEditable(0, 0)).toBe(true)
    expect(win.paletteData.romColors[1][1]).toBe(5)
    expect(win.codes2D[0][0]).toBe("07")
    expect(#win.paletteData.userDefinedCode).toBe(0)

    local col, row = win:getSelected()
    expect(col).toBe(0)
    expect(row).toBe(0)
  end)

  it("rejects assigning an out-of-range ROM address", function()
    local win = makeWindow()

    local ok, err = win:setCellAddress(0, 0, 9999)

    expect(ok).toBe(false)
    expect(type(err)).toBe("string")
    expect(string.find(err, "invalid", 1, true)).toNotBe(nil)
    expect(win:isCellEditable(0, 0)).toBe(false)
  end)

  it("supports compact mode and switches cell size to 20x15", function()
    local win = makeWindow()

    expect(win:supportsCompactMode()).toBe(true)
    expect(win.compactView).toBe(false)
    expect(win.cellW).toBe(32)
    expect(win.cellH).toBe(24)

    win:setCompactMode(true)
    expect(win.compactView).toBe(true)
    expect(win.cellW).toBe(20)
    expect(win.cellH).toBe(15)

    win:setCompactMode(false)
    expect(win.compactView).toBe(false)
    expect(win.cellW).toBe(32)
    expect(win.cellH).toBe(24)
  end)

  it("builds row and column strip codes from the selected ROM-backed color", function()
    local win = makeWindow()

    win:setSelected(1, 0)
    local strips = win:getSelectedStripCodes()

    expect(strips).toBeTruthy()
    expect(strips.code).toBe("09")
    expect(strips.rowIndex).toBe(0)
    expect(strips.colIndex).toBe(9)
    expect(strips.rowCodes[1]).toBe("00")
    expect(strips.rowCodes[16]).toBe("0F")
    expect(strips.colCodes[1]).toBe("09")
    expect(strips.colCodes[4]).toBe("39")
  end)
end)
