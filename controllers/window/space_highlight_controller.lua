local colors = require("app_colors")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {}

local function bankTileKey(bankIdx, tileIdx)
  if type(bankIdx) ~= "number" or type(tileIdx) ~= "number" then
    return nil
  end
  return tostring(bankIdx) .. ":" .. tostring(tileIdx)
end

local function getCtx(ctxOverride)
  return ctxOverride or rawget(_G, "ctx")
end

local function getSpaceHighlightActive(ctxOverride)
  local ctx = getCtx(ctxOverride)
  if not ctx then return false end
  if ctx.getSpaceHighlightActive then
    return ctx.getSpaceHighlightActive() == true
  end
  return love.keyboard.isDown("space")
end

local function addTileRefBankKey(keySet, tileRef, onlyBankIdx)
  if not tileRef then return end
  local bankIdx = tileRef._bankIndex
  local tileIdx = tileRef.index
  if type(bankIdx) ~= "number" or type(tileIdx) ~= "number" then
    return
  end
  if type(onlyBankIdx) == "number" and bankIdx ~= onlyBankIdx then
    return
  end
  local key = bankTileKey(bankIdx, tileIdx)
  if key then
    keySet[key] = true
  end
end

local function getTileRefLike(win, layer, col, row, layerIndex)
  local cols = win.cols or 1
  local idx = (row * cols) + col + 1
  local item = layer.items and layer.items[idx] or nil
  if item ~= nil then
    return item
  end
  if win.getVirtualTileHandle then
    item = win:getVirtualTileHandle(col, row, layerIndex)
    if item ~= nil then
      return item
    end
  end
  if win.get then
    return win:get(col, row, layerIndex)
  end
  return nil
end

local function tileRefMatchesBankKeys(tileRef, bankKeys)
  if not (tileRef and bankKeys) then return false end
  local key = bankTileKey(tileRef._bankIndex, tileRef.index)
  return key ~= nil and bankKeys[key] == true
end

local function spriteMatchesBankKeys(sprite, bankKeys)
  if not (sprite and bankKeys) then return false end
  return tileRefMatchesBankKeys(sprite.topRef, bankKeys)
    or tileRefMatchesBankKeys(sprite.botRef, bankKeys)
end

local function isMappedDisplayWindow(win, spaceHighlightModel)
  if not (win and spaceHighlightModel) then
    return false
  end
  if win == spaceHighlightModel.focusedWindow or win == spaceHighlightModel.bankWindow then
    return true
  end
  if WindowCaps.isChrLike(win) and type(spaceHighlightModel.currentBank) == "number" then
    local winBank = tonumber(win.currentBank) or tonumber(win.activeLayer)
    return type(winBank) == "number" and winBank == spaceHighlightModel.currentBank
  end
  return false
end

function M.collectLayerBankTileKeys(layer, bankIdx)
  local keys = {}
  if not (layer and type(bankIdx) == "number") then
    return keys
  end

  if layer.kind == "sprite" then
    for _, sprite in ipairs(layer.items or {}) do
      if sprite and sprite.removed ~= true then
        addTileRefBankKey(keys, sprite.topRef, bankIdx)
        addTileRefBankKey(keys, sprite.botRef, bankIdx)
      end
    end
    return keys
  end

  local removedCells = layer.removedCells
  for idx, item in pairs(layer.items or {}) do
    if item ~= nil and not (removedCells and removedCells[idx]) then
      addTileRefBankKey(keys, item, bankIdx)
    end
  end
  return keys
end

function M.collectWindowLayerBankTileKeys(win, layer, layerIndex, bankIdx)
  local keys = {}
  if not (win and layer and type(bankIdx) == "number") then
    return keys
  end

  if layer.kind == "sprite" then
    return M.collectLayerBankTileKeys(layer, bankIdx)
  end

  local cols = tonumber(win.cols) or 0
  local rows = tonumber(win.rows) or 0
  if cols > 0 and rows > 0 then
    local removedCells = layer.removedCells
    for row = 0, rows - 1 do
      for col = 0, cols - 1 do
        local idx = (row * cols) + col + 1
        if not (removedCells and removedCells[idx]) then
          addTileRefBankKey(keys, getTileRefLike(win, layer, col, row, layerIndex), bankIdx)
        end
      end
    end
    return keys
  end

  return M.collectLayerBankTileKeys(layer, bankIdx)
end

