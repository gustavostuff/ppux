-- sketch_canvas_toolbar.lua
-- Sketch canvas toolbar: Link, tolerance, Generate, Export CHR/NT.
-- Tile/edit global mode drives packed mirror view (no dedicated Reflect button).

local ToolbarBase = require("user_interface.toolbars.toolbar_base")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local SketchCanvasExportController = require("controllers.game_art.sketch_canvas_export_controller")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local images = require("images")
local colors = require("app_colors")
local Palettes = require("palettes")
local StatusHelpers = require("utils.status_helpers")
local Timer = require("utils.timer_utils")
local Text = require("utils.text_utils")

local SketchCanvasToolbar = {}
SketchCanvasToolbar.__index = SketchCanvasToolbar
setmetatable(SketchCanvasToolbar, { __index = ToolbarBase })

local TOLERANCE_REGEN_DELAY = 0.12

-- Dirty Generate fill: NES $07 is too dark on chrome; use bright $27 (same orange column).
local NES_DIRTY_ORANGE = (Palettes.smooth_fbx and Palettes.smooth_fbx["27"])
  or { 212 / 255, 157 / 255, 41 / 255 }

local function maxDigitWidth()
  local maxW = 0
  for d = 0, 9 do
    local w = Text.getFontWidth(tostring(d))
    if w > maxW then
      maxW = w
    end
  end
  return math.max(1, maxW)
end

--- Draw 1–2 digits in equal-width slots so proportional fonts don't shift between values.
local function drawFixedDigitLabel(button)
  if not button then
    return
  end
  local font = love.graphics.getFont()
  local text = tostring(button.text or "")
  local slotW = tonumber(button._digitSlotW) or maxDigitWidth()
  local textH = font and font:getHeight() or Text.getFontHeight()
  local textY = button.y + (button.h - textH) / 2
  local a = 1
  if button.enabled == false then
    a = 0.5
  end
  local c = button.contentColor or colors.white
  local color = { c[1] or 1, c[2] or 1, c[3] or 1, a }

  if #text <= 1 then
    local ch = text
    if ch == "" then
      ch = "0"
    end
    local charW = Text.getFontWidth(ch)
    local textX = button.x + (button.w - charW) / 2
    Text.print(ch, math.floor(textX), math.floor(textY), {
      color = color,
      literalColor = button.literalContentColor == true,
    })
    return
  end

  -- Two digits: each centered in a fixed slot (stable across 10–32).
  local digits = { text:sub(1, 1), text:sub(2, 2) }
  for i, ch in ipairs(digits) do
    local charW = Text.getFontWidth(ch)
    local slotX = button.x + (i - 1) * slotW
    local textX = slotX + (slotW - charW) / 2
    Text.print(ch, math.floor(textX), math.floor(textY), {
      color = color,
      literalColor = button.literalContentColor == true,
    })
  end
end

local function getApp(self)
  return self.ctx and self.ctx.app or nil
end

