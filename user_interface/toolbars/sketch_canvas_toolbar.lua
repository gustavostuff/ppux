-- sketch_canvas_toolbar.lua
-- Sketch canvas toolbar. Phase 3: Generate + tolerance adjust. Link/reflect later.

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local images = require("images")
local StatusHelpers = require("utils.status_helpers")

local SketchCanvasToolbar = {}
SketchCanvasToolbar.__index = SketchCanvasToolbar
setmetatable(SketchCanvasToolbar, { __index = ToolbarBase })

local function stubAction(self, label)
  return function()
    StatusHelpers.setStatus(self.ctx, label .. " is not implemented yet")
  end
end

function SketchCanvasToolbar.new(window, ctx, windowController)
  local self = setmetatable(ToolbarBase.new(window, {}), SketchCanvasToolbar)
  self.ctx = ctx
  self.windowController = windowController
  local _, _, _, hh = window:getHeaderRect()
  self.h = hh or 22

  local actions = images.icons and images.icons.actions or {}
  local chrome = images.icons and images.icons.chrome or {}

  self.linkButton = self:addButton(
    actions.icon_pattern_table or actions.icon_connect or chrome.icon_circle,
    stubAction(self, "Pattern table link"),
    "Link pattern table (not implemented yet)"
  )
  self.linkButton.enabled = false

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
    stubAction(self, "Reflect"),
    "Reflect pattern table view (not implemented yet)"
  )
  self.reflectButton.enabled = false

  self:updateIcons()
  self:updatePosition()
  return self
end

function SketchCanvasToolbar:_tolerance()
  return math.floor(tonumber(self.window and self.window.tolerance) or 0)
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
  self.window.tolerance = nextTol
  StatusHelpers.setStatus(self.ctx, string.format("Sketch tolerance: %d", nextTol))
  self:updateIcons()
end

function SketchCanvasToolbar:_onGenerate()
  if not self.window then
    return
  end
  local ok, packOrErr = SketchCanvasPackController.generate(self.window)
  StatusHelpers.setStatus(
    self.ctx,
    SketchCanvasPackController.formatGenerateStatus(ok, packOrErr)
  )
  self:updateIcons()
end

function SketchCanvasToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  local tol = self:_tolerance()
  if self.toleranceDownButton then
    self.toleranceDownButton.enabled = tol > 0
    self.toleranceDownButton.tooltip = string.format("Decrease pack tolerance (now %d)", tol)
  end
  if self.toleranceUpButton then
    self.toleranceUpButton.enabled = tol < SketchCanvasPackController.MAX_TOLERANCE
    self.toleranceUpButton.tooltip = string.format("Increase pack tolerance (now %d)", tol)
  end
  if self.generateButton then
    self.generateButton.enabled = true
    self.generateButton.tooltip = string.format(
      "Generate pattern catalog from sketch (tolerance %d)",
      tol
    )
  end
end

return SketchCanvasToolbar
