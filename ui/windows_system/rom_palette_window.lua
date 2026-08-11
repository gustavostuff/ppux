-- rom_palette_window.lua
-- ROM palette window (4 rows x 4 cols) that writes directly to ROM addresses.
-- Each row represents a palette, each column is a color within that palette.
-- Colors are stored at ROM addresses specified in paletteData.romColors[row][col].
-- User-modified colors are saved to paletteData.userDefinedCode.

local PaletteWindow = require("ui.windows_system.palette_window")
local Window = require("ui.windows_system.window")
local chr = require("chr")
local DebugController = require("controllers.dev.debug_controller")
local colors = require("app_colors")
local TableUtils = require("utils.table_utils")
local CanvasSpace = require("utils.canvas_space")
local PaletteEdit = require("utils.palette_edit_helpers")
local Draw = require("utils.draw_utils")
local images = require("images")

local RomPaletteWindow = {}
RomPaletteWindow.__index = RomPaletteWindow
setmetatable(RomPaletteWindow, { __index = PaletteWindow })

local hex2 = PaletteEdit.hex2
local getLabelTextColor = PaletteEdit.getLabelTextColor
local nibbleAdjust = PaletteEdit.nibbleAdjust
local normalizeInvalidBlack = PaletteEdit.normalizeInvalidBlack
local markPaletteUnsaved = PaletteEdit.markPaletteUnsaved
local recordPaletteColorUndo = PaletteEdit.recordPaletteColorUndo
local invalidateLinkedPpuFrames = PaletteEdit.invalidateLinkedPpuFrames

-- Convert hex code string to byte value (0-255)
local function hexCodeToByte(hexCode)
  return tonumber(hexCode, 16) or 0
end

function RomPaletteWindow:isSketchPalette()
  return self.paletteRole == "sketch"
end

function RomPaletteWindow:isCellEditable(col, row)
  if self:isSketchPalette() then
    return true
  end
  if not self.paletteData or not self.paletteData.romColors then return false end
  local rowIndex = (row or 0) + 1
  local colIndex = (col or 0) + 1
  local rowColors = self.paletteData.romColors[rowIndex]
  if not rowColors then return false end
  return type(rowColors[colIndex]) == "number"
end

--- Apply sketch-mode defaults: free colors, gallery-like BG rows 07/17/27/36.
local SKETCH_PALETTE_DEFAULTS = {
  { "07", "17", "27", "36" },
  { "07", "17", "27", "36" },
  { "07", "17", "27", "36" },
  { "07", "17", "27", "36" },
}

