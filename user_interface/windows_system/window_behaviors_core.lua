local DebugController = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local function isChr8x16SelectionMode(win)
  return WindowCaps.isChrLike(win) and win.orderMode == "oddEven"
end

local function getChr8x16TopRow(row)
  row = math.floor(tonumber(row) or 0)
  return row - (row % 2)
end

return function(Window)
function Window:update(dt)
  self.scrollbarOpacity = math.max(0.0, math.min(1.0, self.scrollbarOpacity - dt))
end

-- ==== Layers (unchanged) ====
function Window:getLayerCount() return #self.layers end
function Window:getActiveLayerIndex() return self.activeLayer end
function Window:setActiveLayerIndex(i)
  local n = #self.layers
  if n == 0 then return end
  i = math.max(1, math.min(n, math.floor(i or 1)))
  local oldLayer = self.activeLayer
  self.activeLayer = i
  self.selected = self.selectedByLayer and self.selectedByLayer[i] or nil
  -- Update layer opacities: active = 1, others = nonActiveLayerOpacity if set
  if self.nonActiveLayerOpacity then
    for li, L in ipairs(self.layers) do
      if li == i then
        L.opacity = 1.0
      else
        L.opacity = self.nonActiveLayerOpacity
      end
    end
  end
  
  if oldLayer ~= i then
    DebugController.log("info", "WIN", "Window '%s' active layer changed: %d -> %d", self.title or "untitled", oldLayer, i)
    if self.specializedToolbar and self.specializedToolbar.triggerLayerLabelFlash then
      self.specializedToolbar:triggerLayerLabelFlash()
    end
  end
end

function Window:nextLayer()
  local n = #self.layers
  if n == 0 then return end
  local current = self:getActiveLayerIndex() or 1
  local nextIndex = (math.floor(current) % n) + 1
  self:setActiveLayerIndex(nextIndex)
end

function Window:prevLayer()
  local n = #self.layers
  if n == 0 then return end
  local current = self:getActiveLayerIndex() or 1
  local prevIndex = ((math.floor(current) - 2) % n) + 1
  self:setActiveLayerIndex(prevIndex)
end

