local WindowCaps = require("controllers.window.window_capabilities")
local CursorsController = require("controllers.input_support.cursors_controller")

local M = {}

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

function M.handleEditModeKeys(ctx, utils, key)
  if ctx.getMode() ~= "edit" then return false end
  local app = ctx.app

  if utils.altDown() and (key == "1" or key == "2" or key == "3" or key == "4") then
    if app and utils.changeBrushSize then
      local size = tonumber(key)
      utils.changeBrushSize(app, size)
      return true
    end
  end

  if not utils.altDown() and not utils.ctrlDown() and (key == "1" or key == "2" or key == "3" or key == "4") then
    local colorIndex = tonumber(key) - 1
    ctx.setColor(colorIndex)
    setStatus(ctx, string.format("Color: %d", colorIndex))
    return true
  end

  if key == "r" and not utils.ctrlDown() and not utils.altDown() then
    if not app then return false end
    app.editTool = (app.editTool == "rect_fill") and "pencil" or "rect_fill"
    CursorsController.applyModeCursor(app, ctx.getMode())
    setStatus(ctx, (app.editTool == "rect_fill") and "Rect fill tool" or "Pencil tool")
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
  if w.invalidateNametableLayerCanvas then
    w:invalidateNametableLayerCanvas(li)
  end
  setStatus(ctx, layer.attrMode and "Attr mode ON" or "Attr mode OFF")
  return true
end

function M.handleShaderToggle(ctx, utils, key, focus)
  if key ~= "r" then return false end
  if not (utils and utils.ctrlDown and utils.ctrlDown()) then return false end
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
  if WindowCaps.isPpuFrame(w) and layer.kind == "tile" and w.invalidateNametableLayerCanvas then
    w:invalidateNametableLayerCanvas(li)
  end

  setStatus(ctx, layer.shaderEnabled and "Shader rendering ON" or "Shader rendering OFF (raw pixels)")
  return true
end

function M.handleUndoRedo(ctx, utils, key)
  if not utils.ctrlDown() then return false end

  local app = ctx.app
  if not app or not app.undoRedo then return false end

  if key == "z" then
    if app.undoRedo:undo(app) then
      setStatus(ctx, "Undo")
      return true
    end
  elseif key == "y" then
    if app.undoRedo:redo(app) then
      setStatus(ctx, "Redo")
      return true
    end
  end

  return false
end

return M
