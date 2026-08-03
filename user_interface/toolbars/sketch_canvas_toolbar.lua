-- sketch_canvas_toolbar.lua
-- Sketch canvas toolbar. Phase 6: Link + Generate + live tolerance + Reflect.

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local images = require("images")
local colors = require("app_colors")
local StatusHelpers = require("utils.status_helpers")
local Timer = require("utils.timer_utils")

local SketchCanvasToolbar = {}
SketchCanvasToolbar.__index = SketchCanvasToolbar
setmetatable(SketchCanvasToolbar, { __index = ToolbarBase })

local TOLERANCE_REGEN_DELAY = 0.12

local function getApp(self)
  return self.ctx and self.ctx.app or nil
end

function SketchCanvasToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), SketchCanvasToolbar)
  self.ctx = ctx
  self.windowController = windowController
  self._toleranceRegenTimerId = nil
  local _, _, _, hh = window:getHeaderRect()
  self.h = hh or 22

  local actions = images.icons and images.icons.actions or {}
  local chrome = images.icons and images.icons.chrome or {}

  self.linkButton = self:addButton(
    actions.icon_pattern_table or actions.icon_connect or chrome.icon_circle,
    function()
      self:_onLinkMenu()
    end,
    "Link pattern table"
  )

  self.toleranceDownButton = self:addButton(
    chrome.icon_minus or chrome.icon_circle,
    function()
      self:_onToleranceDelta(-1)
    end,
    "Decrease pack tolerance"
  )

  self.toleranceUpButton = self:addButton(
    chrome.icon_plus or chrome.icon_circle,
    function()
      self:_onToleranceDelta(1)
    end,
    "Increase pack tolerance"
  )

  self.generateButton = self:addButton(
    actions.icon_mosaic or actions.icon_img or chrome.icon_circle,
    function()
      self:_onGenerate()
    end,
    "Generate pattern table catalog from sketch"
  )

  self.reflectButton = self:addButton(
    actions.icon_mirror_x or actions.icon_diff_mode or chrome.icon_circle,
    function()
      self:_onReflectToggle()
    end,
    "Reflect packed pattern table view"
  )

  self:updateIcons()
  self:updatePosition()
  return self
end

function SketchCanvasToolbar:_tolerance()
  return math.floor(tonumber(self.window and self.window.tolerance) or 0)
end

function SketchCanvasToolbar:_isLinked()
  return type(self.window and self.window.linkedPatternTableWindowId) == "string"
    and self.window.linkedPatternTableWindowId ~= ""
end

function SketchCanvasToolbar:_hasPack()
  return SketchCanvasPackController.hasPackData(self.window)
end

function SketchCanvasToolbar:_cancelToleranceRegen()
  if self._toleranceRegenTimerId then
    Timer.cancel(self._toleranceRegenTimerId)
    self._toleranceRegenTimerId = nil
  end
end

function SketchCanvasToolbar:_onLinkMenu()
  local app = getApp(self)
  if not (app and app.showPatternTableLinkDestinationContextMenu and self.window) then
    StatusHelpers.setStatus(self.ctx, "Pattern table link is unavailable")
    return
  end
  local btn = self.linkButton
  local x = (btn and btn.x or 0) + ((btn and btn.w) or 0) * 0.5
  local y = (btn and btn.y or 0) + ((btn and btn.h) or 0) * 0.5
  app:showPatternTableLinkDestinationContextMenu(self.window, x, y)
  self:updateIcons()
end

function SketchCanvasToolbar:_runGenerate()
  if not self.window then
    return false
  end
  self:_cancelToleranceRegen()

  local app = getApp(self)
  local wm = (app and app.wm) or self.windowController
  local beforePack = SketchCanvasPackController.snapshotPackFields(self.window)
  local ptWin = SketchCanvasPackController.resolveLinkedPatternTable(self.window, wm)
  local beforeItems = ptWin and SketchCanvasPackController.snapshotPatternTableItemPixels(ptWin) or nil

  local ok, packOrErr = SketchCanvasPackController.generateAndApply(self.window, wm)
  StatusHelpers.setStatus(
    self.ctx,
    SketchCanvasPackController.formatGenerateStatus(ok, packOrErr)
  )

  if ok and app and app.undoRedo and app.undoRedo.addSketchCanvasGenerateEvent then
    local afterPack = SketchCanvasPackController.snapshotPackFields(self.window)
    local afterItems = ptWin and SketchCanvasPackController.snapshotPatternTableItemPixels(ptWin) or nil
    if not ptWin then
      ptWin = SketchCanvasPackController.resolveLinkedPatternTable(self.window, wm)
      afterItems = ptWin and SketchCanvasPackController.snapshotPatternTableItemPixels(ptWin) or nil
    end
    app.undoRedo:addSketchCanvasGenerateEvent({
      type = "sketch_canvas_generate",
      sketchWin = self.window,
      patternTableWin = ptWin,
      beforePack = beforePack,
      afterPack = afterPack,
      beforeItemsPixels = beforeItems,
      afterItemsPixels = afterItems,
    })
  end

  self:updateIcons()
  return ok == true
