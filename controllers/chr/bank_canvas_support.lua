local M = {}

local function resolveApp(app)
  if app then
    return app
  end
  local ctx = rawget(_G, "ctx")
  return ctx and ctx.app or nil
end

function M.invalidateBank(app, bankIdx)
  local resolvedApp = resolveApp(app)
  if not (resolvedApp and resolvedApp.invalidateChrBankCanvas) then
    return false
  end
  resolvedApp:invalidateChrBankCanvas(bankIdx)
  return true
end

function M.invalidateTile(app, bankIdx, tileIndex)
  local resolvedApp = resolveApp(app)
  if not (resolvedApp and resolvedApp.invalidateChrBankTileCanvas) then
    return M.invalidateBank(resolvedApp, bankIdx)
  end
  resolvedApp:invalidateChrBankTileCanvas(bankIdx, tileIndex)
  return true
end

return M
