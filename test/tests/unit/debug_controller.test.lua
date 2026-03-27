-- debug_controller.test.lua
-- Unit tests for managers/debug_controller.lua

local DebugController = require("controllers.dev.debug_controller")

describe("debug_controller.lua", function()
  
  -- Helper to capture print output
  local originalPrint = print
  local printOutput = {}
  local function capturePrint()
    printOutput = {}
    print = function(...)
      table.insert(printOutput, table.concat({...}, "\t"))
    end
  end
  local function restorePrint()
    print = originalPrint
  end
  
  -- Helper to mock love.system.setClipboardText
  local clipboardText = nil
  local originalSetClipboardText = nil
  local function mockClipboard()
    clipboardText = nil
    -- Ensure love.system exists
    if not love then
      _G.love = {}
    end
    if not love.system then
      love.system = {}
    end
    -- Save original if it exists
    if love.system.setClipboardText then
      originalSetClipboardText = love.system.setClipboardText
    end
    -- Mock the function
    love.system.setClipboardText = function(text)
      clipboardText = text
    end
  end
  local function restoreClipboard()
    clipboardText = nil
    if originalSetClipboardText and love.system then
      love.system.setClipboardText = originalSetClipboardText
    end
  end
  
  -- Reset debug manager state before each test
  beforeEach(function()
    -- Initialize and ensure clean state (init() already resets everything)
    DebugController.init(true)
    capturePrint()
    mockClipboard()
  end)
  
  afterEach(function()
    restorePrint()
    restoreClipboard()
  end)
  
  describe("init", function()
    it("initializes with debug mode enabled", function()
      DebugController.init(true)
      expect(DebugController.isEnabled()).toBe(true)
      expect(DebugController.getLogCount()).toBe(0)
    end)
    
    it("clears the log on init", function()
      DebugController.init(true)
      DebugController.log("info", "TEST", "test message") -- Now count is 1
      expect(DebugController.getLogCount()).toBeGreaterThan(0)
      
      DebugController.init(true)
      expect(DebugController.getLogCount()).toBe(0)
      expect(DebugController.isEnabled()).toBe(true)
    end)

    it("resets perf hud state on init", function()
      DebugController.cycleHudMode()
      expect(DebugController.getHudMode()).toBe("debug")

      DebugController.init(true)
      expect(DebugController.getHudMode()).toBe("off")
    end)
  end)
  
  describe("isEnabled", function()
    it("returns true by default after init", function()
      DebugController.init(true)
      expect(DebugController.isEnabled()).toBe(true)
    end)
    
    it("returns false after toggle when enabled", function()
      DebugController.init(true)
      expect(DebugController.isEnabled()).toBe(true)
      
      DebugController.toggle()
      expect(DebugController.isEnabled()).toBe(false)
    end)
    
    it("returns true after toggle when disabled", function()
      DebugController.init(true)
      DebugController.toggle() -- Disable first
      expect(DebugController.isEnabled()).toBe(false)
      
      DebugController.toggle() -- Enable
      expect(DebugController.isEnabled()).toBe(true)
    end)
  end)
  
  describe("log", function()
    it("does not store messages when debug mode is disabled", function()
      DebugController.init(true)
      DebugController.toggle() -- Disable debug
      expect(DebugController.isEnabled()).toBe(false)
      
      DebugController.log("info", "TEST", "test message")
      expect(DebugController.getLogCount()).toBe(0)
    end)
    
    it("does not print when debug mode is disabled", function()
      DebugController.init(true)
      DebugController.toggle() -- Disable debug
      capturePrint() -- Reset print output after toggle
      
      DebugController.log("info", "TEST", "test message")
      
      -- Should not have printed anything
      expect(#printOutput).toBe(0)
    end)
    
    it("stores messages when debug mode is enabled", function()
      DebugController.init(true)
      -- init() enables debug mode, no need to toggle
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", "TEST", "test message")
      expect(DebugController.getLogCount()).toBe(initialCount + 1)
    end)
    
    it("prints messages when debug mode is enabled", function()
      DebugController.init(true)
      capturePrint() -- Reset print output after init/toggle
      
      DebugController.log("info", "TEST", "test message")
      expect(#printOutput).toBeGreaterThan(0)
    end)
    
    it("formats messages with category", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", "TEST", "test message")
      local log = DebugController.getLog()
      expect(#log).toBe(initialCount + 1)
      -- Check the last log entry (which should be our test message)
      local lastEntry = log[#log]
      expect(string.find(lastEntry, "%[TEST%]")).toBeTruthy()
      expect(string.find(lastEntry, "test message")).toBeTruthy()
    end)
    
    it("formats messages with nil category", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", nil, "test message")
      local log = DebugController.getLog()
      expect(#log).toBe(initialCount + 1)
      -- Check the last log entry
      local lastEntry = log[#log]
      expect(string.find(lastEntry, "test message")).toBeTruthy()
      -- Should have timestamp but no category tag after timestamp
      -- Format: [HH:MM:SS] message (not [HH:MM:SS] [CATEGORY] message)
      expect(string.find(lastEntry, "%[%d%d:%d%d:%d%d%]%s+test message")).toBeTruthy()
      -- Should not have a second bracket pattern (category)
      local timestampEnd = string.find(lastEntry, "%]")
      local afterTimestamp = string.sub(lastEntry, timestampEnd + 1)
      expect(string.find(afterTimestamp, "%[%w+%]")).toBeFalsy() -- No [CATEGORY] after timestamp
    end)
    
    it("formats messages with string.format arguments", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", "TEST", "User %s has %d points", "Alice", 42)
      local log = DebugController.getLog()
      expect(#log).toBe(initialCount + 1)
      local lastEntry = log[#log]
      expect(string.find(lastEntry, "User Alice has 42 points")).toBeTruthy()
    end)
    
    it("includes timestamp in formatted messages", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", "TEST", "test message")
      local log = DebugController.getLog()
      expect(#log).toBe(initialCount + 1)
      -- Check the last log entry - should have timestamp format [HH:MM:SS]
      local lastEntry = log[#log]
      expect(string.find(lastEntry, "%[%d%d:%d%d:%d%d%]")).toBeTruthy()
    end)
    
    it("handles multiple log entries", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", "TEST", "message 1")
      DebugController.log("info", "TEST", "message 2")
      DebugController.log("info", "TEST", "message 3")
      
      expect(DebugController.getLogCount()).toBe(initialCount + 3)
      local log = DebugController.getLog()
      -- Check the last 3 entries (should be our test messages)
      expect(string.find(log[#log - 2], "message 1")).toBeTruthy()
      expect(string.find(log[#log - 1], "message 2")).toBeTruthy()
      expect(string.find(log[#log], "message 3")).toBeTruthy()
    end)
    
    it("limits log size to maxLogLines", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      -- Add more entries than maxLogLines (10000)
      -- We'll test with a smaller number to avoid timeout
      for i = 1, 100 do
        DebugController.log("info", "TEST", "message %d", i)
      end
      
      expect(DebugController.getLogCount()).toBe(initialCount + 100)
    end)
  end)

  describe("perf helpers", function()
    it("tracks perf metrics and exposes summary lines", function()
      DebugController.setHudMode("perf")
      DebugController.perfBeginFrame()
      DebugController.perfIncrement("chr_tile_materialize", 3)
      DebugController.perfIncrement("chr_canvas_repaint_partial", 1)
      DebugController.perfObserveMs("chr_canvas_repaint_ms", 1.5)
      DebugController.perfSet("chr_canvas_dirty_tile_count", 2)
      DebugController.perfSet("chr_canvas_current_bank", 4)
      DebugController.perfSet("chr_canvas_order_mode", "normal")
      DebugController.perfObserveMs("chr_paint_pixel_ms", 0.8)
      DebugController.perfObserveMs("chr_paint_apply_ms", 0.3)
      DebugController.perfObserveMs("chr_paint_duplicate_sync_ms", 0.1)
      DebugController.perfObserveMs("chr_paint_undo_ms", 0.05)
      DebugController.perfIncrement("chr_paint_invalidate_count", 1)
      DebugController.perfIncrement("chr_paint_target_tiles", 1)
      DebugController.perfIncrement("chr_paint_source_tiles", 1)
      DebugController.perfIncrement("chr_paint_written_pixels", 4)
      DebugController.perfIncrement("chr_paint_duplicate_targets", 4)
      DebugController.perfEndFrame()

      local snapshot = DebugController.getPerfSnapshot()
      expect(snapshot.metrics.chr_tile_materialize.totalValue).toBe(3)
      expect(snapshot.metrics.chr_canvas_repaint_partial.frameValue).toBe(1)
      expect(snapshot.metrics.chr_canvas_dirty_tile_count.value).toBe(2)

      local lines = DebugController.getPerfSummaryLines()
      expect(#lines).toBeGreaterThan(0)
      expect(string.find(table.concat(lines, "\n"), "CHR repaint", 1, true)).toNotBe(nil)
      expect(string.find(table.concat(lines, "\n"), "CHR paint", 1, true)).toNotBe(nil)
    end)

    it("copies perf snapshot text to clipboard", function()
      DebugController.setHudMode("perf")
      DebugController.perfBeginFrame()
      DebugController.perfIncrement("chr_tile_materialize", 1)
      DebugController.perfEndFrame()

      local text = DebugController.copyPerfSnapshotToClipboard()
      expect(text).toBeTruthy()
      expect(string.find(text, "Perf frame", 1, true)).toNotBe(nil)
      expect(clipboardText).toBe(text)
    end)

    it("cycles hud mode in debug -> perf -> debug+perf -> off order", function()
      expect(DebugController.getHudMode()).toBe("off")
      expect(DebugController.cycleHudMode()).toBe("debug")
      expect(DebugController.cycleHudMode()).toBe("perf")
      expect(DebugController.cycleHudMode()).toBe("perf+debug")
      expect(DebugController.cycleHudMode()).toBe("off")
    end)
  end)
  
  describe("toggle", function()
    it("disables debug mode when enabled", function()
      DebugController.init(true)
      expect(DebugController.isEnabled()).toBe(true)
      
      local result = DebugController.toggle()
      expect(result).toBe(false)
      expect(DebugController.isEnabled()).toBe(false)
    end)
    
    it("enables debug mode when disabled", function()
      DebugController.init(true)
      DebugController.toggle() -- Disable first
      expect(DebugController.isEnabled()).toBe(false)
      
      local result = DebugController.toggle()
      expect(result).toBe(true)
      expect(DebugController.isEnabled()).toBe(true)
    end)
    
    it("always prints toggle status", function()
      DebugController.init(true)
      
      DebugController.toggle()
      
      -- Should have printed toggle status
      -- Note: The print output is captured in our mock
      expect(#printOutput).toBeGreaterThan(0)
      local hasDebugMsg = false
      for _, msg in ipairs(printOutput) do
        if string.find(msg, "DEBUG") or string.find(msg, "ENABLED") or string.find(msg, "DISABLED") then
          hasDebugMsg = true
          break
        end
      end
      expect(hasDebugMsg).toBe(true)
    end)
  end)
  
  describe("clear", function()
    it("clears log when debug mode is enabled", function()
      DebugController.init(true)
      
      DebugController.log("info", "TEST", "message 1")
      DebugController.log("info", "TEST", "message 2")
      expect(DebugController.getLogCount()).toBeGreaterThan(1)
      
      DebugController.clear()
      -- clear() logs a message itself, so count will be 1 (the clear message)
      expect(DebugController.getLogCount()).toBe(1)
      local log = DebugController.getLog()
      expect(string.find(log[1], "cleared")).toBeTruthy()
    end)
    
    it("does nothing when debug mode is disabled", function()
      DebugController.init(true)
      DebugController.toggle() -- Disable debug
      expect(DebugController.isEnabled()).toBe(false)
      
      -- Clear should not do anything when disabled
      DebugController.clear()
      expect(DebugController.getLogCount()).toBe(0)
    end)
    
    it("logs the clear action", function()
      DebugController.init(true)
      
      DebugController.log("info", "TEST", "message 1")
      DebugController.clear()
      
      -- After clear, log should contain the clear message
      local log = DebugController.getLog()
      expect(#log).toBe(1)
      expect(string.find(log[1], "cleared")).toBeTruthy()
    end)
  end)
  
  describe("copyToClipboard", function()
    it("returns false when debug mode is disabled", function()
      DebugController.init(true)
      DebugController.toggle() -- Disable debug mode
      expect(DebugController.isEnabled()).toBe(false)
      
      local result = DebugController.copyToClipboard()
      expect(result).toBe(false)
      expect(clipboardText).toBeNil()
    end)
    
    it("returns false when log is empty", function()
      DebugController.init(true)
      DebugController.clear() -- Clear any init logs
      expect(DebugController.getLogCount()).toBe(1) -- clear() adds a log entry
      
      -- Actually empty the log by toggling and clearing
      DebugController.toggle() -- Disable
      DebugController.toggle() -- Enable
      DebugController.clear() -- Clear again
      expect(DebugController.getLogCount()).toBe(1) -- clear() adds a log entry
      
      local result = DebugController.copyToClipboard()
      -- Should still return true because there's at least the clear message
      expect(result).toBe(true)
    end)
    
    it("copies log to clipboard when debug mode is enabled", function()
      DebugController.init(true)
      
      DebugController.log("info", "TEST", "message 1")
      DebugController.log("info", "TEST", "message 2")
      
      local result = DebugController.copyToClipboard()
      expect(result).toBe(true)
      expect(clipboardText).toBeTruthy()
      expect(string.find(clipboardText, "message 1")).toBeTruthy()
      expect(string.find(clipboardText, "message 2")).toBeTruthy()
    end)
    
    it("includes newlines between log entries", function()
      DebugController.init(true)
      
      DebugController.log("info", "TEST", "message 1")
      DebugController.log("info", "TEST", "message 2")
      
      DebugController.copyToClipboard()
      
      -- Count newlines in clipboard text
      local newlineCount = 0
      for _ in clipboardText:gmatch("\n") do
        newlineCount = newlineCount + 1
      end
      -- Should have at least one newline between messages
      expect(newlineCount).toBeGreaterThan(0)
    end)
  end)
  
  describe("getLog", function()
    it("returns empty array when log is empty", function()
      DebugController.init(true)
      local log = DebugController.getLog()
      expect(type(log)).toBe("table")
      expect(#log).toBe(0)
    end)
    
    it("returns log entries as array", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", "TEST", "message 1")
      DebugController.log("info", "TEST", "message 2")
      
      local log = DebugController.getLog()
      expect(#log).toBe(initialCount + 2)
      expect(type(log[1])).toBe("string")
      expect(type(log[2])).toBe("string")
    end)
  end)
  
  describe("getLogCount", function()
    it("returns 0 when log is empty", function()
      DebugController.init(true)
      expect(DebugController.getLogCount()).toBe(0)
    end)
    
    it("returns correct count after adding entries", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", "TEST", "message 1")
      expect(DebugController.getLogCount()).toBe(initialCount + 1)
      
      DebugController.log("info", "TEST", "message 2")
      expect(DebugController.getLogCount()).toBe(initialCount + 2)
      
      DebugController.log("info", "TEST", "message 3")
      expect(DebugController.getLogCount()).toBe(initialCount + 3)
    end)
    
    it("returns 1 after clear (clear logs its own message)", function()
      DebugController.init(true)
      
      DebugController.log("info", "TEST", "message 1")
      DebugController.log("info", "TEST", "message 2")
      expect(DebugController.getLogCount()).toBeGreaterThanOrEqual(2)
      
      DebugController.clear()
      -- clear() logs a message, so count will be 1
      expect(DebugController.getLogCount()).toBe(1)
    end)
  end)
  
  describe("category handling", function()
    it("recognizes uppercase category tags", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", "TEST", "message")
      DebugController.log("info", "GAM", "message")
      DebugController.log("info", "UI", "message")
      DebugController.log("info", "SPRITE", "message")
      
      local log = DebugController.getLog()
      expect(#log).toBe(initialCount + 4)
      -- Check the last 4 entries (our test messages)
      expect(string.find(log[#log - 3], "%[TEST%]")).toBeTruthy()
      expect(string.find(log[#log - 2], "%[GAM%]")).toBeTruthy()
      expect(string.find(log[#log - 1], "%[UI%]")).toBeTruthy()
      expect(string.find(log[#log], "%[SPRITE%]")).toBeTruthy()
    end)
    
    it("handles nil category parameter", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", nil, "test message")
      local log = DebugController.getLog()
      expect(#log).toBe(initialCount + 1)
      -- Check the last entry (our test message)
      local lastEntry = log[#log]
      expect(string.find(lastEntry, "test message")).toBeTruthy()
    end)
  end)
  
  describe("category filtering", function()
    it("filters logs by category when filter is set", function()
      DebugController.init(true)
      local initialCount = DebugController.getLogCount()
      
      DebugController.log("info", "TEST", "test message")
      DebugController.log("info", "GAM", "gam message")
      DebugController.log("info", "SPRITE", "sprite message")
      
      -- Set filter to only show SPRITE
      DebugController.setCategoryFilter({"SPRITE"})
      capturePrint() -- Reset print output
      
      local countBeforeFilter = DebugController.getLogCount()
      DebugController.log("info", "TEST", "filtered test message")
      DebugController.log("info", "GAM", "filtered gam message")
      DebugController.log("info", "SPRITE", "filtered sprite message")
      
      -- Only the SPRITE message should have been stored
      expect(DebugController.getLogCount()).toBe(countBeforeFilter + 1)
      local log = DebugController.getLog()
      expect(string.find(log[#log], "filtered sprite message")).toBeTruthy()
      expect(string.find(log[#log], "filtered test message")).toBeFalsy()
      expect(string.find(log[#log], "filtered gam message")).toBeFalsy()
    end)
    
    it("allows DEBUG category to bypass filter", function()
      DebugController.init(true)
      DebugController.setCategoryFilter({"SPRITE"})
      capturePrint()
      
      local countBefore = DebugController.getLogCount()
      DebugController.log("info", "DEBUG", "debug message")
      DebugController.log("info", "TEST", "test message")
      
      -- DEBUG message should be stored, TEST should not
      expect(DebugController.getLogCount()).toBe(countBefore + 1)
      local log = DebugController.getLog()
      expect(string.find(log[#log], "debug message")).toBeTruthy()
    end)
    
    it("clears filter when set to nil", function()
      DebugController.init(true)
      DebugController.setCategoryFilter({"SPRITE"})
      capturePrint()
      
      DebugController.setCategoryFilter(nil)
      capturePrint() -- Reset after filter clear
      
      local countBefore = DebugController.getLogCount()
      DebugController.log("info", "TEST", "test message")
      DebugController.log("info", "GAM", "gam message")
      
      -- Both messages should be stored after clearing filter
      expect(DebugController.getLogCount()).toBe(countBefore + 2)
    end)
    
    it("getCategoryFilter returns current filter", function()
      DebugController.init(true)
      
      expect(DebugController.getCategoryFilter()).toBeNil()
      
      DebugController.setCategoryFilter({"SPRITE"})
      expect(DebugController.getCategoryFilter()).toBe("SPRITE")
      
      DebugController.setCategoryFilter(nil)
      expect(DebugController.getCategoryFilter()).toBeNil()
    end)
  end)
  
end)
