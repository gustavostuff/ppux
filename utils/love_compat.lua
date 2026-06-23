-- love_compat.lua
-- Nil-safe access to common LÖVE APIs for modules that may run outside a full LÖVE frame.

local M = {}

local function has(namespace, fn)
  return love
    and love[namespace]
    and type(love[namespace][fn]) == "function"
end

--- True when the global `love` table exists.
function M.hasLove()
  return love ~= nil
end

--- True when `love[namespace][fn]` is a callable function.
function M.hasApi(namespace, fn)
  return has(namespace, fn)
end

-- ---------------------------------------------------------------------------
-- Timer
-- ---------------------------------------------------------------------------

--- Monotonic seconds since the LÖVE timer started; falls back to `os.clock()` when unavailable.
function M.getTime()
  if has("timer", "getTime") then
    return love.timer.getTime()
  end
  return os.clock()
end

--- Like `getTime()` but uses `fallback` when the LOVE timer is unavailable.
function M.getTimeOr(fallback)
  if has("timer", "getTime") then
    return love.timer.getTime()
  end
  return fallback
end

--- Best-effort frame yield; no-op when `love.timer.sleep` is unavailable.
function M.sleep(seconds)
  if has("timer", "sleep") then
    love.timer.sleep(tonumber(seconds) or 0)
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Keyboard
-- ---------------------------------------------------------------------------

--- True when `key` is held; false when LOVE keyboard is unavailable.
function M.isKeyDown(key)
  if not has("keyboard", "isDown") then
    return false
  end
  return love.keyboard.isDown(key) == true
end

--- True when either left or right Ctrl is held.
function M.isCtrlDown()
  return M.isKeyDown("lctrl") or M.isKeyDown("rctrl")
end

--- True when either left or right Shift is held.
function M.isShiftDown()
  return M.isKeyDown("lshift") or M.isKeyDown("rshift")
end

--- True when either left or right Alt is held.
function M.isAltDown()
  return M.isKeyDown("lalt") or M.isKeyDown("ralt")
end

--- True when any of the given keys is held.
function M.isAnyKeyDown(...)
  for i = 1, select("#", ...) do
    if M.isKeyDown(select(i, ...)) then
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Mouse
-- ---------------------------------------------------------------------------

--- Current mouse position in window coordinates, or `nil, nil` when unavailable.
function M.getMousePosition()
  if not has("mouse", "getPosition") then
    return nil, nil
  end
  return love.mouse.getPosition()
end

--- True when mouse button `button` (default 1) is held.
function M.isMouseDown(button)
  if not has("mouse", "isDown") then
    return false
  end
  return love.mouse.isDown(tonumber(button) or 1) == true
end

-- ---------------------------------------------------------------------------
-- System
-- ---------------------------------------------------------------------------

--- OS clipboard text, or `nil` when unavailable.
function M.getClipboardText()
  if not has("system", "getClipboardText") then
    return nil
  end
  return love.system.getClipboardText()
end

--- Copy `text` to the OS clipboard; returns whether the call was attempted successfully.
function M.setClipboardText(text)
  if type(text) ~= "string" or not has("system", "setClipboardText") then
    return false
  end
  love.system.setClipboardText(text)
  return true
end

--- LOVE OS identifier (e.g. "Linux", "OS X", "Windows"), or `nil`.
function M.getOS()
  if not has("system", "getOS") then
    return nil
  end
  return love.system.getOS()
end

--- Open a URL via the OS handler; returns whether the call was attempted.
function M.openURL(url)
  if type(url) ~= "string" or url == "" or not has("system", "openURL") then
    return false
  end
  return love.system.openURL(url) ~= false
end

-- ---------------------------------------------------------------------------
-- Graphics / window
-- ---------------------------------------------------------------------------

--- Window drawable width, or `fallback` (default 0).
function M.getWindowWidth(fallback)
  if has("graphics", "getWidth") then
    return love.graphics.getWidth()
  end
  return tonumber(fallback) or 0
end

--- Window drawable height, or `fallback` (default 0).
function M.getWindowHeight(fallback)
  if has("graphics", "getHeight") then
    return love.graphics.getHeight()
  end
  return tonumber(fallback) or 0
end

--- Window drawable size as `w, h` with optional fallbacks (default 0, 0).
function M.getWindowSize(fallbackW, fallbackH)
  return M.getWindowWidth(fallbackW), M.getWindowHeight(fallbackH)
end

--- Current window mode as `w, h, flags`, or `nil, nil, nil` when unavailable.
function M.getWindowMode()
  if not has("window", "getMode") then
    return nil, nil, nil
  end
  return love.window.getMode()
end

return M
