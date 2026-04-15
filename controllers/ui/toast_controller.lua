local colors = require("app_colors")
local images = require("images")
local Timer = require("utils.timer_utils")
local UiScale = require("user_interface.ui_scale")
local Text = require("utils.text_utils")
local Draw = require("utils.draw_utils")

local ToastController = {}
ToastController.__index = ToastController

local DEFAULT_DURATION = 3.0
local DEFAULT_FADE_DURATION = 0.5
local STACK_GAP = 6
local MARGIN_RIGHT = 8
local MARGIN_BOTTOM = 6
local TOAST_MIN_W = 150
local TOAST_BASE_MAX_W = 260
local TOAST_EXPANDED_MAX_W = TOAST_BASE_MAX_W * 2
local TOAST_H = 24
local TOAST_PAD_X = 8
local CLOSE_PAD_RIGHT = 6

local TYPE_STYLES = {
  info = {
    bg = colors.blue,
    fg = colors.white,
  },
  warning = {
    bg = colors.yellow,
    fg = colors.black,
  },
  error = {
    bg = colors.red,
    fg = colors.white,
  },
}

local function pointInRect(px, py, x, y, w, h)
  return px >= x and px <= (x + w) and py >= y and py <= (y + h)
end

local function currentFont()
  return love.graphics and love.graphics.getFont and love.graphics.getFont() or nil
end

local function truncateToWidth(text, maxWidth)
  local font = currentFont()
  text = tostring(text or "")
  if not font or maxWidth <= 0 then
    return text
  end
  if font:getWidth(text) <= maxWidth then
    return text
  end

  local ellipsis = "..."
  local ellipsisW = font:getWidth(ellipsis)
  if ellipsisW >= maxWidth then
    return ""
  end

  local len = #text
  if len <= 2 then
    return ellipsis
  end

  local leftCount = math.floor(len / 2)
  local rightCount = len - leftCount

  if leftCount < 1 then leftCount = 1 end
  if rightCount < 1 then rightCount = 1 end

  local candidate = text:sub(1, leftCount) .. ellipsis .. text:sub(len - rightCount + 1)
  while font:getWidth(candidate) > maxWidth and (leftCount > 1 or rightCount > 1) do
    if leftCount >= rightCount and leftCount > 1 then
      leftCount = leftCount - 1
    elseif rightCount > 1 then
      rightCount = rightCount - 1
    else
      break
    end
    candidate = text:sub(1, leftCount) .. ellipsis .. text:sub(len - rightCount + 1)
  end

  if font:getWidth(candidate) <= maxWidth then
    return candidate
  end

  return ellipsis
end

local function toastStyle(kind)
  return TYPE_STYLES[kind] or TYPE_STYLES.info
end

local function closeIconSize()
  local icon = images and images.icons and images.icons.icon_x or nil
  if icon and icon.getWidth and icon.getHeight then
    return icon:getWidth(), icon:getHeight()
  end
  return 8, 8
end

function ToastController.new(app, opts)
  opts = opts or {}
  local self = setmetatable({
    app = app,
    toasts = {},
    nextId = 0,
    canvasW = 0,
    canvasH = 0,
    lastTaskbarTop = nil,
    layoutDirty = true,
    pressedToast = nil,
    marginRight = opts.marginRight or MARGIN_RIGHT,
    marginBottom = opts.marginBottom or MARGIN_BOTTOM,
    stackGap = opts.stackGap or STACK_GAP,
    defaultDuration = opts.defaultDuration or DEFAULT_DURATION,
    defaultFadeDuration = opts.defaultFadeDuration or DEFAULT_FADE_DURATION,
    timerMarkPrefix = string.format("toast_%s", tostring({})),
  }, ToastController)

  return self
end

function ToastController:_toastMarkName(id)
  return string.format("%s_%d", self.timerMarkPrefix, tonumber(id) or 0)
end

function ToastController:_canvasSize()
  local canvas = self.app and self.app.canvas or nil
  local w = self.canvasW
  local h = self.canvasH
  if canvas then
    w = canvas.getWidth and canvas:getWidth() or w
    h = canvas.getHeight and canvas:getHeight() or h
  end
  return w or 0, h or 0
end

function ToastController:_taskbarTop()
  local taskbar = self.app and self.app.taskbar or nil
  if taskbar and taskbar.getTopY then
    return taskbar:getTopY()
  end
  local _, canvasH = self:_canvasSize()
  return canvasH
