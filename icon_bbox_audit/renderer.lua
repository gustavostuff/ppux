local Renderer = {}

local function elideText(font, text, maxW)
  if not font then return tostring(text or "") end
  local out = tostring(text or "")
  if font:getWidth(out) <= maxW then
    return out
  end
  local suffix = ".."
  while #out > 0 and (font:getWidth(out .. suffix) > maxW) do
    out = out:sub(1, -2)
  end
  return out .. suffix
end

local function drawRow(state, cfg, entry, x, y, itemW)
  local image = entry.image
  local iconRight = x + cfg.PREVIEW_MARGIN
  if image then
    local iw = image:getWidth()
    local ih = image:getHeight()
    local drawX = x + cfg.PREVIEW_MARGIN
    local drawY = y + math.floor((cfg.CARD_H - ih) * 0.5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, drawX, drawY)
    iconRight = drawX + iw
  end

  if state.uiFont then
    love.graphics.setFont(state.uiFont)
  end
  local textX = iconRight + 6
  local textW = math.max(1, (x + itemW - cfg.UI_PAD) - textX)
  local fontH = (state.uiFont and state.uiFont:getHeight()) or 8
  local lineY = y + math.floor((cfg.CARD_H - fontH) * 0.5)
  local bw = entry.bounds.w
  local bh = entry.bounds.h
  love.graphics.setColor(1, 1, 1, 1)
  local rowText = string.format("%s  |  %dx%d", tostring(entry.rel or ""), bw, bh)
  love.graphics.print(elideText(state.uiFont, rowText, textW), textX, lineY)

  love.graphics.setColor(0.20, 0.20, 0.20, 1)
  love.graphics.line(x, y + cfg.CARD_H, x + itemW, y + cfg.CARD_H)
end

function Renderer.draw(state, cfg, clampScrollFn)
  love.graphics.setCanvas(state.canvas)
  love.graphics.clear(0.08, 0.08, 0.08, 1)
  if state.uiFont then
    love.graphics.setFont(state.uiFont)
  end

  local w = cfg.BASE_W
  local h = cfg.BASE_H

  local y = cfg.UI_PAD
  local lineH = (state.uiFont and state.uiFont:getHeight()) or 8
  local lineGap = 1
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("PPUX Icon Bounding Box Audit", cfg.UI_PAD, y)
  y = y + lineH + lineGap
  love.graphics.setColor(0.85, 0.85, 0.85, 1)
  love.graphics.print(
    string.format(
      "Scanned: %d | Oversized > %dx%d: %d | Errors: %d",
      #state.scanned,
      cfg.TARGET_MAX_W,
      cfg.TARGET_MAX_H,
      #state.oversized,
      #state.scanErrors
    ),
    cfg.UI_PAD,
    y
  )
  y = y + lineH + lineGap

  local gridTop = y + 2
  local listW = w - (cfg.UI_PAD * 2)
  local rows = #state.oversized
  local contentH = math.max(0, rows * (cfg.CARD_H + cfg.GRID_GAP) - cfg.GRID_GAP)
  local viewportH = math.max(0, h - gridTop - cfg.UI_PAD)
  state.maxScroll = math.max(0, contentH - viewportH)
  if clampScrollFn then
    clampScrollFn(state)
  end

  if #state.oversized == 0 then
    love.graphics.setColor(0.7, 1.0, 0.7, 1)
    love.graphics.print("No oversized icons found.", cfg.UI_PAD, gridTop)
  else
    local startX = cfg.UI_PAD
    for i, entry in ipairs(state.oversized) do
      local row = i - 1
      local x = startX
      local cardY = gridTop + row * (cfg.CARD_H + cfg.GRID_GAP) + state.scrollY
      if (cardY + cfg.CARD_H) >= gridTop and cardY <= h then
        drawRow(state, cfg, entry, x, cardY, listW)
      end
    end
  end

  love.graphics.setCanvas()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(state.canvas, 0, 0, 0, cfg.OUTPUT_SCALE, cfg.OUTPUT_SCALE)
end

return Renderer
