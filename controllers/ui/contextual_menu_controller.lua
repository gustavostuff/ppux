local Panel = require("user_interface.panel")
local UiScale = require("user_interface.ui_scale")

local ContextualMenuController = {}
ContextualMenuController.__index = ContextualMenuController
ContextualMenuController.TEXT_PADDING_X = 4
-- Menu item text/icons: always full opacity (idle and hover).
ContextualMenuController.NORMAL_CONTENT_ALPHA = 1.0
ContextualMenuController.CHILD_HOVER_GRACE_SECONDS = 0.18
-- Space between a menu and its parent (submenus, taskbar strip) and minimum inset from the
-- clamp bounds edges (app canvas for core_controller menus; taskbar getBounds matches canvas BR).
ContextualMenuController.PARENT_GAP_PX = 2

local function nowSeconds()
  if love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return 0
end

local function clampPosition(menu, x, y)
  local bounds = menu.getBounds and menu.getBounds() or nil
  local maxW = bounds and bounds.w or nil
  local maxH = bounds and bounds.h or nil
  local inset = tonumber(ContextualMenuController.PARENT_GAP_PX) or 2
  local clampedX = math.floor(tonumber(x) or 0)
  local clampedY = math.floor(tonumber(y) or 0)

  if clampedX < inset then clampedX = inset end
  if clampedY < inset then clampedY = inset end

  if maxW and menu.panel then
    local maxX = maxW - inset - menu.panel.w
    if clampedX > maxX then
      clampedX = math.max(inset, maxX)
    end
  end
  if maxH and menu.panel then
    local maxY = maxH - inset - menu.panel.h
    if clampedY > maxY then
      clampedY = math.max(inset, maxY)
    end
  end

  return clampedX, clampedY
end

local function hideChild(menu)
  if menu.childMenu then
    menu.childMenu:hide()
    menu.childMenu = nil
  end
  menu.activeChildItem = nil
  menu.childHoverGraceUntil = nil
  menu.pendingChildRow = nil
end

local function makeDisplayText(item)
  local text = tostring(item and item.text or "")
  if item and item.children then
    return text .. " >"
  end
  return text
end

local function iconWidth(icon)
  if not icon then return 0 end
  if type(icon.getWidth) == "function" then
    return tonumber(icon:getWidth()) or 0
  end
  return tonumber(icon.w) or 0
end

-- Items with enabled == false are omitted when the panel is built (same rule everywhere).
local function countRenderableMenuItems(items)
  local n = 0
  for _, item in ipairs(items or {}) do
    if item and item.enabled ~= false then
      n = n + 1
    end
  end
  return n
end

