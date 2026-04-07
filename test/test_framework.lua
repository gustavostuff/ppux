-- test_framework.lua
-- Simple test framework for LÖVE2D

local TestFramework = {}

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

-- Test state
local testState = {
  suites = {},
  currentSuite = nil,
  currentTest = nil,
  currentTask = nil,
  totalTests = 0,
  passedTests = 0,
  failedTests = 0,
  errors = {},
  isRunning = false,
  isComplete = false,
  liveLog = {},
  runQueue = {},
  nextRunIndex = 1,
  completedTests = {},
}

-- Reset test state
function TestFramework.reset()
  testState = {
    suites = {},
    currentSuite = nil,
    currentTest = nil,
    currentTask = nil,
    totalTests = 0,
    passedTests = 0,
    failedTests = 0,
    errors = {},
    isRunning = false,
    isComplete = false,
    liveLog = {},
    runQueue = {},
    nextRunIndex = 1,
    completedTests = {},
  }
end

-- Expect assertion builder
function TestFramework.expect(actual)
  local matchers = {
    actual = actual,
    
    toBe = function(expected)
      if actual ~= expected then
        error(string.format("Expected %s to be %s", tostring(actual), tostring(expected)))
      end
    end,
    
    toEqual = function(expected)
      -- Deep equality check for tables
      local function deepEqual(a, b)
        if a == b then return true end
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        
        local keys = {}
        for k in pairs(a) do keys[k] = true end
        for k in pairs(b) do
          if not keys[k] then return false end
          keys[k] = nil
        end
        for k in pairs(keys) do return false end
        
        for k, v in pairs(a) do
          if not deepEqual(v, b[k]) then return false end
        end
        return true
      end
      
      if not deepEqual(actual, expected) then
        error(string.format("Expected %s to equal %s", 
          TestFramework.inspect(actual), 
          TestFramework.inspect(expected)))
      end
    end,
    
    toBeNil = function()
      if actual ~= nil then
        error(string.format("Expected %s to be nil", tostring(actual)))
      end
    end,
    
    toBeTruthy = function()
      if not actual then
        error(string.format("Expected %s to be truthy", tostring(actual)))
      end
    end,
    
    toBeFalsy = function()
      if actual then
        error(string.format("Expected %s to be falsy", tostring(actual)))
      end
    end,
    
    toThrow = function(expectedError)
      local success, err = pcall(function()
        if type(actual) == "function" then
          actual()
        end
      end)
      
      if success then
        error("Expected function to throw an error")
      end
      
      if expectedError and not string.find(tostring(err), tostring(expectedError), 1, true) then
        error(string.format("Expected error to contain '%s', got '%s'", 
          tostring(expectedError), tostring(err)))
      end
    end,
    
    toBeGreaterThan = function(expected)
      if actual <= expected then
        error(string.format("Expected %s to be greater than %s", tostring(actual), tostring(expected)))
      end
    end,
    
    toBeGreaterThanOrEqual = function(expected)
      if actual < expected then
        error(string.format("Expected %s to be greater than or equal to %s", tostring(actual), tostring(expected)))
      end
    end,
    
    toBeLessThan = function(expected)
      if actual >= expected then
        error(string.format("Expected %s to be less than %s", tostring(actual), tostring(expected)))
      end
    end,
    
    toNotBe = function(expected)
      if actual == expected then
        error(string.format("Expected %s to not be %s", tostring(actual), tostring(expected)))
      end
    end,
  }
  
  return matchers
end

-- Helper to inspect values for error messages
function TestFramework.inspect(value)
  if type(value) == "table" then
    local parts = {}
    for k, v in pairs(value) do
      if type(k) == "number" then
        table.insert(parts, TestFramework.inspect(v))
      else
        table.insert(parts, string.format("%s=%s", k, TestFramework.inspect(v)))
      end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  elseif type(value) == "string" then
    return '"' .. value .. '"'
  else
    return tostring(value)
  end
