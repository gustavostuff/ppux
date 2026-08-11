local Button = require("ui.button")
local Panel = require("ui.panel")
local TextField = require("ui.text_field")
local Text = require("utils.text_utils")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local RomHexGrid = require("ui.rom_hex_grid")
local OamSpritePreview = require("ui.oam_sprite_preview")
local Shared = require("controllers.app.core_controller_shared")
local ResolutionController = require("controllers.app.resolution_controller")
local colors = require("app_colors")

-- Shared Add/Edit sprite modal for PPU Frame and OAM Animation windows.
-- Hex grid + 2x preview sync with the OAM start field (first of 4 OAM bytes).
-- CHR bank/tile come from ROM + the window's linked pattern table on hydrate.

local Dialog = {}
Dialog.__index = Dialog

local FOOTER_ROWS = 3 -- OAM field, buttons, Esc
local PANEL_COLS = 3
Dialog.NES_SPRITE_LIMIT = 64
Dialog.MSG_MAX_PER_ADD = "8 items allowed per Add event"
Dialog.MSG_NES_LIMIT = "64 sprites allowed (NES limit)"
Dialog.MSG_ALREADY_IN_LAYER = "Sprite already in layer"

local function countActiveSprites(layer)
  local n = 0
  for _, item in ipairs((layer and layer.items) or {}) do
    if item.removed ~= true then
      n = n + 1
    end
  end
  return n
end

