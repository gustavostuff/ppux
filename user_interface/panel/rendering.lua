local colors = require("app_colors")

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
  local titleTextColor = titleOnBlue and colors:chromeTextIconsColor()
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
          b.contentColor = colors:chromeTextIconsColor()
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
          c.contentColor = colors:chromeTextIconsColor()
          c.iconRespectTheme = false
          c.literalContentColor = true
          c:draw()
          c.contentColor, c.iconRespectTheme, c.literalContentColor = oc, oir, olit
        else
          c:draw()
        end
      elseif cell.kind == "label" then
        local textColor = cell.textColor
          or (chromeWhite and colors:chromeTextIconsColor())
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
