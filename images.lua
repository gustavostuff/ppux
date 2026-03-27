-- Build a nested table that mirrors img/, but load PNGs lazily on first access.
-- Example: img/cursors/cursor_hand.png -> images.cursors.cursor_hand

local images = {}
local visitedDirs = {}
local imagePathsByNode = setmetatable({}, { __mode = "k" })
local eagerLoad = (rawget(_G, "__PPUX_IMAGES_EAGER__") == true)

local function normalizeDir(path)
  path = tostring(path or ""):gsub("\\", "/")
  path = path:gsub("/+", "/")
  path = path:gsub("/%./", "/")
  path = path:gsub("/%.$", "")
  path = path:gsub("^%./", "")
  if path == "" then
    return "."
  end
  return path
end

local function loadImage(path)
  local img = love.graphics.newImage(path)
  img:setFilter("nearest", "nearest")
  return img
end

local function attachLazyLoader(node)
  if getmetatable(node) then
    return node
  end

  setmetatable(node, {
    __index = function(t, key)
      local paths = imagePathsByNode[t]
      local path = paths and paths[key] or nil
      if not path then
        return nil
      end

      local img = loadImage(path)
      rawset(t, key, img)
      paths[key] = nil
      return img
    end,
  })

  return node
end

local function registerImage(node, key, path)
  local paths = imagePathsByNode[node]
  if not paths then
    paths = {}
    imagePathsByNode[node] = paths
  end
  paths[key] = path
end

local function loadDir(dir, node)
  dir = normalizeDir(dir)
  if visitedDirs[dir] then
    return
  end
  visitedDirs[dir] = true
  attachLazyLoader(node)

  local items = love.filesystem.getDirectoryItems(dir)
  table.sort(items)

  for _, item in ipairs(items) do
    if item ~= "" and item ~= "." and item ~= ".." then
      local path = normalizeDir(dir .. "/" .. item)
      if path == dir then
        goto continue
      end
      local info = love.filesystem.getInfo(path)

      if info and info.type == "directory" then
        local child = attachLazyLoader({})
        rawset(node, item, child)
        loadDir(path, child)
      elseif info and info.type == "file" and item:sub(-4) == ".png" then
        local key = item:sub(1, -5)
        if eagerLoad then
          rawset(node, key, loadImage(path))
        else
          registerImage(node, key, path)
        end
      end
    end
    ::continue::
  end
end

loadDir("img", images)

return images
