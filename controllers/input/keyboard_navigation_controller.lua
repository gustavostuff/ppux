local WindowCaps = require("controllers.window.window_capabilities")
local AnimationWindowUndo = require("controllers.input_support.animation_window_undo")

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

function M.handlePaletteKeys(ctx, utils, key, focus)
  if not (focus and focus.isPalette) then return false end

  local dx, dy = 0, 0
  if key == "left" then
    dx = -1
  elseif key == "right" then
    dx = 1
  elseif key == "up" then
    dy = -1
  elseif key == "down" then
    dy = 1
  else
    return false
  end

  if focus.kind ~= "rom_palette" and not focus.activePalette then
    setStatus(ctx, "Activate palette before using it")
    return true
  end

  if utils.shiftDown() then
    if focus.adjustSelectedByArrows then
      focus:adjustSelectedByArrows(dx, dy)
    end
    return true
  end

  if focus.moveSelectedByArrows then
    focus:moveSelectedByArrows(dx, dy)
    return true
  end

  return true
end

function M.handleLayerNavigation(ctx, utils, key, focus)
  if not focus then return false end
  if key ~= "up" and key ~= "down" then return false end
  if not utils.shiftDown() then return false end
  if not (focus.getActiveLayerIndex and focus.nextLayer and focus.prevLayer and focus.getLayerCount) then
    return false
  end

  if WindowCaps.isAnimationLike(focus) and focus.isPlaying then
    setStatus(ctx, "Cannot change layers while animation is playing")
    return true
  end

  local oldLayer = focus:getActiveLayerIndex()
  if key == "up" then focus:nextLayer() else focus:prevLayer() end
  local newLayer = focus:getActiveLayerIndex()
  if oldLayer ~= newLayer then
    setStatus(ctx, ("Layer %d/%d"):format(newLayer, focus:getLayerCount()))
  end
  return true
end

function M.handleTileSelectionNavigation(ctx, utils, key, focus)
  if key ~= "left" and key ~= "right" and key ~= "up" and key ~= "down" then
    return false
  end
  if utils.ctrlDown() or utils.altDown() or utils.shiftDown() then
    return false
  end
  if not focus or WindowCaps.isAnyPaletteWindow(focus) or WindowCaps.isChrLike(focus) then
    return false
  end
  if not (focus.layers and focus.getActiveLayerIndex and focus.getSelected and focus.setSelected and focus.get) then
    return false
  end

  local li = focus:getActiveLayerIndex()
  local layer = focus.layers and focus.layers[li]
  if not (layer and layer.kind == "tile") then
    return false
  end

  local col, row, selectedLayer = focus:getSelected()
  if not (col and row) then
    return false
  end
  if selectedLayer and selectedLayer ~= li then
    return false
  end

  local dx, dy = 0, 0
  if key == "left" then dx = -1
  elseif key == "right" then dx = 1
  elseif key == "up" then dy = -1
  elseif key == "down" then dy = 1
  end

  local fallbackCol, fallbackRow = col, row
  local nextCol, nextRow = col, row
  while true do
    nextCol = nextCol + dx
    nextRow = nextRow + dy
    if nextCol < 0 or nextRow < 0 or nextCol >= (focus.cols or 0) or nextRow >= (focus.rows or 0) then
      break
    end
    if focus:get(nextCol, nextRow, li) then
      focus:setSelected(nextCol, nextRow, li)
      if ctx.showBankTileLabelForWindowSelection then
        ctx.showBankTileLabelForWindowSelection(focus)
      end
      return true
    end
  end

  focus:setSelected(fallbackCol, fallbackRow, li)
  if ctx.showBankTileLabelForWindowSelection then
    ctx.showBankTileLabelForWindowSelection(focus)
  end
  return true
end

function M.handleChrBankKeys(ctx, utils, key, focus)
  if utils.altDown() then return false end
  local wm = ctx.wm()
  local actuallyFocused = wm and wm:getFocus()
  if not (WindowCaps.isChrLike(actuallyFocused) and actuallyFocused == focus) then
    return false
  end

  if key == "m" then
    focus.orderMode = (focus.orderMode == "normal") and "oddEven" or "normal"
    ctx.rebuildChrBankWindow(focus)
    setStatus(ctx, "Order mode: " .. ((focus.orderMode == "normal") and "8x8" or "8x16"))
    if focus.specializedToolbar and focus.specializedToolbar.updateModeIcon then
      focus.specializedToolbar:updateModeIcon()
    end
    if focus.specializedToolbar and focus.specializedToolbar.triggerLayerLabelFlash then
      focus.specializedToolbar:triggerLayerLabelFlash()
    end
    return true
  end

  if key == "left" or key == "right" then
    local app = ctx.app
    if not app or not app.appEditState or not app.appEditState.chrBanksBytes then return false end

    local banks = app.appEditState.chrBanksBytes
    local n = #banks
    if n == 0 then return false end

    if focus.shiftBank then
      focus:shiftBank((key == "left") and -1 or 1)
    elseif key == "left" and focus.prevLayer then
      focus:prevLayer()
    elseif key == "right" and focus.nextLayer then
      focus:nextLayer()
    end
    app.appEditState.currentBank = focus.currentBank or focus.activeLayer or 1
    setStatus(ctx, string.format("Bank %d/%d", focus.currentBank, n))
    if focus.specializedToolbar and focus.specializedToolbar.triggerLayerLabelFlash then
      focus.specializedToolbar:triggerLayerLabelFlash()
    end
    if focus.specializedToolbar and focus.specializedToolbar.updateModeIcon then
      focus.specializedToolbar:updateModeIcon()
    end
    return true
  end

  return false
