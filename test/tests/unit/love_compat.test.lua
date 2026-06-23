-- love_compat.test.lua
-- Unit tests for utils/love_compat.lua

local LoveCompat = require("utils.love_compat")

describe("love_compat.lua", function()
  local restore = {}

  local function stash(path, value)
    restore[path] = value
  end

  local function setPath(path, value)
    local parts = {}
    for part in string.gmatch(path, "[^%.]+") do
      parts[#parts + 1] = part
    end

    local parent = _G
    for i = 1, #parts - 1 do
      local key = parts[i]
      if parent[key] == nil then
        parent[key] = {}
      end
      parent = parent[key]
    end
    parent[parts[#parts]] = value
  end

  local function getPath(path)
    local parent = _G
    for part in string.gmatch(path, "[^%.]+") do
      parent = parent and parent[part]
    end
    return parent
  end

  afterEach(function()
    for path, value in pairs(restore) do
      if value == "__nil__" then
        setPath(path, nil)
      else
        setPath(path, value)
      end
    end
    restore = {}
  end)

  it("reports LOVE availability", function()
    expect(LoveCompat.hasLove()).toBe(love ~= nil)
    expect(LoveCompat.hasApi("timer", "getTime")).toBe(
      love ~= nil and love.timer ~= nil and type(love.timer.getTime) == "function"
    )
  end)

  it("getTime uses love.timer when present", function()
    stash("love.timer.getTime", getPath("love.timer.getTime"))
    love.timer.getTime = function()
      return 42.5
    end
    expect(LoveCompat.getTime()).toBe(42.5)
  end)

  it("getTimeOr uses fallback when timer is missing", function()
    stash("love", love)
    _G.love = { timer = {} }
    expect(LoveCompat.getTimeOr(7)).toBe(7)
  end)

  it("keyboard helpers return false without LOVE keyboard", function()
    stash("love", love)
    _G.love = {}
    expect(LoveCompat.isKeyDown("a")).toBe(false)
    expect(LoveCompat.isCtrlDown()).toBe(false)
    expect(LoveCompat.isShiftDown()).toBe(false)
    expect(LoveCompat.isAltDown()).toBe(false)
    expect(LoveCompat.isAnyKeyDown("a", "b")).toBe(false)
  end)

  it("isAnyKeyDown returns true when one key is held", function()
    stash("love.keyboard.isDown", getPath("love.keyboard.isDown"))
    love.keyboard.isDown = function(key)
      return key == "kp5"
    end
    expect(LoveCompat.isAnyKeyDown("5", "kp5")).toBe(true)
    expect(LoveCompat.isCtrlDown()).toBe(false)
  end)

  it("mouse helpers degrade safely", function()
    stash("love", love)
    _G.love = { mouse = {} }
    local x, y = LoveCompat.getMousePosition()
    expect(x).toBeNil()
    expect(y).toBeNil()
    expect(LoveCompat.isMouseDown(1)).toBe(false)
  end)

  it("clipboard helpers round-trip through LOVE system", function()
    stash("love.system.getClipboardText", getPath("love.system.getClipboardText"))
    stash("love.system.setClipboardText", getPath("love.system.setClipboardText"))

    local stored = nil
    love.system.setClipboardText = function(text)
      stored = text
      return true
    end
    love.system.getClipboardText = function()
      return stored
    end

    expect(LoveCompat.setClipboardText("tile ff")).toBe(true)
    expect(LoveCompat.getClipboardText()).toBe("tile ff")
    expect(LoveCompat.setClipboardText(nil)).toBe(false)
  end)

  it("getWindowSize falls back when graphics is unavailable", function()
    stash("love", love)
    _G.love = {}
    local w, h = LoveCompat.getWindowSize(640, 360)
    expect(w).toBe(640)
    expect(h).toBe(360)
  end)
end)
