-- sketch_canvas_pack_controller.lua
-- Pack a sketch canvas into tilesPool ({x,y} refs) + nametableBytes with tolerance grouping.

local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

M.MAX_UNIQUE = 256
M.GRID_COLS = 32
M.GRID_ROWS = 30
M.CELL = 8
M.MAX_TOLERANCE = 64

local function pixelDiffCount(pattern1, pattern2, threshold)
  threshold = threshold or 0
  local differences = 0
  for i = 1, 64 do
    if pattern1[i] ~= pattern2[i] then
      differences = differences + 1
      if differences > threshold then
        return differences
      end
    end
  end
  return differences
end

local function resolveCanvas(winOrCanvas)
  if type(winOrCanvas) ~= "table" then
    return nil
  end
  if type(winOrCanvas.extractTilePixels) == "function" and type(winOrCanvas.getPixel) == "function" then
    return winOrCanvas
  end
  if type(winOrCanvas.getActiveCanvas) == "function" then
    return winOrCanvas:getActiveCanvas()
  end
  local layer = winOrCanvas.layers and winOrCanvas.layers[winOrCanvas.activeLayer or 1]
  if layer and layer.kind == "canvas" and layer.canvas then
    return layer.canvas
  end
  return nil
end

local function clampTolerance(tolerance)
  local t = math.floor(tonumber(tolerance) or 0)
  if t < 0 then
    return 0
  end
  if t > M.MAX_TOLERANCE then
    return M.MAX_TOLERANCE
  end
  return t
end

--- Pack a PixelCanvas into unique pool refs + 32x30 nametable indices.
--- @return pack table `{ tilesPool, nametableBytes, uniqueCount }` or nil, err
function M.packFromCanvas(canvas, tolerance)
  if not (canvas and type(canvas.extractTilePixels) == "function") then
    return nil, "no_canvas"
  end
  local width = tonumber(canvas.width) or 0
  local height = tonumber(canvas.height) or 0
  if width < M.GRID_COLS * M.CELL or height < M.GRID_ROWS * M.CELL then
    return nil, "canvas_too_small"
  end

  tolerance = clampTolerance(tolerance)
  local tilesPool = {}
  local uniquePatterns = {}
  local nametableBytes = {}

  for row = 0, M.GRID_ROWS - 1 do
    for col = 0, M.GRID_COLS - 1 do
      local ox = col * M.CELL
      local oy = row * M.CELL
      local pixels = canvas:extractTilePixels(ox, oy, M.CELL)
      local matchIndex = nil
      for i = 1, #uniquePatterns do
        if pixelDiffCount(pixels, uniquePatterns[i], tolerance) <= tolerance then
          matchIndex = i
          break
        end
      end

      if not matchIndex then
        if #tilesPool >= M.MAX_UNIQUE then
          return nil, "too_many_unique"
        end
        tilesPool[#tilesPool + 1] = { x = ox, y = oy }
        uniquePatterns[#uniquePatterns + 1] = pixels
        matchIndex = #tilesPool
      end

      -- 0-based pool index stored in nametableBytes (NES tile index style).
      nametableBytes[#nametableBytes + 1] = matchIndex - 1
    end
  end

  return {
    tilesPool = tilesPool,
    nametableBytes = nametableBytes,
    uniqueCount = #tilesPool,
    tolerance = tolerance,
  }
end

function M.applyPackToWindow(win, pack)
  if not (win and pack) then
    return false
  end
  win.tilesPool = pack.tilesPool or {}
  win.nametableBytes = pack.nametableBytes
  return true
end

--- Pack the sketch window paint buffer into tilesPool + nametableBytes.
--- Does not touch any linked pattern table (Phase 4).
--- @return ok, packOrErr
function M.generate(win)
  if not WindowCaps.isSketchCanvas(win) then
    return false, "not_sketch_canvas"
  end
  local canvas = resolveCanvas(win)
  if not canvas then
    return false, "no_canvas"
  end
  local pack, err = M.packFromCanvas(canvas, win.tolerance)
  if not pack then
    return false, err or "pack_failed"
  end
  M.applyPackToWindow(win, pack)
  return true, pack
end

function M.formatGenerateStatus(ok, packOrErr)
  if ok and type(packOrErr) == "table" then
    local n = tonumber(packOrErr.uniqueCount) or 0
    local tol = tonumber(packOrErr.tolerance) or 0
    return string.format(
      "Sketch generate: %d unique pattern%s (tolerance %d)",
      n,
      n == 1 and "" or "s",
      tol
    )
  end
  local err = tostring(packOrErr or "pack_failed")
  if err == "too_many_unique" then
    return "Sketch generate failed: more than 256 unique patterns (raise tolerance)"
  end
  if err == "no_canvas" then
    return "Sketch generate failed: no canvas"
  end
  if err == "canvas_too_small" then
    return "Sketch generate failed: canvas too small"
  end
  return "Sketch generate failed: " .. err
end

return M