local function parseUserDefinedCodeList(paletteData)
  local userCodes = paletteData and paletteData.userDefinedCode or {}
  if type(userCodes) == "string" then
    local parsed = {}
    for token in userCodes:gmatch("([^;]+)") do
      local code, col, row = token:match("^([^,]+),(-?%d+),(-?%d+)$")
      col, row = tonumber(col), tonumber(row)
      if code and col and row then
        parsed[#parsed + 1] = { code = code:upper(), col = col, row = row }
      end
    end
    if paletteData then
      paletteData.userDefinedCode = parsed
    end
    return parsed
  end
  return type(userCodes) == "table" and userCodes or {}
end

local function ensureBaseCodesGrid(win)
  win.baseCodes2D = win.baseCodes2D or {}
  return win.baseCodes2D
end

local function setBaseCode(win, col, row, code)
  if type(col) ~= "number" or type(row) ~= "number" then
    return
  end
  local grid = ensureBaseCodesGrid(win)
  grid[row] = grid[row] or {}
  if code == nil then
    grid[row][col] = nil
    return
  end
  grid[row][col] = normalizeInvalidBlack(tostring(code):upper())
end

local function getBaseCode(win, col, row)
  local grid = win and win.baseCodes2D
  local code = grid and grid[row] and grid[row][col]
  if type(code) == "string" then
    return normalizeInvalidBlack(code)
  end
  if win and win.isSketchPalette and win:isSketchPalette() then
    local def = SKETCH_PALETTE_DEFAULTS[(row or 0) + 1]
    local sketchCode = def and def[(col or 0) + 1]
    if type(sketchCode) == "string" then
      return normalizeInvalidBlack(sketchCode)
    end
  end
  return nil
end

local function captureBaseCodeIfNeeded(win, col, row, code)
  if getBaseCode(win, col, row) ~= nil then
    return
  end
  if type(code) == "string" then
    setBaseCode(win, col, row, code)
  end
end

function RomPaletteWindow:applyPaletteRole(role)
  role = (role == "sketch") and "sketch" or "rom"
  self.paletteRole = role
  if role ~= "sketch" then
    return
  end
  self.paletteData = self.paletteData or {}
  self.paletteData.romColors = {}
  for row = 0, 3 do
    self.paletteData.romColors[row + 1] = {}
    for col = 0, 3 do
      self.paletteData.romColors[row + 1][col + 1] = "sketch"
    end
  end
  if type(self.title) == "string" and (self.title == "" or self.title == "ROM Palette") then
    self.title = "Sketch palette"
  end
  -- Role change establishes a new baseline (sketch defaults, not prior ROM bytes).
  self.baseCodes2D = nil
  -- Rebuild colors from defaults + any saved userDefinedCode.
  self:initializeFromROMOrUserCodes()
end

-- ROM byte address backing an editable cell, or nil if locked / missing.
function RomPaletteWindow:getRomByteAddress(col, row)
  if not self:isCellEditable(col, row) then
    return nil
  end
  local rowColors = self.paletteData.romColors[(row or 0) + 1]
  local addr = rowColors and rowColors[(col or 0) + 1]
  return type(addr) == "number" and addr or nil
end

--- Captured ROM/base NES code for a cell (before user override), or nil.
function RomPaletteWindow:getCapturedBaseCode(col, row)
  return getBaseCode(self, col, row)
end

--- Hover tooltip copy for one palette cell.
function RomPaletteWindow:formatCellTooltip(col, row)
  col = math.floor(tonumber(col) or -1)
  row = math.floor(tonumber(row) or -1)
  if col < 0 or row < 0 then
    return nil
  end
  if not self:isCellEditable(col, row) then
    return "No ROM address"
  end

  local code = self.codes2D and self.codes2D[row] and self.codes2D[row][col]
  if type(code) ~= "string" or code == "" then
    return nil
  end
  code = normalizeInvalidBlack(code)

  if self:isSketchPalette() then
    local base = getBaseCode(self, col, row)
    if type(base) == "string" and base ~= code then
      return string.format("$%s overrides sketch default $%s", code, base)
    end
    return string.format("Sketch color $%s", code)
  end

  local addr = self:getRomByteAddress(col, row)
  if type(addr) ~= "number" then
    return "No ROM address"
  end
  local base = getBaseCode(self, col, row)
  if type(base) == "string" and base ~= code then
    return string.format("$%s overrides ROM $%s at 0x%06X", code, base, addr)
  end
  return string.format("Color matches ROM address 0x%06X ($%s)", addr, code)
end

function RomPaletteWindow:getTooltipAt(px, py)
  if self._closed or self._minimized or self._collapsed then
    return nil
  end
  if self.isInContentArea and not self:isInContentArea(px, py) then
    return nil
  end
  if not self.toGridCoords then
    return nil
  end
  local ok, col, row = self:toGridCoords(px, py)
  if not ok then
    return nil
  end
  local text = self:formatCellTooltip(col, row)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  local code = self.codes2D and self.codes2D[row] and self.codes2D[row][col] or ""
  local base = getBaseCode(self, col, row) or ""
  return {
    text = text,
    immediate = false,
    key = table.concat({
      "rom_pal_cell",
      tostring(self._id or self.title or ""),
      tostring(col),
      tostring(row),
      tostring(code),
      tostring(base),
    }, ":"),
  }
end

local function getRomPaletteWindowsFromApp(app, primaryWin)
  if app and app.wm and app.wm.getWindowsOfKind then
    local list = app.wm:getWindowsOfKind("rom_palette")
    if type(list) == "table" and #list > 0 then
      return list
    end
  end
  return primaryWin and { primaryWin } or {}
end

-- Every editable ROM palette cell (any window) that maps to the same ROM byte address.
local function collectEditableCellsForRomAddress(primaryWin, app, romAddr)
  local out = {}
  if type(romAddr) ~= "number" then
    return out
  end
  for _, w in ipairs(getRomPaletteWindowsFromApp(app, primaryWin)) do
    local rows = w.rows or 4
    local cols = w.cols or 4
    for r = 0, rows - 1 do
      for c = 0, cols - 1 do
        if w.getRomByteAddress and w:getRomByteAddress(c, r) == romAddr then
          out[#out + 1] = { win = w, col = c, row = r }
        end
      end
    end
  end
  return out
end

-- Apply a NES code to every editable cell that shares romAddr (intra + inter window).
-- Returns undo cell actions and the ordered list of touched palette windows.
local function applyColorToSharedRomAddress(primaryWin, app, romAddr, newCode)
  newCode = normalizeInvalidBlack(tostring(newCode or "0F"):upper())
  local cells = collectEditableCellsForRomAddress(primaryWin, app, romAddr)
  local undoActions = {}
  local paletteWinOrder = {}
  local paletteWinSeen = {}

  for _, cell in ipairs(cells) do
    local w = cell.win
    if w and not paletteWinSeen[w] then
      paletteWinSeen[w] = true
      paletteWinOrder[#paletteWinOrder + 1] = w
    end
  end

  for _, cell in ipairs(cells) do
    local w, c, r = cell.win, cell.col, cell.row
    w.codes2D = w.codes2D or {}
    w.codes2D[r] = w.codes2D[r] or {}
    local prevCode = w.codes2D[r][c]
    if prevCode ~= newCode then
      w.codes2D[r][c] = newCode
      if w.set then
        w:set(c, r, newCode)
      end
      if w.writeColorToROM then
        w:writeColorToROM(r, c, newCode)
      end
      if w.saveUserDefinedCode then
        w:saveUserDefinedCode(r, c, newCode)
      end
      undoActions[#undoActions + 1] = {
        win = w,
        row = r,
        col = c,
        beforeCode = prevCode,
        afterCode = newCode,
      }
    end
  end

  return undoActions, paletteWinOrder, cells
end

-- Agreed color among peer cells for romAddr, excluding one cell. Nil if none or conflict.
local function agreedPeerCodeForRomAddress(primaryWin, app, romAddr, excludeCol, excludeRow)
  local agreed = nil
  for _, cell in ipairs(collectEditableCellsForRomAddress(primaryWin, app, romAddr)) do
    if not (cell.win == primaryWin and cell.col == excludeCol and cell.row == excludeRow) then
      local code = cell.win.codes2D
        and cell.win.codes2D[cell.row]
        and cell.win.codes2D[cell.row][cell.col]
      if type(code) == "string" then
        code = normalizeInvalidBlack(code)
        if agreed == nil then
          agreed = code
        elseif agreed ~= code then
          return nil
        end
      end
    end
  end
  return agreed
end

-- Sketch-mode universal backdrop: color column 0 on every row of *this* sketch palette only.
local function collectSketchUniversalColor0Cells(primaryWin)
  local out = {}
  if primaryWin and primaryWin.isSketchPalette and primaryWin:isSketchPalette() then
    for row = 0, 3 do
      out[#out + 1] = { win = primaryWin, col = 0, row = row }
    end
  end
  return out
end

--- Force column 0 to the same NES code on all rows of this sketch palette.
function RomPaletteWindow:normalizeSketchUniversalColor0(preferredCode)
  if not self:isSketchPalette() then
    return false
  end
  local code = preferredCode
  if type(code) ~= "string" or #code < 2 then
    code = self.codes2D and self.codes2D[0] and self.codes2D[0][0]
  end
  code = normalizeInvalidBlack(tostring(code or "0F"):upper())
  self.codes2D = self.codes2D or {}
  local changed = false
  for row = 0, 3 do
    self.codes2D[row] = self.codes2D[row] or {}
    if self.codes2D[row][0] ~= code then
      self.codes2D[row][0] = code
      if self.set then
        self:set(0, row, code)
      end
      self:saveUserDefinedCode(row, 0, code)
      changed = true
    end
  end
  return changed
end

-- Remove ROM backing for a cell (romColors slot becomes false), drop user override, show locked gray cell.
function RomPaletteWindow:clearRomCellBinding(col, row)
  if not self:isCellEditable(col, row) then
    return false
  end
  self.paletteData = self.paletteData or {}
  self.paletteData.romColors = self.paletteData.romColors or {}
  local ri, ci = (row or 0) + 1, (col or 0) + 1
  self.paletteData.romColors[ri] = self.paletteData.romColors[ri] or {}
  self.paletteData.romColors[ri][ci] = false
  self:removeUserDefinedCode(row, col)
  setBaseCode(self, col, row, nil)
  self.codes2D[row] = self.codes2D[row] or {}
  self.codes2D[row][col] = "0F"
  self:set(col, row, "0F")
  if self.selected and self.selected.col == col and self.selected.row == row and self.clearSelected then
    self:clearSelected()
  end
  invalidateLinkedPpuFrames(self)
  markPaletteUnsaved()
  return true
end

function RomPaletteWindow.new(x, y, zoom, paletteName, rows, cols, data)
  data = data or {}
  data.resizable = false -- palette windows can't be resized
  rows, cols = rows or 4, cols or 4  -- Fixed 4x4 for ROM palettes
  
  -- Don't use default palette controller codes - we'll initialize from ROM
  -- Create empty initCodes array so PaletteWindow doesn't use generic palette codes
  data.initCodes = data.initCodes or {}
  -- Fill with defaults if empty (but we'll override them anyway)
  if #data.initCodes == 0 then
    for i = 1, rows * cols do
      data.initCodes[i] = "0F"  -- Default placeholder
    end
  end
  
  -- Create base palette window (will override some methods)
  local self = PaletteWindow.new(x, y, zoom, paletteName, rows, cols, data)
  setmetatable(self, RomPaletteWindow)
  
  -- ROM palette specific properties
  self.kind = "rom_palette"
  self.isPalette = true  -- Inherit palette behavior
  self.romRaw = data.romRaw  -- Store ROM reference
  -- Load-time migration: always compact (PaletteWindow also forces this).
  self.compactView = true

  -- Store paletteData structure (contains romColors addresses and userDefinedCode)
  self.paletteData = data.paletteData or {}
  self.paletteRole = (data.paletteRole == "sketch") and "sketch" or "rom"

  -- Initialize codes2D from ROM or userDefinedCode
  -- This must run after PaletteWindow.new() to rebuild codes2D with ROM data
  if self:isSketchPalette() then
    -- Sets sketch romColors markers, then rebuilds codes from defaults + userDefinedCode.
    self:applyPaletteRole("sketch")
  else
    self:initializeFromROMOrUserCodes()
  end
  
  -- Ensure codes2D is fully initialized (should be 4x4)
  if not self.codes2D or not self.codes2D[0] or not self.codes2D[0][0] then
    DebugController.log("error", "ROM_PAL", "codes2D not properly initialized after initializeFromROMOrUserCodes")
  end

  self:setCompactMode(true)
  
  return self
end

local function pruneUserDefinedCodeToBaseDiffs(win)
  if not (win and win.paletteData) then
    return
  end
  local userCodes = parseUserDefinedCodeList(win.paletteData)
  local pruned = {}
  for _, item in ipairs(userCodes) do
    if type(item.row) == "number" and type(item.col) == "number" and item.code then
      if win:isCellEditable(item.col, item.row) then
        local code = normalizeInvalidBlack(tostring(item.code):upper())
        local base = getBaseCode(win, item.col, item.row)
        if base == nil or code ~= base then
          pruned[#pruned + 1] = { code = code, col = item.col, row = item.row }
        end
      end
    end
  end
  table.sort(pruned, function(a, b)
    if a.row == b.row then return a.col < b.col end
    return a.row < b.row
  end)
  win.paletteData.userDefinedCode = pruned
end

-- Initialize codes2D from ROM bytes (if available) or userDefinedCode
function RomPaletteWindow:initializeFromROMOrUserCodes()
  -- Sketch-mode: free colors. Rebuild from defaults + userDefinedCode (undo/redo relies on this).
  if self:isSketchPalette() then
    self.codes2D = {}
    for row = 0, 3 do
      self.codes2D[row] = {}
      for col = 0, 3 do
        local code = SKETCH_PALETTE_DEFAULTS[row + 1][col + 1]
        captureBaseCodeIfNeeded(self, col, row, code)
        self.codes2D[row][col] = code
        if self.set then
          self:set(col, row, code)
        end
      end
    end
    local userCodes = parseUserDefinedCodeList(self.paletteData)
    for _, item in ipairs(userCodes) do
      if type(item.row) == "number" and type(item.col) == "number" and item.code then
        local code = normalizeInvalidBlack(tostring(item.code):upper())
        self.codes2D[item.row] = self.codes2D[item.row] or {}
        self.codes2D[item.row][item.col] = code
        if self.set then
          self:set(item.col, item.row, code)
        end
      end
    end
    self:normalizeSketchUniversalColor0()
    pruneUserDefinedCodeToBaseDiffs(self)
    return
  end

  -- If no paletteData, keep the codes2D that PaletteWindow.new() created
  if not self.paletteData then 
    DebugController.log("warning", "ROM_PAL", "No paletteData provided, using default codes from PaletteWindow")
    return 
  end
  
  local romColors = self.paletteData.romColors or {}
  local userCodes = parseUserDefinedCodeList(self.paletteData)
  -- Debug: Log ROM addresses for first row to verify they're correct
  if romColors[1] then
    DebugController.log("info", "ROM_PAL", "Row 0 ROM addresses: [1]=0x%X, [2]=0x%X, [3]=0x%X, [4]=0x%X", 
      (type(romColors[1][1]) == "number" and romColors[1][1]) or 0,
      (type(romColors[1][2]) == "number" and romColors[1][2]) or 0,
      (type(romColors[1][3]) == "number" and romColors[1][3]) or 0,
      (type(romColors[1][4]) == "number" and romColors[1][4]) or 0)
  end
  
  DebugController.log("info", "ROM_PAL", "Initializing ROM palette: romColors rows=%d, userCodes count=%d", 
    romColors and (romColors[1] and 1 or 0) or 0, userCodes and #userCodes or 0)
  
  -- Rebuild codes2D from either ROM or saved user codes
  self.codes2D = {}
  
  for row = 1, 4 do
    local rowIndex = row - 1  -- 0-indexed row (0-3)
    self.codes2D[rowIndex] = {}  -- 0-indexed rows
    local rowColors = romColors[row] or {}
    local rowUserCodes = {}
    
    -- Build map of user codes by position
    for _, item in ipairs(userCodes) do
      if item.row == rowIndex then  -- Already 0-indexed in userDefinedCode
        rowUserCodes[item.col] = item.code
      end
    end
    
    for col = 1, 4 do
      local colIndex = col - 1  -- 0-indexed column (0-3)
      local romAddr = rowColors[col]
      local isEditable = self:isCellEditable(colIndex, rowIndex)

      if not isEditable then
        -- Locked / non-ROM backed slots are displayed as disabled gray cells.
        setBaseCode(self, colIndex, rowIndex, nil)
        self.codes2D[rowIndex][colIndex] = "0F"
      else
        -- Capture the ROM/base color once so live romRaw writes don't erase the baseline.
        local baseCode = getBaseCode(self, colIndex, rowIndex)
        if baseCode == nil then
          if type(romAddr) == "number" and type(self.romRaw) == "string" and #self.romRaw > 0 then
            local byte, err = chr.readByteFromAddress(self.romRaw, romAddr)
            if byte then
              baseCode = hex2(byte)
            else
              baseCode = "0F"
              DebugController.log("warning", "ROM_PAL", "Row %d, Col %d: Failed to read ROM at 0x%X: %s", 
                rowIndex, colIndex, romAddr, tostring(err))
            end
          else
            baseCode = "0F"
            DebugController.log("warning", "ROM_PAL", "Row %d, Col %d: ROM data unavailable for address 0x%X", 
              rowIndex, colIndex, romAddr)
          end
          setBaseCode(self, colIndex, rowIndex, baseCode)
        end

        -- Prefer user-defined code if available, otherwise use the captured ROM base.
        if rowUserCodes[colIndex] then
          local userCode = normalizeInvalidBlack(tostring(rowUserCodes[colIndex]):upper())
          self.codes2D[rowIndex][colIndex] = userCode
          DebugController.log("debug", "ROM_PAL", "Row %d, Col %d: Using user code %s", rowIndex, colIndex, userCode)
        else
          self.codes2D[rowIndex][colIndex] = baseCode
          DebugController.log("debug", "ROM_PAL", "Row %d, Col %d: Using base/ROM code %s", rowIndex, colIndex, baseCode)
        end
      end
      
      -- Update window items for display
      self:set(colIndex, rowIndex, self.codes2D[rowIndex][colIndex])
    end
    
    -- Log first row values after initialization to verify
    if rowIndex == 0 then
      DebugController.log("info", "ROM_PAL", "Row 0 final codes: [0]=%s, [1]=%s, [2]=%s, [3]=%s", 
        self.codes2D[0][0] or "nil", self.codes2D[0][1] or "nil", 
        self.codes2D[0][2] or "nil", self.codes2D[0][3] or "nil")
    end
  end

  pruneUserDefinedCodeToBaseDiffs(self)
end

-- Cells whose current UI color differs from the captured ROM/sketch base.
function RomPaletteWindow:collectUserDefinedOverridesForSave()
  local out = {}
  local rows = self.rows or 4
  local cols = self.cols or 4
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      if self:isCellEditable(col, row) then
        local code = self.codes2D and self.codes2D[row] and self.codes2D[row][col]
        if type(code) == "string" then
          code = normalizeInvalidBlack(code)
          local base = getBaseCode(self, col, row)
          if base == nil or code ~= base then
            out[#out + 1] = { code = code, col = col, row = row }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.row == b.row then return a.col < b.col end
    return a.row < b.row
  end)
  return out
end

-- Override setSelected to add debug logging for ROM palette selection
function RomPaletteWindow:setSelected(col, row, layerIndex, opts)
  if col ~= nil and row ~= nil and not self:isCellEditable(col, row) then
    DebugController.log("info", "ROM_PAL", "ROM Palette '%s' selection blocked for locked cell (%d,%d)", 
      self.title or "untitled", col, row)
    return
  end

  Window.setSelected(self, col, row, layerIndex, opts)
  if col ~= nil and row ~= nil then
    local code = self.codes2D and self.codes2D[row] and self.codes2D[row][col]
    if code then
      DebugController.log("info", "ROM_PAL", "ROM Palette '%s' color selected: (%d,%d) = %s", 
        self.title or "untitled", col, row, code)
    else
      DebugController.log("warning", "ROM_PAL", "ROM Palette '%s' selection at (%d,%d) but no code found", 
        self.title or "untitled", col, row)
    end
  end
end

-- Arrow keys move selection and skip over locked cells.
function RomPaletteWindow:moveSelectedByArrows(dx, dy)
  if (dx or 0) == 0 and (dy or 0) == 0 then return false end
  local sc, sr, li = self:getSelected()
  if sc == nil or sr == nil then return false end

  local nx, ny = sc, sr
  while true do
    nx = nx + (dx or 0)
    ny = ny + (dy or 0)
    if nx < 0 or ny < 0 or nx >= (self.cols or 0) or ny >= (self.rows or 0) then
      return false
    end
    if self:isCellEditable(nx, ny) then
      self:setSelected(nx, ny, li)
      return true
    end
  end
end

-- Override: Update ROM and save to userDefinedCode when color changes
-- Override: Update ROM and save to userDefinedCode when color changes
function RomPaletteWindow:adjustSelectedByArrows(dx, dy)
  local sc, sr = self:getSelected()
  if not sc or not sr then 
    DebugController.log("warning", "ROM_PAL", "No selection: sc=%s, sr=%s", tostring(sc), tostring(sr))
    return 
  end
  
  -- Ensure codes2D exists and has the row/col
  if not self.codes2D or not self.codes2D[sr] or not self.codes2D[sr][sc] then
    DebugController.log("error", "ROM_PAL", "codes2D[%d][%d] does not exist! codes2D=%s", sr, sc, 
      self.codes2D and "exists" or "nil")
    return
  end

  if not self:isCellEditable(sc, sr) then
    DebugController.log("info", "ROM_PAL", "ROM Palette '%s' adjustment blocked for locked cell (%d,%d)", 
      self.title or "untitled", sc, sr)
    return
  end
  
  local old = self.codes2D[sr][sc]
  local new = normalizeInvalidBlack(nibbleAdjust(old, dx, dy))
  local undoActions = {}

  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app

  local function commitSharedRomColor(code)
    local romAddr = self:getRomByteAddress(sc, sr)
    if type(romAddr) ~= "number" then
      return false
    end
    local cells = collectEditableCellsForRomAddress(self, app, romAddr)
    if #cells == 0 then
      return false
    end

    local paletteWinOrder = {}
    local paletteWinSeen = {}
    for _, cell in ipairs(cells) do
      local w = cell.win
      if w and not paletteWinSeen[w] then
        paletteWinSeen[w] = true
        paletteWinOrder[#paletteWinOrder + 1] = w
      end
    end

    local paletteStates = {}
    for _, w in ipairs(paletteWinOrder) do
      paletteStates[#paletteStates + 1] = {
        win = w,
        beforePaletteData = TableUtils.deepcopy(w.paletteData or {}),
        afterPaletteData = nil,
      }
    end

    local actions = select(1, applyColorToSharedRomAddress(self, app, romAddr, code))
    if #actions == 0 then
      return false
    end

    for _, st in ipairs(paletteStates) do
      st.afterPaletteData = TableUtils.deepcopy(st.win.paletteData or {})
    end
    recordPaletteColorUndo(actions, paletteStates)
    for _, w in ipairs(paletteWinOrder) do
      invalidateLinkedPpuFrames(w)
    end
    markPaletteUnsaved()
    return true
  end

  -- Nibble hit a limit: still push this cell's color to shared-address peers so
  -- stale per-window userDefinedCode cannot linger until load/save reconcile.
  if new == old then
    if not self:isSketchPalette() then
      commitSharedRomColor(old)
    end
    return
  end

  DebugController.log("info", "ROM_PAL", "ROM Palette '%s' color adjusted at (%d,%d): %s -> %s", 
    self.title or "untitled", sc, sr, old, new)

  -- Sketch-mode: free colors. Column 0 is the per-window universal backdrop (synced across rows).
  if self:isSketchPalette() then
    local beforePaletteData = TableUtils.deepcopy(self.paletteData or {})
    local paletteStates = {
      {
        win = self,
        beforePaletteData = beforePaletteData,
        afterPaletteData = nil,
      },
    }

    if sc == 0 then
      local cells = collectSketchUniversalColor0Cells(self)

      for _, cell in ipairs(cells) do
        local w, c, r = cell.win, cell.col, cell.row
        w.codes2D = w.codes2D or {}
        w.codes2D[r] = w.codes2D[r] or {}
        local prevCode = w.codes2D[r][c]
        if prevCode ~= new then
          w.codes2D[r][c] = new
          w:set(c, r, new)
          w:writeColorToROM(r, c, new)
          w:saveUserDefinedCode(r, c, new)
          undoActions[#undoActions + 1] = {
            win = w,
            row = r,
            col = c,
            beforeCode = prevCode,
            afterCode = new,
          }
        end
      end

      paletteStates[1].afterPaletteData = TableUtils.deepcopy(self.paletteData or {})
      recordPaletteColorUndo(undoActions, paletteStates)
      invalidateLinkedPpuFrames(self)
    else
      self.codes2D[sr][sc] = new
      self:set(sc, sr, new)
      self:writeColorToROM(sr, sc, new)
      self:saveUserDefinedCode(sr, sc, new)
      recordPaletteColorUndo(
        {
          {
            win = self,
            row = sr,
            col = sc,
            beforeCode = old,
            afterCode = new,
          },
        },
        {
          {
            win = self,
            beforePaletteData = beforePaletteData,
            afterPaletteData = TableUtils.deepcopy(self.paletteData or {}),
          },
        }
      )
      invalidateLinkedPpuFrames(self)
    end
    markPaletteUnsaved()
    return
  end

  commitSharedRomColor(new)
end

-- Write a color code to ROM at the specified address
function RomPaletteWindow:writeColorToROM(row, col, hexCode)
  hexCode = normalizeInvalidBlack(hexCode)
  if not self.paletteData or not self.paletteData.romColors then return end
  if not self:isCellEditable(col, row) then
    return false
  end
  -- Sketch-mode palettes are free colors (no ROM addresses).
  if self:isSketchPalette() then
    return true
  end
  if type(self.romRaw) ~= "string" or #self.romRaw == 0 then
    DebugController.log("warning", "ROM_PAL", "romRaw not available for writing")
    return false
  end
  
  local romColors = self.paletteData.romColors
  local rowIndex = row + 1  -- Convert 0-indexed to 1-indexed
  local colIndex = col + 1  -- Convert 0-indexed to 1-indexed
  
  if not romColors[rowIndex] or not romColors[rowIndex][colIndex] then
    DebugController.log("warning", "ROM_PAL", "No ROM address for palette row %d, col %d", rowIndex, colIndex)
    return false
  end
  
  local romAddr = romColors[rowIndex][colIndex]
  local byteValue = hexCodeToByte(hexCode)
  
  local newRom, err = chr.writeByteToAddress(self.romRaw, romAddr, byteValue)
  if not newRom then
    DebugController.log("error", "ROM_PAL", "Failed to write to ROM at 0x%X: %s", romAddr, tostring(err))
    return false
  end
  
  -- Update local romRaw reference
  self.romRaw = newRom
  
  -- Also update app state if available (for persistence across saves)
  if self._updateRomRawCallback then
    self._updateRomRawCallback(newRom)
  end

  -- Every ROM palette window keeps its own romRaw reference; chr.writeByteToAddress returns a new string.
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  if app and app.wm and app.wm.getWindowsOfKind then
    for _, w in ipairs(app.wm:getWindowsOfKind("rom_palette")) do
      w.romRaw = newRom
    end
  end
  
  DebugController.log("info", "ROM_PAL", "Wrote color %s (byte 0x%02X) to ROM address 0x%X", 
    hexCode, byteValue, romAddr)
  
  return true
end

-- Save color code to userDefinedCode structure (sparse: only diffs vs captured base).
function RomPaletteWindow:saveUserDefinedCode(row, col, hexCode)
  hexCode = normalizeInvalidBlack(hexCode)
  if not self.paletteData then
    self.paletteData = {}
  end

  local base = getBaseCode(self, col, row)
  if base ~= nil and hexCode == base then
    self:removeUserDefinedCode(row, col)
    return
  end
  
  if not self.paletteData.userDefinedCode then
    self.paletteData.userDefinedCode = {}
  end
  
  -- Find existing entry for this position and update, or add new one
  local found = false
  for i, item in ipairs(self.paletteData.userDefinedCode) do
    if item.row == row and item.col == col then
      item.code = hexCode
      found = true
      break
    end
  end
  
  if not found then
    table.insert(self.paletteData.userDefinedCode, {
      code = hexCode,
      col = col,
      row = row
    })
  end
  
  -- Sort for consistent output
  table.sort(self.paletteData.userDefinedCode, function(a, b)
    if a.row == b.row then return a.col < b.col end
    return a.row < b.row
  end)
end

function RomPaletteWindow:removeUserDefinedCode(row, col)
  if not (self.paletteData and type(self.paletteData.userDefinedCode) == "table") then
    return false
  end

  local removed = false
  for i = #self.paletteData.userDefinedCode, 1, -1 do
    local item = self.paletteData.userDefinedCode[i]
    if item and item.row == row and item.col == col then
      table.remove(self.paletteData.userDefinedCode, i)
      removed = true
    end
  end

  return removed
end

function RomPaletteWindow:setCellAddress(col, row, romAddr)
  if type(col) ~= "number" or type(row) ~= "number" then
    return false, "Invalid ROM palette cell"
  end
  if type(romAddr) ~= "number" then
    return false, "ROM address must be a number"
  end
  if col < 0 or row < 0 or col >= (self.cols or 0) or row >= (self.rows or 0) then
    return false, "ROM palette cell is out of range"
  end

  romAddr = math.floor(romAddr)
  -- Same binding: keep the current NES code / user override. Re-reading ROM here
  -- would wipe userDefinedCode and look like a spontaneous color change on Set.
  local existing = self:getRomByteAddress(col, row)
  if existing == romAddr then
    if self.setSelected then
      self:setSelected(col, row)
    end
    local code = self.codes2D and self.codes2D[row] and self.codes2D[row][col]
    return true, code
  end

  local code = "0F"
  if type(self.romRaw) == "string" and #self.romRaw > 0 then
    local byte, err = chr.readByteFromAddress(self.romRaw, romAddr)
    if not byte then
      return false, string.format("ROM address 0x%X is invalid: %s", romAddr, tostring(err))
    end
    code = hex2(byte)
  end

  self.paletteData = self.paletteData or {}
  self.paletteData.romColors = self.paletteData.romColors or {}
  local rowIndex = row + 1
  local colIndex = col + 1
  self.paletteData.romColors[rowIndex] = self.paletteData.romColors[rowIndex] or {}
  self.paletteData.romColors[rowIndex][colIndex] = romAddr

  -- Rebinding establishes a new ROM baseline for this cell.
  setBaseCode(self, col, row, code)
  self:removeUserDefinedCode(row, col)

  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  -- If peers already share this address and agree on a color, adopt it (edit-time sync).
  -- If they disagree or there are no peers, keep the ROM byte and push it to everyone.
  local peerCode = agreedPeerCodeForRomAddress(self, app, romAddr, col, row)
  if peerCode then
    code = peerCode
  end

  applyColorToSharedRomAddress(self, app, romAddr, code)
  self:setSelected(col, row)

  invalidateLinkedPpuFrames(self)
  markPaletteUnsaved()
  return true, code
end

-- Override drawGrid to show codes even when not active (ROM palettes always show codes)
local OVERRIDE_SWATCH_PX = 3
local OVERRIDE_SWATCH_MARGIN_LEFT = 2
local OVERRIDE_SWATCH_MARGIN_TOP = 2
local OVERRIDE_ANTS_PX = 5
local OVERRIDE_ANTS_ALPHA = 1
local OVERRIDE_ANTS_ANIM = {
  stepPx = 1,
  intervalSeconds = 0.1,
}
local LABEL_MARGIN_RIGHT = 2
local LABEL_MARGIN_BOTTOM = 2

--- Bottom-right label: font box has `right`/`bottom` margins inside the cell.
local function drawCellLabel(text, cellX, cellY, cellW, cellH, color)
  text = tostring(text or "")
  local font = love.graphics.getFont()
  if not (font and font.getWidth and font.getHeight) then
    return
  end
  local tw = font:getWidth(text)
  -- Hex digits have no descenders; getHeight() includes empty descent space, so
  -- nudge 1px down so the ink sits on the intended bottom margin.
  local th = font:getHeight()
  local lx = math.floor(cellX + cellW - LABEL_MARGIN_RIGHT - tw)
  local ly = math.floor(cellY + cellH - LABEL_MARGIN_BOTTOM - th) + 1
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
  -- Use love.graphics.print directly so Text.print's EXTRA_Y nudge cannot shift margins.
  love.graphics.print(text, lx, ly)
end

--- Centered label (empty / unbound cells).
local function drawCenteredCellLabel(text, cellX, cellY, cellW, cellH, color)
  text = tostring(text or "")
  local font = love.graphics.getFont()
  if not (font and font.getWidth and font.getHeight) then
    return
  end
  local tw = font:getWidth(text)
  local th = font:getHeight()
  local lx = math.floor(cellX + (cellW - tw) * 0.5)
  local ly = math.floor(cellY + (cellH - th) * 0.5) + 1
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
  love.graphics.print(text, lx, ly)
end

--- Base NES code being overridden by the cell's current color, or nil.
function RomPaletteWindow:getOverriddenBaseCode(col, row)
  if not self:isCellEditable(col, row) then
    return nil
  end
  local code = self.codes2D and self.codes2D[row] and self.codes2D[row][col]
  if type(code) ~= "string" then
    return nil
  end
  local base = getBaseCode(self, col, row)
  if type(base) ~= "string" then
    return nil
  end
  if base == normalizeInvalidBlack(code) then
    return nil
  end
  return base
end

--- True when this cell's displayed color differs from the captured ROM/base.
function RomPaletteWindow:cellHasUserOverride(col, row)
  return self:getOverriddenBaseCode(col, row) ~= nil
end

--- True when any editable cell differs from its captured base.
function RomPaletteWindow:hasAnyUserOverride()
  local rows = self.rows or 4
  local cols = self.cols or 4
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      if self:cellHasUserOverride(c, r) then
        return true
      end
    end
  end
  return false
end

-- Apply base code to one sketch cell (or all col-0 rows when col == 0). Returns undo actions.
local function applySketchCellToBase(win, col, row, baseCode)
  local undoActions = {}
  local cells
  if col == 0 then
    cells = collectSketchUniversalColor0Cells(win)
  else
    cells = { { win = win, col = col, row = row } }
  end
  for _, cell in ipairs(cells) do
    local w, c, r = cell.win, cell.col, cell.row
    w.codes2D = w.codes2D or {}
    w.codes2D[r] = w.codes2D[r] or {}
    local prevCode = w.codes2D[r][c]
    if prevCode ~= baseCode then
      w.codes2D[r][c] = baseCode
      if w.set then
        w:set(c, r, baseCode)
      end
      if w.writeColorToROM then
        w:writeColorToROM(r, c, baseCode)
      end
      if w.saveUserDefinedCode then
        w:saveUserDefinedCode(r, c, baseCode)
      end
      undoActions[#undoActions + 1] = {
        win = w,
        row = r,
        col = c,
        beforeCode = prevCode,
        afterCode = baseCode,
      }
    else
      if w.removeUserDefinedCode then
        w:removeUserDefinedCode(r, c)
      end
    end
  end
  return undoActions
end

--- Restore one cell to its captured ROM/base color and drop its userDefinedCode entry.
--- Returns true when something changed.
function RomPaletteWindow:resetCellToBase(col, row)
  col = math.floor(tonumber(col) or -1)
  row = math.floor(tonumber(row) or -1)
  if col < 0 or row < 0 or not self:isCellEditable(col, row) then
    return false
  end
  local base = self:getCapturedBaseCode(col, row)
  if type(base) ~= "string" or base == "" then
    return false
  end
  base = normalizeInvalidBlack(base)

  local current = self.codes2D and self.codes2D[row] and self.codes2D[row][col]
  if current == base and not self:cellHasUserOverride(col, row) then
    if self:removeUserDefinedCode(row, col) then
      markPaletteUnsaved()
      return true
    end
    return false
  end

  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  local undoActions = {}
  local paletteStates = {}

  if self:isSketchPalette() then
    local beforePaletteData = TableUtils.deepcopy(self.paletteData or {})
    undoActions = applySketchCellToBase(self, col, row, base)
    if #undoActions == 0 then
      if self:removeUserDefinedCode(row, col) then
        markPaletteUnsaved()
        return true
      end
      return false
    end
    paletteStates[1] = {
      win = self,
      beforePaletteData = beforePaletteData,
      afterPaletteData = TableUtils.deepcopy(self.paletteData or {}),
    }
  else
    local romAddr = self:getRomByteAddress(col, row)
    if type(romAddr) ~= "number" then
      return false
    end
    local cells = collectEditableCellsForRomAddress(self, app, romAddr)
    local paletteWinOrder = {}
    local paletteWinSeen = {}
    local beforeByWin = {}
    for _, cell in ipairs(cells) do
      local w = cell.win
      if w and not paletteWinSeen[w] then
        paletteWinSeen[w] = true
        paletteWinOrder[#paletteWinOrder + 1] = w
        beforeByWin[w] = TableUtils.deepcopy(w.paletteData or {})
      end
    end

    undoActions = select(1, applyColorToSharedRomAddress(self, app, romAddr, base)) or {}
    if #undoActions == 0 then
      if self:removeUserDefinedCode(row, col) then
        markPaletteUnsaved()
        return true
      end
      return false
    end

    for _, w in ipairs(paletteWinOrder) do
      paletteStates[#paletteStates + 1] = {
        win = w,
        beforePaletteData = beforeByWin[w] or {},
        afterPaletteData = TableUtils.deepcopy(w.paletteData or {}),
      }
    end
  end

  recordPaletteColorUndo(undoActions, paletteStates)
  for _, st in ipairs(paletteStates) do
    invalidateLinkedPpuFrames(st.win)
  end
  markPaletteUnsaved()
  return true
end

--- Restore every overridden cell on this window to its captured base.
function RomPaletteWindow:resetAllCellsToBase()
  if not self:hasAnyUserOverride() then
    return false
  end

  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  local rows = self.rows or 4
  local cols = self.cols or 4

  local paletteWinOrder = { self }
  local paletteWinSeen = { [self] = true }
  local beforeByWin = { [self] = TableUtils.deepcopy(self.paletteData or {}) }

  if not self:isSketchPalette() and app and app.wm and app.wm.getWindowsOfKind then
    for _, w in ipairs(app.wm:getWindowsOfKind("rom_palette") or {}) do
      if w and not paletteWinSeen[w] then
        paletteWinSeen[w] = true
        paletteWinOrder[#paletteWinOrder + 1] = w
        beforeByWin[w] = TableUtils.deepcopy(w.paletteData or {})
      end
    end
  end

  local undoActions = {}
  local seenRomAddr = {}

  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      if self:cellHasUserOverride(c, r) then
        local base = self:getCapturedBaseCode(c, r)
        if type(base) == "string" and base ~= "" then
          base = normalizeInvalidBlack(base)
          if self:isSketchPalette() then
            local actions = applySketchCellToBase(self, c, r, base)
            for _, a in ipairs(actions) do
              undoActions[#undoActions + 1] = a
            end
          else
            local romAddr = self:getRomByteAddress(c, r)
            if type(romAddr) == "number" and not seenRomAddr[romAddr] then
              seenRomAddr[romAddr] = true
              local actions = select(1, applyColorToSharedRomAddress(self, app, romAddr, base))
              for _, a in ipairs(actions or {}) do
                undoActions[#undoActions + 1] = a
              end
            end
          end
        end
      end
    end
  end

  if #undoActions == 0 then
    return false
  end

  local paletteStates = {}
  for _, w in ipairs(paletteWinOrder) do
    local touched = (w == self)
    if not touched then
      for _, a in ipairs(undoActions) do
        if a.win == w then
          touched = true
          break
        end
      end
    end
    if touched then
      paletteStates[#paletteStates + 1] = {
        win = w,
        beforePaletteData = beforeByWin[w] or TableUtils.deepcopy(w.paletteData or {}),
        afterPaletteData = TableUtils.deepcopy(w.paletteData or {}),
      }
    end
  end

  recordPaletteColorUndo(undoActions, paletteStates)
  for _, st in ipairs(paletteStates) do
    invalidateLinkedPpuFrames(st.win)
  end
  markPaletteUnsaved()
  return true
end

function RomPaletteWindow:drawGrid()
  local sx, sy, sw, sh = self:getInsetContentScreenRect()
  CanvasSpace.setScissorFromContentRect(sx, sy, sw, sh)
  love.graphics.push()
  love.graphics.translate(sx, sy)
  local z = (self.getZoomLevel and self:getZoomLevel()) or self.zoom or 1
  love.graphics.scale(z, z)

  local cw, ch = self.cellW, self.cellH

  for r=0, self.rows-1 do
    for c=0, self.cols-1 do
      local x, y = c*cw, r*ch
      local code = self.codes2D[r][c]
      local editable = self:isCellEditable(c, r)
      local fillColor = colors.gray50
      if editable then
        fillColor = (self.palette[code] or colors.black)
        love.graphics.setColor(fillColor[1], fillColor[2], fillColor[3], 1)
      else
        love.graphics.setColor(colors.gray50[1], colors.gray50[2], colors.gray50[3], 1)
      end
      love.graphics.rectangle("fill", x, y, cw, ch)

      if editable then
        drawCellLabel(code, x, y, cw, ch, getLabelTextColor(fillColor))
        -- Top-left 3x3 swatch of captured ROM/base when overridden.
        local baseCode = self:getOverriddenBaseCode(c, r)
        if baseCode then
          local swatchX = x + OVERRIDE_SWATCH_MARGIN_LEFT
          local swatchY = y + OVERRIDE_SWATCH_MARGIN_TOP
          local baseRgb = self.palette[baseCode] or colors.black
          love.graphics.setColor(baseRgb[1], baseRgb[2], baseRgb[3], 1)
          love.graphics.rectangle("fill", swatchX, swatchY, OVERRIDE_SWATCH_PX, OVERRIDE_SWATCH_PX)

          -- 5x5 ants frame (1px ring around the 3x3); always draw, including when selected.
          if images.pattern_a and Draw.drawRepeatingImageAnimated then
            local antsX = swatchX - math.floor((OVERRIDE_ANTS_PX - OVERRIDE_SWATCH_PX) * 0.5)
            local antsY = swatchY - math.floor((OVERRIDE_ANTS_PX - OVERRIDE_SWATCH_PX) * 0.5)
            love.graphics.setColor(1, 1, 1, OVERRIDE_ANTS_ALPHA)
            Draw.drawRepeatingImageAnimated(
              images.pattern_a,
              antsX,
              antsY,
              OVERRIDE_ANTS_PX,
              OVERRIDE_ANTS_PX,
              OVERRIDE_ANTS_ANIM
            )
          end
        end
      else
        -- Empty / unbound cells: centered dash placeholder (no NES code).
        drawCenteredCellLabel("-", x, y, cw, ch, getLabelTextColor(fillColor))
      end

      love.graphics.setColor(colors.white)
    end
  end

  love.graphics.setScissor()
  self:drawSelectionStrips()

  if self.selected and self:isCellEditable(self.selected.col, self.selected.row) then
    self:highlightSelected(cw, ch)
  end
  love.graphics.pop()
  love.graphics.setColor(colors.white)
end

return RomPaletteWindow
