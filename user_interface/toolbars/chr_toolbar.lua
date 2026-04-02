-- chr_toolbar.lua
-- Toolbar for CHR bank window: bank navigation, mode toggle, bank label

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local images = require("images")
local colors = require("app_colors")

local ChrToolbar = {}
ChrToolbar.__index = ChrToolbar
setmetatable(ChrToolbar, { __index = ToolbarBase })

local CHR_LAYER_LABEL_FADE_SECONDS = 3.0

function ChrToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {
    layerLabelFadeDuration = CHR_LAYER_LABEL_FADE_SECONDS,
  }), ChrToolbar)
  self.allowContentLabelWhenUnfocused = true

  self.ctx = ctx
  self.windowController = windowController

  local hx, hy, hw, hh = window:getHeaderRect()
  self.h = hh

  -- Bank label rendered in content area
  self.bankLabel = self:addLabel("", self.h * 3, function()
    if not self.window then return "Bank" end
    local bank = self.window.currentBank or 1
    return string.format("Bank %d", bank)
  end)
  self.bankLabel.renderInContent = true
  self:triggerLayerLabelFlash()

  -- Prev bank
  self:addButton(images.icons.icon_left, function()
    self:_onBankChange(-1)
  end, "Prev bank")

  -- Next bank
  self:addButton(images.icons.icon_right, function()
    self:_onBankChange(1)
  end, "Next bank")

  -- Mode toggle
  self.modeButton = self:addButton(images.icons.icon_8x8, function()
    self:_onToggleMode()
  end, "Sprite mode (height)")
  self:updateModeIcon()

  if not (window and window.isRomWindow == true) then
    -- Sync duplicate tiles toggle (on by default)
    self.syncButton = self:addButton(images.icons.icon_selected, function()
      self:_onToggleSyncDuplicates()
    end, "Toggle sync duplicate tiles")
    self:updateSyncIcon()
  end

  self:updatePosition()

  return self
end

function ChrToolbar:updateModeIcon()
  if not self.window or not self.modeButton then return end
  if self.window.orderMode == "oddEven" then
    self.modeButton.icon = images.icons.icon_8x16 or self.modeButton.icon
  else
    self.modeButton.icon = images.icons.icon_8x8 or self.modeButton.icon
  end
end

function ChrToolbar:updateSyncIcon()
  if not self.syncButton or not self.ctx or not self.ctx.app then return end
  local enabled = self.ctx.app.syncDuplicateTiles == true
  if enabled then
    self.syncButton.icon = images.icons.icon_selected or self.syncButton.icon
    self.syncButton.tooltip = "Sync duplicates: ON"
  else
    self.syncButton.icon = images.icons.icon_not_selected or self.syncButton.icon
    self.syncButton.tooltip = "Sync duplicates: OFF"
  end
end

function ChrToolbar:updateIcons()
  self:updateModeIcon()
  self:updateSyncIcon()
end

function ChrToolbar:_onBankChange(delta)
  if not self.window or not self.ctx or not self.ctx.app then return end
  local app = self.ctx.app
  local banks = app.appEditState and app.appEditState.chrBanksBytes
  if not banks or #banks == 0 then return end

  local n = #banks
  if self.window.shiftBank then
    self.window:shiftBank(delta)
  else
    self.window.currentBank = ((self.window.currentBank - 1 + delta) % n) + 1
    self.window.activeLayer = self.window.currentBank
  end
  app.appEditState.currentBank = self.window.currentBank or self.window.activeLayer or 1
  if self.ctx.setStatus then
    self.ctx.setStatus(string.format("Bank %d/%d", self.window.currentBank, n))
  end
  self:triggerLayerLabelFlash()
end

function ChrToolbar:showTileLabel(tileIndex)
  if type(tileIndex) ~= "number" then return end
  local text = string.format("tile %d (%02X hex)", tileIndex, tileIndex % 0x100)
  if self.triggerLayerLabelTextFlash then
    self:triggerLayerLabelTextFlash(text)
  else
    self:triggerLayerLabelFlash(text)
  end
end

function ChrToolbar:_onToggleMode()
  if not self.window or not self.ctx or not self.ctx.app then return end
  self.window.orderMode = (self.window.orderMode == "normal") and "oddEven" or "normal"
  if self.ctx.rebuildChrBankWindow then
    self.ctx.rebuildChrBankWindow(self.window)
  end
  self:updateModeIcon()
  if self.ctx.setStatus then
    self.ctx.setStatus("Order mode: " .. ((self.window.orderMode == "normal") and "8x8" or "8x16"))
  end
end

function ChrToolbar:_onToggleSyncDuplicates()
  if not self.ctx or not self.ctx.app then return end
  local newVal
  if self.ctx.setSyncDuplicates then
    newVal = self.ctx.setSyncDuplicates(not self.ctx.app.syncDuplicateTiles)
  else
    self.ctx.app.syncDuplicateTiles = not self.ctx.app.syncDuplicateTiles
    newVal = self.ctx.app.syncDuplicateTiles
  end

  local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
  if newVal then
    ChrDuplicateSync.buildSyncGroups(self.ctx.app.appEditState)
  else
    ChrDuplicateSync.clearSyncGroups(self.ctx.app.appEditState)
  end

  self:updateSyncIcon()
  if self.ctx.setStatus then
    local txt = newVal and "Sync duplicates: ON" or "Sync duplicates: OFF"
    self.ctx.setStatus(txt)
  end
end

return ChrToolbar
