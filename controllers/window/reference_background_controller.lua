-- Reference PNG underlay for tracing: per eligible window, persisted path, R toggles view in tile mode.
local colors = require("app_colors")
local WindowCaps = require("controllers.window.window_capabilities")
local CanvasSpace = require("utils.canvas_space")

local M = {}

function M.isEligibleWindow(win)
  return WindowCaps.isCrtVizLayoutWindow(win)
end

local function windowContentPixelSize(w)
  local cols = tonumber(w.cols) or 0
  local rows = tonumber(w.rows) or 0
  local cw = tonumber(w.cellW) or 8
  local ch = tonumber(w.cellH) or 8
  local maxW, maxH = cols * cw, rows * ch
  if w.layers then
    for _, L in ipairs(w.layers) do
      if L and L.kind == "canvas" and L.canvas and L.canvas.getWidth and L.canvas.getHeight then
        maxW = math.max(maxW, L.canvas:getWidth())
        maxH = math.max(maxH, L.canvas:getHeight())
      end
    end
  end
  return math.max(0, maxW), math.max(0, maxH)
end

function M.dimensionsExceedWindow(pngW, pngH, win)
  local w, h = windowContentPixelSize(win)
  return (pngW > w) or (pngH > h), w, h
end

local function normalizeSlashes(p)
  p = tostring(p or "")
  if package.config:sub(1, 1) == "\\" then
    return p:gsub("/", "\\")
  end
  return p:gsub("\\", "/")
end

local function directoryOfFile(path)
  path = normalizeSlashes(path)
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  return dir or ""
end

local function filenameOnly(path)
  path = normalizeSlashes(path)
  return path:match("[^/\\]+$") or path
end

