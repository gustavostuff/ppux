-- ppu_frame_add_sprite_modal_scan.test.lua
-- Scan checkbox layout + one-shot OAM heuristic scan for Add sprite.

local Dialog = require("ui.modals.ppu_frame_add_sprite_modal")
local RomHexGrid = require("ui.rom_hex_grid")

local function validSpriteLayer(extra)
  local layer = {
    kind = "sprite",
    linkedPatternTableWindowId = "pt_win",
    patternTable = {
      ranges = {
        { from = 0, to = 255, bank = 1 },
      },
    },
    items = {},
  }
  if extra then
    for k, v in pairs(extra) do
      layer[k] = v
    end
  end
  return layer
end

local function plantAt(romSize, offset, bytes, fill)
  fill = fill or 0x80
  local buf = {}
  for i = 1, romSize do
    buf[i] = fill
  end
  for i = 1, #bytes do
    buf[offset + i] = bytes[i] % 256
  end
  local parts = {}
  for i = 1, #buf do
    parts[i] = string.char(buf[i])
  end
  return table.concat(parts)
end

local function oam(y, tile, attr, x)
  return { y, tile, attr, x }
end

local function concatRecords(...)
  local out = {}
  for _, rec in ipairs({ ... }) do
    for i = 1, #rec do
      out[#out + 1] = rec[i]
    end
  end
  return out
end

local function plantMany(romSize, fill, placements)
  fill = fill or 0x80
  local buf = {}
  for i = 1, romSize do
    buf[i] = fill
  end
  for _, p in ipairs(placements or {}) do
    local bytes = p.bytes or {}
    for i = 1, #bytes do
      buf[p.offset + i] = bytes[i] % 256
    end
  end
  local parts = {}
  for i = 1, #buf do
    parts[i] = string.char(buf[i])
  end
  return table.concat(parts)
end

local function panelCellFor(modal, component)
  for _, cell in ipairs(modal.panel:_iterCells()) do
    if cell.component == component then
      return cell
    end
  end
  return nil
end

describe("Add sprite modal Scan mode", function()
  it("places Cancel/Add one column left and Scan to the right of the hex field", function()
    local modal = Dialog.new()
    modal:show({
      romRaw = string.rep("\0", 256),
      spriteLayer = validSpriteLayer({ items = {} }),
      tilesPool = { [1] = {} },
    })
    local cancelCell = panelCellFor(modal, modal.cancelButton)
    local addCell = panelCellFor(modal, modal.addButton)
    local scanCell = panelCellFor(modal, modal.scannedModeCheckbox)
    local fieldCell = panelCellFor(modal, modal.oamStartField)
    expect(cancelCell).toBeTruthy()
    expect(addCell).toBeTruthy()
    expect(scanCell).toBeTruthy()
    expect(fieldCell).toBeTruthy()
    expect(cancelCell.col).toBe(1)
    expect(addCell.col).toBe(2)
    expect(cancelCell.row).toBe(addCell.row)
    expect(scanCell.col).toBe(3)
    expect(scanCell.row).toBe(fieldCell.row)
    expect(modal.scannedModeCheckbox.text).toBe("Scan")
    expect(modal:isScannedMode()).toBe(false)
    modal:hide()
  end)

  it("scans once, underlines hits, and click-toggles every sprite in a hit", function()
    local pad = 32
    local bytes = { 16, 0x10, 0, 40, 16, 0x11, 1, 48 }
    local rom = plantAt(256, pad, bytes, 0x80)
    local modal = Dialog.new()
    modal:show({
      romRaw = rom,
      spriteLayer = validSpriteLayer({ items = {} }),
      tilesPool = { [1] = {} },
    })
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(0)
    expect(modal.hexGrid.replaceSelect).toBe(false)

    modal.scannedModeCheckbox:setChecked(true)
    expect(modal:isScannedMode()).toBe(true)
    expect(modal._scanComputed).toBe(true)
    expect(modal.hexGrid.replaceSelect).toBe(true)
    local underlined = modal.hexGrid:getUnderlinedStarts()
    expect(#underlined).toBeGreaterThan(0)
    expect(modal.hexGrid:getUnderlinedGroupSize(pad)).toBe(8)

    -- Click anywhere in the pair selects both 4-byte items.
    modal:_onGridSelect(pad + 2, { fromGrid = true })
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ pad, pad + 4 })
    expect(modal.hexGrid:getUserSelectedStarts()).toEqual({ pad + 2 })
    local selectedFill = modal.hexGrid:_selectedFillColorForStart(pad)
    local scanTint = modal.hexGrid:highlightColorForStart(pad)
    expect(selectedFill[1]).toBe(scanTint[1])
    expect(selectedFill[2]).toBe(scanTint[2])
    expect(selectedFill[3]).toBe(scanTint[3])

    -- Click same hit again → toggles the whole pair off.
    modal:_onGridSelect(pad + 1, { fromGrid = true })
    expect(modal.hexGrid:getSelectedStarts()).toEqual({})
    expect(#(modal.hexGrid:getUserSelectedStarts())).toBe(0)

    modal:_onGridSelect(pad, { fromGrid = true })
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ pad, pad + 4 })

    -- Outside any scan hit → no-op.
    modal:_onGridSelect(0x08, { fromGrid = true })
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ pad, pad + 4 })

    -- Grid mousepressed on a selected group must emit (replaceSelect + multi-select).
    modal.hexGrid:setPosition(0, 0)
    modal.hexGrid:scrollToReveal(pad)
    local cols = modal.hexGrid:getCols()
    local rel = pad - (modal.hexGrid.scrollOffset or 0)
    local col = rel % cols
    local row = math.floor(rel / cols)
    local hx = 2 + 38 + col * 15 + 2
    local hy = 2 + 12 + row * 11 + 2
    modal.hexGrid:mousepressed(hx, hy, 1)
    expect(modal.hexGrid:getSelectedStarts()).toEqual({})

    -- Re-toggle: scan is not recomputed.
    local hitsBefore = modal.scanHits
    modal.scannedModeCheckbox:setChecked(false)
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(0)
    expect(modal.hexGrid.replaceSelect).toBe(false)
    modal.scannedModeCheckbox:setChecked(true)
    expect(modal.scanHits).toBe(hitsBefore)
    expect(modal._scanComputed).toBe(true)
    expect(#(modal.hexGrid:getUnderlinedStarts())).toBe(#underlined)
    modal:hide()
  end)

  it("keeps occupied gray minimap markers when Scan is on", function()
    local pad = 64
    local bytes = { 24, 0x20, 2, 8, 24, 0x21, 3, 16 }
    local rom = plantAt(256, pad, bytes, 0x80)
    local modal = Dialog.new()
    modal:show({
      romRaw = rom,
      spriteLayer = validSpriteLayer({
        items = { { startAddr = 0x10 } },
      }),
      tilesPool = { [1] = {} },
    })
    modal.scannedModeCheckbox:setChecked(true)
    local markers = modal.hexGrid:getMinimapMarkers()
    local hasGray = false
    local hasScan = false
    for _, m in ipairs(markers) do
      if m.offset == 0x10 and m.color == "gray" then
        hasGray = true
      end
      if m.offset == pad then
        hasScan = true
      end
    end
    expect(hasGray).toBe(true)
    expect(hasScan).toBe(true)
    modal:hide()
    expect(modal.hexGrid:getMinimapMarkers()).toEqual({})
  end)

  it("does not change the 8-item selection cap", function()
    expect(RomHexGrid.MAX_SELECTED_STARTS).toBe(8)
  end)

  it("deselects the last Scan group after the 8-item cap clamps it", function()
    local triple = 32
    local pairA = 64
    local pairB = 96
    local overflow = 128
    local rom = plantMany(256, 0x80, {
      { offset = triple, bytes = concatRecords(
        oam(16, 0x10, 0, 40),
        oam(16, 0x11, 1, 48),
        oam(16, 0x12, 2, 56)
      ) },
      { offset = pairA, bytes = concatRecords(oam(24, 0x20, 0, 8), oam(24, 0x21, 1, 16)) },
      { offset = pairB, bytes = concatRecords(oam(32, 0x30, 2, 8), oam(32, 0x31, 3, 16)) },
      { offset = overflow, bytes = concatRecords(oam(40, 0x40, 0, 8), oam(40, 0x41, 1, 16)) },
    })
    local modal = Dialog.new()
    modal:show({
      romRaw = rom,
      spriteLayer = validSpriteLayer({ items = {} }),
      tilesPool = { [1] = {} },
    })
    modal.scannedModeCheckbox:setChecked(true)
    modal:_onGridSelect(triple, { fromGrid = true })
    modal:_onGridSelect(pairA, { fromGrid = true })
    modal:_onGridSelect(pairB, { fromGrid = true })
    expect(#modal.hexGrid:getSelectedStarts()).toBe(7)

    modal:_onGridSelect(overflow, { fromGrid = true })
    expect(#modal.hexGrid:getSelectedStarts()).toBe(8)
    expect(modal._limitWarning).toBe(Dialog.MSG_MAX_PER_ADD)
    expect(modal.footerLabel.text).toBe(Dialog.MSG_MAX_PER_ADD)
    local hasOverflowStart = false
    local hasOverflowSecond = false
    for _, addr in ipairs(modal.hexGrid:getSelectedStarts()) do
      if addr == overflow then
        hasOverflowStart = true
      end
      if addr == overflow + 4 then
        hasOverflowSecond = true
      end
    end
    expect(hasOverflowStart or hasOverflowSecond).toBe(true)
    expect(hasOverflowStart and hasOverflowSecond).toBe(false)

    modal:_onGridSelect(overflow + 2, { fromGrid = true })
    expect(#modal.hexGrid:getSelectedStarts()).toBe(7)
    for _, addr in ipairs(modal.hexGrid:getSelectedStarts()) do
      expect(addr == overflow).toBe(false)
      expect(addr == overflow + 4).toBe(false)
    end
    expect(modal._limitWarning).toBe(nil)
    modal:hide()
  end)

  it("deselects the last Scan group after it crosses the NES 64 limit", function()
    local pairA = 0x100
    local pairB = 0x120
    local pairC = 0x140
    local rom = plantMany(512, 0x80, {
      { offset = pairA, bytes = concatRecords(oam(16, 0x10, 0, 40), oam(16, 0x11, 1, 48)) },
      { offset = pairB, bytes = concatRecords(oam(24, 0x20, 0, 8), oam(24, 0x21, 1, 16)) },
      { offset = pairC, bytes = concatRecords(oam(32, 0x30, 2, 8), oam(32, 0x31, 3, 16)) },
    })
    local items = {}
    for i = 1, 60 do
      items[i] = { startAddr = (i - 1) * 4 }
    end
    local modal = Dialog.new()
    modal:show({
      romRaw = rom,
      spriteLayer = validSpriteLayer({ items = items }),
      tilesPool = { [1] = {} },
    })
    modal.scannedModeCheckbox:setChecked(true)
    modal:_onGridSelect(pairA, { fromGrid = true })
    modal:_onGridSelect(pairB, { fromGrid = true })
    expect(#modal.hexGrid:getSelectedStarts()).toBe(4)
    expect(modal._limitWarning).toBe(nil)

    modal:_onGridSelect(pairC, { fromGrid = true })
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ pairA, pairA + 4, pairB, pairB + 4, pairC, pairC + 4 })
    expect(modal._limitWarning).toBe(Dialog.MSG_NES_LIMIT)
    expect(modal.footerLabel.text).toBe(Dialog.MSG_NES_LIMIT)

    modal:_onGridSelect(pairC + 1, { fromGrid = true })
    expect(modal.hexGrid:getSelectedStarts()).toEqual({ pairA, pairA + 4, pairB, pairB + 4 })
    expect(modal._limitWarning).toBe(nil)
    modal:hide()
  end)

  it("shows scan status and limit warnings on one footer label", function()
    local pad = 32
    local bytes = { 16, 0x10, 0, 40, 16, 0x11, 1, 48 }
    local rom = plantAt(256, pad, bytes, 0x80)
    local modal = Dialog.new()
    modal:show({
      romRaw = rom,
      spriteLayer = validSpriteLayer({ items = {} }),
      tilesPool = { [1] = {} },
    })
    modal.scannedModeCheckbox:setChecked(true)
    local status = modal._statusText
    expect(type(status) == "string" and status ~= "").toBe(true)
    expect(modal.footerLabel.text).toBe(status)
    expect(modal.footerLabel.isWarning).toBe(false)

    local footerCells = 0
    local escLabels = {}
    for _, cell in ipairs(modal.panel:_iterCells()) do
      if cell.component == modal.footerLabel then
        footerCells = footerCells + 1
      end
      if cell.row == modal.panel.rows and cell.kind == "label" then
        escLabels[#escLabels + 1] = cell.text
      end
    end
    expect(footerCells).toBe(1)
    expect(escLabels).toEqual({ "Esc) Close" })

    local starts = {}
    for i = 0, 8 do
      starts[#starts + 1] = 0x40 + i * 4
    end
    modal._hitMax8 = true
    modal.hexGrid:_setStarts(starts, starts[1], { emit = false, allowOccupied = true })
    modal:_refreshLimitWarning()
    expect(modal._limitWarning).toBe(Dialog.MSG_MAX_PER_ADD)
    expect(modal.footerLabel.text).toBe(Dialog.MSG_MAX_PER_ADD)
    expect(modal.footerLabel.isWarning).toBe(true)
    expect(modal._statusText).toBe(status)

    footerCells = 0
    local statusLabels = 0
    for _, cell in ipairs(modal.panel:_iterCells()) do
      if cell.component == modal.footerLabel then
        footerCells = footerCells + 1
      end
      if cell.kind == "label" and cell.text == status then
        statusLabels = statusLabels + 1
      end
    end
    expect(footerCells).toBe(1)
    expect(statusLabels).toBe(0)
    modal:hide()
  end)
end)