end

-- Describe block - groups related tests
function TestFramework.describe(name, fn)
  local suite = {
    name = name,
    tests = {},
    beforeEach = nil,
    afterEach = nil,
    parent = testState.currentSuite,
  }
  
  local previousSuite = testState.currentSuite
  testState.currentSuite = suite
  
  -- Run the suite definition function
  local success, err = pcall(fn)
  if not success then
    -- Store suite error
    table.insert(testState.errors, {
      suite = name,
      test = "(suite setup)",
      error = tostring(err),
    })
    testState.failedTests = testState.failedTests + 1
  end
  
  -- Only add top-level suites to the list (not nested ones)
  if not previousSuite then
    table.insert(testState.suites, suite)
  else
    -- For nested suites, add them as children
    previousSuite.children = previousSuite.children or {}
    table.insert(previousSuite.children, suite)
  end
  
  testState.currentSuite = previousSuite
end

-- Individual test
function TestFramework.it(name, fn)
  if not testState.currentSuite then
    error("it() called outside of describe() block")
  end
  
  local test = {
    name = name,
    fn = fn,
  }
  
  table.insert(testState.currentSuite.tests, test)
end

local function getSuitePath(suite)
  local parts = {}
  local current = suite
  while current do
    table.insert(parts, 1, current.name or "(unnamed suite)")
    current = current.parent
  end
  return table.concat(parts, " > ")
end

local function getParentHooks(suite)
  local beforeHooks = {}
  local afterHooks = {}
  local current = suite and suite.parent or nil
  while current do
    if current.beforeEach then
      table.insert(beforeHooks, 1, current.beforeEach)
    end
    if current.afterEach then
      table.insert(afterHooks, current.afterEach)
    end
    current = current.parent
  end
  return beforeHooks, afterHooks
end

local function buildRunQueue()
  local queue = {}

  local function enqueueSuite(suite)
    for _, test in ipairs(suite.tests or {}) do
      queue[#queue + 1] = {
        suite = suite,
        test = test,
        suitePath = getSuitePath(suite),
      }
    end
    for _, childSuite in ipairs(suite.children or {}) do
      enqueueSuite(childSuite)
    end
  end

  for _, suite in ipairs(testState.suites or {}) do
    enqueueSuite(suite)
  end

  return queue
end

