-- rom_palette_toolbar.lua
-- Toolbar for ROM palette windows: nav, reset overrides (links via on-canvas badges).

local ToolbarBase = require("ui.toolbars.toolbar_base")
local images = require("images")

local RomPaletteToolbar = {}
RomPaletteToolbar.__index = RomPaletteToolbar
setmetatable(RomPaletteToolbar, { __index = ToolbarBase })

function RomPaletteToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), RomPaletteToolbar)

  self.ctx = ctx
  self.windowController = windowController

  local hx, hy, hw, hh = window:getHeaderRect()
  self.h = hh

  self.prevButton = self:addButton(images.icons.actions.icon_left, function()
    self:_onNavigate(-1)
  end, "Previous ROM palette")

  self.nextButton = self:addButton(images.icons.actions.icon_right, function()
    self:_onNavigate(1)
  end, "Next ROM palette")

  self.resetCellButton = self:addButton(
    images.icons.actions.icon_reset_cell,
    function()
      self:_onResetCell()
    end,
    "Reset selected cell to ROM base color"
  )

  self.resetAllButton = self:addButton(
    images.icons.actions.icon_reset_all,
    function()
      self:_onResetAll()
    end,
    "Reset all cells to ROM base colors"
  )

  self:updateResetButtons()
  self:updatePosition()

  return self
end

function RomPaletteToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  self:updateGroupedNavigationButtons()
  if self.resetCellButton then
    self.resetCellButton.icon = images.icons.actions.icon_reset_cell or self.resetCellButton.icon
  end
  if self.resetAllButton then
    self.resetAllButton.icon = images.icons.actions.icon_reset_all or self.resetAllButton.icon
  end
  self:updateResetButtons()
end

function RomPaletteToolbar:isGroupedPaletteMode()
  local app = self.ctx and self.ctx.app or nil
  return app and app.isGroupedPaletteWindowsEnabled and app:isGroupedPaletteWindowsEnabled() or false
end

function RomPaletteToolbar:updateGroupedNavigationButtons()
  local grouped = self:isGroupedPaletteMode()
  if self.prevButton then
    self.prevButton.visible = grouped
    self.prevButton.enabled = grouped
  end
  if self.nextButton then
    self.nextButton.visible = grouped
    self.nextButton.enabled = grouped
  end
end

function RomPaletteToolbar:updateResetButtons()
  local win = self.window
  local canResetCell = false
  local canResetAll = false
  if win then
    if win.hasAnyUserOverride then
      canResetAll = win:hasAnyUserOverride() == true
    end
    if win.getSelected and win.cellHasUserOverride then
      local col, row = win:getSelected()
      if col ~= nil and row ~= nil then
        canResetCell = win:cellHasUserOverride(col, row) == true
      end
    end
  end
  if self.resetCellButton then
    self.resetCellButton.enabled = canResetCell
    self.resetCellButton.tooltip = canResetCell
      and "Reset selected cell to ROM base color"
      or "Select an overridden cell to reset"
  end
  if self.resetAllButton then
    self.resetAllButton.enabled = canResetAll
    self.resetAllButton.tooltip = canResetAll
      and "Reset all cells to ROM base colors"
      or "No overridden cells to reset"
  end
end

function RomPaletteToolbar:_onNavigate(delta)
  if not self.window or not self.ctx or not self.ctx.app then return end
  local app = self.ctx.app
  if app.cycleGroupedPaletteWindow then
    app:cycleGroupedPaletteWindow(self.window, delta or 0)
  end
end

function RomPaletteToolbar:_onResetCell()
  local win = self.window
  if not win or not win.resetCellToBase or not win.getSelected then
    return
  end
  local col, row = win:getSelected()
  if col == nil or row == nil then
    return
  end
  win:resetCellToBase(col, row)
  self:updateResetButtons()
end

function RomPaletteToolbar:_onResetAll()
  local win = self.window
  if not win or not win.resetAllCellsToBase then
    return
  end
  win:resetAllCellsToBase()
  self:updateResetButtons()
end

return RomPaletteToolbar
