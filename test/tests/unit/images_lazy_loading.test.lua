describe("images.lua - eager vs lazy loading", function()
  local originalImagesModule
  local originalEagerFlag
  local originalGetDirectoryItems
  local originalGetInfo
  local originalNewImage

  local imageLoadCount

  local function installFakeFilesystem()
    love.filesystem.getDirectoryItems = function(path)
      path = tostring(path or "")
      if path == "img" then
        return { "icons", "misc.png" }
      end
      if path == "img/icons" then
        return { "cursor.png" }
      end
      return {}
    end

    love.filesystem.getInfo = function(path)
      local info = {
        ["img"] = { type = "directory" },
        ["img/icons"] = { type = "directory" },
        ["img/misc.png"] = { type = "file" },
        ["img/icons/cursor.png"] = { type = "file" },
      }
      return info[path]
    end
  end

  local function installFakeImageLoader()
    love.graphics.newImage = function(path)
      imageLoadCount = imageLoadCount + 1
      return {
        _path = path,
        setFilter = function() end,
      }
    end
  end

  local function loadImagesModule(eager)
    _G.__PPUX_IMAGES_EAGER__ = eager == true
    package.loaded["images"] = nil
    return require("images")
  end

  beforeEach(function()
    originalImagesModule = package.loaded["images"]
    originalEagerFlag = rawget(_G, "__PPUX_IMAGES_EAGER__")
    originalGetDirectoryItems = love.filesystem.getDirectoryItems
    originalGetInfo = love.filesystem.getInfo
    originalNewImage = love.graphics.newImage
    imageLoadCount = 0

    installFakeFilesystem()
    installFakeImageLoader()
  end)

  afterEach(function()
    love.filesystem.getDirectoryItems = originalGetDirectoryItems
    love.filesystem.getInfo = originalGetInfo
    love.graphics.newImage = originalNewImage
    _G.__PPUX_IMAGES_EAGER__ = originalEagerFlag
    package.loaded["images"] = originalImagesModule
  end)

  it("does not load PNGs during require in lazy mode, then loads on first access", function()
    local images = loadImagesModule(false)

    expect(imageLoadCount).toBe(0)
    expect(type(images.icons)).toBe("table")

    local misc = images.misc
    expect(imageLoadCount).toBe(1)
    expect(misc._path).toBe("img/misc.png")

    local cursor = images.icons.cursor
    expect(imageLoadCount).toBe(2)
    expect(cursor._path).toBe("img/icons/cursor.png")

    local miscAgain = images.misc
    local cursorAgain = images.icons.cursor
    expect(imageLoadCount).toBe(2)
    expect(miscAgain).toBe(misc)
    expect(cursorAgain).toBe(cursor)
  end)

  it("loads all discovered PNGs during require in eager mode", function()
    local images = loadImagesModule(true)

    expect(imageLoadCount).toBe(2)
    expect(images.misc._path).toBe("img/misc.png")
    expect(images.icons.cursor._path).toBe("img/icons/cursor.png")

    local miscAgain = images.misc
    local cursorAgain = images.icons.cursor
    expect(imageLoadCount).toBe(2)
    expect(miscAgain._path).toBe("img/misc.png")
    expect(cursorAgain._path).toBe("img/icons/cursor.png")
  end)
end)