--- Exact OAM Y-byte starts already present in the layer (sorted ascending).
local function collectOccupiedOamStarts(layer, opts)
  opts = opts or {}
  local exclude = opts.excludeStartAddr
  local list = {}
  local seen = {}
  for _, item in ipairs((layer and layer.items) or {}) do
    if item and item.removed ~= true and type(item.startAddr) == "number" then
      local addr = math.floor(item.startAddr)
      if addr >= 0 and not seen[addr] and addr ~= exclude then
        seen[addr] = true
        list[#list + 1] = addr
      end
    end
  end
  table.sort(list)
  return list
end

--- Add mode default: first free group after the last disabled start, or 0 when none.
local function defaultAddOamStart(occupiedStarts, groupSize)
  groupSize = math.max(1, math.floor(tonumber(groupSize) or 4))
  local occupied = occupiedStarts or {}
  if #occupied == 0 then
    return 0
  end
  return math.floor(occupied[#occupied]) + groupSize
end

--- Gray scrollbar markers: one OAM group (4 bytes) per in-layer start.
local function occupiedMinimapMarkers(starts, groupSize)
  groupSize = math.max(1, math.floor(tonumber(groupSize) or 4))
  local markers = {}
  for _, addr in ipairs(starts or {}) do
    markers[#markers + 1] = {
      offset = math.floor(addr),
      color = "gray",
      groupCount = 1,
      groupSize = groupSize,
    }
  end
  return markers
end

-- Exported for unit tests.
Dialog._collectOccupiedOamStarts = collectOccupiedOamStarts
Dialog._defaultAddOamStart = defaultAddOamStart
Dialog._occupiedMinimapMarkers = occupiedMinimapMarkers

--- How many panel rows are needed so spanned cell height >= `height`.
local function rowspanForHeight(height, cellH, spacingY)
  cellH = math.max(1, math.floor(tonumber(cellH) or 15))
  spacingY = math.max(0, math.floor(tonumber(spacingY) or 0))
  local step = cellH + spacingY
  return math.max(1, math.ceil((math.max(1, height) + spacingY) / step))
end

--- Panel cell width so PANEL_COLS (+ spacing) match the hex grid content width.
local function cellWForHexGrid(spacingX)
  local gridW = RomHexGrid.contentWidth()
  spacingX = math.max(0, math.floor(tonumber(spacingX) or 0))
  local gaps = spacingX * math.max(0, PANEL_COLS - 1)
  return math.max(1, math.ceil((gridW - gaps) / PANEL_COLS))
end

local function syncModalGridMetrics(self)
  local spacingX = self.buttonGap or self.colGap or 0
  self.cellW = cellWForHexGrid(spacingX)
end

local function rebuildPanel(self)
  syncModalGridMetrics(self)
  local cellH = self.cellH
  local spacingY = self.rowGap or 0
  local hexRows = rowspanForHeight(RomHexGrid.contentHeight(), cellH, spacingY)
  local previewRows = rowspanForHeight(self.preview:preferredHeight(), cellH, spacingY)
  local totalRows = hexRows + previewRows + FOOTER_ROWS

  self.panel = Panel.new({
    cols = PANEL_COLS,
    rows = totalRows,
    cellW = self.cellW,
    cellH = cellH,
    padding = self.padding,
    spacingX = self.buttonGap,
    spacingY = spacingY,
    cellPaddingX = self.cellPaddingX,
    cellPaddingY = self.cellPaddingY,
    visible = self.visible,
    title = self.title,
    titleH = self.titleH,
    bgColor = self.bgColor,
    titleBgColor = self.titleBgColor,
    _modalChromeOverBlue = self._modalChromeOverBlue == true,
  })

  local previewRow = hexRows + 1
  local oamRow = previewRow + previewRows
  local buttonRow = oamRow + 1
  local escRow = buttonRow + 1

  self.panel:setCell(1, 1, {
    component = self.hexGrid,
    colspan = PANEL_COLS,
    rowspan = hexRows,
  })
  self.panel:setCell(1, previewRow, {
    component = self.preview,
    colspan = PANEL_COLS,
    rowspan = previewRows,
  })
  -- Labels + values in columns 1-2; Cancel in col 2, Add in col 3.
  self.panel:setCell(1, oamRow, { text = "OAM start:" })
  self.panel:setCell(2, oamRow, { component = self.oamStartField })
  self.panel:setCell(2, buttonRow, { component = self.cancelButton })
  self.panel:setCell(3, buttonRow, { component = self.addButton })
  self.panel:setCell(1, escRow, { text = "Esc) Close", colspan = 2 })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Add sprite",
    padding = nil,
    rowGap = nil,
    buttonGap = nil,
    cellW = nil,
    cellH = nil,
    fieldH = ModalPanelUtils.MODAL_BUTTON_H,
    buttonW = 68,
    buttonH = ModalPanelUtils.MODAL_BUTTON_H,
    bgColor = nil,
    cellPaddingX = nil,
    cellPaddingY = nil,
    onConfirm = nil,
    onCancel = nil,
    targetWindow = nil,
    spriteLayer = nil,
    panel = nil,
    _syncingFromGrid = false,
  }, Dialog)

  self.hexGrid = RomHexGrid.new({
    groupSize = 4,
    maxSelectedStarts = RomHexGrid.MAX_SELECTED_STARTS,
    onSelect = function(addr, selectOpts)
      selectOpts = selectOpts or {}
      self:_onGridSelect(addr, {
        fromGrid = true,
        selectionCapHit = selectOpts.selectionCapHit == true,
      })
    end,
  })
  self.preview = OamSpritePreview.new()
  self.oamStartField = TextField.new({
    width = 104,
    height = self.fieldH,
    mask = "0x000000",
  })
  self.addButton = Button.new({
    text = "Add",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_confirm()
    end,
  })
  self.cancelButton = Button.new({
    text = "Cancel",
    w = self.buttonW,
    h = self.buttonH,
    transparent = true,
    action = function()
      self:_cancel()
    end,
  })

  ModalPanelUtils.applyPanelDefaults(self)
  self.buttonGap = self.colGap
  -- Prefer grid-driven width over the modal default cellW.
  self._uses_modal_default_cellW = false
  syncModalGridMetrics(self)
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible
end

function Dialog:_focusOamField()
  self.oamStartField:setFocused(true)
end

function Dialog:_formatOam(addr)
  return string.format("0x%06X", math.floor(tonumber(addr) or 0))
end

function Dialog:_syncPreviewFromGrid()
  local starts = self.hexGrid:getSelectedStarts()
  local groupColors = {}
  for i = 1, #starts do
    groupColors[i] = self.hexGrid:highlightColorForStartIndex(i)
  end
  local prevH = self._previewPrefH
  self.preview:setSelectedStarts(starts, groupColors)
  local newH = self.preview:preferredHeight()
  self._previewPrefH = newH
  if self.visible and prevH ~= nil and newH ~= prevH and self.panel then
    rebuildPanel(self)
  end
  self:_refreshAddEnabled()
end

function Dialog:_refreshAddEnabled()
  local starts = self.hexGrid and self.hexGrid:getSelectedStarts() or {}
  self.addButton.enabled = #starts > 0
end

function Dialog:_refreshLimitWarning()
  local starts = self.hexGrid and self.hexGrid:getSelectedStarts() or {}
  local adding = #starts
  local existing = countActiveSprites(self.spriteLayer)
  local msg = nil
  -- NES 64 overflow takes priority over the per-Add 8-item cap message.
  if self.isEdit ~= true and (existing + adding > Dialog.NES_SPRITE_LIMIT) then
    msg = Dialog.MSG_NES_LIMIT
  elseif self._hitMax8 == true and self.isEdit ~= true then
    msg = Dialog.MSG_MAX_PER_ADD
  end
  self._limitWarning = msg
end

function Dialog:_onGridSelect(addr, opts)
  opts = opts or {}
  addr = math.floor(tonumber(addr) or 0)
  -- Grid already owns multi-select state; only replace it for programmatic/tests.
  if opts.fromGrid ~= true then
    self.hexGrid:setSelectedAddr(addr, { emit = false })
  end
  if opts.selectionCapHit == true then
    self._hitMax8 = true
  elseif #(self.hexGrid:getSelectedStarts()) < RomHexGrid.MAX_SELECTED_STARTS then
    self._hitMax8 = false
  end
  self._syncingFromGrid = true
  if #(self.hexGrid:getSelectedStarts()) > 0 then
    self.oamStartField:setText(self:_formatOam(addr))
  end
  self._syncingFromGrid = false
  self:_syncPreviewFromGrid()
  self:_refreshLimitWarning()
end

function Dialog:_syncFromOamField()
  if self._syncingFromGrid then
    return
  end
  local addr = select(1, Shared.parseHexAddress(self.oamStartField:getText() or ""))
  if type(addr) ~= "number" then
    return
  end
  -- Do not emit onSelect: that setTexts the field and resets the caret (breaks left/right).
  self.hexGrid:setSelectedAddr(addr, { emit = false })
  self._hitMax8 = false
  self:_syncPreviewFromGrid()
  self:_refreshLimitWarning()
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Add sprite"
  self.targetWindow = opts.window
  self.spriteLayer = opts.spriteLayer
  self.isEdit = opts.isEdit == true
    or (type(opts.primaryButtonText) == "string" and opts.primaryButtonText == "Save")
    or (type(opts.title) == "string" and opts.title:find("Edit", 1, true) ~= nil)
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true
  self._hitMax8 = false
  self._limitWarning = nil

  self.addButton.text = opts.primaryButtonText or "Add"

  local romRaw = type(opts.romRaw) == "string" and opts.romRaw or ""
  self.hexGrid:setRomRaw(romRaw)

  local excludeOccupied = nil
  if self.isEdit and opts.appearanceSprite and type(opts.appearanceSprite.startAddr) == "number" then
    excludeOccupied = math.floor(opts.appearanceSprite.startAddr)
  end
  -- Disabled = starts already in *this* layer only (other OAM-anim layers stay selectable).
  local occupied = collectOccupiedOamStarts(opts.spriteLayer, { excludeStartAddr = excludeOccupied })
  self.hexGrid:setOccupiedStarts(occupied)
  -- Minimap: all in-layer starts (including the sprite being edited) so users can find them after scrolling.
  local minimapStarts = collectOccupiedOamStarts(opts.spriteLayer)
  self.hexGrid:setMinimapMarkers(occupiedMinimapMarkers(minimapStarts, self.hexGrid:getGroupSize()))

  self.preview:setContext({
    romRaw = romRaw,
    spriteLayer = opts.spriteLayer,
    tilesPool = opts.tilesPool,
    appEditState = opts.appEditState,
    -- Edit mode: keep layer flip/palette (and live tile refs when address matches).
    appearanceSprite = opts.appearanceSprite,
  })

  local groupSize = self.hexGrid:getGroupSize()
  local initialAddr
  local selectOpts = { emit = false }
  if self.isEdit then
    local initialText = opts.initialOamStart or ""
    self.oamStartField:setText(initialText)
    initialAddr = select(1, Shared.parseHexAddress(initialText))
    if type(initialAddr) ~= "number" then
      initialAddr = 0
    end
    -- Allow keeping the sprite's current OAM start selected while editing.
    selectOpts.allowOccupied = true
  else
    -- After last disabled group in this layer; 0x00 when the layer has none.
    initialAddr = defaultAddOamStart(occupied, groupSize)
    self.oamStartField:setText(self:_formatOam(initialAddr))
  end
  self.hexGrid:setSelectedAddr(initialAddr, selectOpts)
  if self.isEdit ~= true then
    self.hexGrid:scrollToReveal(initialAddr)
  end
  self:_syncPreviewFromGrid()
  self._previewPrefH = self.preview:preferredHeight()
  self:_refreshLimitWarning()

  self:_focusOamField()
  self.addButton.pressed = false
  self.cancelButton.pressed = false
  self.addButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.oamStartField:setFocused(false)
  self.addButton.pressed = false
  self.cancelButton.pressed = false
  self.addButton.hovered = false
  self.cancelButton.hovered = false
  self.onConfirm = nil
  self.onCancel = nil
  self.targetWindow = nil
  self.spriteLayer = nil
  self.isEdit = false
  self._hitMax8 = false
  self._limitWarning = nil
  if self.hexGrid and self.hexGrid.setOccupiedStarts then
    self.hexGrid:setOccupiedStarts({})
  end
  if self.hexGrid and self.hexGrid.setMinimapMarkers then
    self.hexGrid:setMinimapMarkers({})
  end
  if self.preview then
    self.preview.appearanceSprite = nil
  end
  if self.panel then
    self.panel:setVisible(false)
  end
  self._boxX, self._boxY, self._boxW, self._boxH = nil, nil, nil, nil
end

function Dialog:_containsBox(x, y)
  if self.panel and self._boxX then
    return self.panel:contains(x, y)
  end
  return true
end

function Dialog:getTooltipAt(x, y)
  if not self.visible or not self.panel or not self:_containsBox(x, y) then
    return nil
  end
  return self.panel:getTooltipAt(x, y)
end

function Dialog:_confirm()
  local starts = self.hexGrid and self.hexGrid:getSelectedStarts() or {}
  if #starts == 0 then
    return false
  end
  self:_refreshLimitWarning()
  -- Block Add when the selection would push the sprite layer past the NES OAM cap.
  if self.isEdit ~= true and self._limitWarning == Dialog.MSG_NES_LIMIT then
    return false
  end
  local callback = self.onConfirm
  local targetWindow = self.targetWindow
  if callback then
    -- Drop starts whose 4-byte span overlaps an in-layer sprite.
    if self.isEdit ~= true and self.hexGrid and self.hexGrid.startOverlapsOccupied then
      local filtered = {}
      for _, addr in ipairs(starts) do
        if not self.hexGrid:startOverlapsOccupied(addr) then
          filtered[#filtered + 1] = addr
        end
      end
      starts = filtered
      if #starts == 0 then
        self._limitWarning = Dialog.MSG_ALREADY_IN_LAYER
        return false
      end
    end
    local ok = callback(
      self.oamStartField:getText() or "",
      targetWindow,
      { starts = starts }
    )
    if ok == false then
      return false
    end
  end
  self:hide()
  return true
end

function Dialog:_cancel()
  local callback = self.onCancel
  local targetWindow = self.targetWindow
  self:hide()
  if callback then
    callback(targetWindow)
  end
  return true
end

function Dialog:handleKey(key)
  if not self.visible then return false end
  if key == "escape" then
    self:_cancel()
    return true
  end
  if key == "return" or key == "kpenter" then
    self:_confirm()
    return true
  end
  if key == "tab" then
    self:_focusOamField()
    return true
  end
  if self.oamStartField.focused and self.oamStartField:onKeyPressed(key) then
    -- Only re-sync grid/preview when the key can change the address text.
    if key ~= "left" and key ~= "right" and key ~= "home" and key ~= "end" then
      self:_syncFromOamField()
    end
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  if self.oamStartField.focused then
    local ok = self.oamStartField:onTextInput(text)
    if ok then
      self:_syncFromOamField()
    end
    return ok
  end
  return false
end

function Dialog:mousepressed(x, y, button)
  if not self.visible then return false end
  if button ~= 1 then return true end
  if not self:_containsBox(x, y) then
    self:_cancel()
    return true
  end

  if self.oamStartField:contains(x, y) then
    self:_focusOamField()
  end

  return self.panel and self.panel:mousepressed(x, y, button) or true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  return self.panel and self.panel:mousereleased(x, y, button) or true
end

function Dialog:_syncPreviewHoverFromGrid()
  if not (self.preview and self.hexGrid) then
    return
  end
  self.preview:setHoveredStart(self.hexGrid:getHoveredSelectedStart())
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end
  if self.panel then
    self.panel:mousemoved(x, y)
  end
  self:_syncPreviewHoverFromGrid()
  return true
end

function Dialog:wheelmoved(dx, dy)
  if not self.visible then return false end
  local mx, my = 0, 0
  if ResolutionController and ResolutionController.getScaledMouse then
    local mouse = ResolutionController:getScaledMouse(true)
    mx = mouse and mouse.x or 0
    my = mouse and mouse.y or 0
  elseif love and love.mouse and love.mouse.getPosition then
    mx, my = love.mouse.getPosition()
  end
  return self.hexGrid:wheelmovedAt(dx, dy, mx, my)
end

function Dialog:draw(canvas)
  if not self.visible then return end
  ModalPanelUtils.refreshTargetMetrics(self)
  syncModalGridMetrics(self)
  -- Do not rebuild the Panel each frame: each rebuild creates a new Panel and drops `pressedButton`
  -- captured on mouse pressed, so mousereleased never fires Save/Cancel.
  if not self.panel then
    rebuildPanel(self)
  else
    self.panel.cellW = self.cellW
    self.panel.cellH = self.cellH
    self.panel.padding = self.padding
    self.panel.spacingX = self.buttonGap
    self.panel.spacingY = self.rowGap
    self.panel.cellPaddingX = self.cellPaddingX
    self.panel.cellPaddingY = self.cellPaddingY
    self.panel.title = self.title
    self.panel.titleH = self.titleH
    self.panel.bgColor = self.bgColor
    self.panel.titleBgColor = self.titleBgColor
    ModalPanelUtils.syncPanelChrome(self.panel, self)
    self.panel:setVisible(true)
  end
  ModalPanelUtils.drawBackdrop(canvas)
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas)
  self:_syncPreviewHoverFromGrid()
  self.panel:draw()
  self:_drawLimitWarning()
end

function Dialog:_drawLimitWarning()
  local msg = self._limitWarning
  if type(msg) ~= "string" or msg == "" then
    return
  end
  if not (self._boxX and self._boxY and self._boxW and self._boxH) then
    return
  end
  local font = nil
  if love and love.graphics and love.graphics.getFont then
    local ok, f = pcall(love.graphics.getFont)
    if ok then font = f end
  end
  local tw = Text.getFontWidth(msg, font)
  local th = font and font.getHeight and font:getHeight() or 10
  local pad = math.max(2, math.floor(tonumber(self.padding) or 2))
  local x = self._boxX + self._boxW - pad - tw
  local y = self._boxY + self._boxH - pad - th
  Text.print(msg, x, y, {
    color = colors.yellow,
    font = font,
    literalColor = true,
  })
end

return Dialog
