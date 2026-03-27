local MultiSelectController = require("controllers.input_support.multi_select_controller")

local SpriteSelectionController = {}

local function getSelectionSet(layer)
  layer.multiSpriteSelection = layer.multiSpriteSelection or {}
  return layer.multiSpriteSelection
end

local function normalizeSelectionIndices(layer)
  local sel = layer.multiSpriteSelection
  if not sel then return {} end
  local list = {}
  for idx, on in pairs(sel) do
    if on then
      table.insert(list, idx)
    end
  end
  table.sort(list)
  return list
end

local function syncSelectionOrder(layer)
  if not layer then return {} end

  local sel = layer.multiSpriteSelection
  if type(sel) ~= "table" then
    layer.multiSpriteSelectionOrder = nil
    return {}
  end

  local order = {}
  local seen = {}
  local rawOrder = layer.multiSpriteSelectionOrder
  if type(rawOrder) == "table" then
    for _, idx in ipairs(rawOrder) do
      if type(idx) == "number" and sel[idx] and not seen[idx] then
        order[#order + 1] = idx
        seen[idx] = true
      end
    end
  end

  local remaining = {}
  for idx, on in pairs(sel) do
    if on and not seen[idx] then
      remaining[#remaining + 1] = idx
    end
  end
  table.sort(remaining)
  for _, idx in ipairs(remaining) do
    order[#order + 1] = idx
  end

  layer.multiSpriteSelectionOrder = (#order > 0) and order or nil
  return order
end

function SpriteSelectionController.clearSpriteSelection(layer)
  if not layer then return end
  layer.multiSpriteSelection = nil
  layer.multiSpriteSelectionOrder = nil
  layer.selectedSpriteIndex = nil
end

function SpriteSelectionController.setSpriteSelection(layer, indices)
  if not layer then return end
  layer.multiSpriteSelection = {}
  local ordered = {}
  local seen = {}
  for _, idx in ipairs(indices or {}) do
    if type(idx) == "number" and not seen[idx] then
      layer.multiSpriteSelection[idx] = true
      ordered[#ordered + 1] = idx
      seen[idx] = true
    end
  end
  layer.multiSpriteSelectionOrder = (#ordered > 0) and ordered or nil
  layer.selectedSpriteIndex = ordered[1]
end

function SpriteSelectionController.toggleSpriteSelection(layer, idx)
  if not layer or not idx then return end
  local sel = getSelectionSet(layer)
  local order = syncSelectionOrder(layer)
  if sel[idx] then
    sel[idx] = nil
    for i = #order, 1, -1 do
      if order[i] == idx then
        table.remove(order, i)
      end
    end
    layer.multiSpriteSelectionOrder = (#order > 0) and order or nil
    if layer.selectedSpriteIndex == idx then
      local list = layer.multiSpriteSelectionOrder or normalizeSelectionIndices(layer)
      layer.selectedSpriteIndex = list[1]
    end
  else
    sel[idx] = true
    order[#order + 1] = idx
    layer.multiSpriteSelectionOrder = order
    layer.selectedSpriteIndex = layer.selectedSpriteIndex or idx
  end
end

function SpriteSelectionController.getSelectedSpriteIndices(layer)
  if not layer then return {} end
  return normalizeSelectionIndices(layer)
end

function SpriteSelectionController.getSelectedSpriteIndicesInOrder(layer)
  if not layer then return {} end

  local order = syncSelectionOrder(layer)
  if #order == 0 and type(layer.selectedSpriteIndex) == "number" then
    return { layer.selectedSpriteIndex }
  end

  local out = {}
  for i = 1, #order do
    out[i] = order[i]
  end
  return out
end

function SpriteSelectionController.startSpriteMarquee(win, layerIndex, startX, startY, append)
  MultiSelectController.startSpriteMarquee(win, layerIndex, startX, startY, append)
end

function SpriteSelectionController.updateSpriteMarquee(x, y)
  MultiSelectController.updateSpriteMarquee(x, y)
end

function SpriteSelectionController.finishSpriteMarquee(x, y)
  return MultiSelectController.finishSpriteMarquee(x, y)
end

function SpriteSelectionController.getSpriteMarquee()
  return MultiSelectController.getSpriteMarquee()
end

function SpriteSelectionController.selectSpritesInRect(win, layerIndex, rect, append)
  MultiSelectController.selectSpritesInRect(win, layerIndex, rect, append)
end

return SpriteSelectionController
