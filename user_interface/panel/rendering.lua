local colors = require("app_colors")

local function chromeInkForModalButton(b)
  if not b then
    return colors:chromeTextIconsColorNonFocused()
  end
  local canReact = b.enabled ~= false
  if canReact and (b.hovered or b.pressed or b.focused) then
    return colors:chromeTextIconsColorFocused()
  end
  return colors:chromeTextIconsColorNonFocused()
end

local function drawPanelTitle(panel, utils)
  if not (panel and panel.title and panel.title ~= "") then
    return
  end

  local titleRowH = (panel.titleH > 0 and panel.titleH or panel.cellH)
  local titleBgX = panel.x + panel.padding
  local titleBgY = panel.y + panel.padding
  local titleBgW = math.max(0, panel.w - (panel.padding * 2))
  local titleBgH = math.max(0, titleRowH)
  local titleBg = panel.titleBgColor or colors:focusedChromeColor()
  local alpha = (type(titleBg) == "table" and type(titleBg[4]) == "number") and titleBg[4] or 1
  local radius = 2

  local fallbackBg = colors:focusedChromeColor()
  love.graphics.setColor(titleBg[1] or fallbackBg[1], titleBg[2] or fallbackBg[2], titleBg[3] or fallbackBg[3], alpha)
  love.graphics.rectangle("fill", titleBgX, titleBgY, titleBgW, titleBgH, radius)

  local font = love.graphics.getFont()
  local titleW = font and font:getWidth(panel.title) or 0
  local titleX = titleBgX + math.floor((titleBgW - titleW) * 0.5)
  local titleOnBlue = panel._modalChromeOverBlue == true
  local titleTextColor = titleOnBlue and colors:chromeTextIconsColorFocused()
    or (utils.colors.textPrimary or utils.colors.white)
  love.graphics.setColor(titleTextColor[1], titleTextColor[2], titleTextColor[3], titleTextColor[4] or 1)
  local titleY = titleBgY + math.floor((titleBgH - (font and font:getHeight() or 0)) * 0.5)
  utils.Text.print(
    panel.title,
    titleX,
    titleY,
    {
      shadowColor = utils.colors.transparent,
      color = titleTextColor,
      literalColor = titleOnBlue,
    }
  )
end

--- Tabbed modal (settings): paint one continuous "normal" chrome (focused fill) for content + footer,
--- plus active tab row segment and row-gap under it. Outer panel + title use darker chrome (panel.bgColor).
local function rectBandForRows(panel, rowFirst, rowLast)
  local l, r = math.huge, -math.huge
  local topY, botY = math.huge, -math.huge
  for _, cell in ipairs(panel:_iterCells()) do
    if cell.row >= rowFirst and cell.row <= rowLast then
      l = math.min(l, cell.x)
      r = math.max(r, cell.x + cell.w)
      topY = math.min(topY, cell.y)
      botY = math.max(botY, cell.y + cell.h)
    end
  end
  if l == math.huge then
    return nil
  end
  return l, r, topY, botY
end

local function findTabBarCell(panel, tabBar, tabRow)
  for _, cell in ipairs(panel:_iterCells()) do
    if cell.row == tabRow and cell.component == tabBar then
      return cell
    end
  end
  return nil
end

local function drawTabbedModalNormalSurface(panel)
  if panel._tabbedModalChrome ~= true then
    return
  end
  local tabBar = panel._tabbedModalTabBar
  local content0 = panel._tabbedModalContentStartRow
  local footerR = panel._tabbedModalFooterRow
  local tabRow = panel._tabbedModalTabRow
  if not (tabBar and content0 and footerR and tabRow and type(tabBar.getActiveSegmentBounds) == "function") then
    return
  end
  local l, r, topY, botY = rectBandForRows(panel, content0, footerR)
  if not l then
    return
  end
  -- Cells sit inside `padding`, but Settings should read as one full-width chrome block:
  -- extend the lighter surface to the panel's outer bounds (L/R/B) so no `bgColor`
  -- gutter remains between the body and the modal frame.
  local innerL = panel.x
  local innerR = panel.x + panel.w
  local innerB = panel.y + panel.h
  if innerL < innerR and innerB > topY then
    l = math.min(l, innerL)
    r = math.max(r, innerR)
    botY = math.max(botY, innerB)
  end
  local fc = colors:focusedChromeColor()
  local nr, ng, nb = fc[1], fc[2], fc[3]
  love.graphics.setColor(nr, ng, nb, 1)
  local w = r - l
  local totalH = botY - topY
  local rx, ry = 2, 2
  if w > 0 and totalH > 0 then
    if totalH < ry * 2 then
      love.graphics.rectangle("fill", l, topY, w, totalH, rx, ry)
    else
      -- Two-part fill: upper half sharp, lower half rounded (2px) so the modal reads with
      -- rounded bottom corners only on the outer chrome band.
      local h1 = math.floor(totalH / 2)
      local h2 = totalH - h1
      love.graphics.rectangle("fill", l, topY, w, h1)
      love.graphics.rectangle("fill", l, topY + h1, w, h2, rx, ry)
    end
  end

  local tabCell = findTabBarCell(panel, tabBar, tabRow)
  if not tabCell then
    love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 1)
    return
  end
  local sx, sy, sw, sh = tabBar:getActiveSegmentBounds()
  if not sw or sw <= 0 then
    love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 1)
    return
  end
  love.graphics.setColor(nr, ng, nb, 1)
  love.graphics.rectangle("fill", sx, tabCell.y, sw, tabCell.h)
  local gapY = tabCell.y + tabCell.h
  local gapH = topY - gapY
  -- Fill the full inner width (not only under the active tab label) so row-spacing
  -- between the tab strip and the body does not leave darker gutters on the sides.
  if gapH > 0 and innerL < innerR then
    love.graphics.rectangle("fill", innerL, gapY, innerR - innerL, gapH)
  end
  love.graphics.setColor(colors.white[1], colors.white[2], colors.white[3], 1)
