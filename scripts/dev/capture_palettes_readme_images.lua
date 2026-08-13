-- Capture README palettes.png.
-- Layout canvas is 300x200; written file is nearest-neighbor 2x (600x400).
-- Invoked via: love . --capture-palettes
-- See scripts/dev/capture_palettes_readme_images.sh

local E2EHarness = require("test.e2e_harness")
local BubbleExample = require("test.e2e_bubble_example")
local ResolutionController = require("controllers.app.resolution_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
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
local MARGIN = 16
local PALETTE_CELL_W, PALETTE_CELL_H = 24, 16

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
  local cmd = string.format(
    'ffmpeg -v error -y -i %q -vf scale=%d:%d:flags=neighbor -pix_fmt rgba %q',
    tmpPath, OUTPUT_W, OUTPUT_H, path)
  local ok = os.execute(cmd)
  os.remove(tmpPath)
  assert(ok == true or ok == 0, "ffmpeg rgba convert failed for " .. path)
  print(string.format("[capture-palettes] wrote %s (%dx%d from %dx%d)",
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

local function focusedContentY(margin)
  return math.floor(margin or MARGIN) + TOOLBAR_H + TOOLBAR_GAP + HEADER_H
end

local function writePaletteRomBytes(app)
  local rom = app.appEditState.romRaw
  assert(type(rom) == "string" and #rom > 64, "expected loaded ROM")
  local bytes = {
    0x15, 0x30, 0x0F,
    0x26, 0x16, 0x06,
    0x12, 0x22, 0x32,
    0x11, 0x21, 0x01,
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

local function capturePalettes(app)
  closeAllWindows(app)
  local paletteBase = writePaletteRomBytes(app)

  local romAddrs = {}
  local nextAddr = paletteBase
  for row = 1, 4 do
    for col = 1, 4 do
      if col == 1 then
        romAddrs[#romAddrs + 1] = false
      else
        romAddrs[#romAddrs + 1] = nextAddr
        nextAddr = nextAddr + 1
      end
    end
  end

  local palW = 4 * PALETTE_CELL_W
  local romH = 4 * PALETTE_CELL_H
  local gap = 20
  local pairW = palW + gap + palW
  local genX = math.floor((IMAGE_W - pairW) / 2)
  local romX = genX + palW + gap
  local chromeH = TOOLBAR_H + TOOLBAR_GAP + HEADER_H + romH
  local topMargin = math.max(MARGIN, math.floor((IMAGE_H - chromeH) / 2))
  local contentY = focusedContentY(topMargin)

  local generic = assert(app.wm:createPaletteWindow({
    title = "Palette",
    x = genX,
    y = contentY,
    zoom = 1,
    initCodes = { "0F", "30", "36", "26" },
    activePalette = true,
  }))
  placeWindow(generic, genX, contentY)
  generic:setSelected(2, 0)

  local romPal = assert(app.wm:createRomPaletteWindow({
    title = "ROM palette",
    x = romX,
    y = contentY,
    zoom = 1,
    paletteRole = "rom",
    romRaw = app.appEditState.romRaw,
    paletteData = {
      romColors = romColorsFromAddresses(romAddrs, 4, 4),
      userDefinedCode = {},
    },
  }))
  placeWindow(romPal, romX, contentY)
  overrideCell(romPal, 1, 0, "27")
  overrideCell(romPal, 2, 0, "36")
  overrideCell(romPal, 1, 1, "2A")
  overrideCell(romPal, 2, 1, "19")
  romPal:setSelected(1, 0)

  -- Keep both headers aligned; ROM is focused so its role toolbar (RP) is visible.
  app.wm:setFocus(romPal)
  captureCanvas(app, "palettes.png")
end

function M.run()
  print(string.format("[capture-palettes] starting (%dx%d, write %dx%d)",
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
  if app._applyGroupedPaletteWindowsSetting then
    app:_applyGroupedPaletteWindowsSetting(false, false)
  end
  closeAllWindows(app)

  capturePalettes(app)

  harness:destroy()
  print("[capture-palettes] done")
  love.event.quit(0)
end

return M