end

function ToastController:_closeRect(toast)
  local iconW, iconH = closeIconSize()
  local x = math.floor((toast.x or toast.targetX or 0) + toast.w - CLOSE_PAD_RIGHT - iconW)
  local y = math.floor((toast.y or toast.targetY or 0) + math.floor((toast.h - iconH) * 0.5))
  return x, y, iconW, iconH
end

function ToastController:_toastAt(x, y)
  for i = 1, #self.toasts do
    local toast = self.toasts[i]
    if pointInRect(x, y, toast.x or toast.targetX or 0, toast.y or toast.targetY or 0, toast.w, toast.h) then
      return toast
    end
  end
  return nil
end

function ToastController:_layoutToasts()
  local canvasW = self:_canvasSize()
  local bottomY = self:_taskbarTop() - self.marginBottom
  local runningOffset = 0

  for i = 1, #self.toasts do
    local toast = self.toasts[i]
    toast.targetX = canvasW - self.marginRight - toast.w
    toast.targetY = bottomY - toast.h - runningOffset
    runningOffset = runningOffset + toast.h + self.stackGap
    toast.x = toast.targetX
    toast.y = toast.targetY
    toast.state = "visible"
  end

  self.lastTaskbarTop = self:_taskbarTop()
  self.layoutDirty = false
end

function ToastController:updateLayout(canvasW, canvasH)
  local prevW = self.canvasW
  local prevH = self.canvasH
  local nextW = canvasW or self.canvasW
  local nextH = canvasH or self.canvasH
  local taskbarTop

  self.canvasW = nextW
  self.canvasH = nextH
  taskbarTop = self:_taskbarTop()

  if self.layoutDirty
    or nextW ~= prevW
    or nextH ~= prevH
    or taskbarTop ~= self.lastTaskbarTop then
    self:_layoutToasts()
  end
end

function ToastController:_removeToast(toast)
  for i = #self.toasts, 1, -1 do
    if self.toasts[i] == toast then
      table.remove(self.toasts, i)
      if toast.markName then
        Timer.clearMark(toast.markName)
      end
      if self.pressedToast == toast then
        self.pressedToast = nil
      end
      break
    end
  end
end

function ToastController:_dismissToast(toast)
  if not toast then return false end

  self:_removeToast(toast)
  self.layoutDirty = true
  self:_layoutToasts()
  return true
end

function ToastController:_makeWidth(kind, text)
  local font = currentFont()
  local iconW = select(1, closeIconSize())
  if not font then
    return TOAST_BASE_MAX_W
  end

  local textW = font:getWidth(tostring(text or ""))
  local desiredWidth = (TOAST_PAD_X * 2) + textW + TOAST_PAD_X + iconW + CLOSE_PAD_RIGHT
  local width = desiredWidth

  if width < TOAST_MIN_W then
    width = TOAST_MIN_W
  end

  if width > TOAST_BASE_MAX_W then
    width = math.min(width, TOAST_EXPANDED_MAX_W)
  end

  local canvasW = self:_canvasSize()
  if type(canvasW) == "number" and canvasW > 0 then
    local maxVisibleWidth = math.max(TOAST_MIN_W, canvasW - (self.marginRight * 2))
    width = math.min(width, maxVisibleWidth)
  end

  return width
end

function ToastController:show(kind, text, opts)
  opts = opts or {}
  kind = TYPE_STYLES[kind] and kind or "info"
  text = tostring(text or "")
  if text == "" then return nil end

  self.nextId = self.nextId + 1
  local markName = self:_toastMarkName(self.nextId)
  Timer.mark(markName)
  local toast = {
    id = self.nextId,
    kind = kind,
    text = text,
    markName = markName,
    duration = opts.duration or self.defaultDuration,
    fadeDuration = opts.fadeDuration or self.defaultFadeDuration,
    alpha = 1,
    w = self:_makeWidth(kind, text),
    h = opts.height or TOAST_H,
    x = 0,
    y = 0,
    targetX = 0,
    targetY = 0,
    state = "visible",
    hovered = false,
    pressed = false,
    closeHovered = false,
    closePressed = false,
    action = opts.action,
  }

  table.insert(self.toasts, 1, toast)
  self.layoutDirty = true
  self:_layoutToasts()
  return toast
end

function ToastController:info(text, opts)
  return self:show("info", text, opts)
end