end

--- One hover/focus underlay spanning all cells in a row that share `menuItem` (split icon + text).
--- Matches Button's hover fill: semi-transparent black, 2px corner radius.
local function drawUnifiedSplitMenuRowHovers(panel)
  local byRow = {}
  for _, cell in ipairs(panel:_iterCells()) do
    local b = cell.button
    if b and b.skipHoverFocusUnderlay and cell.menuItem then
      local row = cell.row
      byRow[row] = byRow[row] or {}
      byRow[row][#byRow[row] + 1] = cell
    end
  end
  for _, cells in pairs(byRow) do
    if #cells >= 2 then
      local hot = false
      local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
      for _, cell in ipairs(cells) do
        local bb = cell.button
        if bb.enabled ~= false and (bb.hovered or bb.pressed or bb.focused) then
          hot = true
        end
        l = math.min(l, cell.x)
        t = math.min(t, cell.y)
        r = math.max(r, cell.x + cell.w)
        b = math.max(b, cell.y + cell.h)
      end
      local w, h = r - l, b - t
      if hot and w > 0 and h > 0 then
        love.graphics.setColor(0, 0, 0, 0.10)
        love.graphics.rectangle("fill", l, t, w, h, 2, 2)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function install(Panel, utils)
  function Panel:draw()
    if not self.visible then return end

    local bg = self.bgColor
    local bgRadius = 2
    local bgAlpha = (type(bg) == "table" and type(bg[4]) == "number") and bg[4] or 1
    if bgAlpha > 0 then
      love.graphics.setColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, bgAlpha)
      love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, bgRadius)
    end

    drawPanelTitle(self, utils)

    drawTabbedModalNormalSurface(self)

    drawUnifiedSplitMenuRowHovers(self)

    if self.debugShowCells then
      local debugColor = self.debugCellColor or utils.colors.gray10
      local alpha = self.debugCellAlpha or 1
      local titleRowH = (self.title and self.title ~= "") and (self.titleH > 0 and self.titleH or self.cellH) or 0
      local titleSpacing = (titleRowH > 0 and self.rows > 0) and self.spacingY or 0
      local gridStartY = self.y + self.padding + titleRowH + titleSpacing

      love.graphics.setColor(debugColor[1], debugColor[2], debugColor[3], alpha)
      for row = 1, self.rows do
        local cellY = gridStartY + (row - 1) * (self.cellH + self.spacingY)
        for col = 1, self.cols do
          local cellX = self.x + self.padding + (col - 1) * (self.cellW + self.spacingX)
          love.graphics.rectangle("fill", cellX, cellY, self.cellW, self.cellH)
        end
      end
    end

    local chromeWhite = self._modalChromeOverBlue == true
    for _, cell in ipairs(self:_iterCells()) do
      if cell.button then
        if chromeWhite then
          local b = cell.button
          local oc, oir = b.contentColor, b.iconRespectTheme
          local prevLit = b.literalContentColor
          b.contentColor = chromeInkForModalButton(b)
          b.iconRespectTheme = false
          b.literalContentColor = true
          b:draw()
          b.contentColor, b.iconRespectTheme = oc, oir
          b.literalContentColor = prevLit
        else
          cell.button:draw()
        end
      elseif cell.component and type(cell.component.draw) == "function" then
        local c = cell.component
        local isButton = utils.Button and getmetatable(c) == utils.Button
        if chromeWhite and isButton then
          local oc, oir, olit = c.contentColor, c.iconRespectTheme, c.literalContentColor
          c.contentColor = chromeInkForModalButton(c)
          c.iconRespectTheme = false
          c.literalContentColor = true
          c:draw()
          c.contentColor, c.iconRespectTheme, c.literalContentColor = oc, oir, olit
        else
          c:draw()
        end
      elseif cell.kind == "label" then
        local textColor = cell.textColor
          or (chromeWhite and colors:chromeTextIconsColorNonFocused())
          or utils.colors.textPrimary
          or utils.colors.white
        love.graphics.setColor(textColor[1], textColor[2], textColor[3], 1)
        local font = utils.getFont()
        local labelMarginX = math.floor(cell.h / 2)
        local textX = cell.x + labelMarginX
        local textY = cell.y + math.floor((cell.h - (font and font:getHeight() or 0)) * 0.5)
        if cell.align == "center" then
          local textW = font and font:getWidth(cell.text or "") or 0
          textX = math.floor(cell.x + (cell.w - textW) * 0.5)
        elseif cell.align == "right" then
          local textW = font and font:getWidth(cell.text or "") or 0
          textX = math.floor((cell.x + cell.w) - labelMarginX - textW)
        end
        utils.Text.print(cell.text or "", textX, textY, {
          shadowColor = utils.colors.transparent,
          color = textColor,
          literalColor = chromeWhite,
        })
      end
    end

    love.graphics.setColor(utils.colors.white[1], utils.colors.white[2], utils.colors.white[3], 1)
  end
end

return {
  install = install,
}
