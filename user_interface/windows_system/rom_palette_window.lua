-- rom_palette_window.lua
-- ROM palette window (4 rows x 4 cols) that writes directly to ROM addresses.
-- Each row represents a palette, each column is a color within that palette.
-- Colors are stored at ROM addresses specified in paletteData.romColors[row][col].
-- User-modified colors are saved to paletteData.userDefinedCode.

local PaletteWindow = require("user_interface.windows_system.palette_window")
local Window = require("user_interface.windows_system.window")
local chr = require("chr")
local DebugController = require("controllers.dev.debug_controller")
local colors = require("app_colors")
local TableUtils = require("utils.table_utils")

local RomPaletteWindow = {}
RomPaletteWindow.__index = RomPaletteWindow
setmetatable(RomPaletteWindow, { __index = PaletteWindow })

local NORMAL_CELL_W, NORMAL_CELL_H = 32, 24
local COMPACT_CELL_W, COMPACT_CELL_H = 20, 13

local function clamp(n,a,b) if n<a then return a elseif n>b then return b else return n end end
local function hex2(n) return string.format("%02X", n) end

local function getLabelTextColor(rgb)
  rgb = rgb or colors.black
  local r, g, b = rgb[1] or 0, rgb[2] or 0, rgb[3] or 0
  local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
  local base = (luminance >= 0.5) and colors.black or colors.white
  if luminance >= 0.5 then
    return { base[1], base[2], base[3], 0.75 }
  end
  return { base[1], base[2], base[3], 0.75 }
end

local function nibbleAdjust(code, dx, dy)
  local v  = tonumber(code,16) or 0
  local hi = math.floor(v/16)
  local lo = v % 16
  hi = clamp(hi + (dy or 0), 0, 3)
  lo = clamp(lo + (dx or 0), 0, 15)
  return hex2(hi*16+lo)
end

local INVALID_BLACK_CODES = {
  ["0D"] = true, ["0E"] = true,
  ["1E"] = true, ["2E"] = true, ["3E"] = true,
  ["1F"] = true, ["2F"] = true, ["3F"] = true,
}

local function normalizeInvalidBlack(code)
  if type(code) ~= "string" then return code end
  local upper = code:upper()
  if INVALID_BLACK_CODES[upper] then
    return "0F"
  end
  return upper
end

-- Convert hex code string to byte value (0-255)
local function hexCodeToByte(hexCode)
  return tonumber(hexCode, 16) or 0
end

local function markPaletteUnsaved()
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  if app and app.markUnsaved then
    app:markUnsaved("palette_color_change")
  end
end

local function recordPaletteColorUndo(win, actions, beforePaletteData, afterPaletteData)
  local gctx = rawget(_G, "ctx")
  local app = gctx and gctx.app
  if not (app and app.undoRedo and app.undoRedo.addPaletteColorEvent) then
    return false
  end
  return app.undoRedo:addPaletteColorEvent({
    type = "palette_color",
    actions = actions,
    paletteStates = {
      {
        win = win,
        beforePaletteData = beforePaletteData,
        afterPaletteData = afterPaletteData,
      }
    },
  })
end

function RomPaletteWindow:isCellEditable(col, row)
  if not self.paletteData or not self.paletteData.romColors then return false end
  local rowIndex = (row or 0) + 1
  local colIndex = (col or 0) + 1
  local rowColors = self.paletteData.romColors[rowIndex]
  if not rowColors then return false end
  return type(rowColors[colIndex]) == "number"
end

