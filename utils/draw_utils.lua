-- draw_utils.lua
-- Helpers for drawing with repeating textures (animated by default).

local Timer = require("utils.timer_utils")

local M = {}

-- Cache scroll offsets per image (weak table so images can be GC'd).
local _scrollState = setmetatable({}, { __mode = "k" })

-- Shader that masks out the interior of a rectangle, leaving only a border.
local borderShader = love.graphics.newShader([[
extern vec4 u_rect;     // x, y, w, h in screen pixels
extern number u_border; // border thickness in pixels

vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord)
{
    vec2 rel = screenCoord - u_rect.xy;
    float w = u_rect.z;
    float h = u_rect.w;
    float b = max(u_border, 1.0);

    if (rel.x < 0.0 || rel.y < 0.0 || rel.x > w || rel.y > h) {
        return Texel(tex, texCoord) * color;
    }

    bool onBorder = (rel.x < b) || (rel.y < b) || (rel.x > w - b) || (rel.y > h - b);
    if (!onBorder) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }

    return Texel(tex, texCoord) * color;
}
]])

-- Shader to post-process cursors (pulsing blacks, paint-color whites)
local cursorShader = love.graphics.newShader([[
extern vec3 u_paintColor;
extern number u_time;
extern bool u_applyPaint;

vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord)
{
    vec4 px = Texel(tex, texCoord);
    // Transparent: leave as-is (multiplied by incoming color)
    if (px.a <= 0.0) {
        return px * color;
    }

    float maxc = max(px.r, max(px.g, px.b));
    float minc = min(px.r, min(px.g, px.b));
    bool isBlack = maxc < 0.05;
    bool isWhite = (minc > 0.9); // near-white tolerance

    if (isBlack) {
        float pulse = 0.5 + 0.5 * sin(u_time * 8.0); // even faster pulse
        return vec4(vec3(pulse), px.a) * color;
    }

    if (u_applyPaint && isWhite) {
        // Preserve alpha from texture; paint color drives RGB
        return vec4(u_paintColor, px.a) * vec4(1.0, 1.0, 1.0, 1.0);
    }

    return px * color;
}
]])

function M.getCursorShader()
  return cursorShader
end

-- Internal: compute animated offsets for an image.
local function getScrollState(img, tileSize, stepPx, intervalSeconds)
  local state = _scrollState[img]
  if not state then
    state = { ox = 0, oy = 0, timerKey = "draw_utils_scroll_" .. tostring(img) }
    _scrollState[img] = state
    Timer.mark(state.timerKey)
  end

  local interval = intervalSeconds or 0.1
  local elapsed = Timer.elapsed(state.timerKey)
  if not elapsed or elapsed >= interval then
    local step = stepPx or 1
    state.ox = (state.ox + step) % tileSize
    state.oy = (state.oy + step) % tileSize
    Timer.mark(state.timerKey)
  end

  return state.ox, state.oy
end

-- Draw an animated, repeating image over a rectangle.
-- data (optional) controls behavior:
--   data.borderPx      -> number (default 1) draws hollow border via shader; set to 0 to disable shader
--   data.stepPx        -> number (default 1) scroll step
--   data.intervalSeconds -> number (default 0.1) scroll interval
--   data.useShader     -> boolean (default true) apply hollow shader when borderPx > 0
function M.drawRepeatingImageAnimated(img, x, y, w, h, data)
  if not (img and w and h) then return end

  img:setWrap("repeat", "repeat")

  local size = img:getWidth()
  if size == 0 then return end

  local stepPx = data and data.stepPx or nil
  local intervalSeconds = data and data.intervalSeconds or nil
  local borderPx = data and data.borderPx
  if borderPx == nil then borderPx = 1 end
  local useShader = (data and data.useShader) ~= false and borderPx > 0

  local ox, oy = getScrollState(img, size, stepPx, intervalSeconds)
  local quad = love.graphics.newQuad(ox, oy, w, h, size, size)

  if useShader and borderShader then
    love.graphics.push("all")
    -- u_rect must match fragment pixel coords; love.graphics.transformPoint maps from
    -- current drawing space through the active transform stack (LÖVE 11+).
    local x0 = x or 0
    local y0 = y or 0
    local ax, ay = love.graphics.transformPoint(x0, y0)
    local bx, by = love.graphics.transformPoint(x0 + w, y0 + h)
    borderShader:send("u_rect", { math.min(ax, bx), math.min(ay, by), math.abs(bx - ax), math.abs(by - ay) })
    borderShader:send("u_border", borderPx)
    love.graphics.setShader(borderShader)
    love.graphics.draw(img, quad, x or 0, y or 0)
    love.graphics.pop()
  else
    love.graphics.draw(img, quad, x or 0, y or 0)
  end
end

return M