function M.collectSelectedBankTileKeys(win, layer, bankIdx)
  local keys = {}
  if not (win and layer and type(bankIdx) == "number") then
    return keys
  end

  if layer.kind == "sprite" then
    local selected = {}
    if type(layer.multiSpriteSelection) == "table" then
      for idx, on in pairs(layer.multiSpriteSelection) do
        if on == true then
          selected[#selected + 1] = idx
        end
      end
    end
    table.sort(selected)
    if #selected == 0 and type(layer.selectedSpriteIndex) == "number" then
      selected[1] = layer.selectedSpriteIndex
    end

    for _, idx in ipairs(selected) do
      local sprite = layer.items and layer.items[idx] or nil
      if sprite and sprite.removed ~= true then
        addTileRefBankKey(keys, sprite.topRef, bankIdx)
        addTileRefBankKey(keys, sprite.botRef, bankIdx)
      end
    end
    return keys
  end

  local li = win.getActiveLayerIndex and win:getActiveLayerIndex() or win.activeLayer or 1
  local removedCells = (WindowCaps.isPpuFrame(win) and layer.kind == "tile") and nil or layer.removedCells
  if type(layer.multiTileSelection) == "table" then
    for idx, on in pairs(layer.multiTileSelection) do
      if on == true and not (removedCells and removedCells[idx]) then
        local zeroBased = idx - 1
        local cols = win.cols or 1
        local item = getTileRefLike(win, layer, zeroBased % cols, math.floor(zeroBased / cols), li)
        addTileRefBankKey(keys, item, bankIdx)
      end
    end
    if next(keys) ~= nil then
      return keys
    end
  end

  local sel = win.getLayerSelection and win:getLayerSelection(li) or nil
  if sel and sel.col and sel.row then
    local idx = (sel.row * (win.cols or 1)) + sel.col + 1
    if not (removedCells and removedCells[idx]) then
      local item = getTileRefLike(win, layer, sel.col, sel.row, li)
      addTileRefBankKey(keys, item, bankIdx)
    end
  end
  return keys
end

function M.buildModel(ctxOverride, spaceDownOverride)
  local ctx = getCtx(ctxOverride)
  local spaceDown
  if spaceDownOverride ~= nil then
    spaceDown = (spaceDownOverride == true)
  else
    spaceDown = getSpaceHighlightActive(ctx)
  end
  if not spaceDown or not ctx then return nil end

  local wm = ctx.wm and ctx.wm() or nil
  local focus = (ctx.getFocus and ctx.getFocus()) or (wm and wm.getFocus and wm:getFocus()) or nil
  if not focus or WindowCaps.isChrLike(focus) then return nil end

  local layer = focus.layers and focus.layers[focus.activeLayer or 1] or nil
  if not layer then return nil end
  if not (focus.canShowSpaceHighlight and focus:canShowSpaceHighlight(layer)) then
    return nil
  end

  local app = ctx.app
  local bankWindow = app and app.winBank or nil
  local currentBank = (bankWindow and bankWindow.currentBank)
    or (app and app.appEditState and app.appEditState.currentBank)
  if type(currentBank) ~= "number" then
    return nil
  end

  local activeLayerIndex = (focus.getActiveLayerIndex and focus:getActiveLayerIndex()) or focus.activeLayer or 1
  return {
    focusedWindow = focus,
    focusedLayer = layer,
    bankWindow = bankWindow,
    currentBank = currentBank,
    matchedTileKeys = M.collectWindowLayerBankTileKeys(focus, layer, activeLayerIndex, currentBank),
  }
end

function M.buildSelectionModel(ctxOverride)
  local ctx = getCtx(ctxOverride)
  if not ctx then return nil end

  local wm = ctx.wm and ctx.wm() or nil
  local focus = (ctx.getFocus and ctx.getFocus()) or (wm and wm.getFocus and wm:getFocus()) or nil
  if not focus or WindowCaps.isChrLike(focus) then return nil end

  local layer = focus.layers and focus.layers[focus.activeLayer or 1] or nil
  if not layer then return nil end

  local app = ctx.app
  local bankWindow = app and app.winBank or nil
  local currentBank = (bankWindow and bankWindow.currentBank)
    or (app and app.appEditState and app.appEditState.currentBank)
  if type(currentBank) ~= "number" then
    return nil
  end

  local selectedKeys = M.collectSelectedBankTileKeys(focus, layer, currentBank)
  if next(selectedKeys) == nil then
    return nil
  end

  return {
    focusedWindow = focus,
    focusedLayer = layer,
    bankWindow = bankWindow,
    currentBank = currentBank,
    matchedTileKeys = selectedKeys,
  }
end

function M.resolveMappedOverlayColor(win, target, spaceHighlightModel)
  if not (spaceHighlightModel and spaceHighlightModel.matchedTileKeys) then
    return nil
  end
  if not isMappedDisplayWindow(win, spaceHighlightModel) then
    return nil
  end
  if target and target.topRef then
    if spriteMatchesBankKeys(target, spaceHighlightModel.matchedTileKeys) then
      return colors.green
    end
  elseif tileRefMatchesBankKeys(target, spaceHighlightModel.matchedTileKeys) then
    return colors.green
  end
  return nil
end

function M.shouldShowMappedHighlightInWindow(win, spaceHighlightModel)
  if not M.hasMatchedKeys(spaceHighlightModel) then
    return false
  end
  return isMappedDisplayWindow(win, spaceHighlightModel)
end

function M.hasMatchedKeys(spaceHighlightModel)
  return spaceHighlightModel
    and type(spaceHighlightModel.matchedTileKeys) == "table"
    and next(spaceHighlightModel.matchedTileKeys) ~= nil
    or false
end

function M.isSpaceHighlightActive(ctxOverride)
  return getSpaceHighlightActive(ctxOverride)
end

return M
