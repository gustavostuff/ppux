-- Helpers shared by clipboard matrix, PPU toolbar, and grid-resize scenarios.

local M = {}

function M.buttonCenter(button)
  assert(button, "expected button")
  return button.x + math.floor(button.w * 0.5), button.y + math.floor(button.h * 0.5)
end

function M.appQuickButtonCenter(key)
  return function(_, currentApp)
    local buttons = currentApp._appTopQuickButtons or {}
    local button = assert(buttons[key], "expected app top quick button: " .. tostring(key))
    return M.buttonCenter(button)
  end
end

function M.ppuToolbarButtonCenter(winKey, resolver)
  return function(_, currentApp, currentRunner)
    local win = assert(currentRunner[winKey], "expected PPU window for key: " .. tostring(winKey))
    local toolbar = assert(win.specializedToolbar, "expected PPU specialized toolbar")
    toolbar:updateIcons()
    toolbar:updatePosition()
    local button = resolver(toolbar, currentRunner, currentApp)
    assert(button, "expected PPU toolbar button")
    return M.buttonCenter(button)
  end
end

function M.menuRowCenterByText(menuResolver, text)
  return function(_, currentApp, currentRunner)
    local menu = assert(menuResolver(currentApp, currentRunner), "expected visible context menu")
    assert(menu.isVisible and menu:isVisible(), "expected context menu to be visible")
    local items = menu.visibleItems or {}
    local targetRow = nil
    for i, item in ipairs(items) do
      if item and item.text == text then
        targetRow = i
        break
      end
    end
    assert(targetRow, "expected context menu item: " .. tostring(text))
    local anchorCol = (menu.activeSplitIconCell == true and (tonumber(menu.cols) or 1) > 1) and 2 or 1
    local cell = assert(menu.panel:getCell(anchorCol, targetRow), "expected context menu row cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

function M.setFocusedTextFieldValue(field, value)
  assert(field and field.setFocused and field.setText, "expected text field")
  field:setFocused(true)
  field:setText(tostring(value or ""))
end

function M.setupDeterministicPpuFixture(currentApp, currentRunner)
  local BankViewController = require("controllers.chr.bank_view_controller")
  local NametableUtils = require("utils.nametable_utils")
  local chr = require("chr")
  local state = currentApp.appEditState or {}
  assert(type(state.romRaw) == "string" and state.romRaw ~= "", "expected ROM bytes in app state")

  BankViewController.ensureBankTiles(state, 1)

  local nametable = {}
  local attributes = {}
  for i = 1, 32 * 30 do
    nametable[i] = 0
  end
  for i = 1, 64 do
    attributes[i] = 0
  end
  nametable[(4 * 32) + 4 + 1] = 6
  nametable[(4 * 32) + 5 + 1] = 7
  nametable[(5 * 32) + 4 + 1] = 22
  nametable[(5 * 32) + 5 + 1] = 23

  local compressed = NametableUtils.encode_decompressed_nametable(nametable, attributes, "konami")
  assert(type(compressed) == "table" and #compressed > 0, "expected encoded nametable stream")
  local startAddr = 0x40
  local newRom, romErr = chr.writeBytesToRange(state.romRaw, startAddr, #compressed, compressed)
  assert(newRom, "failed to write compressed nametable fixture: " .. tostring(romErr))
  state.romRaw = newRom

  local ppuWin = assert(currentApp.wm:createPPUFrameWindow({
    title = "PPU Toolbar Fixture",
    x = 328,
    y = 70,
    zoom = 2,
    romRaw = state.romRaw,
    bankIndex = 1,
    pageIndex = 1,
  }), "expected PPU frame window")
  ppuWin.visibleCols = 10
  ppuWin.visibleRows = 10
  if ppuWin.setScroll then
    ppuWin:setScroll(0, 0)
  end

  local layer = assert(ppuWin.layers and ppuWin.layers[1], "expected PPU tile layer")
  layer.patternTable = {
    ranges = {
      { bank = 1, page = 1, tileRange = { from = 0, to = 255 } },
    },
  }
  layer.nametableStartAddr = nil
  layer.nametableEndAddr = nil
  if currentApp._ensurePpuPatternTableReferenceLayer then
    currentApp:_ensurePpuPatternTableReferenceLayer(ppuWin, 1, {
      keepActiveLayer = true,
    })
  end

  local oamWin = assert(currentApp.wm:createSpriteWindow({
    animated = true,
    oamBacked = true,
    numFrames = 1,
    title = "OAM Clipboard Fixture",
    x = 40,
    y = 184,
    cols = 8,
    rows = 8,
    zoom = 2,
    spriteMode = "8x8",
  }), "expected OAM animation fixture window")

  currentRunner.ppuFixtureWin = ppuWin
  currentRunner.oamFixtureWin = oamWin
  currentRunner.ppuFixtureRangeStart = startAddr
  currentRunner.ppuFixtureRangeEnd = startAddr + #compressed - 1
  currentRunner.ppuFixtureCompressedLen = #compressed
  currentRunner.ppuFixtureExpectedTile = nametable[(4 * 32) + 4 + 1]

  currentApp.wm:setFocus(ppuWin)
  return ppuWin
end

function M.harnessHoldShiftForGridResize(harness, down)
  harness._keysDown.lshift = down == true
  if not down then
    harness._keysDown.rshift = false
  end
end

function M.assertStatusContainsOccupiedLayout(harness)
  local s = tostring(harness:getStatusText() or "")
  assert(
    s:find("occupied") ~= nil or s:find("layout items") ~= nil,
    string.format("expected occupied layout message in status, got: %q", s)
  )
end

return M
