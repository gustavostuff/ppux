-- Dropdown: trigger uses Button; list uses ContextualMenuController.
--
-- Items: each entry is { value = number (required), text = string (required for non-embed; embed may use ""), onPick?, enabled?, embed? }.
--   embed (optional): a UI object with draw / contains / mousepressed / mousereleased / mousemoved / getWidth /
--   getHeight / setPosition (e.g. ColorPickerMatrix). Renders as the menu row body; no automatic close on that row.
-- opts.default (optional): pick initial selection by matching item.value (number) or item.text (string).
--   If default is a string, label match is tried first, then tonumber(default) vs item.value.
-- If opts.default is omitted, the first item is selected.
-- opts.closeMenuOnItemPick (default true): when false, picking a normal text row runs onPick/selection but does not
--   close the menu; call :closeMenu() from onPick or when an embedded widget finishes (e.g. color onChange).
-- opts.menuBgColor: optional panel fill for the dropdown list (default gray20); use {r,g,b,a} with a=0 for transparent.
-- opts.menuOpenAbove (default false): when true, anchor the menu above the trigger when there is room (else below).
-- opts.onBeforeOpenMenu (optional): function(dropdownSelf) invoked just before the list is shown (e.g. close other dropdowns).
local Button = require("user_interface.button")
local ContextualMenuController = require("controllers.ui.contextual_menu_controller")
local UiScale = require("user_interface.ui_scale")

local Dropdown = {}
Dropdown.__index = Dropdown

local function assertItemShape(it, index)
  if type(it) ~= "table" then
    error(string.format("dropdown item %d: expected table", index))
  end
  if type(it.value) ~= "number" then
    error(string.format("dropdown item %d: value must be a number", index))
  end
  local text = it.text
  if text == nil or (not it.embed and tostring(text) == "") then
    error(string.format("dropdown item %d: text label is required", index))
  end
  if it.embed ~= nil and type(it.embed) ~= "table" then
    error(string.format("dropdown item %d: embed must be a table (component)", index))
  end
end

local function itemMatchesDefault(it, defaultSpec)
  if defaultSpec == nil then
    return false
  end
  if type(defaultSpec) == "number" then
    return it.value == defaultSpec
  end
  local ds = tostring(defaultSpec)
  if tostring(it.text) == ds then
    return true
  end
  local tn = tonumber(ds)
  if tn ~= nil and it.value == tn then
    return true
  end
  return false
end

local function resolveInitialIndex(items, defaultSpec)
  if defaultSpec == nil then
    return 1
  end
  for i, it in ipairs(items) do
    if itemMatchesDefault(it, defaultSpec) then
      return i
    end
  end
  error(
    "dropdown `default` does not match any item (use an item's numeric `value` or its `text` label)"
  )
end

local function applySelection(self, entry)
  self.selectedValue = entry.value
  self.selectedText = tostring(entry.text)
  self.trigger.text = self.selectedText
end

function Dropdown.new(opts)
  opts = opts or {}
  local trigger = Button.new({
    text = "",
    w = 0,
    h = 0,
    transparent = true,
    textAlign = "left",
    contentPaddingX = 4,
    tooltip = opts.tooltip or "",
  })

  local cell = tonumber(opts.cellH) or UiScale.menuCellSize()
  local menuCellW = tonumber(opts.menuCellW) or tonumber(opts.cellW) or cell
  local menuCellH = tonumber(opts.menuCellH) or cell
  local menu = ContextualMenuController.new({
    getBounds = opts.getBounds or function()
      local w, h = love.graphics.getDimensions()
      return { w = w, h = h }
    end,
    cols = opts.menuCols or 8,
    cellW = menuCellW,
    cellH = menuCellH,
    padding = (opts.menuPadding ~= nil) and opts.menuPadding or 0,
    colGap = opts.colGap or 0,
    rowGap = opts.rowGap or 1,
    splitIconCell = false,
    bgColor = opts.menuBgColor,
  })

  local self = setmetatable({
    trigger = trigger,
    menu = menu,
    getBounds = opts.getBounds,
    _defaultSpec = opts.default,
    _items = {},
    _menuItems = {},
    _pressed = false,
    selectedValue = nil,
    selectedText = nil,
    enabled = opts.enabled ~= false,
    _closeMenuOnItemPick = opts.closeMenuOnItemPick ~= false,
    _menuOpenAbove = opts.menuOpenAbove == true,
    onBeforeOpenMenu = opts.onBeforeOpenMenu,
    -- Panel treats components with .action as hover-capable for hit testing.
    action = function() end,
  }, Dropdown)

  self:setItems(opts.items or {})
  return self
end

function Dropdown:setGetBounds(fn)
  self.getBounds = fn
  if self.menu then
    self.menu.getBounds = fn
  end
end

--- Current selection (number), or nil before first successful setItems.
function Dropdown:getValue()
  return self.selectedValue
