-- Capture README hex-grid modal PNGs (palette address, add sprite, nametable range).
-- Crops each modal panel, then nearest-neighbor 2x.
-- Invoked via: love . --capture-hex-grids
-- See scripts/dev/capture_hex_grid_readme_images.sh

local E2EHarness = require("test.e2e_harness")
local BubbleExample = require("test.e2e_bubble_example")
local ResolutionController = require("controllers.app.resolution_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local WindowLinkBadgeController = require("controllers.window.window_link_badge_controller")
local FilesystemPath = require("utils.filesystem_path")
local chr = require("chr")
local RomHexGrid = require("ui.rom_hex_grid")

local M = {}

local OUT_DIR = "img/readme_images"
local IMAGE_W, IMAGE_H = 400, 280
local OUTPUT_SCALE = 2

-- Injected into test_rom.nes (no real OAM / palette rows).
local PALETTE_BASE = 0x40
local OAM_BASE = 0x100
local NT_PAGE = 0x200

local function projectRoot()
  local source = love.filesystem.getSource()
  if type(source) == "string" and source ~= "" then
    return source
  end
  return "."
end

local function absOutPath(filename)
  return FilesystemPath.join(projectRoot(), OUT_DIR, filename)
end

local function closeAllWindows(app)
  for _, win in ipairs(app.wm:getWindows() or {}) do
    if win and not win._closed then
      app.wm:closeWindow(win)
    end
  end
end

local function hideHexModals(app)
  if app.romPaletteAddressModal and app.romPaletteAddressModal.hide then
    app.romPaletteAddressModal:hide()
  end
  if app.ppuFrameAddSpriteModal and app.ppuFrameAddSpriteModal.hide then
    app.ppuFrameAddSpriteModal:hide()
  end
  if app.ppuFrameRangeModal and app.ppuFrameRangeModal.hide then
    app.ppuFrameRangeModal:hide()
  end
end

local function setCanvasSize(app, w, h)
  app.canvas = love.graphics.newCanvas(w, h)
  app.canvas:setFilter("nearest", "nearest")
  if love.window and love.window.setMode then
    love.window.setMode(w, h, {
      fullscreen = false,
      resizable = true,
      vsync = 0,
      minwidth = w,
      minheight = h,
    })
  end
  ResolutionController:init(app.canvas)
  ResolutionController:setMode(ResolutionController.modes.PIXEL_PERFECT)
  ResolutionController:recalculate()
  if app.taskbar and app.taskbar.updateLayout then
    app.taskbar:updateLayout(w, h)
  end
  if app.toastController and app.toastController.updateLayout then
    app.toastController:updateLayout(w, h)
  end
end

local function hideAppChrome(app)
  AppTopToolbarController.draw = function() end
  AppTopToolbarController.getContentOffsetY = function()
    return 0
  end
  if app.taskbar then
    app.taskbar.draw = function() end
  end
  app.showDebugInfo = false
  app.separateToolbar = false
  if app._applyWindowShadowSetting then
    app:_applyWindowShadowSetting(false, false)
  else
    app.windowShadowEnabled = false
  end
  if app.wm then
    app.wm.forceAllWindowsFocused = true
  end
end

local function writePng(imgData, filename)
  local fileData = assert(imgData:encode("png"), "encode png failed")
  local path = absOutPath(filename)
  local tmpPath = path .. ".tmp.png"
  local f = assert(io.open(tmpPath, "wb"), "open for write: " .. tmpPath)
  f:write(fileData:getString())
  f:close()
  local srcW, srcH = imgData:getDimensions()
  local outW, outH = srcW * OUTPUT_SCALE, srcH * OUTPUT_SCALE
  local cmd = string.format(
    'ffmpeg -v error -y -i %q -vf scale=%d:%d:flags=neighbor -pix_fmt rgba %q',
    tmpPath, outW, outH, path)
  local ok = os.execute(cmd)
  os.remove(tmpPath)
  assert(ok == true or ok == 0, "ffmpeg rgba convert failed for " .. path)
  print(string.format("[capture-hex-grids] wrote %s (%dx%d from %dx%d)",
    path, outW, outH, srcW, srcH))
end

local function cropModalImage(full, modal)
  local canvasW, canvasH = full:getDimensions()
  local x = math.max(0, math.floor(tonumber(modal._boxX) or 0))
  local y = math.max(0, math.floor(tonumber(modal._boxY) or 0))
  local w = math.max(1, math.floor(tonumber(modal._boxW) or 0))
  local h = math.max(1, math.floor(tonumber(modal._boxH) or 0))
  if x + w > canvasW then
    w = canvasW - x
  end
  if y + h > canvasH then
    h = canvasH - y
  end
  assert(w > 8 and h > 8, string.format(
    "modal crop too small: %dx%d at %d,%d (canvas %dx%d)", w, h, x, y, canvasW, canvasH))
  local cropped = love.image.newImageData(w, h)
  cropped:paste(full, 0, 0, x, y, w, h)
  return cropped
end

local function layoutModal(app, modal)
  assert(modal and modal.draw, "expected modal")
  modal:draw(app.canvas)
end

local function captureModal(app, modal, filename)
  assert(modal and modal.isVisible and modal:isVisible(), "expected visible modal for " .. filename)
  layoutModal(app, modal)
  app:update(0)
  app:draw()
  local full = app.canvas:newImageData()
  writePng(cropModalImage(full, modal), filename)
end

local function writeRomBytes(app, startAddr, values)
  local rom = app.appEditState.romRaw
  assert(type(rom) == "string" and #rom > startAddr + #values, "expected loaded ROM")
  local nextRom, err = chr.writeBytesStartingAt(rom, startAddr, values)
  assert(nextRom, err or "writeBytesStartingAt failed")
  app.appEditState.romRaw = nextRom
end

local function palettePageBytes()
  -- Mostly valid NES colors so Hide-invalid leaves a colorful grid with a few holes.
  local pretty = {
    0x0F, 0x30, 0x36, 0x26, 0x16, 0x06, 0x12, 0x22,
    0x32, 0x11, 0x21, 0x01, 0x19, 0x29, 0x2A, 0x1A,
    0x27, 0x07, 0x17, 0x37, 0x2C, 0x1C, 0x0C, 0x00,
  }
  local bytes = {}
  local invalidAt = {
    [0x0A] = 0x0D,
    [0x1F] = 0x0E,
    [0x33] = 0x1E,
    [0x4C] = 0x2E,
    [0x61] = 0x3F,
  }
  for i = 0, RomHexGrid.BYTES_PER_PAGE - 1 do
    bytes[i + 1] = invalidAt[i] or pretty[(i % #pretty) + 1]
  end
  return bytes
end

local function oamGroupBytes()
  -- Synthetic OAM: Y, tile, attr, X. Tiles exist in test_rom CHR.
  return {
    0x10, 0x06, 0x00, 0x20,
    0x10, 0x07, 0x00, 0x28,
    0x18, 0x16, 0x00, 0x20,
    0x18, 0x17, 0x00, 0x28,
    0x20, 0x01, 0x00, 0x30,
  }
end

local function injectCaptureBytes(app)
  writeRomBytes(app, PALETTE_BASE, palettePageBytes())
  writeRomBytes(app, OAM_BASE, oamGroupBytes())
end

local function ensureBankTiles(app, bank)
  BankViewController.ensureBankTiles(app.appEditState, bank or 1)
end

local function populatePatternTable(app, ptWin)
  PatternTableDisplayController.populateTileLayerItemsFromPatternTable(ptWin, 1, {
    wm = app.wm,
    tilesPool = app.appEditState and app.appEditState.tilesPool,
    appEditState = app.appEditState,
    ensureTiles = function(bank)
      ensureBankTiles(app, bank)
    end,
  })
end

local function overrideCell(win, col, row, code)
  if not (win.codes2D and win.codes2D[row]) then
    return
  end
  win.codes2D[row][col] = code
  if win.set then
    win:set(col, row, code)
  end
  if win.saveUserDefinedCode then
    win:saveUserDefinedCode(row, col, code)
  end
end

local function capturePaletteAddress(app)
  closeAllWindows(app)
  hideHexModals(app)

  local addrs = {}
  for i = 1, 16 do
    addrs[i] = PALETTE_BASE + i - 1
  end
  local romColors = {}
  local i = 1
  for r = 1, 4 do
    romColors[r] = {}
    for c = 1, 4 do
      romColors[r][c] = addrs[i]
      i = i + 1
    end
  end

  local pal = assert(app.wm:createRomPaletteWindow({
    title = "ROM palette",
    x = 8,
    y = 24,
    zoom = 1,
    paletteRole = "rom",
    romRaw = app.appEditState.romRaw,
    paletteData = {
      romColors = romColors,
      userDefinedCode = {},
    },
  }))
  overrideCell(pal, 1, 0, "27")
  pal:setSelected(1, 0)
  app.wm:setFocus(pal)

  assert(app:showRomPaletteAddressModal(pal, 1, 0), "expected palette address modal")
  local modal = assert(app.romPaletteAddressModal, "expected romPaletteAddressModal")
  assert(modal:isVisible(), "expected palette address modal visible")
  layoutModal(app, modal)
  -- Park the colorful injected page at the top of the grid.
  modal.hexGrid.scrollOffset = RomHexGrid.alignRow(PALETTE_BASE)
  if modal._refreshSemiSelected then
    modal:_refreshSemiSelected()
  end
  layoutModal(app, modal)
  captureModal(app, modal, "edit_palette_rom_address.png")
  modal:hide()
  closeAllWindows(app)
end

local function captureAddSprite(app)
  closeAllWindows(app)
  hideHexModals(app)
  ensureBankTiles(app, 1)

  local pt = assert(app.wm:createPatternTableWindow({
    title = "Pattern table",
    x = 8,
    y = 24,
    zoom = 2,
    cols = 8,
    rows = 8,
    visibleCols = 8,
    visibleRows = 8,
    patternTable = {
      ranges = {
        { bank = 1, from = 0, to = 255 },
      },
    },
  }))
  if pt.setScroll then
    pt:setScroll(0, 0)
  end
  populatePatternTable(app, pt)

  local oam = assert(app.wm:createSpriteWindow({
    animated = true,
    oamBacked = true,
    numFrames = 1,
    title = "OAM",
    x = 160,
    y = 24,
    cols = 8,
    rows = 8,
    zoom = 2,
    spriteMode = "8x8",
  }))
  local layer = assert(oam.layers and oam.layers[1], "expected sprite layer")
  local linked = WindowLinkBadgeController.applyLink(app, pt, "pattern_source", oam, "oam_pattern")
  assert(linked == true, "expected PT -> OAM link")
  if type(layer.linkedPatternTableWindowId) ~= "string" or layer.linkedPatternTableWindowId == "" then
    layer.linkedPatternTableWindowId = pt._id
  end
  local PatternTableMapping = require("utils.pattern_table_mapping")
  if not PatternTableMapping.validate(layer.patternTable) then
    layer.patternTable = {
      ranges = {
        { bank = 1, from = 0, to = 255 },
      },
    }
  end
  app.wm:setFocus(oam)

  assert(app:showPpuFrameAddSpriteModal(oam), "expected add sprite modal")
  local modal = assert(app.ppuFrameAddSpriteModal, "expected ppuFrameAddSpriteModal")
  assert(modal:isVisible(), "expected add sprite modal visible")
  layoutModal(app, modal)

  local starts = { OAM_BASE, OAM_BASE + 4, OAM_BASE + 8, OAM_BASE + 12 }
  -- Keep the four groups mid-grid (scrollToReveal would park them on the last row).
  modal.hexGrid.scrollOffset = math.max(0, RomHexGrid.alignRow(OAM_BASE) - 3 * RomHexGrid.COLS)
  modal.hexGrid:_setStarts(starts, starts[1], {
    emit = false,
    allowEmpty = false,
    resetColors = true,
    scrollToReveal = false,
  })
  modal:_onGridSelect(starts[1], { fromGrid = true })
  layoutModal(app, modal)
  captureModal(app, modal, "add_oam_sprite.png")
  modal:hide()
  closeAllWindows(app)
end

local function captureNametableRange(app)
  closeAllWindows(app)
  hideHexModals(app)
  ensureBankTiles(app, 1)

  local ppu = assert(app.wm:createPPUFrameWindow({
    title = "PPU Frame",
    x = 8,
    y = 24,
    zoom = 2,
    romRaw = app.appEditState.romRaw,
    bankIndex = 1,
    pageIndex = 1,
  }))
  ppu.visibleCols = 8
  ppu.visibleRows = 8
  if ppu.setScroll then
    ppu:setScroll(0, 0)
  end
  local layer = assert(ppu.layers and ppu.layers[1], "expected tile layer")
  -- Non-Konami: Scanned mode checkbox stays hidden (README note).
  layer.codec = "raw"
  layer.nametableStartAddr = nil
  layer.nametableEndAddr = nil
  app.wm:setFocus(ppu)

  assert(app:showPpuFrameRangeModal(ppu), "expected nametable range modal")
  local modal = assert(app.ppuFrameRangeModal, "expected ppuFrameRangeModal")
  assert(modal:isVisible(), "expected range modal visible")
  layoutModal(app, modal)

  local grid = modal.hexGrid
  grid:scrollToReveal(NT_PAGE)
  local pageStart = math.floor(tonumber(grid.scrollOffset) or NT_PAGE)
  local pageBytes = grid:bytesPerPage()
  -- Leave a thin unselected rim so the blue range is obviously a selection.
  local startAddr = pageStart + 2
  local endAddr = pageStart + pageBytes - 3
  modal:_commitRange(startAddr, endAddr)
  layoutModal(app, modal)
  captureModal(app, modal, "set_nametable_range.png")
  modal:hide()
  closeAllWindows(app)
end

function M.run()
  print(string.format("[capture-hex-grids] starting (canvas %dx%d, crop modal, %dx)",
    IMAGE_W, IMAGE_H, OUTPUT_SCALE))
  local harness = E2EHarness.new({
    settings = { skipSplash = true },
    shimEventQuit = false,
  })
  local app = harness:boot()
  app.separateToolbar = false
  if app._applyGroupedPaletteWindowsSetting then
    app:_applyGroupedPaletteWindowsSetting(false, false)
  end
  if app._applyWindowLinksSetting then
    app:_applyWindowLinksSetting("always", false)
  end

  hideAppChrome(app)
  setCanvasSize(app, IMAGE_W, IMAGE_H)
  harness:loadROM(assert(BubbleExample.getRomPath(), "expected test/test_rom.nes"))
  hideAppChrome(app)
  closeAllWindows(app)
  injectCaptureBytes(app)
  ensureBankTiles(app, 1)

  capturePaletteAddress(app)
  captureAddSprite(app)
  captureNametableRange(app)

  harness:destroy()
  print("[capture-hex-grids] done")
  love.event.quit(0)
end

return M
