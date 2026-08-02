-- sketch_canvas_toolbar.lua
-- Sketch canvas toolbar shell. Link / tolerance / generate / reflect are
-- placeholders until pack + pattern-table wiring lands.

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
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
    stubAction(self, "Tolerance"),
    "Decrease tolerance (not implemented yet)"
  )
  self.toleranceDownButton.enabled = false

  self.toleranceUpButton = self:addButton(
    chrome.icon_plus or chrome.icon_circle,
    stubAction(self, "Tolerance"),
    "Increase tolerance (not implemented yet)"
  )
  self.toleranceUpButton.enabled = false

  self.generateButton = self:addButton(
    actions.icon_mosaic or actions.icon_img or chrome.icon_circle,
    stubAction(self, "Generate"),
    "Generate pattern table from sketch (not implemented yet)"
  )
  self.generateButton.enabled = false

  self.reflectButton = self:addButton(
    actions.icon_mirror_x or actions.icon_diff_mode or chrome.icon_circle,
    stubAction(self, "Reflect"),
    "Reflect pattern table view (not implemented yet)"
  )
  self.reflectButton.enabled = false

  self:updatePosition()
  return self
end

function SketchCanvasToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
end

return SketchCanvasToolbar
