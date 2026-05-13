-- chr_toolbar.lua
-- Toolbar for CHR bank window: bank navigation, mode toggle, bank label

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local BankViewController = require("controllers.chr.bank_view_controller")
local OpenRomFolder = require("utils.open_rom_folder")
local images = require("images")
local colors = require("app_colors")

-- Experimental zero-distractions (canvas-only) mode; toolbar entry hidden until stabilized.
local SHOW_ZERO_DISTRACTIONS_TOGGLE = false

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
  self:addButton(images.icons.actions.icon_left, function()
    self:_onBankChange(-1)
  end, "Prev bank")

  -- Next bank
  self:addButton(images.icons.actions.icon_right, function()
    self:_onBankChange(1)
  end, "Next bank")

  self.openBaseRomFolderButton = self:addButton(images.icons.actions.icon_open, function()
    self:_onOpenBaseRomFolder()
  end, "Open base ROM folder in file manager")

  -- Mode toggle
  self.modeButton = self:addButton(images.icons.actions.icon_8x8, function()
    self:_onToggleMode()
  end, "Sprite mode (height)")
  self:updateModeIcon()

  self.diffModeButton = self:addButton(images.icons.actions.icon_diff_mode, function()
    self:_onToggleDiffMode()
  end, "Diff vs loaded CHR")
  self:updateDiffModeButton()

  self:_updateOpenBaseRomFolderButton()

  self.canvasOnlyButton = self:addButton(images.icons.chrome.icon_compact_mode, function()
    self:_onCanvasOnly()
  end, "Toggle zero distractions mode")
  if not SHOW_ZERO_DISTRACTIONS_TOGGLE then
    self.canvasOnlyButton.hidden = true
  end

  if not (window and window.isRomWindow == true) then
    -- Sync duplicate tiles toggle (off by default; icon matches until updateSyncIcon runs).
    self.syncButton = self:addButton(images.icons.chrome.icon_not_selected or images.icons.chrome.icon_selected, function()
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
    self.modeButton.icon = images.icons.actions.icon_8x16 or self.modeButton.icon
  else
    self.modeButton.icon = images.icons.actions.icon_8x8 or self.modeButton.icon
  end
end

function ChrToolbar:updateSyncIcon()
  if not self.syncButton or not self.ctx or not self.ctx.app then return end
  local enabled = self.ctx.app.syncDuplicateTiles == true
  if enabled then
    self.syncButton.icon = images.icons.chrome.icon_selected or self.syncButton.icon
    self.syncButton.tooltip = "Sync duplicates: ON"
  else
    self.syncButton.icon = images.icons.chrome.icon_not_selected or self.syncButton.icon
    self.syncButton.tooltip = "Sync duplicates: OFF"
  end
end

function ChrToolbar:updateCanvasOnlyIcon()
  if not self.canvasOnlyButton or not self.ctx or not self.ctx.app or not self.window then
    return
  end
  local app = self.ctx.app
  if app.chrCanvasOnlyWindow == self.window then
    self.canvasOnlyButton.icon = images.icons.chrome.icon_normal_mode or self.canvasOnlyButton.icon
    self.canvasOnlyButton.tooltip = "Toggle zero distractions mode"
  else
    self.canvasOnlyButton.icon = images.icons.chrome.icon_compact_mode or self.canvasOnlyButton.icon
    self.canvasOnlyButton.tooltip = "Toggle zero distractions mode"
  end
end

function ChrToolbar:updateIcons()
  self:updateModeIcon()
  self:updateDiffModeButton()
  self:updateSyncIcon()
  self:updateCanvasOnlyIcon()
  self:_updateOpenBaseRomFolderButton()
end

function ChrToolbar:_romPathForOpenFolder(app)
  if not app then
    return nil
  end
  local state = app.appEditState
  local p = state and state.romOriginalPath or nil
  if type(p) == "string" and p ~= "" then
    return p
  end
  return nil
end

function ChrToolbar:_updateOpenBaseRomFolderButton()
  local btn = self.openBaseRomFolderButton
  if not btn then
    return
  end
  local app = self.ctx and self.ctx.app or nil
  local path = self:_romPathForOpenFolder(app)
  local canOpen = OpenRomFolder.canOpenParentOfRom(path)
  btn.enabled = canOpen == true
  if canOpen then
    btn.tooltip = "Open folder containing base ROM"
  elseif not (app and app.hasLoadedROM and app:hasLoadedROM()) then
    btn.tooltip = "Open base ROM folder (load a ROM first)"
  else
    btn.tooltip = "Open base ROM folder (path unknown for this workspace)"
  end
end

function ChrToolbar:_onOpenBaseRomFolder()
  local app = self.ctx and self.ctx.app
  local path = self:_romPathForOpenFolder(app)
  if type(path) ~= "string" or path == "" then
    if app and app.setStatus then
      app:setStatus("No ROM path - open or save against a ROM on disk first.")
    end
    return
  end
  local ok, err = OpenRomFolder.openParentFolderOfRomPath(path)
  if app and app.setStatus then
    app:setStatus(ok and "Opened ROM folder." or ("Could not open folder: " .. tostring(err or "unknown")))
  end
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
  self:triggerLayerLabelFlash()
  if app.setStatus then
    app:setStatus(BankViewController.formatBankWindowStatus(
      self.window,
      app.appEditState,
      self.window.orderMode
    ))
  end
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
end

function ChrToolbar:updateDiffModeButton()
  if not self.diffModeButton or not self.window then
    return
  end
  if self.window.showChrDiffMode == true then
    self.diffModeButton.bgColor = colors.green
    self.diffModeButton.contentColor = colors.white
    self.diffModeButton.tooltip =
      "Diff vs loaded CHR: ON (50% black on unchanged tiles, 50% green on changed tiles). Shortcut D."
  else
    self.diffModeButton.bgColor = nil
    self.diffModeButton.contentColor = colors.white
    self.diffModeButton.tooltip =
      "Diff vs loaded CHR (shortcut D)"
  end
end

function ChrToolbar:_onToggleDiffMode()
  if not self.window or not self.ctx or not self.ctx.app then
    return
  end
  self.window.showChrDiffMode = not (self.window.showChrDiffMode == true)
  self:updateDiffModeButton()
  local app = self.ctx.app
  if app.setStatus and BankViewController.formatBankWindowStatus then
    app:setStatus(BankViewController.formatBankWindowStatus(
      self.window,
      app.appEditState,
      self.window.orderMode
    ))
  end
  self:triggerLayerLabelFlash()
end

function ChrToolbar:_onCanvasOnly()
  if not self.ctx or not self.ctx.app or not self.window then
    return
  end
  local app = self.ctx.app
  if app.chrCanvasOnlyWindow == self.window then
    app:clearChrCanvasOnlyMode()
  else
    app:setChrCanvasOnlyMode(self.window)
  end
  self:updateCanvasOnlyIcon()
end

function ChrToolbar:updatePosition()
  if not self.window then
    return
  end
  local app = self.ctx and self.ctx.app
  if app and app.chrCanvasOnlyWindow == self.window and app.canvas then
    local _, _, _, hh = self.window:getHeaderRect()
    local rowH = self:_getRowHeight(hh)
    self.rowHeight = rowH
    self.h = self:_getToolbarHeight(hh)
    local ty = app.chrCanvasOnlyToolbarY
    if ty == nil then
      ty = 4
      app.chrCanvasOnlyToolbarY = ty
    end
    self.y = ty
    local lay = app._appTopToolbarLayout
    local dockLeftX = 3
    if lay and type(lay.dockLeftX) == "number" then
      dockLeftX = lay.dockLeftX
    end
    self._dockLayout = { leftX = dockLeftX, topY = ty, rowHeight = rowH }
    ToolbarBase._layoutButtons(self)
    self._dockLayout = nil
    local targetX = app.chrCanvasOnlyToolbarX
    if targetX == nil then
      app.chrCanvasOnlyToolbarX = self.x
    else
      local dxn = targetX - self.x
      if dxn ~= 0 then
        for _, b in ipairs(self.buttons) do
          b:setPosition(b.x + dxn, b.y)
        end
        for _, lab in ipairs(self.labels) do
          if not lab.renderInContent then
            lab.x = lab.x + dxn
          end
        end
        self.x = targetX
      end
    end
    return
  end
  ToolbarBase.updatePosition(self)
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
end

return ChrToolbar