end

function M.handleAnimationWindowKeys(ctx, key, focus)
  if not WindowCaps.isAnimationLike(focus) then return false end

  local app = ctx and ctx.app
  local undoRedo = app and app.undoRedo

  local function pushAnimationUndoIfChanged(snapBefore)
    local snapAfter = AnimationWindowUndo.snapshot(focus)
    if undoRedo and undoRedo.addAnimationWindowStateEvent and not AnimationWindowUndo.snapshotsEqual(snapBefore, snapAfter) then
      undoRedo:addAnimationWindowStateEvent({
        type = "animation_window_state",
        win = focus,
        beforeState = snapBefore,
        afterState = snapAfter,
      })
    end
  end

  if key == "=" or key == "+" then
    local snapBefore = AnimationWindowUndo.snapshot(focus)
    local newLayerIdx = focus:addLayerAfterActive({
      name = "Frame " .. (#focus.layers + 1),
    })
    pushAnimationUndoIfChanged(snapBefore)
    setStatus(ctx, ("Added layer %d"):format(newLayerIdx))
    return true
  end

  if key == "-" or key == "_" then
    local snapBefore = AnimationWindowUndo.snapshot(focus)
    local success = focus:removeActiveLayer()
    if success then
      pushAnimationUndoIfChanged(snapBefore)
      setStatus(ctx, ("Removed layer, now on layer %d"):format(focus:getActiveLayerIndex()))
    else
      setStatus(ctx, "Cannot remove the last layer")
    end
    return true
  end

  if key == "p" or key == "P" then
    local isPlaying = focus:togglePlay()
    setStatus(ctx, isPlaying and "Animation playing" or "Animation paused")
    return true
  end

  return false
end

function M.handleAnimationDelayAdjust(ctx, utils, key, focus)
  if not WindowCaps.isAnimationLike(focus) then return false end
  if not utils.shiftDown() then return false end
  if key ~= "left" and key ~= "right" then return false end
  if not focus.adjustAllFrameDelays then return false end

  local app = ctx and ctx.app
  local undoRedo = app and app.undoRedo
  local snapBefore = AnimationWindowUndo.snapshot(focus)

  local direction = (key == "right") and 1 or -1
  local newDelay = focus:adjustAllFrameDelays(direction)
  if not newDelay then
    return false
  end

  local snapAfter = AnimationWindowUndo.snapshot(focus)
  if undoRedo and undoRedo.addAnimationWindowStateEvent and not AnimationWindowUndo.snapshotsEqual(snapBefore, snapAfter) then
    undoRedo:addAnimationWindowStateEvent({
      type = "animation_window_state",
      win = focus,
      beforeState = snapBefore,
      afterState = snapAfter,
    })
  end

  setStatus(ctx, string.format("Frame delay: %.2fs (all frames)", newDelay))
  return true
end

function M.handleInactiveLayerOpacity(ctx, utils, key, focus)
  if not utils.ctrlDown() then return false end
  if key ~= "up" and key ~= "down" then return false end
  if not focus then return false end
  if WindowCaps.isChrLike(focus) or WindowCaps.isAnyPaletteWindow(focus) then return false end
  if WindowCaps.isPpuFrame(focus) and focus.patternLayerSoloMode == true then
    setStatus(ctx, "Inactive layer opacity is disabled in pattern layer mode")
    return true
  end
  if not (focus.layers and focus.getActiveLayerIndex) then return false end

  local app = ctx and ctx.app
  local undoRedo = app and app.undoRedo
  local snapBefore = AnimationWindowUndo.snapshot(focus)

  local step = 0.2
  local dir = (key == "up") and 1 or -1
  local base = focus.nonActiveLayerOpacity or 1.0
  local newOpacity = math.max(0, math.min(1, base + dir * step))
  focus.nonActiveLayerOpacity = newOpacity
  local activeIdx = focus:getActiveLayerIndex()
  for li, layer in ipairs(focus.layers) do
    if li ~= activeIdx then
      layer.opacity = newOpacity
    else
      layer.opacity = 1.0
    end
  end

  local snapAfter = AnimationWindowUndo.snapshot(focus)
  if undoRedo and undoRedo.addAnimationWindowStateEvent and not AnimationWindowUndo.snapshotsEqual(snapBefore, snapAfter) then
    undoRedo:addAnimationWindowStateEvent({
      type = "animation_window_state",
      win = focus,
      beforeState = snapBefore,
      afterState = snapAfter,
    })
  end

  setStatus(ctx, string.format("Inactive layers opacity: %.0f%%", newOpacity * 100))
  return true
end

return M