local function showToast(self, kind, text)
  if self.ctx and type(self.ctx.showToast) == "function" then
    self.ctx.showToast(kind, text)
    return
  end
  local app = getApp(self)
  if app and type(app.showToast) == "function" then
    app:showToast(kind, text)
  end
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

  -- Palette link destination handle (ROM palette → sketch), separate from PT link.
  self.paletteLinkButton = self:addButton(
    actions.icon_connect or chrome.icon_circle,
    function()
      self:_onPaletteLinkMenu()
    end,
    "Palette link handle; right-drag to a sketch palette to link; left-click for menu",
    {
      paletteLinkHandle = true,
    }
  )

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

  local digitSlotW = maxDigitWidth()
  self.toleranceValueButton = self:addTextButton(
    "0",
    nil,
    "Pack tolerance",
    {
      w = digitSlotW * 2,
      transparent = true,
      contentPaddingX = 0,
      contentPaddingRight = 0,
      textAlign = "center",
    }
  )
  -- Display-only: keep enabled so Aseprite font ink stays full opacity.
  self.toleranceValueButton.enabled = true
  self.toleranceValueButton.skipHoverFocusUnderlay = true
  self.toleranceValueButton._digitSlotW = digitSlotW
  self.toleranceValueButton.draw = function(btn)
    drawFixedDigitLabel(btn)
  end

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

  self.exportChrButton = self:addButton(
    actions.save or actions.icon_img or chrome.icon_circle,
    function()
      self:_onExportChr()
    end,
    "Export CHR bank (4KB)"
  )

  self.exportNametableButton = self:addButton(
    actions.icon_nametable_range or actions.icon_folder or chrome.icon_circle,
    function()
      self:_onExportNametable()
    end,
    "Export nametable binary"
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

function SketchCanvasToolbar:_hasCanvas()
  if not self.window then
    return false
  end
  if type(self.window.getActiveCanvas) == "function" then
    return self.window:getActiveCanvas() ~= nil
  end
  local layer = self.window.layers and self.window.layers[self.window.activeLayer or 1]
  return layer and layer.kind == "canvas" and layer.canvas ~= nil
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

function SketchCanvasToolbar:getLinkHandleRect()
  if not self.paletteLinkButton or self.paletteLinkButton.hidden == true then
    return nil
  end
  self:updatePosition()
  return self.paletteLinkButton.x, self.paletteLinkButton.y, self.paletteLinkButton.w, self.paletteLinkButton.h
end

function SketchCanvasToolbar:_onPaletteLinkMenu()
  local app = getApp(self)
  if not (app and app.showPaletteLinkDestinationContextMenu and self.window) then
    StatusHelpers.setStatus(self.ctx, "Palette link is unavailable")
    return
  end
  local btn = self.paletteLinkButton
  local x = (btn and btn.x or 0) + ((btn and btn.w) or 0) * 0.5
  local y = (btn and btn.y or 0) + ((btn and btn.h) or 0) * 0.5
  app:showPaletteLinkDestinationContextMenu(self.window, x, y)
  self:updateIcons()
end

function SketchCanvasToolbar:_runGenerate(opts)
  opts = opts or {}
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
  do
    local kind, text = SketchCanvasPackController.formatGenerateToast(ok, packOrErr)
    if opts.statusOnly then
      StatusHelpers.setStatus(self.ctx, text)
    else
      showToast(self, kind, text)
    end
  end

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
      -- Tolerance buttons: status bar only (no toast spam while adjusting).
      self:_runGenerate({ statusOnly = true })
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
  if not self:_isLinked() then
    StatusHelpers.setStatus(self.ctx, "Sketch Generate needs a linked pattern table")
    return
  end
  if not self:_hasCanvas() then
    StatusHelpers.setStatus(self.ctx, "Sketch Generate needs a paint canvas")
    return
  end
  self:_runGenerate()
end

function SketchCanvasToolbar:_onExportChr()
  if not self.window then
    return
  end
  if not self:_hasPack() then
    StatusHelpers.setStatus(self.ctx, "Export CHR needs a successful Generate first")
    return
  end
  local ok, pathOrErr = SketchCanvasExportController.exportChrBankToFile(getApp(self), self.window)
  if not ok then
    StatusHelpers.setStatus(self.ctx, "Export CHR failed: " .. tostring(pathOrErr or "error"))
    return
  end
  StatusHelpers.setStatus(self.ctx, "Exported CHR (4KB): " .. tostring(pathOrErr))
end

function SketchCanvasToolbar:_onExportNametable()
  if not self.window then
    return
  end
  if not self:_hasPack() then
    StatusHelpers.setStatus(self.ctx, "Export nametable needs a successful Generate first")
    return
  end
  local ok, pathOrErr = SketchCanvasExportController.exportNametableToFile(
    getApp(self),
    self.window,
    nil,
    { includeAttributes = true }
  )
  if not ok then
    StatusHelpers.setStatus(self.ctx, "Export nametable failed: " .. tostring(pathOrErr or "error"))
    return
  end
  StatusHelpers.setStatus(self.ctx, "Exported nametable: " .. tostring(pathOrErr))
end

function SketchCanvasToolbar:updateIcons()
  ToolbarBase.updateIcons(self)
  local tol = self:_tolerance()
  local linked = self:_isLinked()
  local hasPack = self:_hasPack()
  local hasCanvas = self:_hasCanvas()
  local generateDirty = SketchCanvasPackController.isGenerateDirty(self.window)
  local linkedPalette = PaletteLinkController.getActiveLayerLinkedPaletteWindow(
    self.window,
    self.windowController
  )

  if self.paletteLinkButton then
    self.paletteLinkButton.enabled = true
    self.paletteLinkButton.bgColor = linkedPalette and colors.green or colors.gray20
    if linkedPalette then
      self.paletteLinkButton.tooltip = string.format(
        "Linked to %s; right-drag to a sketch palette to change link; left-click for menu",
        tostring(linkedPalette.title or "palette")
      )
    else
      self.paletteLinkButton.tooltip =
        "No palette linked; right-drag to a sketch palette to link; left-click for menu"
    end
  end
  if self.linkButton then
    self.linkButton.enabled = true
    self.linkButton.bgColor = linked and colors.green or colors.gray20
    self.linkButton.tooltip = linked and "Manage linked pattern table" or "Link pattern table"
  end
  if self.toleranceDownButton then
    self.toleranceDownButton.enabled = tol > 0
    self.toleranceDownButton.tooltip = linked
      and string.format("Decrease pack tolerance (now %d; live update when linked)", tol)
      or string.format("Decrease pack tolerance (now %d)", tol)
  end
  if self.toleranceValueButton then
    self.toleranceValueButton.text = tostring(tol)
    self.toleranceValueButton.tooltip = linked
      and string.format("Pack tolerance: %d (live update when linked)", tol)
      or string.format("Pack tolerance: %d", tol)
  end
  if self.toleranceUpButton then
    self.toleranceUpButton.enabled = tol < SketchCanvasPackController.MAX_TOLERANCE
    self.toleranceUpButton.tooltip = linked
      and string.format("Increase pack tolerance (now %d; live update when linked)", tol)
      or string.format("Increase pack tolerance (now %d)", tol)
  end
  if self.generateButton then
    self.generateButton.enabled = hasCanvas and linked
    if generateDirty and hasCanvas and linked then
      self.generateButton.bgColor = NES_DIRTY_ORANGE
      self.generateButton.bgAlpha = 1
      self.generateButton.skipChromeTextTint = true
    else
      self.generateButton.bgColor = colors.gray20
      self.generateButton.bgAlpha = nil
      self.generateButton.skipChromeTextTint = nil
    end
    if not linked then
      self.generateButton.tooltip = "Generate needs a linked pattern table"
    elseif not hasCanvas then
      self.generateButton.tooltip = "Generate needs a paint canvas"
    elseif generateDirty then
      self.generateButton.tooltip = string.format(
        "Pixels changed since last Generate (tolerance %d) - click to refresh pattern table",
        tol
      )
    else
      self.generateButton.tooltip = string.format(
        "Generate and apply to linked pattern table (tolerance %d)",
        tol
      )
    end
  end
  if self.exportChrButton then
    self.exportChrButton.enabled = hasPack
    self.exportChrButton.tooltip = hasPack
      and "Export packed CHR bank (4KB / 256 tiles)"
      or "Export CHR needs a successful Generate first"
  end
  if self.exportNametableButton then
    self.exportNametableButton.enabled = hasPack
    self.exportNametableButton.tooltip = hasPack
      and "Export nametable binary (960 tiles + 64 attrs)"
      or "Export nametable needs a successful Generate first"
  end
end

return SketchCanvasToolbar
