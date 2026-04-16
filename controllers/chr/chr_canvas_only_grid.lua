-- Grid overlays for CHR canvas-only mode (same visuals as windowed CHR: chess + lines).

local colors = require("app_colors")
local WindowCaps = require("controllers.window.window_capabilities")
local CanvasSpace = require("utils.canvas_space")

local M = {}

local function getActiveGlobalPaletteBgColor(wm)
  if not (wm and wm.getWindows) then
    return nil
  end
  local paletteWin = nil
  local fallback = nil
  for _, win in ipairs(wm:getWindows() or {}) do
    if WindowCaps.isGlobalPaletteWindow(win) and not win._closed and not win._minimized and win._groupHidden ~= true then
      if not fallback then
        fallback = win
      end
      if win.activePalette then
        paletteWin = win
        break
      end
    end
  end
  paletteWin = paletteWin or fallback
  if paletteWin and paletteWin.getFirstColor then
    return paletteWin:getFirstColor()
  end
  return nil
end

local function getRomPaletteBgColorForWindow(win, wm)
  local layers = win and win.layers
  if not layers then
    return nil
  end
  for _, L in ipairs(layers) do
    local pd = L.paletteData
    if pd and pd.winId then
      local paletteWin = wm and wm.findWindowById and wm:findWindowById(pd.winId)
      if paletteWin and paletteWin.getFirstColor then
        return paletteWin:getFirstColor()
      end
      break
    end
  end
  return nil
end

local function contentBgColor(app, win)
  local wm = app and app.wm
  return getRomPaletteBgColorForWindow(win, wm) or getActiveGlobalPaletteBgColor(wm) or colors.black
end

function M.fillBankViewportBackground(app, win, scrollYNes, scale, viewWNes, viewHNes, canvasW, canvasH)
  if not (app and win and canvasW and canvasH) then
    return
  end
  local bgColor = contentBgColor(app, win)
  love.graphics.push("all")
  CanvasSpace.setScissorFromContentRect(0, 0, canvasW, canvasH)
  love.graphics.scale(scale, scale)
  love.graphics.translate(0, -scrollYNes)
  love.graphics.setColor(bgColor)
  love.graphics.rectangle("fill", 0, 0, viewWNes, viewHNes)
  love.graphics.pop()
  love.graphics.setColor(colors.white)
end

function M.drawChessBehindBank(app, win, scrollYNes, scale, viewWNes, viewHNes, canvasW, canvasH)
  if not (app and win and canvasW and canvasH) then
    return
  end
  local bgColor = contentBgColor(app, win)
  local grid = (win.getDisplayGridMetrics and win:getDisplayGridMetrics()) or {
    cellW = win.cellW or 8,
    cellH = win.cellH or 8,
    rowStride = 1,
  }
  local rowStride = grid.rowStride or 1
  local drawH = (tonumber(grid.cellH) or 8) + 1
  local cell = win.cellW or 8

  love.graphics.push("all")
  CanvasSpace.setScissorFromContentRect(0, 0, canvasW, canvasH)
  love.graphics.translate(0, 0)
  love.graphics.scale(scale, scale)
  love.graphics.translate(0, -scrollYNes)

  love.graphics.setColor(bgColor)
  love.graphics.rectangle("fill", 0, 0, viewWNes, viewHNes)

  local vR0 = math.floor(scrollYNes / cell)
  local vR1 = math.floor((scrollYNes + viewHNes - 1) / cell)
  local spill = 1
  local r0 = math.max(0, vR0 - spill)
  local r1 = math.min((win.rows or 32) - 1, vR1 + spill)
  local c0 = 0
  local c1 = math.min((win.cols or 16) - 1, math.ceil(viewWNes / cell) - 1 + spill)

  for row = r0, r1 do
    if not (rowStride > 1 and (row % rowStride) ~= 0) then
      for col = c0, c1 do
        local x, y = col * cell, row * cell
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", x, y, cell, drawH)
        if ((math.floor(row / rowStride)) + col) % 2 == 0 then
          local c = colors.white
          love.graphics.setColor(c[1], c[2], c[3], 0.1)
          love.graphics.rectangle("fill", x, y, cell, drawH)
        end
      end
    end
  end

  love.graphics.pop()
  love.graphics.setColor(colors.white)
end

local linesGridShader = love.graphics.newShader([[
extern vec2 u_origin;
extern vec2 u_step;
extern number u_thickness;

vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord)
{
    float stepx = max(u_step.x, 1.0);
    float stepy = max(u_step.y, 1.0);
    float t = max(u_thickness, 1.0);
    vec2 rel = screenCoord - u_origin;
    float mx = mod(rel.x, stepx);
    float my = mod(rel.y, stepy);

    bool onLine = (mx <= t) || (stepx - mx <= t) || (my <= t) || (stepy - my <= t);
    if (!onLine) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    return Texel(tex, texCoord) * color;
}
]])

function M.drawLinesOverlay(_app, win, scrollYNes, scale, canvasW, canvasH)
  if not (win and canvasW and canvasH) or win._collapsed then
    return
  end
  local grid = (win.getDisplayGridMetrics and win:getDisplayGridMetrics()) or {
    baseCellW = win.cellW or 8,
    baseCellH = win.cellH or 8,
    cellW = win.cellW or 8,
    cellH = win.cellH or 8,
  }
  local s = tonumber(scale) or 1
  local stepX = grid.cellW * s
  local stepY = grid.cellH * s
  if stepX <= 0 or stepY <= 0 then
    return
  end

  local x, y, w, h = 0, 0, canvasW, canvasH
  local thickness = 1
  local scrollOffsetX = (((win.scrollCol or 0) * (grid.baseCellW or grid.cellW)) * s) % stepX
  local scrollOffsetY = ((scrollYNes * s) % stepY)

  love.graphics.push("all")
  love.graphics.setShader(linesGridShader)
  local ox, oy = love.graphics.transformPoint(x - scrollOffsetX, y - scrollOffsetY)
  linesGridShader:send("u_origin", { ox, oy })
  linesGridShader:send("u_step", { stepX, stepY })
  linesGridShader:send("u_thickness", thickness)
  local c = colors.gray50
  love.graphics.setColor(c[1], c[2], c[3], 0.5)
  CanvasSpace.setScissorFromContentRect(x, y, w, h)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.pop()
  love.graphics.setColor(colors.white)
end

return M
