local WindowCaps = require("controllers.window.window_capabilities")
local CursorsController = require("controllers.input_support.cursors_controller")
local PixelSel = require("controllers.game_art.sketch_canvas_pixel_selection_controller")

local M = {}

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
    return true
  end

  -- S: pixel select on sketch canvases (edit mode). Plain drag = rect; Shift+drag = freeform.
  if key == "s" and not utils.ctrlDown() and not utils.altDown() and not utils.shiftDown() then
    if not app then return false end
    local focus = ctx.getFocus and ctx.getFocus() or nil
    if WindowCaps.isSketchCanvas(focus) and not WindowCaps.isSketchReflectNametable(focus) then
      app.editTool = (app.editTool == "rect_select") and "pencil" or "rect_select"
      CursorsController.applyModeCursor(app, ctx.getMode())
      if ctx.setStatus then
        ctx.setStatus(
          app.editTool == "rect_select"
            and "Tool: select (S) — Shift+drag freeform"
            or "Tool: pencil"
        )
      end
      return true
    end
  end

  return false
end

function M.handleAttrModeToggle(ctx, key, focus)
  if key ~= "a" then return false end
  if ctx.getMode() == "edit" then return false end

  local w = focus
  if not w then return false end
  local isPpu = WindowCaps.isPpuFrame(w)
  local isSketch = WindowCaps.isSketchCanvas(w)
  if not (isPpu or isSketch) then return false end
  if not (w.layers and w.getActiveLayerIndex) then return false end

  local li = w:getActiveLayerIndex()
  local layer = w.layers[li]
  if not layer or layer.kind == "sprite" then return false end

  if isSketch then
    local SketchPalette = require("controllers.game_art.sketch_canvas_palette_controller")
    SketchPalette.ensureAttrBytes(w)
  end

  layer.attrMode = not layer.attrMode
  if w.invalidateNametableLayerCanvas then
    w:invalidateNametableLayerCanvas(li)
  end
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

  return true
end

function M.handleUndoRedo(ctx, utils, key)
  if not utils.ctrlDown() then return false end

  local app = ctx.app
  if not app or not app.undoRedo then return false end

  if key == "z" then
    -- Cancel an in-progress floating selection before undoing older edits.
    local focus = ctx.getFocus and ctx.getFocus() or nil
    if focus and PixelSel.hasFloatingSelection(focus) and PixelSel.cancelFloating(focus, app) then
      if ctx.setStatus then
        ctx.setStatus("Undid floating selection")
      end
      return true
    end
    if app.undoRedo:undo(app) then
      return true
    end
  elseif key == "y" then
    if app.undoRedo:redo(app) then
      return true
    end
  end

  return false
end

return M