function ToastController:warning(text, opts)
  return self:show("warning", text, opts)
end

function ToastController:error(text, opts)
  return self:show("error", text, opts)
end

function ToastController:update(dt)
  for i = #self.toasts, 1, -1 do
    local toast = self.toasts[i]
    local age = toast.markName and Timer.elapsed(toast.markName) or nil
    age = tonumber(age) or 0
    local duration = tonumber(toast.duration) or self.defaultDuration
    local fadeDuration = tonumber(toast.fadeDuration) or self.defaultFadeDuration

    if fadeDuration <= 0 then
      toast.alpha = 1
      if age >= duration then
        self:_dismissToast(toast)
      end
    elseif age >= duration then
      local fadeElapsed = age - duration
      if fadeElapsed >= fadeDuration then
        self:_dismissToast(toast)
      else
        local t = math.max(0, math.min(1, fadeElapsed / fadeDuration))
        toast.alpha = 1 - t
      end
    else
      toast.alpha = 1
    end
  end
end

function ToastController:_toastAlpha(toast)
  local a = tonumber(toast and toast.alpha)
  if not a then
    return 1
  end
  if a < 0 then
    return 0
  end
  if a > 1 then
    return 1
  end
  return a
end

function ToastController:mousemoved(x, y)
  local handled = false

  for i = 1, #self.toasts do
    local toast = self.toasts[i]
    toast.hovered = false
    toast.closeHovered = false
    if pointInRect(x, y, toast.x or toast.targetX or 0, toast.y or toast.targetY or 0, toast.w, toast.h) then
      handled = true
      toast.hovered = true
      local cx, cy, cw, ch = self:_closeRect(toast)
      if pointInRect(x, y, cx, cy, cw, ch) then
        toast.closeHovered = true
      end
    end
  end

  return handled
end

function ToastController:mousepressed(x, y, button)
  if button ~= 1 then return false end

  local toast = self:_toastAt(x, y)
  if not toast then return false end

  self.pressedToast = toast
  toast.pressed = true
  local cx, cy, cw, ch = self:_closeRect(toast)
  toast.closePressed = pointInRect(x, y, cx, cy, cw, ch)
  return true
end

function ToastController:mousereleased(x, y, button)
  if button ~= 1 then return false end

  local toast = self.pressedToast
  self.pressedToast = nil
  if not toast then return false end

  local insideToast = pointInRect(x, y, toast.x or toast.targetX or 0, toast.y or toast.targetY or 0, toast.w, toast.h)
  toast.pressed = false
  toast.closePressed = false

  if insideToast then
    self:_dismissToast(toast)
    return true
  end

  return false
end

function ToastController:draw(canvasW, canvasH)
  if (canvasW and canvasW ~= self.canvasW) or (canvasH and canvasH ~= self.canvasH) then
    self:updateLayout(canvasW, canvasH)
  end

  local font = currentFont()
  local icon = images and images.icons and images.icons.icon_x or nil
  local iconW, iconH = closeIconSize()

  for i = #self.toasts, 1, -1 do
    local toast = self.toasts[i]
    local style = toastStyle(toast.kind)
    local alpha = self:_toastAlpha(toast)
    local x = math.floor(toast.x or toast.targetX or 0)
    local y = math.floor(toast.y or toast.targetY or 0)

    love.graphics.setColor(style.bg[1], style.bg[2], style.bg[3], alpha)
    love.graphics.rectangle("fill", x, y, toast.w, toast.h)

    if font then
      local textX = x + TOAST_PAD_X
      local textY = y + math.floor((toast.h - font:getHeight()) * 0.5)
      local closeX = x + toast.w - CLOSE_PAD_RIGHT - iconW
      local messageMaxW = closeX - TOAST_PAD_X - textX
      local message = truncateToWidth(toast.text, messageMaxW)

      Text.print(message, textX, textY, {
        color = { style.fg[1], style.fg[2], style.fg[3], alpha },
      })
    end

    local closeX, closeY = self:_closeRect(toast)
    love.graphics.setColor(style.fg[1], style.fg[2], style.fg[3], alpha)
    if icon then
      Draw.drawIcon(icon, closeX, closeY)
    elseif font then
      Text.print("x", closeX, closeY - 1, {
        color = { style.fg[1], style.fg[2], style.fg[3], alpha },
      })
    end
  end

  love.graphics.setColor(colors.white)
end

return ToastController
