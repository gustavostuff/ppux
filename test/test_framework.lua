-- test_framework.lua
-- Simple test framework for LÖVE2D

local TestFramework = {}

-- Test state
local testState = {
  suites = {},
  currentSuite = nil,
  currentTest = nil,
  totalTests = 0,
  passedTests = 0,
  failedTests = 0,
  errors = {},
  isRunning = false,
  isComplete = false,
}

-- Reset test state
function TestFramework.reset()
  testState = {
    suites = {},
    currentSuite = nil,
    currentTest = nil,
    totalTests = 0,
    passedTests = 0,
    failedTests = 0,
    errors = {},
    isRunning = false,
    isComplete = false,
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

-- Run all tests
function TestFramework.run()
  -- Reset counters
  testState.totalTests = 0
  testState.passedTests = 0
  testState.failedTests = 0
  testState.errors = {}
  testState.isRunning = true
  testState.isComplete = false
  
  -- Helper to collect parent beforeEach/afterEach hooks (excluding current suite)
  local function getParentHooks(suite)
    local beforeHooks = {}
    local afterHooks = {}
    local current = suite.parent
    while current do
      if current.beforeEach then
        table.insert(beforeHooks, 1, current.beforeEach) -- Insert at beginning to run parent first
      end
      if current.afterEach then
        table.insert(afterHooks, current.afterEach) -- Append to run parent after child
      end
      current = current.parent
    end
    return beforeHooks, afterHooks
  end
  
  -- Helper to run a suite and its nested suites recursively
  local function runSuite(suite, indent)
    indent = indent or ""
    
    for _, test in ipairs(suite.tests) do
      testState.totalTests = testState.totalTests + 1
      testState.currentTest = test

      -- Always run cleanup hooks even if beforeEach/test fails.
      -- We preserve the primary failure and append cleanup failures for context.
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

      -- Run current suite's afterEach first, then parent hooks, regardless of failure.
      runHook("afterEach", suite.afterEach)
      for i, hook in ipairs(afterHooks) do
        runHook("afterEach(parent " .. i .. ")", hook)
      end

      if #failures == 0 then
        testState.passedTests = testState.passedTests + 1
        test.passed = true
      else
        testState.failedTests = testState.failedTests + 1
        test.passed = false
        test.error = table.concat(failures, "\n")
        table.insert(testState.errors, {
          suite = suite.name,
          test = test.name,
          error = test.error,
        })
      end
    end
    
    -- Run nested suites
    if suite.children then
      for _, childSuite in ipairs(suite.children) do
        runSuite(childSuite, indent .. "  ")
      end
    end
  end
  
  -- Run all top-level suites
  for _, suite in ipairs(testState.suites) do
    runSuite(suite)
  end
  
  testState.isRunning = false
  testState.isComplete = true
  
  return testState.failedTests == 0
end

-- Get test state for rendering
function TestFramework.getState()
  return testState
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
