local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local state = {
  active = false,
  activeText = nil,
  previousText = nil,
}

local MODIFIER_KEYS = {
  lshift = true,
  rshift = true,
  lctrl = true,
  rctrl = true,
  lalt = true,
  ralt = true,
  f = true,
  g = true,
}

local function setStatus(ctx, text)
  if ctx and ctx.app and type(ctx.app.setStatus) == "function" then
    ctx.app:setStatus(text)
    return
  end
  if ctx and type(ctx.setStatus) == "function" then
    ctx.setStatus(text)
  end
end

function M.reset()
  state.active = false
  state.activeText = nil
  state.previousText = nil
end

function M.isModifierKey(key)
  return MODIFIER_KEYS[key] == true
end

local function getCurrentStatusText(ctx)
  if ctx and ctx.getStatus then
    return ctx.getStatus()
  end
  local app = ctx and ctx.app
  if app then
    return app.lastEventText or app.statusText
  end
  return nil
end

local function getActiveLayerAndIndex(focus)
  if not (focus and focus.layers and focus.getActiveLayerIndex) then
    return nil, nil
  end
  local layerIndex = focus:getActiveLayerIndex()
  return focus.layers[layerIndex], layerIndex
end

local function hasSpriteSelection(layer)
  if not (layer and layer.kind == "sprite") then return false end

  if type(layer.selectedSpriteIndex) == "number" then
    return true
  end

  if layer.multiSpriteSelection then
    for _, selected in pairs(layer.multiSpriteSelection) do
      if selected then return true end
    end
  end

  return false
end

local function hasTileSelection(focus, layerIndex)
  if not (focus and focus.getSelected) then return false end

  local col, row, selectedLayerIndex = focus:getSelected()
  if col == nil or row == nil then return false end

  local li = selectedLayerIndex or layerIndex
  if not li then return false end

  if focus.get then
    return focus:get(col, row, li) ~= nil
  end

  local layer = focus.layers and focus.layers[li]
  if not layer then return false end

  local cols = focus.cols or 0
  if cols <= 0 then return false end

  local idx = (row * cols + col) + 1
  return layer.items and (layer.items[idx] ~= nil) or false
end

local function hasActiveSelection(focus, layer, layerIndex)
  if not layer then return false end
  if layer.kind == "sprite" then
    return hasSpriteSelection(layer)
  end
  if layer.kind == "tile" then
    return hasTileSelection(focus, layerIndex)
  end
  return false
end

local function getModifierHintText(ctx, utils)
  local ctrlDown = utils.ctrlDown and utils.ctrlDown()
  local shiftDown = utils.shiftDown and utils.shiftDown()
  local fillDown = utils.fillDown and utils.fillDown()
  local grabDown = utils.grabDown and utils.grabDown()
  local altDown = utils.altDown and utils.altDown()

  if not (ctrlDown or shiftDown or altDown or fillDown or grabDown) then
    return nil
  end

  local mode = ctx and ctx.getMode and ctx.getMode() or "tile"
  local focus = ctx and ctx.getFocus and ctx.getFocus() or nil
  local layer, layerIndex = getActiveLayerAndIndex(focus)
  local hasSelection = hasActiveSelection(focus, layer, layerIndex)

  if ctrlDown and altDown then
    if mode == "edit" then
      return "Ctrl + Alt + Wheel = brush size"
    end
    if WindowCaps.isStaticOrAnimationArt(focus) and layer and layer.kind == "tile" then
      return "Ctrl + Alt + Click/Drag = tile paint mode"
    end
    return nil
  end

  if altDown then
    if mode == "edit" then
      return "Alt + 1..4 = brush size"
    end
    if hasSelection then
      return "Alt + Arrows = offset pixels"
    end
    return nil
  end

  if fillDown then
    if mode == "edit" then
      return "Hold F + Click = flood fill"
    end
    return nil
  end

  if grabDown then
    if mode == "edit" then
      return "Hold G + Click/Drag = grab color"
    end
    return nil
  end

  if shiftDown then
    if mode == "edit" then
      return "Shift + Click = line, Shift + Drag = filled rect"
    end
    if WindowCaps.isStaticOrAnimationArt(focus) and layer and layer.kind == "tile" and hasSelection then
      return "Shift + Drag = marquee select copy"
    end
    if focus and focus.layers and focus.getActiveLayerIndex and not hasSelection then
      return "Up/Down = change layer, Left/Right = change frame delay"
    end
    return nil
  end

  if ctrlDown then
    if mode == "edit" then
      return "Ctrl + R = toggle shader"
    end
    if WindowCaps.isAnimationLike(focus) then
      return "Press + or = to add a new layer"
    end
    if focus and focus.layers and focus.getActiveLayerIndex and not WindowCaps.isAnyPaletteWindow(focus) and not WindowCaps.isChrLike(focus) then
      return "Ctrl + Up/Down = inactive layer opacity"
    end
  end

  return nil
end

function M.updateStatus(ctx, utils)
  local hintText = getModifierHintText(ctx, utils)
  if hintText then
    local currentStatus = getCurrentStatusText(ctx)
    if (not state.active) or (currentStatus ~= state.activeText) then
      state.previousText = currentStatus
    end
    state.active = true
    state.activeText = hintText
    setStatus(ctx, hintText)
    return
  end

  if state.active then
    local currentStatus = getCurrentStatusText(ctx)
    if state.previousText ~= nil and currentStatus == state.activeText then
      setStatus(ctx, state.previousText)
    end
  end
  state.active = false
  state.activeText = nil
  state.previousText = nil
end

return M
