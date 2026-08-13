-- Capture README tile/edit mode indicator PNGs.
-- Canvas is 300x200; we crop the bottom-right 160x90 and write nearest-neighbor 2x (320x180).
-- Invoked via: love . --capture-mode-indicators
-- See scripts/dev/capture_mode_indicator_readme_images.sh

local E2EHarness = require("test.e2e_harness")
local ResolutionController = require("controllers.app.resolution_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local FilesystemPath = require("utils.filesystem_path")

local M = {}

local OUT_DIR = "img/readme_images"
local IMAGE_W, IMAGE_H = 300, 200
local CROP_W, CROP_H = 160, 90
local OUTPUT_SCALE = 2
local OUTPUT_W, OUTPUT_H = CROP_W * OUTPUT_SCALE, CROP_H * OUTPUT_SCALE

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

local function hideAppToolbar(app)
  AppTopToolbarController.draw = function() end
  AppTopToolbarController.getContentOffsetY = function()
    return 0
  end
  app.showDebugInfo = false
  app.separateToolbar = false
  if app._applyWindowShadowSetting then
    app:_applyWindowShadowSetting(false, false)
  else
    app.windowShadowEnabled = false
  end
end

local function setAppMode(app, mode)
  if app._buildCtx then
    app:_buildCtx().setMode(mode)
    return
  end
  app.mode = (mode == "edit") and "edit" or "tile"
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
  print(string.format("[capture-mode-indicators] wrote %s (%dx%d from %dx%d)",
    path, OUTPUT_W, OUTPUT_H, imgData:getWidth(), imgData:getHeight()))
end

local function cropBottomRight(full)
  local fw, fh = full:getDimensions()
  assert(fw >= CROP_W and fh >= CROP_H,
    string.format("canvas %dx%d too small to crop %dx%d", fw, fh, CROP_W, CROP_H))
  local crop = love.image.newImageData(CROP_W, CROP_H)
  crop:paste(full, 0, 0, fw - CROP_W, fh - CROP_H, CROP_W, CROP_H)
  return crop
end

local function captureMode(app, mode, filename)
  setAppMode(app, mode)
  app:update(0)
  app:draw()
  local crop = cropBottomRight(app.canvas:newImageData())
  writePng(crop, filename)
end

function M.run()
  print(string.format("[capture-mode-indicators] starting (crop %dx%d, write %dx%d)",
    CROP_W, CROP_H, OUTPUT_W, OUTPUT_H))
  local harness = E2EHarness.new({
    settings = { skipSplash = true },
    shimEventQuit = false,
  })
  local app = harness:boot()
  hideAppToolbar(app)
  setCanvasSize(app, IMAGE_W, IMAGE_H)
  hideAppToolbar(app)
  closeAllWindows(app)
  if app.wm then
    app.wm.focused = nil
  end

  captureMode(app, "tile", "tile_mode_indicator.png")
  captureMode(app, "edit", "edit_mode_indicator.png")

  harness:destroy()
  print("[capture-mode-indicators] done")
  love.event.quit(0)
end

return M
