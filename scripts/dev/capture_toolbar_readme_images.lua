-- This was AI generated!
-- Capture specialized / app toolbar strips for README images.
-- Invoked via: love . --capture-toolbars  (see scripts/dev/capture_toolbar_readme_images.sh)

local E2EHarness = require("test.e2e_harness")
local BubbleExample = require("test.e2e_bubble_example")
local ResolutionController = require("controllers.app.resolution_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local BankViewController = require("controllers.chr.bank_view_controller")
local WindowFactory = require("controllers.game_art.window_factory_controller")
local FilesystemPath = require("utils.filesystem_path")

local M = {}

local OUT_DIR = "img/readme_images/toolbars"

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
    if win then
      win._closed = true
    end
  end
end

local function forceOneXWindow(app)
  local cw = app.canvas:getWidth()
  local ch = app.canvas:getHeight()
  if love.window and love.window.setMode then
    love.window.setMode(cw, ch, {
      fullscreen = false,
      resizable = true,
      vsync = 0,
      minwidth = cw,
      minheight = ch,
    })
  end
  ResolutionController:setMode(ResolutionController.modes.PIXEL_PERFECT)
  ResolutionController:recalculate()
end

local function makeCornersTransparent(imgData)
  local w, h = imgData:getDimensions()
  if w < 1 or h < 1 then
    return
  end
  imgData:setPixel(0, 0, 0, 0, 0, 0)
  imgData:setPixel(w - 1, 0, 0, 0, 0, 0)
  imgData:setPixel(0, h - 1, 0, 0, 0, 0)
  imgData:setPixel(w - 1, h - 1, 0, 0, 0, 0)
end

-- Disabled toolbar icon ink (#6d6d6d) -> enabled look (#b6b6b6) for README shots.
local DISABLED_ICON_GRAY = 0x6d / 255
local ENABLED_ICON_GRAY = 0xb6 / 255
local GRAY_MATCH_EPS = 1e-4

local function remapDisabledIconGrayToEnabled(imgData)
  local w, h = imgData:getDimensions()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = imgData:getPixel(x, y)
      if math.abs(r - DISABLED_ICON_GRAY) < GRAY_MATCH_EPS
        and math.abs(g - DISABLED_ICON_GRAY) < GRAY_MATCH_EPS
        and math.abs(b - DISABLED_ICON_GRAY) < GRAY_MATCH_EPS then
        imgData:setPixel(x, y, ENABLED_ICON_GRAY, ENABLED_ICON_GRAY, ENABLED_ICON_GRAY, a)
      end
    end
  end
end

local function writePng(imgData, filename)
  remapDisabledIconGrayToEnabled(imgData)
  makeCornersTransparent(imgData)
  local fileData = assert(imgData:encode("png"), "encode png failed")
  local path = absOutPath(filename)
  local tmpPath = path .. ".tmp.png"
  local f = assert(io.open(tmpPath, "wb"), "open for write: " .. tmpPath)
  f:write(fileData:getString())
  f:close()
  -- LOVE may emit a paletted PNG; force RGBA so corner alpha survives attach_header.
  local cmd = string.format('ffmpeg -v error -y -i %q -pix_fmt rgba %q', tmpPath, path)
  local ok = os.execute(cmd)
  os.remove(tmpPath)
  assert(ok == true or ok == 0, "ffmpeg rgba convert failed for " .. path)
  print(string.format("[capture-toolbars] wrote %s (%dx%d)", path, imgData:getWidth(), imgData:getHeight()))
end

local function cropCanvas(app, x, y, w, h)
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w = math.floor(tonumber(w) or 0)
  h = math.floor(tonumber(h) or 0)
  assert(w > 0 and h > 0, "invalid crop size")
  local canvasW, canvasH = app.canvas:getDimensions()
  assert(x >= 0 and y >= 0 and x + w <= canvasW and y + h <= canvasH,
    string.format("crop out of bounds: %d,%d %dx%d (canvas %dx%d)", x, y, w, h, canvasW, canvasH))

  app:update(0)
  app:draw()
  local full = app.canvas:newImageData()
  local cropped = love.image.newImageData(w, h)
  cropped:paste(full, 0, 0, x, y, w, h)
  return cropped
end

local function specializedToolbarBounds(toolbar)
  assert(toolbar, "expected specialized toolbar")
  if toolbar.updateIcons then
    toolbar:updateIcons()
  end
  toolbar:updatePosition()
  local drawX = math.floor((tonumber(toolbar.x) or 0) - 1)
  local drawY = math.floor(tonumber(toolbar.y) or 0)
  local drawW = math.max(0, math.floor(tonumber(toolbar.w) or 0))
  local drawH = math.max(0, math.floor(tonumber(toolbar.h) or 0))
  -- Prefer occupied first-row width when layout tracked it (matches draw()).
  local rowWidths = toolbar._layoutRowWidths
  if type(rowWidths) == "table" and type(rowWidths[1]) == "number" and rowWidths[1] > 0 then
    local labelWidth = 0
    for _, label in ipairs(toolbar.labels or {}) do
      if not label.renderInContent then
        labelWidth = labelWidth + (tonumber(label.width) or 0)
      end
    end
    drawW = math.floor(labelWidth + rowWidths[1])
  end
  assert(drawW > 0 and drawH > 0, "toolbar has empty bounds")
  return drawX, drawY, drawW, drawH
end

local function captureSpecializedToolbar(app, win, filename)
  assert(win and not win._closed, "expected open window")
  app.wm:setFocus(win)
  local toolbar = assert(win.specializedToolbar, "expected specializedToolbar on " .. tostring(win.title))
  toolbar.visible = true
  toolbar.enabled = true
  local x, y, w, h = specializedToolbarBounds(toolbar)
  writePng(cropCanvas(app, x, y, w, h), filename)
end

local function captureAppToolbar(app, filename)
  AppTopToolbarController.syncLayout(app)
  local lay = assert(app._appTopToolbarLayout, "expected app top toolbar layout")
  local x = math.floor(tonumber(lay.quickLeftX) or 0)
  local y = 0
  local w = math.floor((tonumber(lay.quickRightX) or 0) - x)
  local h = math.floor(tonumber(lay.totalH) or 15)
  assert(w > 0 and h > 0, "app toolbar empty bounds")
  writePng(cropCanvas(app, x, y, w, h), filename)
end

local function createChrLike(app, opts)
  local win = WindowFactory.createChrBankWindow(opts)
  app.wm:finalizeNewWindow(win)
  BankViewController.ensureBankTiles(app.appEditState, win.currentBank or 1)
  BankViewController.rebuildBankWindowItems(
    win,
    app.appEditState,
    win.orderMode,
    function() end
  )
  return win
end

local function ensurePpuSpriteLayer(ppu)
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

local function placeWindow(win, x, y)
  win.x = x
  win.y = y
end

function M.run()
  print("[capture-toolbars] starting (1x canvas capture)")
  local harness = E2EHarness.new({
    settings = { skipSplash = true },
    shimEventQuit = false,
  })
  local app = harness:boot()
  app.separateToolbar = false
  if app._applyWindowLinksSetting then
    app:_applyWindowLinksSetting("never", false)
  end

  forceOneXWindow(app)
  harness:loadROM(assert(BubbleExample.getLoadPath(), "expected test ROM"))

  -- App top quick-action strip (no window).
  closeAllWindows(app)
  captureAppToolbar(app, "app_toolbar.png")

  -- CHR Banks
  closeAllWindows(app)
  do
    local win = createChrLike(app, {
      id = "capture_chr_banks",
      title = "CHR Banks",
      x = 40,
      y = 80,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      isRomWindow = false,
      currentBank = 1,
    })
    placeWindow(win, 40, 80)
    captureSpecializedToolbar(app, win, "chr_banks_toolbar.png")
  end

  -- ROM Banks
  closeAllWindows(app)
  do
    local win = createChrLike(app, {
      id = "capture_rom_banks",
      title = "ROM Banks",
      x = 40,
      y = 80,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      isRomWindow = true,
      currentBank = 1,
    })
    placeWindow(win, 40, 80)
    captureSpecializedToolbar(app, win, "rom_banks_toolbar.png")
  end

  -- Tile animation (not static art)
  closeAllWindows(app)
  do
    local win = assert(app.wm:createTileWindow({
      animated = true,
      title = "Tile Animation",
      x = 40,
      y = 80,
      cols = 8,
      rows = 8,
      zoom = 2,
      numFrames = 2,
    }))
    captureSpecializedToolbar(app, win, "animation_tile_toolbar.png")
  end

  -- OAM animation (not static sprites)
  closeAllWindows(app)
  do
    local win = assert(app.wm:createSpriteWindow({
      animated = true,
      oamBacked = true,
      title = "OAM Animation",
      x = 40,
      y = 80,
      cols = 8,
      rows = 8,
      zoom = 2,
      numFrames = 2,
      spriteMode = "8x8",
    }))
    captureSpecializedToolbar(app, win, "oam_animation_toolbar.png")
  end

  -- Generic palette
  closeAllWindows(app)
  do
    local win = assert(app.wm:createPaletteWindow({
      title = "Generic palette",
      x = 40,
      y = 80,
    }))
    captureSpecializedToolbar(app, win, "global_palette_toolbar.png")
  end

  -- ROM palette
  closeAllWindows(app)
  do
    local win = assert(app.wm:createRomPaletteWindow({
      title = "ROM palette",
      x = 40,
      y = 80,
    }))
    captureSpecializedToolbar(app, win, "rom_palette_toolbar.png")
  end

  -- PPU frame with sprite layer (origin-guides button visible)
  closeAllWindows(app)
  do
    local win = assert(app.wm:createPPUFrameWindow({
      title = "PPU Frame",
      x = 40,
      y = 80,
      zoom = 2,
      romRaw = app.appEditState and app.appEditState.romRaw,
      bankIndex = 1,
      pageIndex = 1,
    }))
    ensurePpuSpriteLayer(win)
    if win.specializedToolbar and win.specializedToolbar.updateIcons then
      win.specializedToolbar:updateIcons()
    end
    captureSpecializedToolbar(app, win, "ppu_frame_sprite_layer_toolbar.png")
  end

  -- Pattern table
  closeAllWindows(app)
  do
    local win = assert(app.wm:createPatternTableWindow({
      title = "Pattern table",
      x = 40,
      y = 80,
      zoom = 2,
      patternTable = {
        ranges = {
          { bank = 1, from = 0, to = 255 },
        },
      },
    }))
    captureSpecializedToolbar(app, win, "pattern_table_toolbar.png")
  end

  -- Sketch canvas
  closeAllWindows(app)
  do
    local win = assert(app.wm:createSketchCanvasWindow({
      title = "Sketch canvas",
      x = 40,
      y = 80,
    }))
    captureSpecializedToolbar(app, win, "sketch_canvas_toolbar.png")
  end

  harness:destroy()
  print("[capture-toolbars] love capture done")
  love.event.quit(0)
end

return M