function Window:addLayer(opts)
  opts = opts or {}
  local layerName = opts.name or ("Layer " .. (#self.layers + 1))
  local layerKind = opts.kind or "tile"
  table.insert(self.layers, {
    items   = {},
    opacity = 1.0,
    name    = layerName,

    -- Layer semantics:
    kind    = layerKind,  -- "tile" or "sprite" (and potentially others)
    mode    = opts.mode,            -- optional: "8x8" / "8x16" etc.

    -- Nametable / ROM metadata (optional, mainly for PPU-style layers):
    nametableStartAddr = opts.nametableStartAddr,
    nametableEndAddr   = opts.nametableEndAddr,
    noOverflowSupported = opts.noOverflowSupported,
    page                  = opts.page,
    bank                  = opts.bank,
    tileSwaps             = opts.tileSwaps, -- optional table of { val,row,col }

    -- Sprite metadata (optional, mainly for sprite layers):
    originX = opts.originX,
    originY = opts.originY,
  })
  DebugController.log("info", "WIN", "Window '%s' added layer: '%s' (kind: %s, total layers: %d)", self.title or "untitled", layerName, layerKind, #self.layers)
  if self.specializedToolbar and self.specializedToolbar.triggerLayerLabelFlash then
    self.specializedToolbar:triggerLayerLabelFlash()
  end
  return #self.layers
end

function Window:getLayer(i) return self.layers[i or self.activeLayer] end
function Window:setLayerOpacity(i, a)
  local L = self:getLayer(i); if not L then return end
  L.opacity = math.max(0, math.min(1, a or 1))
end
function Window:getLayerOpacity(i)
  local L = self:getLayer(i); return L and L.opacity or 1
end

function Window:getSpriteLayers()
  local result = {}
  if not self.layers then return result end
  for i, L in ipairs(self.layers) do
    if L.kind == "sprite" then
      table.insert(result, { index = i, layer = L })
    end
  end
  return result
end

-- ==== Cell stacks (unchanged) ====
local function idxBy(cols, col, row) return row * cols + col + 1 end

function Window:get(col, row, layerIndex)
  local L = self:getLayer(layerIndex); if not L then return nil end
  local i = idxBy(self.cols, col, row)
  if L.removedCells and L.removedCells[i] then
    return nil
  end
  local item = L.items[i]
  -- Return nil if item doesn't exist
  -- Note: We no longer check item.removed since tiles are shared references
  -- and marking them as removed would affect all windows
  if item == nil then
    return nil
  end
  return item
end

function Window:set(col, row, item, layerIndex)
  local L = self:getLayer(layerIndex); if not L then return end
  local i = idxBy(self.cols, col, row)
  if L.removedCells then
    L.removedCells[i] = nil
  end
  -- Note: We no longer use item.removed for tiles since they're shared references
  -- Sprites may still use removed flag (they're not shared), but that's handled separately
  L.items[i] = item
end

-- legacy API, left here for compatibility
function Window:getStack(col, row, layerIndex)
  local L = self:getLayer(layerIndex); if not L then return nil end
  local i = idxBy(self.cols, col, row)
  if L.removedCells and L.removedCells[i] then
    return nil
  end
  local item = L.items[i]
  -- Note: We no longer check item.removed since tiles are shared references
  if item == nil then
    return nil
  end
  return { item }, { { ox = 0, oy = 0 } }
end

function Window:remove(col, row, layerIndex, item)
  local L = self:getLayer(layerIndex); if not L then return end
  local i = idxBy(self.cols, col, row)
  local v = L.items[i]
  if v == nil then return end
  if item == nil or v == item then
    -- Just set to nil - don't mark shared tile objects as removed
    L.items[i] = nil
  end
end

function Window:removeAt(col, row, layerIndex, stackIndex)
  local L = self:getLayer(layerIndex); if not L then return end
  local i = idxBy(self.cols, col, row)
  local item = L.items[i]
  if item == nil then return end
  -- Just set to nil - don't mark shared tile objects as removed
  -- since tiles are shared references to tilesPool, marking them as removed
  -- would affect all windows that use the same tile
  L.items[i] = nil
end

-- Kept for API compatibility; no-op in single-item mode.
function Window:liftToTopIndex(col, row, layerIndex, stackIndex)
  -- no-op
end

function Window:clear(col, row, layerIndex)
  local L = self:getLayer(layerIndex); if not L then return end
  local i = idxBy(self.cols, col, row)
  -- Just set to nil - don't mark shared tile objects as removed
  -- since tiles are shared references to tilesPool, marking them as removed
  -- would affect all windows that use the same tile
  L.items[i] = nil
end

function Window:getLayerSelection(layerIndex)
  local li = math.max(1, math.floor(layerIndex or self.activeLayer or 1))
  if self.selectedByLayer and self.selectedByLayer[li] then
    return self.selectedByLayer[li]
  end
  if self.selected and (self.selected.layer or li) == li then
    return self.selected
  end
  return nil
end

function Window:getSelected(getIndex)
  local li = self.activeLayer or 1
  local sel = self:getLayerSelection(li)
  if not sel then return nil,nil,nil end

  local col, row = sel.col, sel.row
  if isChr8x16SelectionMode(self) then
    row = getChr8x16TopRow(row)
  end

  if getIndex then
    -- calculate index in selg.items:
    local L = self:getLayer(li)
    local idx = row * self.cols + col
    return idx, L.items[idx]
  end

  return col, row, li
end
function Window:setSelected(col, row, layerIndex)
  local li = math.max(1, math.floor(layerIndex or self.activeLayer or 1))
  if isChr8x16SelectionMode(self) then
    row = getChr8x16TopRow(row)
  end
  self.selectedByLayer = self.selectedByLayer or {}
  local sel = { col = col, row = row, layer = li }
  self.selectedByLayer[li] = sel
  self.selected = self.selectedByLayer[self.activeLayer or li]
end
function Window:clearSelected(layerIndex)
  local li = math.max(1, math.floor(layerIndex or self.activeLayer or 1))
  if self.selectedByLayer then
    self.selectedByLayer[li] = nil
  end
  self.selected = self.selectedByLayer and self.selectedByLayer[self.activeLayer or 1] or nil
end

function Window:isInHeader(px, py)
  local hx, hy, hw, hh = self:getHeaderRect()
  return px >= hx and px <= hx + hw and py >= hy and py <= hy + hh
end

function Window:isCellRemoved(col, row, layerIndex)
  local L = self:getLayer(layerIndex); if not L or not L.removedCells then return false end
  local i = idxBy(self.cols, col, row)
  return L.removedCells[i] == true
end

function Window:markCellRemoved(col, row, layerIndex)
  local L = self:getLayer(layerIndex); if not L then return end
  local i = idxBy(self.cols, col, row)
  L.removedCells = L.removedCells or {}
  L.removedCells[i] = true
end

function Window:clearRemovedCell(col, row, layerIndex)
  local L = self:getLayer(layerIndex); if not L or not L.removedCells then return end
  local i = idxBy(self.cols, col, row)
  L.removedCells[i] = nil
end

end