local function visibleItems(menu)
  local out = {}
  for _, item in ipairs(menu.items or {}) do
    if item and item.enabled ~= false then
      out[#out + 1] = item
    end
  end
  return out
end

local function menuUsesSplitIconCell(menu)
  if not ((menu.splitIconCell == true) and ((tonumber(menu.cols) or 1) > 1)) then
    return false
  end

  for _, item in ipairs(visibleItems(menu)) do
    if item and item.icon then
      return true
    end
  end
  return false
end

local function textWidth(text)
  local font = love.graphics and love.graphics.getFont and love.graphics.getFont() or nil
  if font and font.getWidth then
    return font:getWidth(text or "")
  end
  return #(tostring(text or "")) * 8
end

local function resolveCellWidth(menu)
  local items = visibleItems(menu)
  local splitIconCell = menuUsesSplitIconCell(menu)
  local defaultCell = UiScale.menuCellSize()
  if splitIconCell then
    local cols = math.max(2, math.floor(tonumber(menu.cols) or 8))
    local iconCols = 1
    local textCols = math.max(1, cols - iconCols)
    local baseCell = tonumber(menu.cellW) or tonumber(menu.cellH) or defaultCell
    local leftInset = ContextualMenuController.TEXT_PADDING_X
    local rightInset = ContextualMenuController.TEXT_PADDING_X
    local resolved = baseCell

    for _, item in ipairs(items) do
      local text = makeDisplayText(item)
      local requiredTextWidth = textWidth(text) + leftInset + rightInset
      local requiredTextCellWidth = math.ceil(requiredTextWidth / textCols)
      local iw = iconWidth(item.icon)
      local requiredIconCellWidth = math.max(baseCell, iw)
      resolved = math.max(resolved, requiredTextCellWidth, requiredIconCellWidth)
    end

    return resolved
  end

  local resolved = tonumber(menu.cellW) or tonumber(menu.cellH) or defaultCell
  local leftInset = ContextualMenuController.TEXT_PADDING_X
  local rightInset = leftInset

  for _, item in ipairs(items) do
    local text = makeDisplayText(item)
    local width
    if item.component and item.menuWidthFromComponentOnly then
      width = (type(item.component.getWidth) == "function" and tonumber(item.component:getWidth())) or 0
    else
      width = textWidth(text) + leftInset + rightInset
      local iw = iconWidth(item.icon)
      if iw > 0 then
        width = width + iw + 5
      end
      if item.component and type(item.component.getWidth) == "function" then
        width = math.max(width, tonumber(item.component:getWidth()) or 0)
      end
    end
    resolved = math.max(resolved, math.floor(width + 0.5))
  end

  return resolved
end

local function makeItemAction(menu, item, row)
  return function()
    if item.children then
      menu:_openChildForRow(row)
      return
    end
    if item.callback then
      item.callback()
    elseif item.action then
      item.action()
    end
    if item.keepMenuOpen == true then
      return
    end
    menu:hideRoot()
  end
end

local function rebuildPanel(menu)
  local items = visibleItems(menu)
  local rows = math.max(1, #items)
  local splitIconCell = menuUsesSplitIconCell(menu)
  local cols = splitIconCell and math.max(2, math.floor(tonumber(menu.cols) or 8)) or 1
  local cellW = resolveCellWidth(menu)
  local panel

  if splitIconCell then
    panel = Panel.new({
      cols = cols,
      rows = rows,
      cellW = menu.cellH,
      cellH = menu.cellH,
      padding = menu.padding,
      spacingX = menu.colGap or 0,
      spacingY = menu.rowGap,
      cellPaddingX = menu.cellPaddingX,
      cellPaddingY = menu.cellPaddingY,
      visible = menu.visible,
      bgColor = menu.bgColor,
    })
    panel.cellWidths = {}
    panel.cellWidths[1] = menu.cellH
    for col = 2, cols do
      panel.cellWidths[col] = cellW
    end
  else
    panel = Panel.new({
      cols = cols,
      rows = rows,
      cellW = cellW,
      cellH = menu.cellH,
      padding = menu.padding,
      spacingX = menu.colGap or 0,
      spacingY = menu.rowGap,
      cellPaddingX = menu.cellPaddingX,
      cellPaddingY = menu.cellPaddingY,
      visible = menu.visible,
      bgColor = menu.bgColor,
    })
  end

  local leftInset = ContextualMenuController.TEXT_PADDING_X
  for i, item in ipairs(items) do
    if item.component then
      panel:setCell(1, i, {
        component = item.component,
        enabled = item.enabled ~= false,
        tooltip = item.tooltip,
      })
      local cell = panel:getCell(1, i)
      if cell then
        cell.menuItem = item
      end
    elseif splitIconCell then
      local action = makeItemAction(menu, item, i)
      panel:setCell(1, i, {
        kind = "button",
        icon = item.icon,
        text = nil,
        normalContentAlpha = ContextualMenuController.NORMAL_CONTENT_ALPHA,
        transparent = item.transparent ~= false,
        enabled = item.enabled ~= false,
        tooltip = item.tooltip,
        contentPaddingX = 0,
        action = action,
      })
      panel:setCell(2, i, {
        kind = "button",
        text = makeDisplayText(item),
        colspan = cols - 1,
        normalContentAlpha = ContextualMenuController.NORMAL_CONTENT_ALPHA,
        transparent = item.transparent ~= false,
        enabled = item.enabled ~= false,
        tooltip = item.tooltip,
        textAlign = "left",
        contentPaddingX = leftInset,
        action = action,
      })
      local iconCell = panel:getCell(1, i)
      local textCell = panel:getCell(2, i)
      if iconCell then
        iconCell.menuItem = item
      end
      if textCell then
        textCell.menuItem = item
      end
    else
      local action = makeItemAction(menu, item, i)
      panel:setCell(1, i, {
        kind = "button",
        icon = item.icon,
        text = makeDisplayText(item),
        normalContentAlpha = ContextualMenuController.NORMAL_CONTENT_ALPHA,
        transparent = item.transparent ~= false,
        enabled = item.enabled ~= false,
        tooltip = item.tooltip,
        textAlign = "left",
        contentPaddingX = leftInset,
        alignTextToContentPadding = true,
        action = action,
      })
      local cell = panel:getCell(1, i)
      if cell then
        cell.menuItem = item
      end
    end
  end

  menu.visibleItems = items
  menu.activeSplitIconCell = splitIconCell
  menu.resolvedCellW = cellW
  menu.panel = panel
end

local function resolveChildPosition(parentMenu, anchorCell, childMenu)
  local childPanel = childMenu and childMenu.panel or nil
  if not (anchorCell and childPanel) then
    return 0, 0
  end

  local gap = tonumber(ContextualMenuController.PARENT_GAP_PX) or 2
  local inset = gap
  local bounds = parentMenu.getBounds and parentMenu.getBounds() or nil
  local x = anchorCell.x + anchorCell.w + gap
  local y = anchorCell.y

  if bounds then
    local maxRight = bounds.w - inset
    if (x + childPanel.w) > maxRight then
      x = anchorCell.x - childPanel.w - gap
    end
    local maxBottom = bounds.h - inset
    if (y + childPanel.h) > maxBottom then
      y = anchorCell.y + anchorCell.h - childPanel.h
    end
  end

  return x, y
end

function ContextualMenuController.new(opts)
  opts = opts or {}
  local defaultCell = UiScale.menuCellSize()
  local self = setmetatable({
    visible = false,
    x = 0,
    y = 0,
    items = {},
    panel = nil,
    childMenu = nil,
    activeChildItem = nil,
    parentMenu = opts.parentMenu,
    rootMenu = opts.rootMenu,
    getBounds = opts.getBounds,
    cols = opts.cols or 8,
    cellW = opts.cellW or defaultCell,
    cellH = opts.cellH or defaultCell,
    padding = (opts.padding ~= nil) and opts.padding or 0,
    colGap = (opts.colGap ~= nil) and opts.colGap or 0,
    rowGap = (opts.rowGap ~= nil) and opts.rowGap or 1,
    cellPaddingX = opts.cellPaddingX,
    cellPaddingY = opts.cellPaddingY,
    bgColor = opts.bgColor,
    splitIconCell = (opts.splitIconCell ~= false),
    childHoverGraceSeconds = tonumber(opts.childHoverGraceSeconds) or ContextualMenuController.CHILD_HOVER_GRACE_SECONDS,
    childHoverGraceUntil = nil,
    pendingChildRow = nil,
  }, ContextualMenuController)

  self.rootMenu = self.rootMenu or self
  rebuildPanel(self)
  return self
end

function ContextualMenuController:isVisible()
  return self.visible == true
end

function ContextualMenuController:hide()
  self.visible = false
  hideChild(self)
  if self.panel then
    self.panel:setVisible(false)
  end
end

function ContextualMenuController:hideRoot()
  if self.rootMenu and self.rootMenu ~= self then
    self.rootMenu:hideRoot()
    return
  end
  self:hide()
end

function ContextualMenuController:setItems(items)
  self.items = items or {}
  self.childHoverGraceUntil = nil
  self.pendingChildRow = nil
  hideChild(self)
  if countRenderableMenuItems(self.items) == 0 then
    self:hide()
    return false
  end
  rebuildPanel(self)
  return true
end

function ContextualMenuController:setCellSize(cellW, cellH)
  local nextW = tonumber(cellW) or self.cellW
  local nextH = tonumber(cellH) or self.cellH
  local changed = (self.cellW ~= nextW) or (self.cellH ~= nextH)

  self.cellW = nextW
  self.cellH = nextH

  if self.childMenu and self.childMenu.setCellSize then
    self.childMenu:setCellSize(nextW, nextH)
  end

  if changed then
    self.childHoverGraceUntil = nil
    self.pendingChildRow = nil
    hideChild(self)
    rebuildPanel(self)
  end

  if self.visible and self.panel then
    self.panel:setVisible(true)
    self:setPosition(self.x, self.y)
  end

  return changed
end

function ContextualMenuController:showAt(x, y, items)
  self.childHoverGraceUntil = nil
  self.pendingChildRow = nil
  hideChild(self)
  if items then
    self.items = items
    rebuildPanel(self)
  end
  if countRenderableMenuItems(self.items) == 0 then
    self:hide()
    return false
  end
  self.visible = true
  if self.panel then
    self.panel:setVisible(true)
  end
  self:setPosition(x, y)
  return true
end

function ContextualMenuController:setPosition(x, y)
  self.x, self.y = clampPosition(self, x, y)
  if self.panel then
    self.panel:setPosition(self.x, self.y)
  end
end

function ContextualMenuController:toggleAt(x, y, items)
  if self:isVisible() then
    self:hide()
    return false
  end
  self:showAt(x, y, items)
  return self:isVisible()
end

function ContextualMenuController:_childItemsFor(item)
  if not item then return nil end
  local children = item.children
  if type(children) == "function" then
    children = children(self, item)
  end
  if type(children) ~= "table" or #children == 0 then
    return nil
  end
  return children
end

function ContextualMenuController:_clearChildHoverGrace()
  self.childHoverGraceUntil = nil
  self.pendingChildRow = nil
end

function ContextualMenuController:_beginChildHoverGrace(pendingRow)
  if not self.childMenu then
    self.childHoverGraceUntil = nil
    self.pendingChildRow = nil
    return
  end
  self.pendingChildRow = pendingRow
  if self.childHoverGraceUntil == nil then
    self.childHoverGraceUntil = nowSeconds() + self.childHoverGraceSeconds
  end
end

function ContextualMenuController:_openChildForRow(row)
  if not (self.panel and self:isVisible()) then
    return false
  end

  local anchorCol = (self.activeSplitIconCell == true and self.cols > 1) and 2 or 1
  local cell = self.panel:getCell(anchorCol, row)
  local item = cell and cell.menuItem or nil
  local childItems = self:_childItemsFor(item)
  if not (cell and item and childItems) then
    hideChild(self)
    return false
  end

  if self.childMenu and self.activeChildItem == item then
    self:_clearChildHoverGrace()
    return true
  end

  hideChild(self)

  local childMenu = ContextualMenuController.new({
    parentMenu = self,
    rootMenu = self.rootMenu or self,
    getBounds = self.getBounds,
    cols = self.cols,
    cellW = self.cellW,
    cellH = self.cellH,
    padding = self.padding,
    colGap = self.colGap,
    rowGap = self.rowGap,
    cellPaddingX = self.cellPaddingX,
    cellPaddingY = self.cellPaddingY,
    bgColor = self.bgColor,
    splitIconCell = self.splitIconCell,
  })
  if not childMenu:setItems(childItems) then
    return false
  end
  self.childMenu = childMenu
  self.activeChildItem = item
  self:_clearChildHoverGrace()
  local childX, childY = resolveChildPosition(self, cell, self.childMenu)
  if not self.childMenu:showAt(childX, childY) then
    hideChild(self)
    return false
  end

  return true
end

function ContextualMenuController:contains(px, py)
  if self:isVisible() and self.panel and self.panel:contains(px, py) then
    return true
  end
  if self.childMenu and self.childMenu:contains(px, py) then
    return true
  end
  return false
end

function ContextualMenuController:getButtonAt(px, py)
  if self.childMenu and self.childMenu:contains(px, py) then
    return self.childMenu:getButtonAt(px, py)
  end
  if self.panel and self:isVisible() then
    return self.panel:getButtonAt(px, py)
  end
  return nil
end

function ContextualMenuController:getTooltipAt(px, py)
  if self.childMenu and self.childMenu:contains(px, py) then
    return self.childMenu:getTooltipAt(px, py)
  end
  if self.panel and self:isVisible() then
    return self.panel:getTooltipAt(px, py)
  end
  return nil
end

function ContextualMenuController:hasPressedButton()
  if self.panel and self.panel.pressedButton then
    return true
  end
  if self.childMenu and self.childMenu:hasPressedButton() then
    return true
  end
  return false
end

function ContextualMenuController:mousepressed(x, y, button)
  if not self:isVisible() then
    return false
  end

  if self.childMenu and self.childMenu:contains(x, y) then
    return self.childMenu:mousepressed(x, y, button)
  end

  if self.panel and self.panel:contains(x, y) then
    return self.panel:mousepressed(x, y, button)
  end

  if button == 1 then
    self:hideRoot()
  end
  return false
end

function ContextualMenuController:mousereleased(x, y, button)
  if not self:isVisible() then
    return false
  end

  if self.childMenu and (self.childMenu:contains(x, y) or (self.childMenu.panel and self.childMenu.panel.pressedButton)) then
    return self.childMenu:mousereleased(x, y, button)
  end

  if self.panel and (self.panel:contains(x, y) or self.panel.pressedButton) then
    return self.panel:mousereleased(x, y, button)
  end

  return false
end

function ContextualMenuController:update(now)
  if not self:isVisible() then
    return
  end

  if self.childMenu then
    self.childMenu:update(now)
  end

  local t = tonumber(now) or nowSeconds()
  if self.childMenu and self.childHoverGraceUntil and t >= self.childHoverGraceUntil then
    local pendingRow = self.pendingChildRow
    if pendingRow then
      self:_clearChildHoverGrace()
      if self:_openChildForRow(pendingRow) then
        return
      end
    end
    hideChild(self)
  end
end

function ContextualMenuController:mousemoved(x, y)
  if not self:isVisible() then
    return false
  end

  if self.panel then
    self.panel:mousemoved(x, y)
  end

  local hoveredCell = self.panel and self.panel:getCellAt(x, y) or nil
  local hoveredItem = hoveredCell and hoveredCell.menuItem or nil
  if self.panel then
    for _, cell in ipairs(self.panel:_iterCells()) do
      if cell.button and cell.menuItem then
        cell.button.hovered = (hoveredItem ~= nil and cell.menuItem == hoveredItem)
      end
    end
  end

  local insideChild = self.childMenu and self.childMenu:contains(x, y) or false
  if hoveredItem and hoveredItem.children and hoveredItem == self.activeChildItem then
    self:_clearChildHoverGrace()
  elseif hoveredItem and hoveredItem.children and self.childMenu then
    self:_beginChildHoverGrace(hoveredCell.row)
  elseif hoveredItem and hoveredItem.children then
    self:_clearChildHoverGrace()
    self:_openChildForRow(hoveredCell.row)
  elseif self.childMenu then
    if insideChild then
      self:_clearChildHoverGrace()
    else
      self:_beginChildHoverGrace(nil)
    end
  end

  if self.childMenu then
    self.childMenu:mousemoved(x, y)
  end
  return true
end

function ContextualMenuController:draw()
  if not self:isVisible() then
    return
  end
  if self.panel then
    self.panel:draw()
  end
  if self.childMenu then
    self.childMenu:draw()
  end
end

return ContextualMenuController
