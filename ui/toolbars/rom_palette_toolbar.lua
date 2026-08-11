-- rom_palette_toolbar.lua
-- Toolbar for ROM palette windows: nav, reset overrides, palette link

local ToolbarBase = require("ui.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")
local PaletteLinkController = require("controllers.palette.palette_link_controller")

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

  --[[ Toggle compact view — commented out while compact is the only size (FORCE_COMPACT_ONLY).
  self.compactButton = self:addButton(images.icons.chrome.icon_minus or images.icons.chrome.icon_down, function()
    self:_onToggleCompact()
  end, "Toggle compact palette view")
  self.compactButton.visible = false
  self.compactButton.enabled = false
  --]]

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

  self.linkButton = self:addButton(images.icons.actions.icon_connect or images.icons.chrome.icon_pivot or images.icons.chrome.icon_empty or images.icons.chrome.icon_scroll_toolbar_empty, nil, "Palette link handle; right-drag to link layers; left-click for menu", {
    paletteLinkHandle = true,
  })

  self:updateResetButtons()
  self:updatePosition()

  return self
end

function RomPaletteToolbar:getLinkHandleRect()
  if not self.linkButton or self.linkButton.hidden == true then return nil end
  self:updatePosition()
  return self.linkButton.x, self.linkButton.y, self.linkButton.w, self.linkButton.h
end

function RomPaletteToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  self:updateGroupedNavigationButtons()
  if self.linkButton then
    self.linkButton.icon = images.icons.actions.icon_connect or images.icons.chrome.icon_pivot or self.linkButton.icon
    local targets = PaletteLinkController.getLinkedTargetsForPalette(self.windowController, self.window)
    local linkedCount = #(targets or {})
    self.linkButton.bgColor = linkedCount > 0 and colors.green or colors.gray20
    self.linkButton.contentColor = colors.white
    if linkedCount > 0 then
      self.linkButton.tooltip = string.format(
        "%d linked layer(s); right-drag to link or move; left-click for menu",
        linkedCount
      )
    else
      self.linkButton.tooltip = "No linked layers; right-drag to link; left-click for menu"
    end
  end
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

--[[ Toggle compact view — commented out while compact is the only size (FORCE_COMPACT_ONLY).
function RomPaletteToolbar:updateCompactIcon()
  if not self.compactButton or not self.window then return end
  local supported = self.window.supportsCompactMode and self.window:supportsCompactMode()
  self.compactButton.visible = supported
  self.compactButton.enabled = supported
  if not supported then return end

  if self.window.compactView then
    self.compactButton.icon = images.icons.chrome.icon_normal_mode or self.compactButton.icon
    self.compactButton.tooltip = "Switch to normal view"
  else
    self.compactButton.icon = images.icons.chrome.icon_compact_mode or self.compactButton.icon
    self.compactButton.tooltip = "Switch to compact view"
  end
end

function RomPaletteToolbar:_onToggleCompact()
  if not self.window or not self.window.setCompactMode then return end
  if self.window.supportsCompactMode and not self.window:supportsCompactMode() then
    return
  end
  local newVal = not self.window.compactView
  self.window:setCompactMode(newVal)
  self:updateCompactIcon()
end
--]]

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
