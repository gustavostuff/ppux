-- Capture README window-link example PNGs.
-- Layout canvas is 300x200; written files are nearest-neighbor 2x (600x400).
-- Invoked via: love . --capture-source-links
-- See scripts/dev/capture_source_links_readme_images.sh

local E2EHarness = require("test.e2e_harness")
local BubbleExample = require("test.e2e_bubble_example")
local ResolutionController = require("controllers.app.resolution_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local WindowLinkBadgeController = require("controllers.window.window_link_badge_controller")
local FilesystemPath = require("utils.filesystem_path")
local chr = require("chr")

local M = {}

local OUT_DIR = "img/readme_images"
local IMAGE_W, IMAGE_H = 300, 200
local OUTPUT_SCALE = 2
local OUTPUT_W, OUTPUT_H = IMAGE_W * OUTPUT_SCALE, IMAGE_H * OUTPUT_SCALE
local HEADER_H = 15
local TOOLBAR_H = 15
local TOOLBAR_GAP = 1
-- Inset for fully-visible windows (peek slivers stay on the canvas edge).
local MARGIN = 12

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
  -- Hidden app bar must not clamp specialized toolbars to MIN_BAR_H.
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
end

local function writePng(imgData, filename)
  local fileData = assert(imgData:encode("png"), "encode png failed")
  local path = absOutPath(filename)
  local tmpPath = path .. ".tmp.png"
  local f = assert(io.open(tmpPath, "wb"), "open for write: " .. tmpPath)
  f:write(fileData:getString())
  f:close()
  local cmd = string.format(
    'ffmpeg -v error -y -i %q -vf scale=%d:%d:flags=neighbor -pix_fmt rgba %q',
    tmpPath, OUTPUT_W, OUTPUT_H, path)
  local ok = os.execute(cmd)
  os.remove(tmpPath)
  assert(ok == true or ok == 0, "ffmpeg rgba convert failed for " .. path)
  print(string.format("[capture-source-links] wrote %s (%dx%d from %dx%d)",
    path, OUTPUT_W, OUTPUT_H, imgData:getWidth(), imgData:getHeight()))
end

local function captureCanvas(app, filename)
  app:update(0)
  app:draw()
  local full = app.canvas:newImageData()
  local w, h = full:getDimensions()
  assert(w == IMAGE_W and h == IMAGE_H, string.format("expected %dx%d canvas, got %dx%d", IMAGE_W, IMAGE_H, w, h))
  writePng(full, filename)
end

local function placeWindow(win, x, y)
  win.x = math.floor(x)
  win.y = math.floor(y)
end

local function setVisibleGrid(win, cols, rows)
  win.visibleCols = math.max(1, math.floor(tonumber(cols) or win.visibleCols or 1))
  win.visibleRows = math.max(1, math.floor(tonumber(rows) or win.visibleRows or 1))
  if win.setScroll then
    win:setScroll(0, 0)
  end
end

-- Content origin (win.y) so a focused window's specialized toolbar sits below `margin`.
local function focusedContentY(margin)
  return math.floor(margin or MARGIN) + TOOLBAR_H + TOOLBAR_GAP + HEADER_H
end

-- Content origin when the window is unfocused (header only, no spec toolbar).
local function unfocusedContentY(margin)
  return math.floor(margin or MARGIN) + HEADER_H
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

local function addSpriteLayer(ppu)
  for _, layer in ipairs(ppu.layers or {}) do
    if layer and layer.kind == "sprite" then
      return layer
    end
  end
  return ppu:addLayer({
    opacity = 1.0,
    name = "Sprites",
    kind = "sprite",
    mode = "8x8",
  })
end

local function linkWindows(app, a, slotA, b, slotB)
  local ok = WindowLinkBadgeController.applyLink(app, a, slotA, b, slotB)
  assert(ok == true, string.format("link failed: %s/%s -> %s/%s",
    tostring(a and a.title), tostring(slotA), tostring(b and b.title), tostring(slotB)))
end

local function writePaletteRomBytes(app)
  local rom = app.appEditState.romRaw
  assert(type(rom) == "string" and #rom > 64, "expected loaded ROM")
  -- Distinct NES colors for two 4x4 palettes (skip col0 of palette A; those stay unbound).
  local bytes = {
    -- palette A rows 0-3, cols 1-3 (12 colors)
    0x26, 0x20, 0x15,
    0x2C, 0x09, 0x0F,
    0x36, 0x16, 0x07,
    0x30, 0x11, 0x01,
    -- palette B all 16 cells
    0x0F, 0x0C, 0x27, 0x05,
    0x0F, 0x1C, 0x37, 0x30,
    0x0F, 0x16, 0x26, 0x36,
    0x0F, 0x01, 0x11, 0x21,
  }
  local base = 0x40
  for i, value in ipairs(bytes) do
    local nextRom, err = chr.writeByteToAddress(rom, base + i - 1, value)
    assert(nextRom, err or "write palette byte failed")
    rom = nextRom
  end
  app.appEditState.romRaw = rom
  return base
end

local function romColorsFromAddresses(addrs, rows, cols)
  local out = {}
  local i = 1
  for r = 1, rows do
    out[r] = {}
    for c = 1, cols do
      out[r][c] = addrs[i]
      i = i + 1
    end
  end
  return out
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

local function createPeekPpu(app, title, x, y)
  local win = assert(app.wm:createPPUFrameWindow({
    title = title,
    x = x,
    y = y,
    zoom = 1,
    romRaw = app.appEditState.romRaw,
  }))
  -- Narrow sliver: left-edge badges + a few empty cells.
  setVisibleGrid(win, 4, 12)
  placeWindow(win, x, y)
  addSpriteLayer(win)
  return win
end

local function createFittedPpu(app, title, x, y, cols, rows)
  local win = assert(app.wm:createPPUFrameWindow({
    title = title,
    x = x,
    y = y,
    zoom = 1,
    romRaw = app.appEditState.romRaw,
  }))
  setVisibleGrid(win, cols or 28, rows or 16)
  placeWindow(win, x, y)
  addSpriteLayer(win)
  return win
end

local function createPatternTable(app, title, x, y, cols, rows, zoom)
  local tileCount = math.max(1, cols * rows)
  local win = assert(app.wm:createPatternTableWindow({
    title = title,
    x = x,
    y = y,
    zoom = zoom or 2,
    cols = cols,
    rows = rows,
    visibleCols = cols,
    visibleRows = rows,
    patternTable = {
      ranges = {
        { bank = 1, from = 0, to = tileCount - 1 },
      },
    },
  }))
  setVisibleGrid(win, cols, rows)
  placeWindow(win, x, y)
  populatePatternTable(app, win)
  return win
end

local function captureExample1(app)
  closeAllWindows(app)
  local paletteBase = writePaletteRomBytes(app)

  local palAAddrs = {}
  local nextAddr = paletteBase
  for row = 1, 4 do
    for col = 1, 4 do
      if col == 1 then
        palAAddrs[#palAAddrs + 1] = false
      else
        palAAddrs[#palAAddrs + 1] = nextAddr
        nextAddr = nextAddr + 1
      end
    end
  end
  local palBAddrs = {}
  for _ = 1, 16 do
    palBAddrs[#palBAddrs + 1] = nextAddr
    nextAddr = nextAddr + 1
  end

  local palX = MARGIN
  local palY1 = focusedContentY(8)
  local pal1 = assert(app.wm:createRomPaletteWindow({
    title = "ROM palette",
    x = palX,
    y = palY1,
    zoom = 1,
    paletteRole = "rom",
    romRaw = app.appEditState.romRaw,
    paletteData = {
      romColors = romColorsFromAddresses(palAAddrs, 4, 4),
      userDefinedCode = {},
    },
  }))
  placeWindow(pal1, palX, palY1)
  overrideCell(pal1, 1, 0, "27")
  overrideCell(pal1, 2, 0, "36")
  overrideCell(pal1, 1, 1, "2A")
  overrideCell(pal1, 2, 1, "19")
  pal1:setSelected(1, 0)

  local palH = 4 * 16
  local palY2 = palY1 + palH + HEADER_H + 8
  local pal2 = assert(app.wm:createRomPaletteWindow({
    title = "ROM palette",
    x = palX,
    y = palY2,
    zoom = 1,
    paletteRole = "rom",
    romRaw = app.appEditState.romRaw,
    paletteData = {
      romColors = romColorsFromAddresses(palBAddrs, 4, 4),
      userDefinedCode = {},
    },
  }))
  placeWindow(pal2, palX, palY2)
  pal2:setSelected(1, 3)

  local peekX = IMAGE_W - 24
  local ppu = createPeekPpu(app, "PPU Frame", peekX, palY1)
  linkWindows(app, pal1, "palette_source", ppu, "ppu_palette")
  app.wm:setFocus(pal1)
  captureCanvas(app, "source_links_example_1.png")
end

local function captureExample2(app)
  closeAllWindows(app)
  ensureBankTiles(app, 1)
  local ptY = focusedContentY()
  local pt = createPatternTable(app, "Pattern table", MARGIN, ptY, 8, 8, 2)
  local peekX = IMAGE_W - 18
  local ppu1 = createPeekPpu(app, "PPU Frame", peekX, ptY)
  setVisibleGrid(ppu1, 4, 8)
  local ppu1H = 8 * 8
  local ppu2Y = ptY + ppu1H + HEADER_H + 8
  local ppu2 = createPeekPpu(app, "PPU Frame", peekX, ppu2Y)
  setVisibleGrid(ppu2, 4, 8)
  linkWindows(app, pt, "pattern_source", ppu1, "ppu_pattern_bg")
  linkWindows(app, pt, "pattern_source", ppu1, "ppu_pattern_sprite")
  linkWindows(app, pt, "pattern_source", ppu2, "ppu_pattern_bg")
  linkWindows(app, pt, "pattern_source", ppu2, "ppu_pattern_sprite")
  app.wm:setFocus(pt)
  captureCanvas(app, "source_links_example_2.png")
end

local function captureExample3(app)
  closeAllWindows(app)
  ensureBankTiles(app, 1)
  local pt = createPatternTable(app, "Pattern table", -240, unfocusedContentY(), 16, 16, 2)
  local ppuCols, ppuRows = 16, 16
  local ppuW = ppuCols * 8
  local ppuX = IMAGE_W - ppuW - MARGIN
  local ppu = createFittedPpu(app, "PPU Frame", ppuX, focusedContentY(), ppuCols, ppuRows)
  linkWindows(app, pt, "pattern_source", ppu, "ppu_pattern_bg")
  app.wm:setFocus(ppu)
  captureCanvas(app, "source_links_example_3.png")
end

local function captureExample4(app)
  closeAllWindows(app)
  ensureBankTiles(app, 1)
  local pt = createPatternTable(app, "Pattern table", -240, unfocusedContentY(), 16, 16, 2)
  local oamSize = 8 * 8 * 2
  local oamX = IMAGE_W - oamSize - MARGIN
  local oamY = focusedContentY()
  local oam = assert(app.wm:createSpriteWindow({
    animated = true,
    oamBacked = true,
    numFrames = 1,
    title = "OAM Animation",
    x = oamX,
    y = oamY,
    cols = 8,
    rows = 8,
    zoom = 2,
    spriteMode = "8x8",
  }))
  setVisibleGrid(oam, 8, 8)
  placeWindow(oam, oamX, oamY)
  linkWindows(app, pt, "pattern_source", oam, "oam_pattern")
  app.wm:setFocus(oam)
  captureCanvas(app, "source_links_example_4.png")
end

function M.run()
  print(string.format("[capture-source-links] starting (%dx%d, write %dx%d)",
    IMAGE_W, IMAGE_H, OUTPUT_W, OUTPUT_H))
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
  harness:loadROM(assert(BubbleExample.getLoadPath(), "expected test ROM"))
  hideAppChrome(app)
  closeAllWindows(app)
  ensureBankTiles(app, 1)

  captureExample1(app)
  captureExample2(app)
  captureExample3(app)
  captureExample4(app)

  harness:destroy()
  print("[capture-source-links] done")
  love.event.quit(0)
end

return M
