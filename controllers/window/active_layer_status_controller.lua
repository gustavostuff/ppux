-- Status bar line when the user switches the active layer in a multi-layer window.
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local function windowTitle(win)
  if win and type(win.title) == "string" and win.title ~= "" then
    return win.title
  end
  if win and win.kind then
    return tostring(win.kind)
  end
  return "Window"
end

function M.tryNotify(win, oldIndex, newIndex)
  if not win or type(newIndex) ~= "number" or oldIndex == newIndex then
    return
  end

  local ctx = rawget(_G, "ctx")
  local app = ctx and ctx.app
  if not (app and type(app.setStatus) == "function") then
    return
  end

  if WindowCaps.isAnyPaletteWindow(win) then
    return
  end

  if WindowCaps.isChrLike(win) then
    return
  end

  if WindowCaps.isCrtLens(win) then
    local n = win.getLayerCount and win:getLayerCount() or 0
    if n <= 0 then
      return
    end
    app:setStatus(string.format("%s: reference %d/%d", windowTitle(win), newIndex, n))
    return
  end

  local layers = win.layers
  local n = type(layers) == "table" and #layers or 0
  if n <= 0 then
    return
  end

  local L = layers[newIndex]
  local label
  if L and type(L.name) == "string" and L.name ~= "" then
    label = L.name
  else
    label = "Layer " .. tostring(newIndex)
  end

  app:setStatus(string.format("%s: %s (%d/%d)", windowTitle(win), label, newIndex, n))
end

return M