function RomPaletteWindow.new(x, y, zoom, paletteName, rows, cols, data)
  data = data or {}
  data.resizable = false -- palette windows can't be resized
  rows, cols = rows or 4, cols or 4  -- Fixed 4x4 for ROM palettes
  
  -- Don't use default palette controller codes - we'll initialize from ROM
  -- Create empty initCodes array so PaletteWindow doesn't use global palette codes
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
  self.compactView = (data.compactView == true)
  self.normalCellW = NORMAL_CELL_W
  self.normalCellH = NORMAL_CELL_H
  self.compactCellW = COMPACT_CELL_W
  self.compactCellH = COMPACT_CELL_H
  
  -- Store paletteData structure (contains romColors addresses and userDefinedCode)
  self.paletteData = data.paletteData or {}
  
  -- Initialize codes2D from ROM or userDefinedCode
  -- This must run after PaletteWindow.new() to rebuild codes2D with ROM data
  self:initializeFromROMOrUserCodes()
  
  -- Ensure codes2D is fully initialized (should be 4x4)
  if not self.codes2D or not self.codes2D[0] or not self.codes2D[0][0] then
    DebugController.log("error", "ROM_PAL", "codes2D not properly initialized after initializeFromROMOrUserCodes")
  end

  self:setCompactMode(self.compactView)
  
  return self
end

function RomPaletteWindow:supportsCompactMode()
  return true
end

function RomPaletteWindow:setCompactMode(enabled)
  self.compactView = (enabled == true)
  if self.compactView then
    self.cellW = self.compactCellW
    self.cellH = self.compactCellH
  else
    self.cellW = self.normalCellW
    self.cellH = self.normalCellH
  end
  return self.compactView
end

