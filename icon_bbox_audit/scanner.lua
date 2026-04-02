local State = require("state")

local Scanner = {}

local function shellQuote(str)
  str = tostring(str or "")
  return "'" .. str:gsub("'", "'\\''") .. "'"
end

local function listPngFiles(rootPath)
  local cmd = "find " .. shellQuote(rootPath) .. " -type f -iname '*.png' -print"
  local pipe = io.popen(cmd)
  if not pipe then
    return {}
  end

  local out = {}
  for line in pipe:lines() do
    out[#out + 1] = line
  end
  pipe:close()

  table.sort(out)
  return out
end

local function dirExists(path)
  local cmd = "[ -d " .. shellQuote(path) .. " ] && echo 1 || echo 0"
  local pipe = io.popen(cmd)
  if not pipe then return false end
  local out = pipe:read("*l")
  pipe:close()
  return out == "1"
end

local function readImageDataFromAbsolutePath(path)
  local file, err = io.open(path, "rb")
  if not file then
    return nil, err or "open failed"
  end

  local bytes = file:read("*a")
  file:close()
  if not bytes or #bytes == 0 then
    return nil, "empty file"
  end

  local name = path:match("([^/\\]+)$") or "icon.png"
  local okFd, fileData = pcall(love.filesystem.newFileData, bytes, name, "file")
  if not okFd or not fileData then
    return nil, "failed to build file data"
  end

  local okImage, imageData = pcall(love.image.newImageData, fileData)
  if not okImage or not imageData then
    return nil, "failed to decode PNG"
  end

  return imageData, nil
end

local function computeOpaqueBounds(imageData)
  local w, h = imageData:getDimensions()
  local left = w
  local right = -1
  local top = h
  local bottom = -1

  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local _, _, _, a = imageData:getPixel(x, y)
      if a > 0 then
        if x < left then left = x end
        if x > right then right = x end
        if y < top then top = y end
        if y > bottom then bottom = y end
      end
    end
  end

  if right < left or bottom < top then
    return {
      empty = true,
      left = 0,
      right = -1,
      top = 0,
      bottom = -1,
      w = 0,
      h = 0,
    }
  end

  return {
    empty = false,
    left = left,
    right = right,
    top = top,
    bottom = bottom,
    w = (right - left + 1),
    h = (bottom - top + 1),
  }
end

local function isOversized(bounds, cfg)
  return (bounds.w > cfg.TARGET_MAX_W) or (bounds.h > cfg.TARGET_MAX_H)
end

local function relPath(path, rootPath)
  local prefix = rootPath .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

function Scanner.resolveIconsDir(baseDir)
  local dir = baseDir .. "/img/icons"
  if not dirExists(dir) then
    dir = baseDir .. "/../img/icons"
  end
  return dir
end

function Scanner.scan(state, cfg)
  State.resetScan(state)

  local pngFiles = listPngFiles(state.iconsDir)
  for _, absolutePath in ipairs(pngFiles) do
    local imageData, err = readImageDataFromAbsolutePath(absolutePath)
    if not imageData then
      state.scanErrors[#state.scanErrors + 1] = {
        path = absolutePath,
        err = tostring(err or "decode error"),
      }
    else
      local bounds = computeOpaqueBounds(imageData)
      local iw, ih = imageData:getDimensions()
      local entry = {
        path = absolutePath,
        rel = relPath(absolutePath, state.iconsDir),
        imgW = iw,
        imgH = ih,
        bounds = bounds,
      }
      state.scanned[#state.scanned + 1] = entry

      if isOversized(bounds, cfg) then
        local image = love.graphics.newImage(imageData)
        image:setFilter("nearest", "nearest")
        entry.image = image
        state.oversized[#state.oversized + 1] = entry
      end
    end
  end

  table.sort(state.oversized, function(a, b)
    local areaA = a.bounds.w * a.bounds.h
    local areaB = b.bounds.w * b.bounds.h
    if areaA ~= areaB then
      return areaA > areaB
    end
    if a.bounds.h ~= b.bounds.h then
      return a.bounds.h > b.bounds.h
    end
    return a.rel < b.rel
  end)
end

return Scanner
