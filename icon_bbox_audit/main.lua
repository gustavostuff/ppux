local Config = require("config")
local State = require("state")
local Scanner = require("scanner")
local Renderer = require("renderer")

local state = State.new()

local function rescan()
  Scanner.scan(state, Config)
end

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  state.canvas = love.graphics.newCanvas(Config.BASE_W, Config.BASE_H)
  state.canvas:setFilter("nearest", "nearest")
  state.uiFont = love.graphics.newFont("proggy-tiny.ttf", Config.UI_FONT_SIZE)
  state.uiFont:setFilter("nearest", "nearest")

  local base = love.filesystem.getSourceBaseDirectory() or "."
  state.iconsDir = Scanner.resolveIconsDir(base)
  rescan()
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
    return
  end
  if key == "r" then
    rescan()
  end
end

function love.wheelmoved(_, y)
  if y == 0 then return end
  state.scrollY = state.scrollY + (y * Config.SCROLL_STEP)
  State.clampScroll(state)
end

function love.draw()
  Renderer.draw(state, Config, State.clampScroll)
end
