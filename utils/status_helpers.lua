-- status_helpers.lua
-- Route status-line updates through app or legacy ctx.setStatus callbacks.

local M = {}

function M.setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

function M.setStatusFromEnv(env, text)
  M.setStatus(env and env.ctx, text)
end

return M