local function runQueuedTest(task)
  local suite = task.suite
  local test = task.test
  local startedAt = nowSeconds()
  testState.currentTask = task
  testState.currentSuite = suite
  testState.currentTest = test

  local beforeHooks, afterHooks = getParentHooks(suite)
  local failures = {}

  local function recordFailure(label, err)
    failures[#failures + 1] = string.format("%s: %s", label, tostring(err))
  end

  local function runHook(label, hook)
    if type(hook) ~= "function" then return true end
    local ok, err = pcall(hook)
    if not ok then
      recordFailure(label, err)
      return false
    end
    return true
  end

  local canRunTest = true
  for i, hook in ipairs(beforeHooks) do
    if not runHook("beforeEach(parent " .. i .. ")", hook) then
      canRunTest = false
      break
    end
  end

  if canRunTest and suite.beforeEach then
    if not runHook("beforeEach", suite.beforeEach) then
      canRunTest = false
    end
  end

  if canRunTest then
    local ok, err = pcall(test.fn)
    if not ok then
      recordFailure("test", err)
    end
  end

  runHook("afterEach", suite.afterEach)
  for i, hook in ipairs(afterHooks) do
    runHook("afterEach(parent " .. i .. ")", hook)
  end

  test.finished = true
  test.durationSeconds = math.max(0, nowSeconds() - startedAt)
  if #failures == 0 then
    testState.passedTests = testState.passedTests + 1
    test.passed = true
    test.error = nil
  else
    testState.failedTests = testState.failedTests + 1
    test.passed = false
    test.error = table.concat(failures, "\n")
    table.insert(testState.errors, {
      suite = task.suitePath,
      test = test.name,
      error = test.error,
    })
  end

  local completedEntry = {
    suite = task.suitePath,
    test = test.name,
    passed = test.passed == true,
    error = test.error,
    durationSeconds = test.durationSeconds,
    durationMs = test.durationSeconds * 1000,
    index = #testState.completedTests + 1,
  }
  testState.completedTests[#testState.completedTests + 1] = completedEntry
  testState.liveLog[#testState.liveLog + 1] = {
    suite = completedEntry.suite,
    test = completedEntry.test,
    passed = completedEntry.passed,
    error = completedEntry.error,
    durationSeconds = completedEntry.durationSeconds,
    durationMs = completedEntry.durationMs,
    index = completedEntry.index,
  }
end

function TestFramework.startRun()
  testState.totalTests = 0
  testState.passedTests = 0
  testState.failedTests = 0
  testState.errors = {}
  testState.isRunning = true
  testState.isComplete = false
  testState.currentTask = nil
  testState.currentTest = nil
  testState.liveLog = {}
  testState.runQueue = buildRunQueue()
  testState.nextRunIndex = 1
  testState.completedTests = {}
  testState.totalTests = #testState.runQueue
  testState.currentTask = testState.runQueue[1]
  return testState.totalTests
end

function TestFramework.updateRun(maxTestsPerTick)
  if not testState.isRunning then
    return false
  end

  local remaining = math.max(1, math.floor(tonumber(maxTestsPerTick) or 1))
  local processed = 0

  while remaining > 0 do
    local task = testState.runQueue[testState.nextRunIndex]
    if not task then
      testState.isRunning = false
      testState.isComplete = true
      testState.currentTask = nil
      testState.currentTest = nil
      return processed > 0
    end

    runQueuedTest(task)
    testState.nextRunIndex = testState.nextRunIndex + 1
    testState.currentTask = testState.runQueue[testState.nextRunIndex]
    processed = processed + 1
    remaining = remaining - 1
  end

  if not testState.runQueue[testState.nextRunIndex] then
    testState.isRunning = false
    testState.isComplete = true
    testState.currentTask = nil
    testState.currentTest = nil
  end

  return processed > 0
end

-- Run all tests synchronously
function TestFramework.run()
  TestFramework.startRun()
  while testState.isRunning do
    TestFramework.updateRun(testState.totalTests)
  end
  return testState.failedTests == 0
end

-- Get test state for rendering
function TestFramework.getState()
  return testState
end

function TestFramework.getSlowestTests(limit)
  local items = {}
  for i, entry in ipairs(testState.completedTests or {}) do
    items[i] = entry
  end

  table.sort(items, function(a, b)
    local ad = tonumber(a and a.durationSeconds) or 0
    local bd = tonumber(b and b.durationSeconds) or 0
    if ad == bd then
      return (tonumber(a and a.index) or 0) < (tonumber(b and b.index) or 0)
    end
    return ad > bd
  end)

  local maxItems = math.max(0, math.floor(tonumber(limit) or #items))
  while #items > maxItems do
    items[#items] = nil
  end
  return items
end

-- Setup hooks for current suite
function TestFramework.beforeEach(fn)
  if not testState.currentSuite then
    error("beforeEach() called outside of describe() block")
  end
  testState.currentSuite.beforeEach = fn
end

function TestFramework.afterEach(fn)
  if not testState.currentSuite then
    error("afterEach() called outside of describe() block")
  end
  testState.currentSuite.afterEach = fn
end

-- Expose global functions
function TestFramework.setupGlobals()
  _G.describe = TestFramework.describe
  _G.it = TestFramework.it
  _G.expect = TestFramework.expect
  _G.beforeEach = TestFramework.beforeEach
  _G.afterEach = TestFramework.afterEach
end

return TestFramework