-- Initialize codes2D from ROM bytes (if available) or userDefinedCode
function RomPaletteWindow:initializeFromROMOrUserCodes()
  -- If no paletteData, keep the codes2D that PaletteWindow.new() created
  if not self.paletteData then 
    DebugController.log("warning", "ROM_PAL", "No paletteData provided, using default codes from PaletteWindow")
    return 
  end
  
  local romColors = self.paletteData.romColors or {}
  local userCodes = self.paletteData.userDefinedCode or {}
  if type(userCodes) == "string" then
    userCodes = {}
    for token in self.paletteData.userDefinedCode:gmatch("([^;]+)") do
      local code, col, row = token:match("^([^,]+),(-?%d+),(-?%d+)$")
      col, row = tonumber(col), tonumber(row)
      if code and col and row then
        userCodes[#userCodes + 1] = { code = code:upper(), col = col, row = row }
      end
    end
    self.paletteData.userDefinedCode = userCodes
  end
  
  -- Debug: Log ROM addresses for first row to verify they're correct
  if romColors[1] then
    DebugController.log("info", "ROM_PAL", "Row 0 ROM addresses: [1]=0x%X, [2]=0x%X, [3]=0x%X, [4]=0x%X", 
      romColors[1][1] or 0, romColors[1][2] or 0, romColors[1][3] or 0, romColors[1][4] or 0)
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
        self.codes2D[rowIndex][colIndex] = "0F"
      else
        -- Prefer user-defined code if available, otherwise read from ROM.
        if rowUserCodes[colIndex] then
          self.codes2D[rowIndex][colIndex] = rowUserCodes[colIndex]
          DebugController.log("debug", "ROM_PAL", "Row %d, Col %d: Using user code %s", rowIndex, colIndex, rowUserCodes[colIndex])
        elseif type(self.romRaw) == "string" and #self.romRaw > 0 then
          local byte, err = chr.readByteFromAddress(self.romRaw, romAddr)
          if byte then
            local hexCode = hex2(byte)
            self.codes2D[rowIndex][colIndex] = hexCode
            DebugController.log("debug", "ROM_PAL", "Row %d, Col %d: Read from ROM 0x%X = %s (byte 0x%02X)", 
              rowIndex, colIndex, romAddr, hexCode, byte)
          else
            self.codes2D[rowIndex][colIndex] = "0F"  -- Default
            DebugController.log("warning", "ROM_PAL", "Row %d, Col %d: Failed to read ROM at 0x%X: %s", 
              rowIndex, colIndex, romAddr, tostring(err))
          end
        else
          self.codes2D[rowIndex][colIndex] = "0F"  -- Default
          DebugController.log("warning", "ROM_PAL", "Row %d, Col %d: ROM data unavailable for address 0x%X", 
            rowIndex, colIndex, romAddr)
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
end

-- Override setSelected to add debug logging for ROM palette selection
function RomPaletteWindow:setSelected(col, row, layerIndex)
  if col ~= nil and row ~= nil and not self:isCellEditable(col, row) then
    DebugController.log("info", "ROM_PAL", "ROM Palette '%s' selection blocked for locked cell (%d,%d)", 
      self.title or "untitled", col, row)
    return
  end

  Window.setSelected(self, col, row, layerIndex)
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
  local new = nibbleAdjust(old, dx, dy)
  if new == old then
    return
  end
  local beforePaletteData = TableUtils.deepcopy(self.paletteData or {})
  local undoActions = {}

  DebugController.log("info", "ROM_PAL", "ROM Palette '%s' color adjusted at (%d,%d): %s -> %s", 
    self.title or "untitled", sc, sr, old, new)

  -- If we're editing the first column, sync it across all rows (universal background)
  if sc == 0 then
    -- Update all rows' first column in the UI + ROM + userDefinedCode
    local rows = self.rows or 4
    for row = 0, rows - 1 do
      if not self:isCellEditable(0, row) then
        goto continue
      end

      local oldRowCode = self.codes2D[row] and self.codes2D[row][0] or old

      -- Make sure the row exists
      self.codes2D[row] = self.codes2D[row] or {}

      self.codes2D[row][0] = new
      self:set(0, row, new)

      -- Write to ROM and save user-defined code for each row's first color
      self:writeColorToROM(row, 0, new)
      self:saveUserDefinedCode(row, 0, new)
      undoActions[#undoActions + 1] = {
        win = self,
        row = row,
        col = 0,
        beforeCode = oldRowCode,
        afterCode = new,
      }
      ::continue::
    end
  else
    -- Normal behavior for non-first columns
    self.codes2D[sr][sc] = new
    self:set(sc, sr, new)

    -- Write to ROM
    self:writeColorToROM(sr, sc, new)

    -- Save to userDefinedCode
    self:saveUserDefinedCode(sr, sc, new)
    undoActions[#undoActions + 1] = {
      win = self,
      row = sr,
      col = sc,
      beforeCode = old,
      afterCode = new,
    }
  end

  recordPaletteColorUndo(self, undoActions, beforePaletteData, TableUtils.deepcopy(self.paletteData or {}))
  markPaletteUnsaved()
end

-- Write a color code to ROM at the specified address
function RomPaletteWindow:writeColorToROM(row, col, hexCode)
  hexCode = normalizeInvalidBlack(hexCode)
  if not self.paletteData or not self.paletteData.romColors then return end
  if not self:isCellEditable(col, row) then
    return false
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
  
  DebugController.log("info", "ROM_PAL", "Wrote color %s (byte 0x%02X) to ROM address 0x%X", 
    hexCode, byteValue, romAddr)
  
  return true
end

-- Save color code to userDefinedCode structure
function RomPaletteWindow:saveUserDefinedCode(row, col, hexCode)
  hexCode = normalizeInvalidBlack(hexCode)
  if not self.paletteData then
    self.paletteData = {}
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
  self.paletteData.romColors[rowIndex][colIndex] = math.floor(romAddr)

  self:removeUserDefinedCode(row, col)

  self.codes2D = self.codes2D or {}
  self.codes2D[row] = self.codes2D[row] or {}
  self.codes2D[row][col] = code
  self:set(col, row, code)
  self:setSelected(col, row)

  markPaletteUnsaved()
  return true, code
end

-- Override drawGrid to show codes even when not active (ROM palettes always show codes)
function RomPaletteWindow:drawGrid()
  local sx, sy, sw, sh = self:getScreenRect()
  love.graphics.setScissor(sx, sy, sw, sh)
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.scale(self.zoom, self.zoom)

  local Text = require("utils.text_utils")
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

      -- Always show codes for ROM palettes
      if editable then
        Text.print(code, x + 3, y + 2, {
          color = getLabelTextColor(fillColor),
          shadowColor = colors.transparent,
        })
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
