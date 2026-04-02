local M = {}

function M.create(opts)
  opts = opts or {}

  local isHighSpeedMode = opts.isHighSpeedMode or function()
    return false
  end
  local isInteractiveFrame = opts.isInteractiveFrame or function()
    return false
  end

  local backgroundSleepSeconds = tonumber(opts.backgroundSleepSeconds) or 0.01
  local focusedSleepSeconds = tonumber(opts.focusedSleepSeconds) or 0.001
  local normalSleepSeconds = tonumber(opts.normalSleepSeconds) or 0.001

  return function()
    if love.load then
      love.load(love.arg.parseGameArguments(arg), arg)
    end

    if love.timer then
      love.timer.step()
    end

    return function()
      if love.event then
        love.event.pump()
        for name, a, b, c, d, e, f, g, h in love.event.poll() do
          if name == "quit" then
            if not love.quit or not love.quit() then
              return a or 0
            end
          end
          love.handlers[name](a, b, c, d, e, f, g, h)
        end
      end

      local dt = 0
      if love.timer then
        dt = love.timer.step()
      end

      if love.update then
        love.update(dt)
      end

      if love.graphics and love.graphics.isActive() then
        love.graphics.origin()
        love.graphics.clear(love.graphics.getBackgroundColor())

        if love.draw then
          love.draw()
        end

        love.graphics.present()
      end

      if love.timer then
        if isHighSpeedMode() then
          if isInteractiveFrame() then
            love.timer.sleep(0)
          elseif love.window and love.window.hasFocus and not love.window.hasFocus() then
            love.timer.sleep(backgroundSleepSeconds)
          else
            love.timer.sleep(focusedSleepSeconds)
          end
        else
          love.timer.sleep(normalSleepSeconds)
        end
      end
    end
  end
end

return M
