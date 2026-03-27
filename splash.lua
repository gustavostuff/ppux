local colors = require("app_colors")
local Button = require("user_interface.button")
local images = require("images")

local Splash = {}
Splash.__index = Splash

function Splash.new(settings)
  local self = setmetatable({}, Splash)
  self.skip = settings and settings.skipSplash == true
  self.saveFn = settings and settings.saveFn
  self.image = nil
  self.button = nil
  self.visible = false

  if not self.skip then
    if love.filesystem.getInfo("img/splash.png") then
      self.image = love.graphics.newImage("img/splash.png")
      self.visible = true
      -- Create dismiss-forever button; icon will be set later by user
      local icon = (settings and settings.buttonIcon) or
          images.icons.icon_not_selected or
          images.icons.icon_plus or
          images.icons.icon_minus
      if self.saveFn then
        self.button = Button.new({
          icon = icon,
          w = icon:getWidth(),
          h = icon:getHeight(),
          tooltip = "Don't show again",
          action = function()
            if self.saveFn then self.saveFn() end
            self.skip = true
            self.visible = false
          end,
        })
      end
    end
  end

  return self
end

function Splash:isVisible()
  return self.visible
end

-- Position button relative to splash image
local function buttonRect(self, sw, sh)
  if not (self.image and self.button) then return nil end
  sw = sw or love.graphics.getWidth()
  sh = sh or love.graphics.getHeight()
  local iw, ih = self.image:getWidth(), self.image:getHeight()
  local sx = (sw - iw) / 2
  local sy = (sh - ih) / 2
  local margin = 4
  local bx = sx + margin
  local by = sy + ih - self.button.h - margin
  return bx, by
end

function Splash:mousepressed(x, y)
  if not self.visible then return false end
  if self.button then
    local bx, by = buttonRect(self, self._canvasW, self._canvasH)
    self.button:setPosition(bx, by)
    if self.button:contains(x, y) then
      self.button.pressed = true
      return "button"
    end
  end
  return "dismiss"
end

function Splash:mousereleased(x, y, saveFn)
  if not self.visible then return false end
  if self.button and self.button.pressed then
    self.button.pressed = false
    local bx, by = buttonRect(self, self._canvasW, self._canvasH)
    if self.button:contains(x, y) then
      if self.button.action then self.button:action() end
    end
  end
  self.visible = false
  return true
end

function Splash:keypressed(key)
  if not self.visible then return false end
  if key ~= "escape" then return false end
  if self.button then
    self.button.pressed = false
  end
  self.visible = false
  return true
end

function Splash:draw(canvas)
  if not self.visible or not self.image then return end
  local sw, sh = canvas:getWidth(), canvas:getHeight()
  self._canvasW, self._canvasH = sw, sh
  local iw, ih = self.image:getWidth(), self.image:getHeight()
  local x = (sw - iw) / 2
  local y = (sh - ih) / 2

  -- Dim background
  love.graphics.setColor(colors.black[1], colors.black[2], colors.black[3], 0.65)
  love.graphics.rectangle("fill", 0, 0, sw, sh)

  love.graphics.setColor(colors.white)
  love.graphics.draw(self.image, x, y)

  if self.button then
    local bx, by = buttonRect(self, sw, sh)
    self.button:setPosition(bx, by)
    -- Draw simple backing so the button is visible even if icon alpha is low
    local hover = self.button.hovered
    if hover then
      love.graphics.setColor(1, 1, 1, 0.2)
      love.graphics.rectangle("fill", bx, by, self.button.w, self.button.h)
    end
    love.graphics.setColor(1, 1, 1, 0)
    love.graphics.rectangle("fill", bx, by, self.button.w, self.button.h)
    self.button:draw()
  end

  love.graphics.setColor(colors.white)
end

return Splash
