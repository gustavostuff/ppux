-- debug_controller.lua
-- Centralized debug logging system for the application

local DebugController = {}
DebugController.__index = DebugController

-- Internal state
local debugEnabled = false
local debugLog = {}  -- Array of debug message strings
local maxLogLines = 10000  -- Maximum number of lines to keep in memory
local categoryFilter = nil  -- If set, only logs matching categories in this table will be printed/stored (can be table of strings or single string for backward compat)
local hudMode = "off"
local lastActiveHudMode = "perf+debug"
local perfStats = {}
local perfFrameNumber = 0
local perfFrameStartSeconds = nil
local perfLastFrameMs = 0
local perfAverageFrameMs = 0

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function perfTrackingEnabled()
  return debugEnabled or hudMode == "perf" or hudMode == "perf+debug"
end

local function normalizeHudMode(mode)
  if mode == "perf" or mode == "debug" or mode == "perf+debug" then
    return mode
  end
  return "off"
end

local function hudModeIncludes(kind)
  kind = tostring(kind or "")
  return hudMode == kind or hudMode == "perf+debug"
end

local function applyHudMode(mode)
  local normalized = normalizeHudMode(mode)
  hudMode = normalized
  if normalized ~= "off" then
    lastActiveHudMode = normalized
  end
  debugEnabled = (normalized == "debug" or normalized == "perf+debug")
  return hudMode
end

local function resetFrameValues()
  for _, stat in pairs(perfStats) do
    if stat.kind == "counter" then
      stat.frameValue = 0
    elseif stat.kind == "duration" then
      stat.frameCount = 0
      stat.frameTotalMs = 0
      stat.frameLastMs = 0
    elseif stat.kind == "gauge" then
      stat.frameValue = nil
    end
  end
end

local function ensurePerfStat(name, kind)
  local stat = perfStats[name]
  if stat and stat.kind == kind then
    return stat
  end

  stat = {
    kind = kind,
    name = name,
  }
  if kind == "counter" then
    stat.totalValue = 0
    stat.frameValue = 0
  elseif kind == "duration" then
    stat.totalMs = 0
    stat.totalCount = 0
    stat.lastMs = 0
    stat.maxMs = 0
    stat.frameCount = 0
    stat.frameTotalMs = 0
    stat.frameLastMs = 0
  elseif kind == "gauge" then
    stat.value = nil
    stat.frameValue = nil
  end
  perfStats[name] = stat
  return stat
end

-- Get a formatted timestamp for debug messages
local function getTimestamp()
  return os.date("%H:%M:%S")
end

-- Format a debug message with optional category and context
local function formatMessage(category, message, ...)
  local args = {...}
  local timestamp = getTimestamp()
  
  -- Format message with optional arguments
  local formatted = message
  if #args > 0 then
    formatted = string.format(message, ...)
  end
  
  -- Build final message with category prefix if provided
  if category and category ~= "" then
    return string.format("[%s] [%s] %s", timestamp, category, formatted)
  else
    return string.format("[%s] %s", timestamp, formatted)
  end
end

-- Get ANSI color code for log level
local function getColorCode(level)
  if level == "warning" then
    return "\27[33m"  -- Yellow
  elseif level == "error" then
    return "\27[31m"  -- Red
  else
    return "\27[0m"   -- Default/reset (for "info" or unknown)
  end
end