--- Store path relative to project file when it shares the same directory tree; else absolute.
function M.pathForPersist(app, absoluteImagePath)
  local img = normalizeSlashes(absoluteImagePath or "")
  local proj = app and app.projectPath and normalizeSlashes(app.projectPath) or ""
  if img == "" then
    return ""
  end
  if proj == "" then
    return img
  end
  local pd = directoryOfFile(proj)
  local id = directoryOfFile(img)
  if pd ~= "" and id == pd then
    return filenameOnly(img)
  end
  if pd ~= "" and id ~= "" then
    local slashPref = pd .. "/"
    local backPref = pd .. "\\"
    local head = id:sub(1, #pd + 1)
    if head == slashPref or head == backPref then
      return normalizeSlashes(img:sub(#pd + 2))
    end
  end
  return img
end

--- Resolve saved path (relative to project dir or absolute) to filesystem path.
function M.resolvePathOnLoad(app, storedPath)
  local s = tostring(storedPath or "")
  if s == "" then
    return ""
  end
  s = normalizeSlashes(s)
  if s:match("^%a:[/\\]") or s:sub(1, 1) == "/" then
    return s
  end
  local proj = app and app.projectPath
  local pd = directoryOfFile(normalizeSlashes(proj or ""))
  if pd ~= "" then
    local sep = (package.config:sub(1, 1) == "\\") and "\\" or "/"
    return normalizeSlashes(pd .. sep .. s)
  end
  return s
end

function M.releaseImage(win)
  if win.referenceImageDrawable and win.referenceImageDrawable.release then
    pcall(function()
      win.referenceImageDrawable:release()
    end)
  end
  win.referenceImageDrawable = nil
  win.referenceImageMissing = nil
end

function M.tryLoadImageAtPath(absPath)
  absPath = tostring(absPath or "")
  if absPath == "" then
    return nil, "empty_path"
  end
  local ok, img = pcall(love.graphics.newImage, absPath)
  if not ok or not img then
    return nil, "load_failed"
  end
  img:setFilter("nearest", "nearest")
  return img
end

function M.applyStoredPath(win, app, storedPath, opts)
  opts = opts or {}
  M.releaseImage(win)
  win.referenceImageStoredPath = nil
  win.referenceDisplayReference = false

  storedPath = tostring(storedPath or "")
  if storedPath == "" then
    return true
  end

  local abs = M.resolvePathOnLoad(app, storedPath)
  win.referenceImageStoredPath = storedPath
  local drawable, reason = M.tryLoadImageAtPath(abs)
  if drawable then
    win.referenceImageDrawable = drawable
    win.referenceImageMissing = false
    win.referenceResolvedPath = abs
    if opts.toastWarnOversized then
      local iw, ih = drawable:getWidth(), drawable:getHeight()
      local tooBig, cw, ch = M.dimensionsExceedWindow(iw, ih, win)
      if tooBig and app and app.showToast then
        app:showToast(
          "warning",
          string.format(
            "Reference image (%dx%d) is larger than this window (%dx%d).",
            iw,
            ih,
            cw,
            ch
          )
        )
      end
    end
    return true
  end
  win.referenceImageMissing = true
  if app and app.showToast then
    app:showToast("warning", "Reference image not found (moved or renamed). Re-link or remove it from the toolbar.")
  end
  return false, reason
end

--- User picked a PNG: absolute path from file dialog.
function M.setReferenceFromAbsolutePath(win, app, absolutePath, opts)
  opts = opts or {}
  absolutePath = tostring(absolutePath or "")
  M.releaseImage(win)
  win.referenceDisplayReference = false
  if absolutePath == "" then
    win.referenceImageStoredPath = nil
    return false
  end

  local drawable = M.tryLoadImageAtPath(absolutePath)
  if not drawable then
    if app and app.showToast then
      app:showToast("error", "Could not load PNG as reference.")
    end
    return false
  end

  win.referenceImageDrawable = drawable
  win.referenceImageMissing = false
  win.referenceResolvedPath = normalizeSlashes(absolutePath)
  win.referenceImageStoredPath = M.pathForPersist(app, absolutePath)

  local iw, ih = drawable:getWidth(), drawable:getHeight()
  local tooBig, cw, ch = M.dimensionsExceedWindow(iw, ih, win)
  if tooBig and app and app.showToast then
    app:showToast(
      "warning",
      string.format(
        "Reference image (%dx%d) is larger than this window (%dx%d).",
        iw,
        ih,
        cw,
        ch
      )
    )
  end

  if app and app.markUnsaved then
    app:markUnsaved("reference_background_change")
  end
  return true
end

function M.windowHasStoredReference(win)
  return win and type(win.referenceImageStoredPath) == "string" and win.referenceImageStoredPath ~= ""
end

function M.clearReference(win, app)
  M.releaseImage(win)
  win.referenceImageStoredPath = nil
  win.referenceResolvedPath = nil
  win.referenceDisplayReference = false
  if app and app.markUnsaved then
    app:markUnsaved("reference_background_change")
  end
end

function M.toggleDisplay(win)
  if not (win and win.referenceImageStoredPath and win.referenceImageStoredPath ~= "" and win.referenceImageDrawable) then
    return false
  end
  win.referenceDisplayReference = not win.referenceDisplayReference
  return true
end

function M.hasReference(win)
  return win
    and type(win.referenceImageStoredPath) == "string"
    and win.referenceImageStoredPath ~= ""
    and win.referenceImageDrawable
    and win.referenceImageMissing ~= true
end

--- Draw centered in window content coords; call after chess grid, before layers. Clip to viewport.
function M.drawReferenceBehindLayers(win)
  if not M.hasReference(win) or not win.referenceDisplayReference then
    return
  end
  local img = win.referenceImageDrawable
  if not (img and img.draw) then
    return
  end

  local sx, sy, sw, sh = win:getScreenRect()
  love.graphics.push()
  love.graphics.translate(win.x, win.y)
  local z = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
  love.graphics.scale(z, z)
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)

  local cw = win.cellW or 8
  local ch = win.cellH or 8
  local scol = win.scrollCol or 0
  local srow = win.scrollRow or 0
  love.graphics.translate(-scol * cw, -srow * ch)

  local maxW, maxH = windowContentPixelSize(win)
  local iw, ih = img:getWidth(), img:getHeight()
  local dx = math.floor((maxW - iw) / 2)
  local dy = math.floor((maxH - ih) / 2)

  love.graphics.setColor(1, 1, 1, 1)
  img:draw(dx, dy)
  love.graphics.setColor(colors.white)

  love.graphics.pop()
  love.graphics.setScissor()
end

return M
