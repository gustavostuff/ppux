local Timer = {}

-- Internal state
local _nextId  = 0
local _timers  = {}   -- id -> { id, at, fn }
local _marks   = {}   -- name -> timestamp (love.timer.getTime())

----------------------------------------------------------------
-- Timer scheduling
----------------------------------------------------------------

--- Schedule a callback to run after `delay` seconds.
-- @param delay number - delay in seconds
-- @param fn    function - callback to invoke
-- @return integer id - timer id (can be cancelled)
function Timer.after(delay, fn)
  assert(type(delay) == "number" and delay >= 0, "Timer.after: delay must be >= 0")
  assert(type(fn) == "function", "Timer.after: fn must be a function")

  _nextId = _nextId + 1
  local id = _nextId

  local now = love.timer.getTime()
  _timers[id] = {
    id = id,
    at = now + delay,
    fn = fn,
  }

  return id
end

--- Cancel a pending timer by id.
-- Safe to call with an unknown id (no-op).
function Timer.cancel(id)
  _timers[id] = nil
end

--- Cancel all pending timers.
function Timer.clear()
  for k in pairs(_timers) do
    _timers[k] = nil
  end
end

--- Update timers; call this from love.update(dt).
function Timer.update(dt)
  -- dt is not strictly needed since we use absolute time,
  -- but we keep it in the signature for convenience.
  local now = love.timer.getTime()

  -- Collect due timers first to avoid mutation-while-iterating issues.
  local due = {}
  for id, t in pairs(_timers) do
    if now >= t.at then
      due[#due+1] = t
      _timers[id] = nil
    end
  end

  -- Run callbacks after we’ve removed them from the table.
  for i = 1, #due do
    local ok, err = pcall(due[i].fn)
    if not ok then
      -- You can replace this with your own logging if you like.
      print("[Timer] callback error:", err)
    end
  end
end

----------------------------------------------------------------
-- Marks / elapsed time measurement
----------------------------------------------------------------

--- Mark a named event with the current time.
-- Subsequent calls overwrite the previous mark for that name.
-- @param name string
function Timer.mark(name)
  assert(type(name) == "string", "Timer.mark: name must be a string")
  _marks[name] = love.timer.getTime()
end

--- Return seconds elapsed since a given mark name was set.
-- @param name string
-- @return number|nil seconds or nil if mark doesn't exist yet
function Timer.elapsed(name)
  local t = _marks[name]
  if not t then return nil end
  return love.timer.getTime() - t
end

--- Clear a specific mark.
function Timer.clearMark(name)
  _marks[name] = nil
end

--- Clear all marks.
function Timer.clearAllMarks()
  for k in pairs(_marks) do
    _marks[k] = nil
  end
end

return Timer
