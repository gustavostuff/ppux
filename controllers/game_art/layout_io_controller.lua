-- game_art_layout_io_controller.lua
-- Layout/project snapshot + Lua I/O helpers extracted from game_art_controller.lua

local SpriteController = require("controllers.sprite.sprite_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local DebugController = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local TableUtils = require("utils.table_utils")
local GridModeUtils = require("controllers.grid_mode_utils")

local M = {}
local DEFAULT_ANIMATION_FRAME_DELAY = 0.2
M.PROJECT_FORMAT_VERSION = 1

local PPUX_COMPRESSION_FORMAT = "zlib"
local PATTERN_CANVAS_SNAPSHOT_ENCODING = "2bpp_v1"
local PATTERN_CANVAS_TEXT_ENCODING = "base64"

-------------------------------------------------------
-- File utilities
-------------------------------------------------------
local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local s = f:read("*a"); f:close()
  return s
end

local function write_file(path, s)
  local f, err = io.open(path, "wb")
  if not f then return false, err end
  f:write(s); f:close()
  return true
end

M.readFile = read_file
M.writeFile = write_file

local function packPatternCanvas2bpp(canvas)
  if not canvas or type(canvas.width) ~= "number" or type(canvas.height) ~= "number" or type(canvas.getPixel) ~= "function" then
    return nil, "invalid_canvas"
  end

  local out = {}
  local width = math.floor(canvas.width)
  local height = math.floor(canvas.height)
  for y = 0, height - 1 do
    for x = 0, width - 1, 4 do
      local p0 = (canvas:getPixel(x + 0, y) or 0) % 4
      local p1 = (canvas:getPixel(x + 1, y) or 0) % 4
      local p2 = (canvas:getPixel(x + 2, y) or 0) % 4
      local p3 = (canvas:getPixel(x + 3, y) or 0) % 4
      local byte = p0 + p1 * 4 + p2 * 16 + p3 * 64
      out[#out + 1] = string.char(byte)
    end
  end
  return table.concat(out)
end

local function unpackPatternCanvas2bpp(canvas, raw)
  if not canvas or type(canvas.edit) ~= "function" then
    return false, "invalid_canvas"
  end
  if type(raw) ~= "string" then
    return false, "invalid_raw"
  end

  local width = math.floor(canvas.width or 0)
  local height = math.floor(canvas.height or 0)
  local expectedBytes = math.floor((width * height) / 4)
  if #raw ~= expectedBytes then
    return false, string.format("unexpected_snapshot_size:%d:%d", #raw, expectedBytes)
  end

  if canvas.clear then
    canvas:clear(0)
  end

  local i = 1
  for y = 0, height - 1 do
    for x = 0, width - 1, 4 do
      local byte = string.byte(raw, i) or 0
      i = i + 1
      canvas:edit(x + 0, y, byte % 4)
      canvas:edit(x + 1, y, math.floor(byte / 4) % 4)
      canvas:edit(x + 2, y, math.floor(byte / 16) % 4)
      canvas:edit(x + 3, y, math.floor(byte / 64) % 4)
    end
  end
  return true
end

local function encodePatternCanvasSnapshot(canvas)
  if not (love and love.data and love.data.compress and love.data.encode) then
    return nil, "love.data.compress/encode is unavailable"
  end

  local raw, rawErr = packPatternCanvas2bpp(canvas)
  if not raw then
    return nil, rawErr
  end

  local ok, compressed = pcall(love.data.compress, "string", PPUX_COMPRESSION_FORMAT, raw)
  if not ok then
    return nil, tostring(compressed)
  end

  local encodedOk, encodedCompressed = pcall(love.data.encode, "string", PATTERN_CANVAS_TEXT_ENCODING, compressed)
  if not encodedOk then
    return nil, tostring(encodedCompressed)
  end

  local hash = nil
  if love.data and love.data.hash then
    local hashOk, hashed = pcall(love.data.hash, "sha1", raw)
    if hashOk and hashed then
      local encodedHashOk, encodedHash = pcall(love.data.encode, "string", PATTERN_CANVAS_TEXT_ENCODING, hashed)
      if encodedHashOk and encodedHash then
        hash = encodedHash
      end
    end
  end

  return {
    kind = "canvas_snapshot",
    encoding = PATTERN_CANVAS_SNAPSHOT_ENCODING,
    compression = PPUX_COMPRESSION_FORMAT,
    textEncoding = PATTERN_CANVAS_TEXT_ENCODING,
    width = canvas.width,
    height = canvas.height,
    data = encodedCompressed,
    hash = hash,
  }
end

function M.decodePatternCanvasSnapshot(canvas, edits)
  if not edits then return false, "missing_edits" end
  if type(edits) ~= "table" then return false, "invalid_edits" end
  if edits.kind ~= "canvas_snapshot" then return false, "unsupported_kind" end
  if edits.encoding ~= PATTERN_CANVAS_SNAPSHOT_ENCODING then return false, "unsupported_encoding" end
  if not (love and love.data and love.data.decompress and love.data.decode) then
    return false, "love.data.decompress/decode is unavailable"
  end

  local textEncoding = edits.textEncoding or PATTERN_CANVAS_TEXT_ENCODING
  local decodeOk, compressed = pcall(love.data.decode, "string", textEncoding, edits.data or "")
  if not decodeOk then
    return false, tostring(compressed)
  end

  local ok, raw = pcall(love.data.decompress, "string", edits.compression or PPUX_COMPRESSION_FORMAT, compressed)
  if not ok then
    return false, tostring(raw)
  end

  if edits.hash and love.data and love.data.hash then
    local hashOk, actualHash = pcall(love.data.hash, "sha1", raw)
    if hashOk and actualHash then
      local actualEncodedOk, actualEncodedHash = pcall(love.data.encode, "string", textEncoding, actualHash)
      if actualEncodedOk and actualEncodedHash and actualEncodedHash ~= edits.hash then
        return false, "snapshot_hash_mismatch"
      end
    end
  end

  if edits.width and canvas.width and tonumber(edits.width) ~= tonumber(canvas.width) then
    return false, "snapshot_width_mismatch"
  end
  if edits.height and canvas.height and tonumber(edits.height) ~= tonumber(canvas.height) then
    return false, "snapshot_height_mismatch"
  end

  return unpackPatternCanvas2bpp(canvas, raw)
end

-- -------------------------------------------------------------------
-- Normalize invalid black entries before saving
-- Known-problematic blacks when written to ROM / project:
--   0D, 0E, 1E, 2E, 3E, 1F, 2F, 3F  -> force to 0F
-- -------------------------------------------------------------------
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

-- Recursively walk a table and normalize any 2-digit hex strings
local function normalizeInvalidBlacksInTable(t)
  if type(t) ~= "table" then return t end

  for k, v in pairs(t) do
    if type(v) == "string" and v:match("^[%x][%x]$") then
      t[k] = normalizeInvalidBlack(v)
    elseif type(v) == "table" then
      normalizeInvalidBlacksInTable(v)
    end
  end

  return t
end

-- Encode userDefinedCode entries ({code,col,row}) into a compact string: "code,col,row;..."
local function encodeUserDefinedCodes(entries)
  if not entries or #entries == 0 then return nil end
  local parts = {}
  for _, item in ipairs(entries) do
    if item.code and item.col ~= nil and item.row ~= nil then
      parts[#parts + 1] = string.format("%s,%d,%d", tostring(item.code), item.col, item.row)
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ";")
end

-- Decode string "code,col,row;..." back into list of tables.
function M.decodeUserDefinedCodes(str)
  if type(str) ~= "string" or str == "" then return nil end
  local out = {}
  for token in str:gmatch("([^;]+)") do
    local code, col, row = token:match("^([^,]+),(-?%d+),(-?%d+)$")
    col, row = tonumber(col), tonumber(row)
    if code and col and row then
      out[#out + 1] = { code = normalizeInvalidBlack(code), col = col, row = row }
    end
  end
  if #out == 0 then return nil end
  table.sort(out, function(a, b)
    if a.row == b.row then return a.col < b.col end
    return a.row < b.row
  end)
  return out
end

-- Apply any pending "removed" flags by actually clearing the items table.
local function purgeRemovedTiles(win)
  if not (win and win.layers) then return end
  for _, L in ipairs(win.layers) do
    if not (WindowCaps.isPpuFrame(win) and L.kind == "tile") and L.removedCells and L.items then
      for idx, removed in pairs(L.removedCells) do
        if removed == true then
          L.items[idx] = nil
        end
      end
      -- Keep the map so repeated saves don't re-remove already purged cells
    end
  end
end

function M.saveProjectLua(path, projectTable)
  local project = TableUtils.deepcopy(projectTable or { windows = {}, currentBank = 1, kind = "project" })
  project.kind = "project"
  project.projectVersion = M.PROJECT_FORMAT_VERSION
  local body = TableUtils.serialize_lua_table(project)
  return write_file(path, body)
end

local function projectToLuaString(projectTable)
  local project = TableUtils.deepcopy(projectTable or { windows = {}, currentBank = 1, kind = "project" })
  project.kind = "project"
  project.projectVersion = M.PROJECT_FORMAT_VERSION
  return TableUtils.serialize_lua_table(project)
end

local function migrateProjectTable(project)
  local currentVersion = M.PROJECT_FORMAT_VERSION
  local loadedVersion = tonumber(project.projectVersion)

  -- Legacy projects had no explicit version field.
  if loadedVersion == nil then
    loadedVersion = 0
  end

  if loadedVersion > currentVersion then
    return nil, string.format(
      "Unsupported project version: %d (max supported: %d)",
      loadedVersion,
      currentVersion
    )
  end

  local originalVersion = loadedVersion

  -- v0 -> v1 migration:
  --   introduce explicit projectVersion field, preserve legacy shape.
  if loadedVersion < 1 then
    loadedVersion = 1
  end

  project.projectVersion = loadedVersion
  -- Legacy optional metadata fields are intentionally ignored.
  -- Project/ROM association is now convention-based by sibling filenames.
  project.sourceRomPath = nil
  project.sourceRomFilename = nil

  if originalVersion ~= loadedVersion then
    DebugController.log(
      "info",
      "GAM",
      "Migrated project format v%d -> v%d",
      originalVersion,
      loadedVersion
    )
  end

  return project
end

M.migrateProjectTable = migrateProjectTable

function M.loadProjectLua(path)
  local s, err = read_file(path)
  if not s then
    return nil, string.format("Failed to read project file: %s", tostring(err))
  end

  return M.loadProjectLuaString(s, path)
end

function M.loadProjectLuaString(s, path)
  if type(s) ~= "string" then
    return nil, string.format("Failed to read project file: %s", tostring(path or "unknown"))
  end

  if not s:match("^%s*return%s") then
    s = "return " .. s
  end

  local chunk, perr = load(s, "@project", "t", {})
  if not chunk then
    local errorMsg = string.format("Project file syntax error (%s): %s", path, tostring(perr))
    DebugController.log("error", "GAM", errorMsg)
    return nil, errorMsg
  end

  local ok, res = pcall(chunk)
  if not ok then
    local errorMsg = string.format("Project file runtime error (%s): %s", path, tostring(res))
    DebugController.log("error", "GAM", errorMsg)
    return nil, errorMsg
  end

  if type(res) ~= "table" or type(res.windows) ~= "table" then
    local errorMsg = string.format("Invalid project format: %s (expected table with windows)", path)
    DebugController.log("error", "GAM", errorMsg)
    return nil, errorMsg
  end

  res.kind = res.kind or "project"
  local migrated, migrateErr = migrateProjectTable(res)
  if not migrated then
    DebugController.log("error", "GAM", migrateErr)
    return nil, migrateErr
  end
  res = migrated

  local function logOrPrint(category, message, ...)
    if DebugController.isEnabled() then
      DebugController.log("info", category, message, ...)
    else
      local args = {...}
      local formattedMsg = string.format(message, unpack(args))
      print(string.format("[%s] %s", category or "DEBUG", formattedMsg))
    end
  end

  logOrPrint("GAM", "Loaded project: %s", path)
  logOrPrint("GAM", "  #windows = %d", #(res.windows or {}))
  logOrPrint("GAM", "  projectVersion = %d", res.projectVersion or 0)
  if res.edits then
    local editCount = 0
    if res.edits.banks then
      for _ in pairs(res.edits.banks) do editCount = editCount + 1 end
    end
    logOrPrint("GAM", "  edits.banks count = %d", editCount)
  else
    logOrPrint("GAM", "  edits = nil")
  end
  return res
end

function M.saveProjectPpux(path, projectTable)
  if not (love and love.data and love.data.compress) then
    return false, "love.data.compress is unavailable"
  end

  local body = projectToLuaString(projectTable)
  local ok, compressed = pcall(love.data.compress, "string", PPUX_COMPRESSION_FORMAT, body)
  if not ok then
    return false, tostring(compressed)
  end

  return write_file(path, compressed)
end

function M.loadProjectPpux(path)
  local s, err = read_file(path)
  if not s then
    return nil, string.format("Failed to read project file: %s", tostring(err))
  end

  return M.loadProjectPpuxString(s, path)
end

function M.loadProjectPpuxString(s, path)
  if not (love and love.data and love.data.decompress) then
    return nil, "love.data.decompress is unavailable"
  end
  if type(s) ~= "string" then
    return nil, string.format("Failed to read project file: %s", tostring(path or "unknown"))
  end

  local ok, decoded = pcall(love.data.decompress, "string", PPUX_COMPRESSION_FORMAT, s)
  if not ok then
    return nil, string.format("Compressed project decode error (%s): %s", tostring(path or "project"), tostring(decoded))
  end

  return M.loadProjectLuaString(decoded, path)
end

function M.getCompressedDataFrom(win)
  if WindowCaps.isPpuFrame(win) then
    return win:getCompressedData()
  end
  return nil
end

function M.snapshotLayout(wm, bankWindow, currentBank)
  local wins = wm:getWindows()
  if WindowCaps.isChrLike(bankWindow) then
    currentBank = bankWindow.currentBank or currentBank
  end
  local out = {
    currentBank = currentBank,
    windows = {}
  }

  local toolbarOy = 0
  do
    local ctx = rawget(_G, "ctx")
    local app = ctx and ctx.app
    if app then
      local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
      toolbarOy = tonumber(AppTopToolbarController.getContentOffsetY(app)) or 0
    end
  end

  for zi, w in ipairs(wins) do
    if w._closed then
      goto continue
    end
    if w._runtimeOnly == true then
      goto continue
    end
    purgeRemovedTiles(w)
    local isPalette = WindowCaps.isAnyPaletteWindow(w)
    local entryKind = WindowCaps.isRomPaletteWindow(w) and "rom_palette" or (isPalette and "palette" or (w.kind or "normal"))
    local entry = {
      id    = (w == bankWindow) and "bank" or (w._id or ""),
      title = w.title,
      kind  = entryKind,
      x     = w.x,
      y     = (type(w.y) == "number") and (w.y - toolbarOy) or w.y,
      cols  = w.cols,
      rows  = w.rows,
      visibleRows = w.visibleRows or w.rows,
      visibleCols = w.visibleCols or w.cols,
      scrollCol   = w.scrollCol or 0,
      scrollRow   = w.scrollRow or 0,
      zoom  = w.zoom,
      z     = zi * 10,
      collapsed = w._collapsed or false,
      minimized = w._minimized or false,
      showGrid = GridModeUtils.normalize(w.showGrid),
      nonActiveLayerOpacity = w.nonActiveLayerOpacity,
    }

    if WindowCaps.isPpuFrame(w) then
      entry.showSpriteOriginGuides = (w.showSpriteOriginGuides == true)
    end
    if WindowCaps.isOamAnimation(w) then
      entry.multiRowToolbar = (w.multiRowToolbar == true)
      entry.showSpriteOriginGuides = (w.showSpriteOriginGuides == true)
    end

    if not isPalette then
      entry.cellW = w.cellW
      entry.cellH = w.cellH
    end

    if entry.kind == "palette" then
      entry.paletteName = w.paletteName
      entry.activePalette = w.activePalette or false
      entry.compactView = (w.compactView == true)
      entry.items = {}
      for row = 0, w.rows - 1 do
        for col = 0, w.cols - 1 do
          local code = w:get(col, row)
          if code then
            code = normalizeInvalidBlack(code)
            table.insert(entry.items, { col = col, row = row, code = code })
          end
        end
      end
      local sc, sr = w:getSelected()
      if sc ~= nil and sr ~= nil then
        entry.selectedCol = sc
        entry.selectedRow = sr
      end

    elseif entry.kind == "rom_palette" then
      entry.paletteName = w.paletteName
      entry.activePalette = false
      entry.compactView = (w.compactView == true)

      if w.paletteData then
        entry.paletteData = {
          romColors = TableUtils.deepcopy(w.paletteData.romColors or {}),
          userDefinedCode = {}
        }

        if w.codes2D then
          for row = 0, (w.rows or 4) - 1 do
            for col = 0, (w.cols or 4) - 1 do
              local code = w.codes2D[row] and w.codes2D[row][col]
              if code and w.isCellEditable and w:isCellEditable(col, row) then
                code = normalizeInvalidBlack(code)
                table.insert(entry.paletteData.userDefinedCode, {
                  code = code,
                  col = col,
                  row = row,
                })
              end
            end
          end

          normalizeInvalidBlacksInTable(entry.paletteData)
          table.sort(entry.paletteData.userDefinedCode, function(a, b)
            if a.row == b.row then return a.col < b.col end
            return a.row < b.row
          end)
          entry.paletteData.userDefinedCode = encodeUserDefinedCodes(entry.paletteData.userDefinedCode)
        end
      end

      local sc, sr = w:getSelected()
      if sc ~= nil and sr ~= nil then
        entry.selectedCol = sc
        entry.selectedRow = sr
      end
      if sc and sr then
        entry.selectedCol = sc
        entry.selectedRow = sr
      end

    elseif entry.kind == "chr" then
      entry.activeLayer = 1
      entry.orderMode = w.orderMode or "normal"
      entry.currentBank = w.currentBank or 1
      if w.isRomWindow == true then
        entry.isRomWindow = true
      end
      entry.layers = {
        {
          opacity = (w.layers[1] and w.layers[1].opacity) or 1.0,
          name    = (w.layers[1] and w.layers[1].name) or "Bank",
          items   = {},
        }
      }
    else
      entry.activeLayer = w.activeLayer or 1
      entry.layers = {}
      if WindowCaps.isPatternTableBuilder(w) then
        entry.patternTolerance = w.patternTolerance or 0
      end

      for li = 1, #(w.layers or {}) do
        local L = w.layers[li]
        if L then
          if L._runtimePatternTableRefLayer == true or L._runtimeOnly == true then
            goto continue_layer
          end
          local kind = L.kind or (L.spriteLayer and "sprite") or "tile"

          if kind == "sprite" then
            if SpriteController and SpriteController.snapshotSpriteLayer then
              local snap = SpriteController.snapshotSpriteLayer(L)
              if snap then
                snap.name = snap.name or L.name
                snap.opacity = 1.0
                snap.kind = "sprite"
                if L.paletteData ~= nil then
                  snap.paletteData = TableUtils.deepcopy(L.paletteData)
                end
                if L.attrMode ~= nil then
                  snap.attrMode = L.attrMode
                end
                table.insert(entry.layers, snap)
              end
            end

          else
            local isNametableLayer = (L.nametableStartAddr ~= nil)
            if isNametableLayer then
              local snap = NametableTilesController.snapshotNametableLayer(w, L)
              if snap then
                snap.name = snap.name or L.name
                snap.opacity = 1.0
                if L.paletteData ~= nil then
                  snap.paletteData = TableUtils.deepcopy(L.paletteData)
                end
                if L.attrMode ~= nil then
                  snap.attrMode = L.attrMode
                end
                table.insert(entry.layers, snap)
              end
            else
              local Lout = {
                name    = L.name,
                kind    = kind,
                opacity = 1.0,
                mode    = L.mode,
                items   = {},
                page    = L.page,
                bank    = L.bank,
              }

              if kind == "canvas" and L.canvas then
                Lout.edits = encodePatternCanvasSnapshot(L.canvas)
                Lout.items = nil
                table.insert(entry.layers, Lout)
                goto continue_layer
              end

              if L.paletteData ~= nil then
                Lout.paletteData = TableUtils.deepcopy(L.paletteData)
                normalizeInvalidBlacksInTable(Lout.paletteData)
              end

              if L.attrMode ~= nil then
                Lout.attrMode = L.attrMode
              end

              for row = 0, w.rows - 1 do
                for col = 0, w.cols - 1 do
                  local ref = w:get(col, row, li)
                  if ref and ref._bankIndex ~= nil and ref.index ~= nil and ref.removed ~= true then
                    local idx = row * w.cols + col
                    local palNum = nil
                    if L.paletteNumbers then
                      palNum = L.paletteNumbers[idx]
                    end

                    local item = {
                      col = col,
                      row = row,
                      bank = ref._bankIndex,
                      tile = ref.index,
                    }
                    if palNum ~= nil then
                      item.paletteNumber = palNum
                    end
                    table.insert(Lout.items, item)
                  end
                end
              end
              table.insert(entry.layers, Lout)
            end
          end
        end
        ::continue_layer::
      end
    end

    if (entry.kind == "animation" or entry.kind == "oam_animation") and type(w.frameDelays) == "table" then
      local delays = {}
      local hasExplicitDelays = false
      local layerCount = #(w.layers or {})
      for i = 1, layerCount do
        local d = w.frameDelays[i]
        if d ~= nil then
          hasExplicitDelays = true
        end
        delays[i] = d or DEFAULT_ANIMATION_FRAME_DELAY
      end
      if hasExplicitDelays and #delays > 0 then
        entry.delaysPerLayer = delays
      end
    end

    table.insert(out.windows, entry)
    ::continue::
  end

  local focused = wm:getFocus()
  if focused and not focused._closed and focused._id then
    out.focusedWindowId = focused._id
  end

  return out
end

function M.saveLayoutLua(path, layoutTable)
  local s = TableUtils.serialize_lua_table(layoutTable or { windows = {} })
  return write_file(path, s)
end

function M.loadLayoutLua(path)
  local s, err = read_file(path)
  if not s then return nil, err end
  local chunk, perr = load(s, "@layout", "t", {})
  if not chunk then return nil, perr end
  local ok, res = pcall(chunk)
  if not ok then return nil, res end
  if type(res) ~= "table" or type(res.windows) ~= "table" then
    return nil, "invalid layout format"
  end
  return res
end

return M
