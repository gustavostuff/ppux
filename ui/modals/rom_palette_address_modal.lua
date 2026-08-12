local Button = require("ui.button")
local Checkbox = require("ui.checkbox")
local Panel = require("ui.panel")
local TextField = require("ui.text_field")
local Text = require("utils.text_utils")
local ModalPanelUtils = require("ui.modals.panel_modal_utils")
local RomHexGrid = require("ui.rom_hex_grid")
local Shared = require("controllers.app.core_controller_shared")
local ResolutionController = require("controllers.app.resolution_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local Palettes = require("palettes")
local Draw = require("utils.draw_utils")
local images = require("images")
local colors = require("app_colors")
local chr = require("chr")

-- Enter color address: ROM hex grid + color preview(s) + address field.
-- New cells: "Selected". Already-bound cells: "Base ROM color" + "User override".

local Dialog = {}
Dialog.__index = Dialog

local FOOTER_ROWS_DEFAULT = 5 -- Hide-invalid, Selected, address, buttons, Esc
local FOOTER_ROWS_WITH_OVERRIDE = 6 -- Hide-invalid, Base, User override, address, buttons, Esc
local PANEL_COLS = 3
local SWATCH_PX = 11
local SELECTION_RECT_ANIM = {
  stepPx = 1,
  intervalSeconds = 0.1,
}

-- Forbidden / redundant / out-of-bounds NES palette indices (not valid color codes).
local INVALID_NES_COLOR = {
  [0x0D] = true,
  [0x0E] = true, [0x1E] = true, [0x2E] = true, [0x3E] = true,
  [0x1F] = true, [0x2F] = true, [0x3F] = true,
}

local function trim(text)
  text = tostring(text or "")
  return text:match("^%s*(.-)%s*$")
end

function Dialog.isValidNesPaletteByte(byte)
  byte = math.floor(tonumber(byte) or -1)
  if byte < 0 or byte > 0x3F then
    return false
  end
  return INVALID_NES_COLOR[byte] ~= true
end

--- Addresses on the visible hex page whose ROM byte is a valid NES palette color.
function Dialog.collectValidColorAddrsOnPage(romRaw, scrollOffset, bytesPerPage)
  local starts = {}
  if type(romRaw) ~= "string" then
    return starts
  end
  local len = #romRaw
  local pageStart = math.max(0, math.floor(tonumber(scrollOffset) or 0))
  local pageBytes = math.max(1, math.floor(tonumber(bytesPerPage) or RomHexGrid.BYTES_PER_PAGE))
  local pageEnd = pageStart + pageBytes - 1
  for addr = pageStart, pageEnd do
    if addr >= 0 and addr < len then
      local byte = string.byte(romRaw, addr + 1) or 0
      if Dialog.isValidNesPaletteByte(byte) then
        starts[#starts + 1] = addr
      end
    end
  end
  return starts
end

local function nesCodeFromByte(byte)
  byte = math.floor(tonumber(byte) or 0x0F) % 256
  -- Out-of-bounds codes mirror $00-$3F for display.
  if byte > 0x3F then
    byte = byte % 0x40
  end
  return string.format("%02X", byte)
end

local function rgbForNesCode(code)
  local paletteName = ShaderPaletteController.paletteName or "smooth_fbx"
  local p = Palettes[paletteName] or Palettes.smooth_fbx
  local rgb = p and p[code]
  if type(rgb) == "table" and type(rgb[1]) == "number" then
    return { rgb[1], rgb[2] or 0, rgb[3] or 0, rgb[4] or 1 }
  end
  return { 0, 0, 0, 1 }
end

-- When true, Enter-color minimap marks every bound address from all ROM palette
-- windows (not only the one being edited). Dev/config flag; not user-facing.
Dialog.MINIMAP_MARK_ALL_ROM_PALETTES = false

--- Collect bound ROM addresses and their palette UI cell colors.
local function collectBoundAddrColors(win)
  local byAddr = {}
  if type(win) ~= "table" then
    return byAddr
  end
  local romColors = win.paletteData and win.paletteData.romColors
  if type(romColors) ~= "table" then
    return byAddr
  end
  local rows = math.max(0, math.floor(tonumber(win.rows) or 4))
  local cols = math.max(0, math.floor(tonumber(win.cols) or 4))
  for r = 0, rows - 1 do
    local rowLine = romColors[r + 1]
    if type(rowLine) == "table" then
      for c = 0, cols - 1 do
        local addr = rowLine[c + 1]
        if type(addr) == "number" then
          local offset = math.floor(addr)
          local code = win.codes2D and win.codes2D[r] and win.codes2D[r][c]
          if type(code) == "string" and code ~= "" then
            byAddr[offset] = tostring(code):upper()
          else
            byAddr[offset] = "0F"
          end
        end
      end
    end
  end
  return byAddr
end

local function mergeBoundAddrColors(dst, src, overwrite)
  for addr, code in pairs(src or {}) do
    if overwrite or dst[addr] == nil then
      dst[addr] = code
    end
  end
end

--- Resolve the ROM palette window list used for minimap marks.
local function resolveRomPaletteWindowsForMinimap(primaryWin, opts)
  opts = opts or {}
  if not Dialog.MINIMAP_MARK_ALL_ROM_PALETTES then
    return { primaryWin }
  end
  local list = opts.romPaletteWindows
  if type(list) ~= "table" or #list == 0 then
    local gctx = rawget(_G, "ctx")
    local app = gctx and gctx.app
    if app and app.wm and app.wm.getWindowsOfKind then
      list = app.wm:getWindowsOfKind("rom_palette")
    end
  end
  if type(list) ~= "table" or #list == 0 then
    return { primaryWin }
  end
  return list
end

--- Minimap marks for ROM addresses bound to palette UI cells.
--- One 1px marker per bound byte, tinted with that cell's NES UI color (zoom track is cols-wide).
--- When MINIMAP_MARK_ALL_ROM_PALETTES is true, includes every ROM palette window.
function Dialog.collectBoundRomColorMinimapMarkers(win, _romRaw, opts)
  local markers = {}
  local windows = resolveRomPaletteWindowsForMinimap(win, opts)
  local boundAddrColors = {}
  for _, w in ipairs(windows) do
    if w ~= nil and w ~= win then
      mergeBoundAddrColors(boundAddrColors, collectBoundAddrColors(w), false)
    end
  end
  -- Prefer the palette currently being edited when addresses collide.
  mergeBoundAddrColors(boundAddrColors, collectBoundAddrColors(win), true)

  local addrs = {}
  for addr in pairs(boundAddrColors) do
    addrs[#addrs + 1] = addr
  end
  table.sort(addrs)
  for _, addr in ipairs(addrs) do
    local code = boundAddrColors[addr] or "0F"
    local rgb = rgbForNesCode(code)
    markers[#markers + 1] = {
      offset = addr,
      color = { rgb[1], rgb[2], rgb[3], 0.9 },
      groupCount = 1,
      groupSize = 1,
    }
  end
  return markers
end

local function rowspanForHeight(height, cellH, spacingY)
  cellH = math.max(1, math.floor(tonumber(cellH) or 15))
  spacingY = math.max(0, math.floor(tonumber(spacingY) or 0))
  local step = cellH + spacingY
  return math.max(1, math.ceil((math.max(1, height) + spacingY) / step))
end

--- Drop a wasted panel row when ceil overshoots (closes gap above Hide invalid).
local function rowspanForHeightTight(height, cellH, spacingY)
  local rows = rowspanForHeight(height, cellH, spacingY)
  cellH = math.max(1, math.floor(tonumber(cellH) or 15))
  spacingY = math.max(0, math.floor(tonumber(spacingY) or 0))
  local step = cellH + spacingY
  local used = rows * step - spacingY
  if rows > 1 and (used - height) >= math.max(1, cellH - 2) then
    rows = rows - 1
  end
  return math.max(1, rows)
end

local function cellWForHexGrid(spacingX, cols, panelCols)
  local gridW = RomHexGrid.contentWidth(cols)
  spacingX = math.max(0, math.floor(tonumber(spacingX) or 0))
  panelCols = math.max(1, math.floor(tonumber(panelCols) or 2))
  local gaps = spacingX * math.max(0, panelCols - 1)
  return math.max(1, math.ceil((gridW - gaps) / panelCols))
end

----------------------------------------------------------------
-- Selected color preview (label handled by panel; this is swatch + $HH)
----------------------------------------------------------------

local SelectedPreview = {}
SelectedPreview.__index = SelectedPreview

function SelectedPreview.new(opts)
  opts = opts or {}
  return setmetatable({
    x = 0,
    y = 0,
    w = 72,
    h = ModalPanelUtils.MODAL_BUTTON_H,
    code = nil,
    rgb = { 0, 0, 0, 1 },
    showAnts = opts.showAnts ~= false,
  }, SelectedPreview)
end

function SelectedPreview:setColorCode(code)
  if type(code) ~= "string" or code == "" then
    self.code = nil
    self.rgb = { 0, 0, 0, 1 }
    return
  end
  self.code = code:upper()
  self.rgb = rgbForNesCode(self.code)
end

function SelectedPreview:setPosition(x, y)
  self.x = math.floor(tonumber(x) or 0)
  self.y = math.floor(tonumber(y) or 0)
end

function SelectedPreview:setSize(w, h)
  if type(w) == "number" then self.w = math.floor(w) end
  if type(h) == "number" then self.h = math.floor(h) end
end

function SelectedPreview:getWidth()
  return self.w
end

function SelectedPreview:getHeight()
  return self.h
end

function SelectedPreview:contains(px, py)
  return px >= self.x and px < self.x + self.w
    and py >= self.y and py < self.y + self.h
end

function SelectedPreview:draw()
  local font = nil
  if love and love.graphics and love.graphics.getFont then
    local ok, f = pcall(love.graphics.getFont)
    if ok then font = f end
  end
  local cy = self.y + math.floor((self.h - SWATCH_PX) * 0.5)
  local sx = self.x
  if self.code then
    local rgb = self.rgb
    love.graphics.setColor(rgb[1], rgb[2], rgb[3], rgb[4] or 1)
    love.graphics.rectangle("fill", sx, cy, SWATCH_PX, SWATCH_PX)
    if self.showAnts and images.pattern_a then
      love.graphics.setColor(1, 1, 1, 1)
      Draw.drawRepeatingImageAnimated(
        images.pattern_a,
        sx,
        cy,
        SWATCH_PX,
        SWATCH_PX,
        SELECTION_RECT_ANIM
      )
    end
    local label = "$" .. self.code
    local tw = Text.getFontWidth(label, font)
    local ty = self.y + math.floor((self.h - (font and font.getHeight and font:getHeight() or 10)) * 0.5)
    Text.print(label, sx + SWATCH_PX + 4, ty, {
      color = colors.white,
      font = font,
      literalColor = true,
    })
    self.w = math.max(72, SWATCH_PX + 4 + tw + 2)
  else
    Text.print("-", sx, self.y + 2, {
      color = colors.gray75,
      font = font,
      literalColor = true,
    })
  end
  love.graphics.setColor(1, 1, 1, 1)
end

----------------------------------------------------------------
-- Modal
----------------------------------------------------------------

local function syncModalGridMetrics(self)
  local spacingX = self.buttonGap or self.colGap or 0
  local cols = (self.hexGrid and self.hexGrid.getCols and self.hexGrid:getCols()) or 16
  self.cellW = cellWForHexGrid(spacingX, cols, PANEL_COLS)
end

local function rebuildPanel(self)
  syncModalGridMetrics(self)
  local cellH = self.cellH
  local spacingY = self.rowGap or 0
  local hexRows = rowspanForHeightTight(RomHexGrid.contentHeight(), cellH, spacingY)
  local showOverride = self._showUserOverride == true
  local footerRows = showOverride and FOOTER_ROWS_WITH_OVERRIDE or FOOTER_ROWS_DEFAULT
  local totalRows = hexRows + footerRows

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

  local hideRow = hexRows + 1
  local colorRow = hideRow + 1
  local overrideRow = showOverride and (colorRow + 1) or nil
  local addrRow = (overrideRow or colorRow) + 1
  local buttonRow = addrRow + 1
  local escRow = buttonRow + 1

  self.panel:setCell(1, 1, {
    component = self.hexGrid,
    colspan = PANEL_COLS,
    rowspan = hexRows,
  })
  self.panel:setCell(1, hideRow, {
    component = self.hideInvalidCheckbox,
    colspan = PANEL_COLS,
  })
  -- Labels + values in columns 1-2; Cancel in col 2, Set in col 3.
  local colorLabel = showOverride and "Base ROM color:" or "Selected:"
  self.panel:setCell(1, colorRow, { text = colorLabel })
  self.panel:setCell(2, colorRow, { component = self.selectedPreview })
  if showOverride then
    self.panel:setCell(1, overrideRow, { text = "User override:" })
    self.panel:setCell(2, overrideRow, { component = self.overridePreview })
  end
  self.panel:setCell(1, addrRow, { text = "Address:" })
  self.panel:setCell(2, addrRow, { component = self.textField })
  self.panel:setCell(2, buttonRow, { component = self.cancelButton })
  self.panel:setCell(3, buttonRow, { component = self.setButton })
  self.panel:setCell(1, escRow, { text = "Esc) Close", colspan = 2 })
end

function Dialog.new()
  local self = setmetatable({
    visible = false,
    title = "Enter color address",
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
    targetCol = nil,
    targetRow = nil,
    romRaw = "",
    panel = nil,
    _syncingFromGrid = false,
    _invalidColorWarning = nil,
    _showUserOverride = false,
  }, Dialog)

  self.hexGrid = RomHexGrid.new({
    cols = 16,
    groupSize = 1,
    maxSelectedStarts = 1,
    defaultCellStyle = "ninja",
    selectionAnts = true,
    boundAsSelected = true,
    selectionCrosshair = true,
    rejectedCellStyle = "hidden",
    -- Bound palette addresses: Selected fills via minimap markers (boundAsSelected).
    semiColorForAddr = function(addr)
      return self:_nesFillColorForAddr(addr, 1)
    end,
    selectedColorForAddr = function(addr)
      return self:_nesFillColorForAddr(addr, 1)
    end,
    canSelectAddr = function(addr)
      return self:_isValidColorAddr(addr)
    end,
    onRejectSelect = function()
      -- Hidden invalid cells clear selection silently; ninja mode still warns.
      if self:isHideInvalidColors() then
        self._invalidColorWarning = nil
      else
        self._invalidColorWarning = "Not a valid color"
      end
      self.hexGrid:_setStarts({}, 0, {
        emit = false,
        allowEmpty = true,
        resetColors = true,
        scrollToReveal = false,
      })
      self._syncingFromGrid = true
      self.textField:setText("")
      self:_refreshSelectedPreview(nil)
      self._syncingFromGrid = false
      self:_refreshSetEnabled()
    end,
    onSelect = function(addr, selectOpts)
      selectOpts = selectOpts or {}
      self._invalidColorWarning = nil
      self:_onGridSelect(addr, {
        fromGrid = true,
        selectionCapHit = selectOpts.selectionCapHit == true,
      })
    end,
    onScroll = function()
      self:_refreshSemiSelected()
    end,
  })
  self.hideInvalidCheckbox = Checkbox.new({
    text = "Hide invalid colors",
    checked = true,
    onChange = function(checked)
      self:_onHideInvalidChanged(checked == true)
    end,
  })
  self.selectedPreview = SelectedPreview.new({ showAnts = true })
  self.overridePreview = SelectedPreview.new({ showAnts = false })
  self.textField = TextField.new({
    width = 104,
    height = self.fieldH,
    mask = "0x000000",
  })
  self.setButton = Button.new({
    text = "Set",
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
  self._uses_modal_default_cellW = false
  syncModalGridMetrics(self)
  rebuildPanel(self)
  return self
end

function Dialog:isVisible()
  return self.visible
end

function Dialog:_focusAddressField()
  self.textField:setFocused(true)
end

function Dialog:_formatAddr(addr)
  return string.format("0x%06X", math.floor(tonumber(addr) or 0))
end

function Dialog:_byteAt(addr)
  addr = math.floor(tonumber(addr) or -1)
  if addr < 0 or type(self.romRaw) ~= "string" or addr >= #self.romRaw then
    return nil
  end
  return string.byte(self.romRaw, addr + 1)
end

--- Effective NES code for Base ROM preview / hex paints at `addr`.
--- At the cell's bound address, prefer the captured base (romRaw may already hold the override).
function Dialog:_displayCodeAt(addr)
  addr = math.floor(tonumber(addr) or -1)
  if self._boundAddr ~= nil
      and addr == self._boundAddr
      and type(self._baseRomCode) == "string"
      and self._baseRomCode ~= "" then
    return self._baseRomCode
  end
  local byte = self:_byteAt(addr)
  if byte == nil then
    return nil
  end
  if not Dialog.isValidNesPaletteByte(byte) then
    return nil
  end
  return nesCodeFromByte(byte)
end

function Dialog:_isValidColorAddr(addr)
  -- Bound address stays selectable even when live romRaw holds an invalid override byte.
  if self._boundAddr ~= nil and math.floor(tonumber(addr) or -1) == self._boundAddr then
    if type(self._baseRomCode) == "string" and self._baseRomCode ~= "" then
      local b = tonumber(self._baseRomCode, 16)
      if b ~= nil and Dialog.isValidNesPaletteByte(b) then
        return true
      end
    end
  end
  local byte = self:_byteAt(addr)
  if byte == nil then
    return false
  end
  return Dialog.isValidNesPaletteByte(byte)
end

function Dialog:_nesFillColorForAddr(addr, alpha)
  local code = self:_displayCodeAt(addr)
  if code == nil then
    return { 1, 1, 1, alpha or 0.5 }
  end
  local rgb = rgbForNesCode(code)
  return { rgb[1], rgb[2], rgb[3], alpha or 0.5 }
end

function Dialog:_refreshSemiSelected()
  local starts = Dialog.collectValidColorAddrsOnPage(
    self.romRaw,
    self.hexGrid.scrollOffset,
    self.hexGrid:bytesPerPage()
  )
  -- Ensure the bound address stays semi-selectable when we restored its base for display.
  if self._boundAddr ~= nil and self:_isValidColorAddr(self._boundAddr) then
    local pageStart = math.max(0, math.floor(tonumber(self.hexGrid.scrollOffset) or 0))
    local pageEnd = pageStart + self.hexGrid:bytesPerPage() - 1
    if self._boundAddr >= pageStart and self._boundAddr <= pageEnd then
      local found = false
      for _, a in ipairs(starts) do
        if a == self._boundAddr then
          found = true
          break
        end
      end
      if not found then
        starts[#starts + 1] = self._boundAddr
      end
    end
  end
  self.hexGrid:setSemiSelectedStarts(starts)
end

--- Recompute page semi fills only when the visible hex page moved.
function Dialog:_refreshSemiSelectedIfScrolled(prevScroll)
  if self.hexGrid.scrollOffset ~= prevScroll then
    self:_refreshSemiSelected()
    return true
  end
  return false
end

function Dialog:_refreshSelectedPreview(addr)
  local code = self:_displayCodeAt(addr)
  if code == nil then
    self.selectedPreview:setColorCode(nil)
    return
  end
  self.selectedPreview:setColorCode(code)
end

--- Snapshot romRaw with the bound address restored to the captured base for hex display.
local function romRawWithBaseRestored(romRaw, boundAddr, baseRomCode)
  if type(romRaw) ~= "string" or type(boundAddr) ~= "number" then
    return romRaw
  end
  if type(baseRomCode) ~= "string" or baseRomCode == "" then
    return romRaw
  end
  local byte = tonumber(baseRomCode, 16)
  if byte == nil then
    return romRaw
  end
  local newRom, err = chr.writeByteToAddress(romRaw, boundAddr, byte)
  if not newRom or err then
    return romRaw
  end
  return newRom
end

function Dialog:_refreshSetEnabled()
  local starts = self.hexGrid and self.hexGrid:getSelectedStarts() or {}
  self.setButton.enabled = #starts > 0
end

function Dialog:_onGridSelect(addr, opts)
  opts = opts or {}
  addr = math.floor(tonumber(addr) or 0)
  if opts.fromGrid ~= true then
    self.hexGrid:setSelectedAddr(addr, { emit = false })
  end
  local starts = self.hexGrid:getSelectedStarts()
  self._syncingFromGrid = true
  if #starts > 0 then
    self.textField:setText(self:_formatAddr(starts[1]))
    self:_refreshSelectedPreview(starts[1])
  else
    self:_refreshSelectedPreview(nil)
  end
  self._syncingFromGrid = false
  self:_refreshSetEnabled()
end

function Dialog:_syncFromAddressField()
  if self._syncingFromGrid then
    return
  end
  local addr = select(1, Shared.parseHexAddress(self.textField:getText() or ""))
  if type(addr) ~= "number" then
    return
  end
  local prevScroll = self.hexGrid.scrollOffset
  if self:_isValidColorAddr(addr) then
    self._invalidColorWarning = nil
    self.hexGrid:setSelectedAddr(addr, { emit = false })
    self:_refreshSelectedPreview(addr)
  else
    self._invalidColorWarning = "Not a valid color"
    self.hexGrid:_setStarts({}, addr, {
      emit = false,
      allowEmpty = true,
      resetColors = true,
      scrollToReveal = true,
    })
    self:_refreshSelectedPreview(nil)
  end
  self:_refreshSemiSelectedIfScrolled(prevScroll)
  self:_refreshSetEnabled()
end

--- Cursor over this modal: hand on interactive cells; hidden invalid → arrow.
function Dialog:cursorNameAt(mx, my)
  if not self.visible then
    return nil
  end
  if self.panel and type(self.panel.getButtonAt) == "function" and self.panel:getButtonAt(mx, my) then
    return "hand"
  end
  if self.hideInvalidCheckbox and self.hideInvalidCheckbox.contains
      and self.hideInvalidCheckbox:contains(mx, my) then
    return "hand"
  end
  if self.textField and self.textField.contains and self.textField:contains(mx, my) then
    return "hand"
  end
  local grid = self.hexGrid
  if grid and type(grid.cursorNameAt) == "function" then
    local name = grid:cursorNameAt(mx, my)
    if type(name) == "string" then
      return name
    end
  end
  return "arrow"
end

function Dialog:_onHideInvalidChanged(hide)
  if self.hexGrid then
    self.hexGrid.rejectedCellStyle = hide and "hidden" or "ninja"
  end
end

function Dialog:isHideInvalidColors()
  return self.hideInvalidCheckbox and self.hideInvalidCheckbox:isChecked()
end

function Dialog:show(opts)
  opts = opts or {}
  self.title = opts.title or "Enter color address"
  self.targetWindow = opts.window
  self.targetCol = opts.col
  self.targetRow = opts.row
  self.onConfirm = opts.onConfirm
  self.onCancel = opts.onCancel
  self.visible = true
  local sourceRom = type(opts.romRaw) == "string" and opts.romRaw or ""
  self._invalidColorWarning = nil
  self._boundAddr = type(opts.boundAddr) == "number" and math.floor(opts.boundAddr) or nil
  self._baseRomCode = nil
  if type(opts.baseRomCode) == "string" and opts.baseRomCode ~= "" then
    self._baseRomCode = tostring(opts.baseRomCode):upper()
  end

  local overrideCode = opts.userOverrideCode
  if type(overrideCode) == "string" and overrideCode ~= "" then
    self._showUserOverride = true
    self.overridePreview:setColorCode(overrideCode)
  else
    self._showUserOverride = false
    self.overridePreview:setColorCode(nil)
    self._boundAddr = nil
    self._baseRomCode = nil
  end

  -- Hex grid must show the captured base at the bound address (live romRaw holds the override).
  self.romRaw = romRawWithBaseRestored(sourceRom, self._boundAddr, self._baseRomCode)
  self.hexGrid:setRomRaw(self.romRaw)
  self.hexGrid:setDisabledStarts({})
  -- Default: hide invalid colors (empty cells, arrow cursor; click still clears).
  if self.hideInvalidCheckbox then
    self.hideInvalidCheckbox:setChecked(true, { silent = true })
  end
  self.hexGrid.rejectedCellStyle = "hidden"
  self.hexGrid:setMinimapMarkers(
    Dialog.collectBoundRomColorMinimapMarkers(self.targetWindow, self.romRaw, {
      romPaletteWindows = opts.romPaletteWindows,
    })
  )

  local initialText = opts.initialAddress or ""
  self.textField:setText(initialText)
  local initialAddr = select(1, Shared.parseHexAddress(initialText))
  if type(initialAddr) ~= "number" then
    initialAddr = 0
  end
  if initialText ~= "" and self:_isValidColorAddr(initialAddr) then
    self.hexGrid:setSelectedAddr(initialAddr, { emit = false })
    self:_refreshSelectedPreview(initialAddr)
  else
    if initialText ~= "" then
      self._invalidColorWarning = "Not a valid color"
      self.hexGrid:_setStarts({}, initialAddr, {
        emit = false,
        allowEmpty = true,
        resetColors = true,
        scrollToReveal = true,
      })
    else
      self.hexGrid:_setStarts({}, 0, { emit = false, allowEmpty = true, resetColors = true })
    end
    self:_refreshSelectedPreview(nil)
  end
  self:_refreshSemiSelected()
  self:_refreshSetEnabled()

  self:_focusAddressField()
  self.setButton.pressed = false
  self.cancelButton.pressed = false
  self.setButton.hovered = false
  self.cancelButton.hovered = false
  rebuildPanel(self)
end

function Dialog:hide()
  self.visible = false
  self.textField:setFocused(false)
  self.setButton.pressed = false
  self.cancelButton.pressed = false
  self.setButton.hovered = false
  self.cancelButton.hovered = false
  self.onConfirm = nil
  self.onCancel = nil
  self.targetWindow = nil
  self.targetCol = nil
  self.targetRow = nil
  self.romRaw = ""
  self._invalidColorWarning = nil
  self._showUserOverride = false
  self._boundAddr = nil
  self._baseRomCode = nil
  if self.overridePreview then
    self.overridePreview:setColorCode(nil)
  end
  if self.hexGrid then
    self.hexGrid:setSemiSelectedStarts({})
    self.hexGrid:setMinimapMarkers({})
    self.hexGrid:setRomRaw("")
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
  if self.setButton and self.setButton.enabled == false then
    return false
  end
  local starts = self.hexGrid and self.hexGrid:getSelectedStarts() or {}
  if #starts == 0 then
    return false
  end
  local raw = self.textField:getText() or ""
  local value = trim(raw)
  if value == "" then
    return false
  end

  local callback = self.onConfirm
  local targetWindow = self.targetWindow
  local targetCol = self.targetCol
  local targetRow = self.targetRow

  if callback then
    local ok = callback(value, targetWindow, targetCol, targetRow)
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
  local targetCol = self.targetCol
  local targetRow = self.targetRow
  self:hide()
  if callback then
    callback(targetWindow, targetCol, targetRow)
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
    self:_focusAddressField()
    return true
  end
  if self.textField.focused and self.textField:onKeyPressed(key) then
    if key ~= "left" and key ~= "right" and key ~= "home" and key ~= "end" then
      self:_syncFromAddressField()
    end
    return true
  end
  return false
end

function Dialog:textinput(text)
  if not self.visible then return false end
  if self.textField.focused then
    local ok = self.textField:onTextInput(text)
    if ok then
      self:_syncFromAddressField()
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

  if self.textField:contains(x, y) then
    self:_focusAddressField()
  end

  return self.panel and self.panel:mousepressed(x, y, button) or true
end

function Dialog:mousereleased(x, y, button)
  if not self.visible then return false end
  if self.hexGrid then
    self.hexGrid:mousereleased(x, y, button)
  end
  return self.panel and self.panel:mousereleased(x, y, button) or true
end

function Dialog:mousemoved(x, y)
  if not self.visible then return false end
  if self.hexGrid then
    self.hexGrid:mousemoved(x, y)
  end
  if self.panel and not (self.hexGrid and self.hexGrid:isScrollDragging()) then
    self.panel:mousemoved(x, y)
  end
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
  -- onScroll callback refreshes semi-select when the page moves.
  return self.hexGrid:wheelmovedAt(dx, dy, mx, my)
end

function Dialog:draw(canvas)
  if not self.visible then return end
  ModalPanelUtils.refreshTargetMetrics(self)
  syncModalGridMetrics(self)
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
  self._boxX, self._boxY, self._boxW, self._boxH = ModalPanelUtils.centerPanel(self.panel, canvas, self)
  self.panel:draw()
  self:_drawInvalidColorWarning()
end

function Dialog:_drawInvalidColorWarning()
  local msg = self._invalidColorWarning
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