end

--- Current selection label string.
function Dropdown:getLabel()
  return self.selectedText
end

function Dropdown:setItems(items)
  items = items or {}
  for i, it in ipairs(items) do
    assertItemShape(it, i)
  end

  self._items = items
  if #self._items == 0 then
    self._menuItems = {}
    self.selectedValue = nil
    self.selectedText = nil
    self.trigger.text = ""
    return
  end

  local index = resolveInitialIndex(self._items, self._defaultSpec)
  applySelection(self, self._items[index])

  self._menuItems = {}
  for _, entry in ipairs(self._items) do
    local it = entry
    local text = tostring(it.text)
    if it.embed then
      self._menuItems[#self._menuItems + 1] = {
        text = text,
        enabled = it.enabled ~= false,
        component = it.embed,
        menuWidthFromComponentOnly = true,
      }
    else
      local menuItem = {
        text = text,
        enabled = it.enabled ~= false,
        action = function()
          if it.onPick then
            it.onPick(it)
          end
          applySelection(self, it)
        end,
      }
      if not self._closeMenuOnItemPick then
        menuItem.keepMenuOpen = true
      end
      self._menuItems[#self._menuItems + 1] = menuItem
    end
  end
end

function Dropdown:isMenuVisible()
  return self.menu and self.menu:isVisible()
end

function Dropdown:closeMenu()
  if self.menu then
    self.menu:hide()
  end
end

function Dropdown:_anchorMenuPosition()
  local gap = tonumber(ContextualMenuController.PARENT_GAP_PX) or 2
  local bounds = (self.getBounds and self.getBounds()) or { w = 800, h = 600 }
  local inset = gap
  local mx = math.floor(self.trigger.x)
  local belowY = math.floor(self.trigger.y + self.trigger.h + gap)
  local aboveY = math.floor(self.trigger.y - gap)

  if not (self.menu and self.menu.panel) then
    return mx, belowY
  end

  local h = tonumber(self.menu.panel.h) or 1
  local spaceBelow = (tonumber(bounds.h) or 600) - belowY - inset
  local spaceAbove = aboveY - inset

  if self._menuOpenAbove then
    if spaceAbove >= h or spaceAbove >= spaceBelow then
      return mx, aboveY - h
    end
    return mx, belowY
  end
  if spaceBelow >= h or spaceBelow >= spaceAbove then
    return mx, belowY
  end
  return mx, aboveY - h
end

function Dropdown:openMenu()
  if not self.menu or #self._menuItems == 0 then
    return false
  end
  if self.onBeforeOpenMenu then
    self.onBeforeOpenMenu(self)
  end
  local x, y = self:_anchorMenuPosition()
  return self.menu:showAt(x, y, self._menuItems)
end

function Dropdown:toggleMenu()
  if self:isMenuVisible() then
    self:closeMenu()
    return false
  end
  return self:openMenu()
end

function Dropdown:contains(px, py)
  if not self.enabled then
    return false
  end
  if self:isMenuVisible() and self.menu:contains(px, py) then
    return true
  end
  return self.trigger:contains(px, py)
end

function Dropdown:setPosition(x, y)
  self.trigger:setPosition(x, y)
end

function Dropdown:setSize(w, h)
  self.trigger:setSize(w, h)
end

function Dropdown:setFocused(focused)
  self.trigger.focused = focused == true
end

function Dropdown:draw()
  self.trigger:draw()
end

function Dropdown:drawMenu()
  if not self:isMenuVisible() then
    return
  end
  if self.menu.update then
    self.menu:update()
  end
  self.menu:draw()
end

function Dropdown:mousemoved(x, y)
  if self:isMenuVisible() then
    self.menu:mousemoved(x, y)
    return
  end
  self.trigger.hovered = self.trigger:contains(x, y)
end

function Dropdown:handleMousePressed(x, y, button)
  if not self.enabled or button ~= 1 then
    return false
  end
  if self:isMenuVisible() then
    if self.trigger:contains(x, y) then
      self:closeMenu()
      self.trigger.pressed = false
      self._pressed = false
      return true
    end
    if self.menu:contains(x, y) then
      self.menu:mousepressed(x, y, button)
      return true
    end
    self.menu:mousepressed(x, y, button)
    return true
  end
  if self.trigger:contains(x, y) then
    self.trigger.pressed = true
    self._pressed = true
    return true
  end
  return false
end

function Dropdown:handleMouseReleased(x, y, button)
  if not self.enabled then
    return false
  end
  if self:isMenuVisible() then
    self.menu:mousereleased(x, y, button)
    self.trigger.pressed = false
    self._pressed = false
    return true
  end
  if self._pressed and button == 1 then
    self._pressed = false
    self.trigger.pressed = false
    if self.trigger:contains(x, y) then
      self:toggleMenu()
    end
    return true
  end
  return false
end

return Dropdown
