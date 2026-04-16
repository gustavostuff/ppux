-- Snapshot / restore animation window timeline UI (layers list, delays, opacity).

local M = {}

local function shallowCopyLayers(layers)
  local t = {}
  for i = 1, #(layers or {}) do
    t[i] = layers[i]
  end
  return t
end

local function cloneFrameDelays(fd)
  local t = {}
  if not fd then
    return t
  end
  for k, v in pairs(fd) do
    t[k] = v
  end
  return t
end

local function cloneSelectedByLayer(sb)
  if not sb then
    return nil
  end
  local t = {}
  for k, v in pairs(sb) do
    t[k] = v
  end
  return t
end

function M.snapshot(win)
  if not win then
    return nil
  end
  local layerOpacities = {}
  for i = 1, #(win.layers or {}) do
    local L = win.layers[i]
    layerOpacities[i] = L and L.opacity
  end
  return {
    layers = shallowCopyLayers(win.layers),
    activeLayer = win.activeLayer,
    frameDelays = cloneFrameDelays(win.frameDelays),
    nonActiveLayerOpacity = win.nonActiveLayerOpacity,
    selectedByLayer = cloneSelectedByLayer(win.selectedByLayer),
    layerOpacities = layerOpacities,
  }
end

function M.apply(win, snap)
  if not (win and snap) then
    return false
  end
  win.layers = shallowCopyLayers(snap.layers)
  win.activeLayer = snap.activeLayer
  win.frameDelays = cloneFrameDelays(snap.frameDelays)
  win.nonActiveLayerOpacity = snap.nonActiveLayerOpacity
  if snap.layerOpacities then
    for i, op in ipairs(snap.layerOpacities) do
      if win.layers[i] then
        win.layers[i].opacity = op
      end
    end
  end
  if snap.selectedByLayer then
    win.selectedByLayer = cloneSelectedByLayer(snap.selectedByLayer)
  end
  if win.selectedByLayer then
    win.selected = win.selectedByLayer[win.activeLayer]
  end
  if win.updateLayerOpacities then
    win:updateLayerOpacities()
  end
  if win.isPlaying and win.scheduleNextFrame then
    win:scheduleNextFrame()
  end
  return true
end

local function frameDelaysEqual(a, b)
  if not a and not b then
    return true
  end
  if not a or not b then
    return false
  end
  local keys = {}
  for k in pairs(a) do
    keys[k] = true
  end
  for k in pairs(b) do
    keys[k] = true
  end
  for k in pairs(keys) do
    if (a[k] or 0) ~= (b[k] or 0) then
      return false
    end
  end
  return true
end

function M.snapshotsEqual(a, b)
  if not (a and b) then
    return false
  end
  if #(a.layers or {}) ~= #(b.layers or {}) then
    return false
  end
  for i = 1, #(a.layers or {}) do
    if (a.layers[i] ~= b.layers[i]) then
      return false
    end
  end
  if (a.activeLayer or 0) ~= (b.activeLayer or 0) then
    return false
  end
  if (a.nonActiveLayerOpacity or 0) ~= (b.nonActiveLayerOpacity or 0) then
    return false
  end
  local la, lb = a.layerOpacities, b.layerOpacities
  if la or lb then
    if not (la and lb) or #la ~= #lb then
      return false
    end
    for i = 1, #la do
      if (la[i] or 0) ~= (lb[i] or 0) then
        return false
      end
    end
  end
  if not frameDelaysEqual(a.frameDelays, b.frameDelays) then
    return false
  end
  return true
end

return M