-- Add a debug message to the log
-- Usage: log(level, category, message, ...)
-- @param level: Log level ("info", "warning", or "error")
-- @param category: Category/tag for the message (e.g., "GAM", "UI", "SPRITE")
-- @param message: The debug message (can use string.format patterns)
-- @param ...: Optional arguments for string.format
function DebugController.log(level, category, message, ...)
  -- If debug mode is off, do nothing (don't store or print)
  if not debugEnabled then
    return
  end
  
  -- Check category filter - if set, only process logs matching the category
  -- DEBUG category always bypasses the filter (it's meta-information about the debug system)
  if categoryFilter and category ~= "DEBUG" then
    local matches = false
    -- Support both single string (backward compat) and table of categories
    if type(categoryFilter) == "string" then
      matches = (category == categoryFilter)
    elseif type(categoryFilter) == "table" then
      for _, filterCat in ipairs(categoryFilter) do
        if category == filterCat then
          matches = true
          break
        end
      end
    end
    
    if not matches then
      return  -- Skip this log entry
    end
  end
  
  -- Validate level (default to "info" if invalid)
  if level ~= "info" and level ~= "warning" and level ~= "error" then
    level = "info"
  end
  
  local args = {...}
  -- Use table.unpack for Lua 5.3+ compatibility, fallback to unpack for Lua 5.1/5.2/LuaJIT
  local unpack_fn = table.unpack or unpack
  local formattedMsg = formatMessage(category, message, unpack_fn(args))
  
  -- Store in log table (without color codes for storage)
  table.insert(debugLog, formattedMsg)
  
  -- Limit log size
  if #debugLog > maxLogLines then
    table.remove(debugLog, 1)  -- Remove oldest entry
  end
  
  -- Print to terminal with color
  local colorCode = getColorCode(level)
  local resetCode = "\27[0m"
  print(colorCode .. formattedMsg .. resetCode)
end

-- Toggle debug mode on/off
function DebugController.toggle()
  if debugEnabled then
    if hudMode == "debug" then
      applyHudMode("off")
    elseif hudMode == "perf+debug" then
      applyHudMode("perf")
    else
      debugEnabled = false
    end
  else
    if hudMode == "off" then
      applyHudMode("debug")
    elseif hudMode == "perf" then
      applyHudMode("perf+debug")
    else
      debugEnabled = true
    end
  end
  local status = debugEnabled and "ENABLED" or "DISABLED"
  local msg = string.format("Debug mode %s", status)
  -- Always print toggle status even if debug was off
  print(string.format("[DEBUG] %s", msg))
  -- Log the toggle (this will only store if debug is now enabled)
  if debugEnabled then
    DebugController.log("info", "DEBUG", msg)
  end
  return debugEnabled
end

-- Check if debug mode is enabled
function DebugController.isEnabled()
  return debugEnabled
end

-- Clear the debug log
function DebugController.clear()
  -- Only work if debug mode is enabled
  if not debugEnabled then
    return
  end
  local count = #debugLog
  debugLog = {}
  DebugController.log("info", "DEBUG", "Debug log cleared (%d entries removed)", count)
  print(string.format("[DEBUG] Debug log cleared (%d entries removed)", count))
end

-- Copy all debug log lines to clipboard
function DebugController.copyToClipboard()
  -- Only work if debug mode is enabled
  if not debugEnabled then
    return false
  end
  
  if #debugLog == 0 then
    DebugController.log("info", "DEBUG", "Debug log is empty, nothing to copy")
    print("[DEBUG] Debug log is empty, nothing to copy")
    return false
  end
  
  -- Concatenate all log lines with newlines
  local logText = table.concat(debugLog, "\n")
  
  -- Copy to clipboard using Love2D's clipboard API
  love.system.setClipboardText(logText)
  
  local lineCount = #debugLog
  DebugController.log("info", "DEBUG", "Copied %d debug log lines to clipboard", lineCount)
  print(string.format("[DEBUG] Copied %d debug log lines to clipboard", lineCount))
  
  return true
end

function DebugController.setHudMode(mode)
  local previous = hudMode
  local nextMode = applyHudMode(mode)
  if previous == "off" and nextMode ~= "off" then
    DebugController.perfReset()
  end
  return nextMode
end

function DebugController.getHudMode()
  return hudMode
end

function DebugController.toggleHud()
  if hudMode == "off" then
    return DebugController.setHudMode(lastActiveHudMode or "perf+debug")
  end
  return DebugController.setHudMode("off")
end

function DebugController.cycleHudMode()
  local nextMode = "debug"
  if hudMode == "debug" then
    nextMode = "perf"
  elseif hudMode == "perf" then
    nextMode = "perf+debug"
  elseif hudMode == "perf+debug" then
    nextMode = "off"
  elseif hudMode == "off" then
    nextMode = "debug"
  else
    nextMode = "debug"
  end
  return DebugController.setHudMode(nextMode)
end

function DebugController.getHudModeLabel(mode)
  local normalized = normalizeHudMode(mode or hudMode)
  if normalized == "debug" then
    return "debug"
  elseif normalized == "perf" then
    return "perf"
  elseif normalized == "perf+debug" then
    return "debug+perf"
  end
  return "off"
end

function DebugController.getNextCycleModes()
  return { "debug", "perf", "perf+debug", "off" }
end

function DebugController.hudModeIncludes(kind)
  return hudModeIncludes(kind)
end

function DebugController.perfToggleHud()
  local nextMode = DebugController.toggleHud()
  return nextMode ~= "off"
end

function DebugController.perfIsHudEnabled()
  return hudModeIncludes("perf")
end

function DebugController.perfReset()
  perfStats = {}
  perfFrameNumber = 0
  perfFrameStartSeconds = nil
  perfLastFrameMs = 0
  perfAverageFrameMs = 0
end

function DebugController.perfBeginFrame()
  if not perfTrackingEnabled() then
    return false
  end
  perfFrameNumber = perfFrameNumber + 1
  resetFrameValues()
  perfFrameStartSeconds = nowSeconds()
  return true
end

function DebugController.perfEndFrame()
  if not perfTrackingEnabled() then
    return false
  end
  if perfFrameStartSeconds == nil then
    return false
  end

  perfLastFrameMs = math.max(0, (nowSeconds() - perfFrameStartSeconds) * 1000)
  if perfFrameNumber <= 1 then
    perfAverageFrameMs = perfLastFrameMs
  else
    perfAverageFrameMs = (perfAverageFrameMs * 0.9) + (perfLastFrameMs * 0.1)
  end
  perfFrameStartSeconds = nil
  return true
end

function DebugController.perfIncrement(name, amount)
  if not perfTrackingEnabled() then
    return false
  end
  local stat = ensurePerfStat(name, "counter")
  local delta = tonumber(amount) or 1
  stat.totalValue = stat.totalValue + delta
  stat.frameValue = stat.frameValue + delta
  return true
end

function DebugController.perfObserveMs(name, ms)
  if not perfTrackingEnabled() then
    return false
  end
  local stat = ensurePerfStat(name, "duration")
  local value = math.max(0, tonumber(ms) or 0)
  stat.totalCount = stat.totalCount + 1
  stat.totalMs = stat.totalMs + value
  stat.lastMs = value
  if value > stat.maxMs then
    stat.maxMs = value
  end
  stat.frameCount = stat.frameCount + 1
  stat.frameTotalMs = stat.frameTotalMs + value
  stat.frameLastMs = value
  return true
end

function DebugController.perfSet(name, value)
  if not perfTrackingEnabled() then
    return false
  end
  local stat = ensurePerfStat(name, "gauge")
  stat.value = value
  stat.frameValue = value
  return true
end

function DebugController.getPerfSnapshot()
  local snapshot = {
    frameNumber = perfFrameNumber,
    lastFrameMs = perfLastFrameMs,
    averageFrameMs = perfAverageFrameMs,
    hudEnabled = hudMode ~= "off",
    hudMode = hudMode,
    debugEnabled = debugEnabled,
    metrics = {},
  }

  for name, stat in pairs(perfStats) do
    local entry = {
      kind = stat.kind,
      name = name,
    }
    if stat.kind == "counter" then
      entry.totalValue = stat.totalValue
      entry.frameValue = stat.frameValue
    elseif stat.kind == "duration" then
      entry.totalCount = stat.totalCount
      entry.totalMs = stat.totalMs
      entry.lastMs = stat.lastMs
      entry.maxMs = stat.maxMs
      entry.frameCount = stat.frameCount
      entry.frameTotalMs = stat.frameTotalMs
      entry.frameLastMs = stat.frameLastMs
      entry.averageMs = (stat.totalCount > 0) and (stat.totalMs / stat.totalCount) or 0
    elseif stat.kind == "gauge" then
      entry.value = stat.value
      entry.frameValue = stat.frameValue
    end
    snapshot.metrics[name] = entry
  end

  return snapshot
end

local function metric(snapshot, name)
  return snapshot and snapshot.metrics and snapshot.metrics[name] or nil
end

function DebugController.getDebugSummaryLines()
  local filter = DebugController.getCategoryFilter()
  local filterText = "all"
  if type(filter) == "string" then
    filterText = filter
  elseif type(filter) == "table" then
    filterText = table.concat(filter, ",")
  end

  return {
    string.format("Debug %s lines:%d filter:%s", debugEnabled and "on" or "off", #debugLog, filterText),
  }
end

function DebugController.getPerfSummaryLines()
  local snapshot = DebugController.getPerfSnapshot()
  local lines = {
    string.format("Perf frame %.2fms avg %.2fms", snapshot.lastFrameMs or 0, snapshot.averageFrameMs or 0),
  }

  local full = metric(snapshot, "chr_canvas_repaint_full")
  local partial = metric(snapshot, "chr_canvas_repaint_partial")
  local repaint = metric(snapshot, "chr_canvas_repaint_ms")
  local dirty = metric(snapshot, "chr_canvas_dirty_tile_count")
  local mat = metric(snapshot, "chr_tile_materialize")
  local create = metric(snapshot, "chr_tile_create")
  local ghost = metric(snapshot, "chr_ghost_canvas_draw")
  local invTile = metric(snapshot, "chr_canvas_invalidate_tile")
  local invBank = metric(snapshot, "chr_canvas_invalidate_bank")
  local currentBank = metric(snapshot, "chr_canvas_current_bank")
  local orderMode = metric(snapshot, "chr_canvas_order_mode")
  local paint = metric(snapshot, "chr_paint_pixel_ms")
  local paintApply = metric(snapshot, "chr_paint_apply_ms")
  local paintSync = metric(snapshot, "chr_paint_duplicate_sync_ms")
  local paintUndo = metric(snapshot, "chr_paint_undo_ms")
  local paintInv = metric(snapshot, "chr_paint_invalidate_count")
  local paintTargetTiles = metric(snapshot, "chr_paint_target_tiles")
  local paintSourceTiles = metric(snapshot, "chr_paint_source_tiles")
  local paintPixels = metric(snapshot, "chr_paint_written_pixels")
  local paintDupTargets = metric(snapshot, "chr_paint_duplicate_targets")

  if full or partial or repaint or dirty then
    lines[#lines + 1] = string.format(
      "CHR repaint f:%d p:%d last:%.2fms avg:%.2fms dirty:%s",
      full and full.frameValue or 0,
      partial and partial.frameValue or 0,
      repaint and repaint.lastMs or 0,
      repaint and repaint.averageMs or 0,
      dirty and tostring(dirty.value) or "-"
    )
  end

  if mat or create or ghost then
    lines[#lines + 1] = string.format(
      "CHR materialize frame:%d total:%d create:%d ghost:%d",
      mat and mat.frameValue or 0,
      mat and mat.totalValue or 0,
      create and create.frameValue or 0,
      ghost and ghost.frameValue or 0
    )
  end

  if invTile or invBank or currentBank or orderMode then
    lines[#lines + 1] = string.format(
      "CHR inv tile:%d bank:%d view:%s/%s",
      invTile and invTile.frameValue or 0,
      invBank and invBank.frameValue or 0,
      currentBank and tostring(currentBank.value) or "-",
      orderMode and tostring(orderMode.value) or "-"
    )
  end

  if paint or paintApply or paintSync or paintUndo or paintInv then
    lines[#lines + 1] = string.format(
      "CHR paint last:%.2fms avg:%.2fms apply:%.2fms sync:%.2fms undo:%.2fms inv:%d",
      paint and paint.lastMs or 0,
      paint and paint.averageMs or 0,
      paintApply and paintApply.lastMs or 0,
      paintSync and paintSync.lastMs or 0,
      paintUndo and paintUndo.lastMs or 0,
      paintInv and paintInv.frameValue or 0
    )
  end

  if paintPixels or paintTargetTiles or paintSourceTiles or paintDupTargets then
    lines[#lines + 1] = string.format(
      "CHR paint px:%d tiles:%d src:%d dup:%d",
      paintPixels and paintPixels.frameValue or 0,
      paintTargetTiles and paintTargetTiles.frameValue or 0,
      paintSourceTiles and paintSourceTiles.frameValue or 0,
      paintDupTargets and paintDupTargets.frameValue or 0
    )
  end

  return lines
end

function DebugController.getHudSummaryLines()
  local lines = {
    string.format("Dev HUD: %s", hudMode),
  }
  if hudModeIncludes("perf") then
    local perfLines = DebugController.getPerfSummaryLines()
    for _, line in ipairs(perfLines) do
      lines[#lines + 1] = line
    end
  end
  if hudModeIncludes("debug") then
    local debugLines = DebugController.getDebugSummaryLines()
    for _, line in ipairs(debugLines) do
      lines[#lines + 1] = line
    end
  end
  return lines
end

function DebugController.copyPerfSnapshotToClipboard()
  local lines = DebugController.getPerfSummaryLines()
  local text = table.concat(lines, "\n")
  if love and love.system and love.system.setClipboardText then
    love.system.setClipboardText(text)
  end
  if debugEnabled then
    for _, line in ipairs(lines) do
      DebugController.log("info", "PERF", "%s", line)
    end
  else
    print("[PERF] " .. text:gsub("\n", "\n[PERF] "))
  end
  return text
end

function DebugController.copyDevSnapshotToClipboard()
  local sections = {}
  local hudLines = DebugController.getHudSummaryLines()
  if #hudLines > 0 then
    sections[#sections + 1] = table.concat(hudLines, "\n")
  end
  if #debugLog > 0 then
    sections[#sections + 1] = "Debug Log:"
    sections[#sections + 1] = table.concat(debugLog, "\n")
  end

  local text = table.concat(sections, "\n")
  if love and love.system and love.system.setClipboardText then
    love.system.setClipboardText(text)
  end
  if debugEnabled and #hudLines > 0 then
    for _, line in ipairs(hudLines) do
      DebugController.log("info", "PERF", "%s", line)
    end
  end
  return text
end

-- Get the current debug log (for inspection, if needed)
function DebugController.getLog()
  return debugLog
end

-- Get the number of log entries
function DebugController.getLogCount()
  return #debugLog
end

-- Set category filter - only logs matching the specified categories will be printed/stored
-- @param category: Category to filter by (string), table of categories (array of strings), or nil to clear the filter
-- Examples:
--   setCategoryFilter("SPRITE") -- single category
--   setCategoryFilter({"SPRITE", "UNDO"}) -- multiple categories
--   setCategoryFilter(nil) -- clear filter
function DebugController.setCategoryFilter(category)
  -- Normalize single-element tables to strings for backward compatibility
  if category and type(category) == "table" and #category == 1 then
    categoryFilter = category[1]
  else
    categoryFilter = category
  end
  
  if category then
    local filterStr
    if type(category) == "table" then
      filterStr = table.concat(category, ", ")
    else
      filterStr = tostring(category)
    end
  else
    local msg = "Debug category filter cleared"
    print(string.format("[DEBUG] %s", msg))
    if debugEnabled then
      DebugController.log("info", "DEBUG", msg)
    end
  end
end

-- Get the current category filter
-- Returns: string (single category), table (multiple categories), or nil (no filter)
function DebugController.getCategoryFilter()
  return categoryFilter
end

-- Initialize debug manager (can be called at startup)
function DebugController.init(v)
  debugEnabled = v or false
  debugLog = {}
  categoryFilter = nil
  hudMode = "off"
  lastActiveHudMode = "perf+debug"
  DebugController.perfReset()
end

-- Export as module
local M = {}
M.log = DebugController.log
M.toggle = DebugController.toggle
M.isEnabled = DebugController.isEnabled
M.clear = DebugController.clear
M.copyToClipboard = DebugController.copyToClipboard
M.getLog = DebugController.getLog
M.getLogCount = DebugController.getLogCount
M.setCategoryFilter = DebugController.setCategoryFilter
M.getCategoryFilter = DebugController.getCategoryFilter
M.init = DebugController.init
M.perfToggleHud = DebugController.perfToggleHud
M.perfIsHudEnabled = DebugController.perfIsHudEnabled
M.setHudMode = DebugController.setHudMode
M.getHudMode = DebugController.getHudMode
M.toggleHud = DebugController.toggleHud
M.cycleHudMode = DebugController.cycleHudMode
M.getHudModeLabel = DebugController.getHudModeLabel
M.hudModeIncludes = DebugController.hudModeIncludes
M.perfReset = DebugController.perfReset
M.perfBeginFrame = DebugController.perfBeginFrame
M.perfEndFrame = DebugController.perfEndFrame
M.perfIncrement = DebugController.perfIncrement
M.perfObserveMs = DebugController.perfObserveMs
M.perfSet = DebugController.perfSet
M.getPerfSnapshot = DebugController.getPerfSnapshot
M.getDebugSummaryLines = DebugController.getDebugSummaryLines
M.getPerfSummaryLines = DebugController.getPerfSummaryLines
M.getHudSummaryLines = DebugController.getHudSummaryLines
M.copyPerfSnapshotToClipboard = DebugController.copyPerfSnapshotToClipboard
M.copyDevSnapshotToClipboard = DebugController.copyDevSnapshotToClipboard

return M