end

function SketchCanvasToolbar:_scheduleToleranceRegen()
  self:_cancelToleranceRegen()
  self._toleranceRegenTimerId = Timer.after(TOLERANCE_REGEN_DELAY, function()
    self._toleranceRegenTimerId = nil
    if self.window and self:_isLinked() then
      self:_runGenerate()
    end
  end)
end

function SketchCanvasToolbar:_onToleranceDelta(delta)
  if not self.window then
    return
  end
  local nextTol = self:_tolerance() + (tonumber(delta) or 0)
  if nextTol < 0 then
    nextTol = 0
  elseif nextTol > SketchCanvasPackController.MAX_TOLERANCE then
    nextTol = SketchCanvasPackController.MAX_TOLERANCE
  end
  if nextTol == self:_tolerance() then
    return
  end
  self.window.tolerance = nextTol
  self:updateIcons()

  if self:_isLinked() then
    -- Live regen sets the final status (avoid a flash of "updating…" then generate).
    self:_scheduleToleranceRegen()
  else
    StatusHelpers.setStatus(self.ctx, string.format("Sketch tolerance: %d", nextTol))
  end
end

function SketchCanvasToolbar:_onGenerate()
  self:_runGenerate()
end

function SketchCanvasToolbar:_onReflectToggle()
  if not self.window then
    return
  end
  if not self:_hasPack() then
    StatusHelpers.setStatus(self.ctx, "Sketch Reflect needs a successful Generate first")
    return
  end
  local ok, onOrErr = SketchCanvasPackController.toggleReflectPatternTable(self.window)
  if not ok then
    StatusHelpers.setStatus(self.ctx, "Sketch Reflect failed: " .. tostring(onOrErr or "error"))
    return
  end
  StatusHelpers.setStatus(
    self.ctx,
    onOrErr and "Sketch Reflect on (paint disabled)" or "Sketch Reflect off"
  )
  self:updateIcons()
end

function SketchCanvasToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  local tol = self:_tolerance()
  local linked = self:_isLinked()
  local hasPack = self:_hasPack()
  local reflecting = self.window and self.window.reflectPatternTable == true

  if self.linkButton then
    self.linkButton.enabled = true
    self.linkButton.tooltip = linked and "Manage linked pattern table" or "Link pattern table"
  end
  if self.toleranceDownButton then
    self.toleranceDownButton.enabled = tol > 0
    self.toleranceDownButton.tooltip = linked
      and string.format("Decrease pack tolerance (now %d; live update)", tol)
      or string.format("Decrease pack tolerance (now %d)", tol)
  end
  if self.toleranceUpButton then
    self.toleranceUpButton.enabled = tol < SketchCanvasPackController.MAX_TOLERANCE
    self.toleranceUpButton.tooltip = linked
      and string.format("Increase pack tolerance (now %d; live update)", tol)
      or string.format("Increase pack tolerance (now %d)", tol)
  end
  if self.generateButton then
    self.generateButton.enabled = true
    self.generateButton.tooltip = linked
      and string.format("Generate and apply to linked pattern table (tolerance %d)", tol)
      or string.format("Generate pattern catalog from sketch (tolerance %d)", tol)
  end
  if self.reflectButton then
    self.reflectButton.enabled = hasPack
    self.reflectButton.bgColor = reflecting and colors.green or colors.gray20
    if hasPack then
      self.reflectButton.tooltip = reflecting
        and "Reflect on: showing packed tiles (click to restore paint view)"
        or "Reflect off: show packed pattern-table view"
    else
      self.reflectButton.tooltip = "Reflect needs a successful Generate first"
    end
  end
end

return SketchCanvasToolbar
