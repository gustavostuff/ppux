local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

function M.handleEditModeKeys(ctx, utils, key)
  if ctx.getMode() ~= "edit" then return false end

  if utils.altDown() and (key == "1" or key == "2" or key == "3" or key == "4") then
    local app = ctx.app
    if app and utils.changeBrushSize then
      local size = tonumber(key)
      utils.changeBrushSize(app, size)
      return true
    end
  end

  if not utils.altDown() and not utils.ctrlDown() and (key == "1" or key == "2" or key == "3" or key == "4") then
    local colorIndex = tonumber(key) - 1
    ctx.setColor(colorIndex)
    ctx.setStatus(string.format("Color: %d", colorIndex))
    return true
  end

  return false
end

function M.handleAttrModeToggle(ctx, key, focus)
  if key ~= "a" then return false end
  if ctx.getMode() == "edit" then return false end

  local w = focus
  if not w then return false end
  if not WindowCaps.isPpuFrame(w) then return false end
  if not (w.layers and w.getActiveLayerIndex) then return false end

  local li = w:getActiveLayerIndex()
  local layer = w.layers[li]
  if not layer or layer.kind == "sprite" then return false end

  layer.attrMode = not layer.attrMode
  ctx.setStatus(layer.attrMode and "Attr mode ON" or "Attr mode OFF")
  return true
end

function M.handleShaderToggle(ctx, key, focus)
  if key ~= "r" then return false end
  if WindowCaps.isAnyPaletteWindow(focus) then return false end

  local w = focus
  if not w then return false end
  if not (w.layers and w.getActiveLayerIndex) then return false end

  local li = w:getActiveLayerIndex()
  local layer = w.layers[li]
  if not layer then return false end

  if layer.shaderEnabled == nil then
    layer.shaderEnabled = true
  end
  layer.shaderEnabled = not layer.shaderEnabled

  ctx.setStatus(layer.shaderEnabled and "Shader rendering ON" or "Shader rendering OFF (raw pixels)")
  return true
end

function M.handleUndoRedo(ctx, utils, key)
  if not utils.ctrlDown() then return false end

  local app = ctx.app
  if not app or not app.undoRedo then return false end

  if key == "z" then
    if app.undoRedo:undo(app) then
      ctx.setStatus("Undo")
      return true
    end
  elseif key == "y" then
    if app.undoRedo:redo(app) then
      ctx.setStatus("Redo")
      return true
    end
  end

  return false
end

return M
