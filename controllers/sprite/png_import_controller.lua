-- sprite_png_import_controller.lua
-- PNG drop/import pipeline for sprite layers.

local chr = require("chr")
local DebugController = require("controllers.dev.debug_controller")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local PngPaletteMappingController = require("controllers.png.palette_mapping_controller")

local M = {}

local function loadImageDataFromDroppedFile(file)
  if not file then return nil, "no_file" end
  file:open("r")
  local bytes = file:read()
  file:close()
  if not bytes then return nil, "read_failed" end
  local fd = love.filesystem.newFileData(bytes, file:getFilename() or "sprite.png")
  return love.image.newImageData(fd)
end

local function countUniqueColors(imgData)
  local colorSet = {}
  local w, h = imgData:getWidth(), imgData:getHeight()
  local count = 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = imgData:getPixel(x, y)
      local key = string.format("%d_%d_%d_%d",
        math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), math.floor(a * 255))
      if not colorSet[key] then
        colorSet[key] = true
        count = count + 1
        if count > 4 then
          return count
        end
      end
    end
  end
  return count
end

local function countUniqueNonTransparentColors(imgData)
  local colorSet = {}
  local w, h = imgData:getWidth(), imgData:getHeight()
  local count = 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = imgData:getPixel(x, y)
      if a > 0 then
        local key = string.format("%d_%d_%d",
          math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
        if not colorSet[key] then
          colorSet[key] = true
          count = count + 1
          if count > 3 then
            return count
          end
        end
      end
    end
  end
  return count
end

local function buildBrightnessIndexMapForSprites(imgData)
  return PngPaletteMappingController.buildBrightnessRankMap(imgData, {
    rankStart = 1,
    maxRank = 3,
  })
end

local function buildPaletteBrightnessRemapForSprite(layer, paletteNumber, romRaw)
  if not paletteNumber then
    return nil
  end

  local paletteColors = ShaderPaletteController.getPaletteColors(layer, paletteNumber, romRaw)
  if type(paletteColors) ~= "table" then
    return nil
  end

  return PngPaletteMappingController.buildPaletteBrightnessRemap(paletteColors, {
    pixelValues = { 1, 2, 3 },
    rankStart = 1,
  })
end

local function mapPixelToPaletteIndex(r, g, b, a, brightnessMap, paletteRemap)
  if a == 0 then
    return 0
  end

  local key = PngPaletteMappingController.rgbKeyFromFloats(r, g, b)
  local rank = brightnessMap[key] or 1
  if paletteRemap and paletteRemap[rank] then
    return paletteRemap[rank]
  end
  return (paletteRemap and paletteRemap[1]) or 1
end

local function recordEdit(edits, bankIdx, tileIdx, x, y, color)
  edits.banks = edits.banks or {}
  edits.banks[bankIdx] = edits.banks[bankIdx] or {}
  edits.banks[bankIdx][tileIdx] = edits.banks[bankIdx][tileIdx] or {}
  edits.banks[bankIdx][tileIdx][x .. "_" .. y] = color
end

local function writeTilePixels(tileRef, imgData, srcX, srcY, brightnessMap, paletteRemap, edits, undoRedo, app, syncChangedTargets)
  if not tileRef then return false, "no_tile" end
  local bankBytes = tileRef._bankBytesRef
  local tileIndex = tileRef.index
  local bankIdx = tileRef._bankIndex
  local state = app and app.appEditState or nil

  local targets = {}
  if state and type(bankIdx) == "number" and type(tileIndex) == "number" then
    targets = ChrDuplicateSync.getSyncGroup(state, bankIdx, tileIndex, ChrDuplicateSync.isEnabled(app))
  end
  if #targets == 0 and type(bankIdx) == "number" and type(tileIndex) == "number" then
    targets = { { bank = bankIdx, tileIndex = tileIndex } }
  end
  if #targets == 0 then
    return false, "no_targets"
  end

  local touchedRefs = {}
  local touchedRefSet = {}

  for y = 0, 7 do
    for x = 0, 7 do
      local r, g, b, a = imgData:getPixel(srcX + x, srcY + y)
      local idx = mapPixelToPaletteIndex(r, g, b, a, brightnessMap, paletteRemap)
      for _, target in ipairs(targets) do
        local tBank = target.bank
        local tIdx = target.tileIndex

        local tBankBytes = (state and state.chrBanksBytes and state.chrBanksBytes[tBank]) or nil
        if not tBankBytes and tBank == bankIdx then
          tBankBytes = bankBytes
        end

        local tRef = nil
        if state and state.tilesPool and state.tilesPool[tBank] then
          tRef = state.tilesPool[tBank][tIdx]
        end
        if not tRef and tBank == bankIdx and tIdx == tileIndex then
          tRef = tileRef
        end

        local beforePixel = nil
        if tRef and tRef.pixels then
          beforePixel = tRef.pixels[y * 8 + x + 1]
        end

        if tBankBytes and tIdx ~= nil then
          chr.setTilePixel(tBankBytes, tIdx, x, y, idx)
          if edits and tBank ~= nil then
            recordEdit(edits, tBank, tIdx, x, y, idx)
          end
          if syncChangedTargets and tBank ~= nil then
            local keyId = string.format("%d:%d", tBank, tIdx)
            if not syncChangedTargets._set[keyId] then
              syncChangedTargets._set[keyId] = true
              syncChangedTargets.list[#syncChangedTargets.list + 1] = { bank = tBank, tileIndex = tIdx }
            end
          end
        end
        if undoRedo and undoRedo.recordPixelChange and tBank ~= nil and tIdx ~= nil and (beforePixel or 0) ~= idx then
          undoRedo:recordPixelChange(tBank, tIdx, x, y, beforePixel or 0, idx)
        end
        if tRef and tRef.pixels then
          tRef.pixels[y * 8 + x + 1] = idx
          local refKey = tostring(tRef)
          if not touchedRefSet[refKey] then
            touchedRefSet[refKey] = true
            touchedRefs[#touchedRefs + 1] = tRef
          end
        end
      end
    end
  end

  for _, ref in ipairs(touchedRefs) do
    if ref.refreshImage then
      ref:refreshImage()
    end
  end
  return true
end

local function applyFrameToSprite(sprite, imgData, frameX, frameY, spriteW, spriteH, brightnessMap, paletteRemap, edits, undoRedo, app, syncChangedTargets)
  if not sprite or sprite.removed == true then
    return false, "sprite missing"
  end
  if not paletteRemap then
    return false, "missing palette remap"
  end
  if not sprite.topRef then
    return false, "missing top tile"
  end

  local okTop, errTop = writeTilePixels(sprite.topRef, imgData, frameX, frameY, brightnessMap, paletteRemap, edits, undoRedo, app, syncChangedTargets)
  if not okTop then
    return false, errTop
  end

  if spriteH == 16 then
    if not sprite.botRef then
      return false, "missing bottom tile"
    end
    local okBot, errBot = writeTilePixels(sprite.botRef, imgData, frameX, frameY + 8, brightnessMap, paletteRemap, edits, undoRedo, app, syncChangedTargets)
    if not okBot then
      return false, errBot
    end
  end

  return true
end

local function buildFrameList(imgData, spriteW, spriteH)
  local frames = {}
  local w, h = imgData:getWidth(), imgData:getHeight()
  local cols = math.floor(w / spriteW)
  local rows = math.floor(h / spriteH)
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      frames[#frames + 1] = { x = col * spriteW, y = row * spriteH }
    end
  end
  return frames, cols, rows
end

local function frameIsTransparent(imgData, frameX, frameY, spriteW, spriteH)
  for y = 0, spriteH - 1 do
    for x = 0, spriteW - 1 do
      local _, _, _, a = imgData:getPixel(frameX + x, frameY + y)
      if a ~= 0 then
        return false
      end
    end
  end
  return true
end

function M.handleSpritePngDrop(SpriteController, app, file, win)
  if not (SpriteController and app and file and win and win.layers and win.getActiveLayerIndex) then
    DebugController.log("warning", "PNG_DROP", "handleSpritePngDrop: invalid args app=%s file=%s win=%s", tostring(app ~= nil), tostring(file ~= nil), tostring(win ~= nil))
    return false
  end

  local function fmtIndices(list, limit)
    limit = limit or 16
    if type(list) ~= "table" or #list == 0 then return "[]" end
    local out = {}
    local n = math.min(#list, limit)
    for i = 1, n do
      out[#out + 1] = tostring(list[i])
    end
    if #list > limit then
      out[#out + 1] = "..."
    end
    return "[" .. table.concat(out, ",") .. "]"
  end

  DebugController.log(
    "info",
    "PNG_DROP",
    "Sprite import candidate win kind=%s id=%s title=%s activeLayer=%s totalLayers=%d file=%s",
    tostring(win.kind),
    tostring(win._id),
    tostring(win.title),
    tostring(win.getActiveLayerIndex and win:getActiveLayerIndex() or "?"),
    tonumber(win.layers and #win.layers or 0) or 0,
    tostring(file.getFilename and file:getFilename() or "<unknown>")
  )

  local li = win:getActiveLayerIndex()
  local layer = win.layers[li]
  if not (layer and layer.kind == "sprite") then
    DebugController.log("info", "PNG_DROP", "Active layer %s is not sprite; resolving sprite layer fallback", tostring(li))
    local spriteLayers = {}
    if win.getSpriteLayers then
      spriteLayers = win:getSpriteLayers() or {}
    else
      for i, L in ipairs(win.layers or {}) do
        if L and L.kind == "sprite" then
          spriteLayers[#spriteLayers + 1] = { index = i, layer = L }
        end
      end
    end

    if #spriteLayers == 0 then
      DebugController.log("warning", "PNG_DROP", "No sprite layers found in win kind=%s title=%s", tostring(win.kind), tostring(win.title))
      return false
    end

    DebugController.log("info", "PNG_DROP", "Found %d sprite layers in window", #spriteLayers)

    for _, info in ipairs(spriteLayers) do
      local sel = SpriteController.getSelectedSpriteIndicesInOrder(info.layer)
      if #sel == 0 and type(info.layer.selectedSpriteIndex) == "number" then
        local s = info.layer.items and info.layer.items[info.layer.selectedSpriteIndex]
        if s and s.removed ~= true then
          sel = { info.layer.selectedSpriteIndex }
        end
      end
      if #sel > 0 then
        li = info.index
        layer = info.layer
        DebugController.log("info", "PNG_DROP", "Chose sprite layer %d due to selection order=%s", li, fmtIndices(sel))
        break
      end
    end

    if not (layer and layer.kind == "sprite") then
      for _, info in ipairs(spriteLayers) do
        for _, s in ipairs(info.layer.items or {}) do
          if s and s.removed ~= true then
            li = info.index
            layer = info.layer
            DebugController.log("info", "PNG_DROP", "Chose sprite layer %d as first with non-removed sprites", li)
            break
          end
        end
        if layer then break end
      end
    end

    if not (layer and layer.kind == "sprite") then
      li = spriteLayers[1].index
      layer = spriteLayers[1].layer
      DebugController.log("info", "PNG_DROP", "Fallback to first sprite layer %d", li)
    end
  end

  local selectedIndices = SpriteController.getSelectedSpriteIndicesInOrder(layer)
  if (#selectedIndices == 0) and layer.selectedSpriteIndex then
    selectedIndices = { layer.selectedSpriteIndex }
  end
  DebugController.log("info", "PNG_DROP", "Resolved sprite layer=%d selectedOrder=%s selectedSpriteIndex=%s", tonumber(li) or -1, fmtIndices(selectedIndices), tostring(layer.selectedSpriteIndex))

  local sprites = {}
  local useSelectedSprites = #selectedIndices > 0
  if useSelectedSprites then
    for _, idx in ipairs(selectedIndices) do
      local s = layer.items and layer.items[idx]
      if s and s.removed ~= true then
        sprites[#sprites + 1] = { sprite = s, itemIndex = idx }
      end
    end
  else
    for idx, s in ipairs(layer.items or {}) do
      if s and s.removed ~= true then
        sprites[#sprites + 1] = { sprite = s, itemIndex = idx }
      end
    end
  end

  if #sprites == 0 then
    DebugController.log(
      "warning",
      "PNG_DROP",
      "No sprite targets after filtering useSelected=%s selectedOrder=%s layer=%d",
      tostring(useSelectedSprites),
      fmtIndices(selectedIndices),
      tonumber(li) or -1
    )
    if useSelectedSprites then
      app:setStatus("No selected sprites in this layer to import into")
    else
      app:setStatus("No sprites in this layer to import into")
    end
    return true
  end

  local imgData, readErr = loadImageDataFromDroppedFile(file)
  if not imgData then
    DebugController.log("warning", "PNG_DROP", "Failed to load image data: %s", tostring(readErr))
    app:setStatus("Failed to read PNG: " .. tostring(readErr))
    return true
  end

  local w, h = imgData:getWidth(), imgData:getHeight()
  DebugController.log("info", "PNG_DROP", "Loaded PNG size=%dx%d spriteTargets=%d useSelected=%s", w, h, #sprites, tostring(useSelectedSprites))

  local colorCount = countUniqueColors(imgData)
  if colorCount > 4 then
    DebugController.log("warning", "PNG_DROP", "Rejected PNG: too many colors=%d", colorCount)
    app:setStatus(string.format("PNG has too many colors (%d). Max 4 incl. transparency.", colorCount))
    return true
  end
  local nonTransparentCount = countUniqueNonTransparentColors(imgData)
  if nonTransparentCount > 3 then
    DebugController.log("warning", "PNG_DROP", "Rejected PNG: too many non-transparent colors=%d", nonTransparentCount)
    app:setStatus(string.format("PNG has too many non-transparent colors (%d). Max 3 for sprites.", nonTransparentCount))
    return true
  end

  local brightnessMap = buildBrightnessIndexMapForSprites(imgData)

  local mode = layer.mode or "8x8"
  local spriteW = 8
  local spriteH = (mode == "8x16") and 16 or 8

  if (w % spriteW) ~= 0 or (h % spriteH) ~= 0 then
    DebugController.log("warning", "PNG_DROP", "Rejected PNG: grid mismatch spriteSize=%dx%d image=%dx%d", spriteW, spriteH, w, h)
    app:setStatus(string.format("PNG must align to %dx%d sprites (got %dx%d)", spriteW, spriteH, w, h))
    return true
  end

  local frames, frameCols, frameRows = buildFrameList(imgData, spriteW, spriteH)
  if #frames == 0 then
    DebugController.log("warning", "PNG_DROP", "Rejected PNG: no frames")
    app:setStatus("PNG contains no frames")
    return true
  end
  DebugController.log("info", "PNG_DROP", "Frame grid cols=%d rows=%d total=%d spriteSize=%dx%d", frameCols, frameRows, #frames, spriteW, spriteH)

  app.edits = app.edits or { banks = {} }
  local romRaw = app.appEditState and app.appEditState.romRaw
  local undoRedo = app and app.undoRedo
  local trackUndo = undoRedo
    and undoRedo.startPaintEvent
    and undoRedo.recordPixelChange
    and undoRedo.finishPaintEvent
    and (undoRedo.activeEvent == nil)
  if trackUndo then
    undoRedo:startPaintEvent()
  end
  local function finalizeUndo()
    if not trackUndo then return end
    if undoRedo.activeEvent then
      undoRedo:finishPaintEvent()
    end
  end
  local paletteRemapByPaletteNumber = {}
  local syncChangedTargets = { list = {}, _set = {} }

  local function getPaletteRemapForSprite(sprite)
    local palNum = (sprite and type(sprite.paletteNumber) == "number") and sprite.paletteNumber or 1
    if paletteRemapByPaletteNumber[palNum] ~= nil then
      local cached = paletteRemapByPaletteNumber[palNum]
      return cached ~= false and cached or nil
    end

    local remap = buildPaletteBrightnessRemapForSprite(layer, palNum, romRaw)
    paletteRemapByPaletteNumber[palNum] = remap or false
    return remap
  end

  local cw   = win.cellW or 8
  local ch   = win.cellH or 8
  local contentW = (win.cols or 32) * cw
  local contentH = (win.rows or 30) * ch
  local blockW = (frameCols or 1) * spriteW
  local blockH = (frameRows or 1) * spriteH
  local topLeftContentX = math.max(0, math.floor((contentW - blockW) * 0.5 + 0.5))
  local topLeftContentY = math.max(0, math.floor((contentH - blockH) * 0.5 + 0.5))
  local originX = layer.originX or 0
  local originY = layer.originY or 0
  local function moveSpriteToFrame(spriteEntry, frame)
    local targetContentX = topLeftContentX + frame.x
    local targetContentY = topLeftContentY + frame.y
    local targetWorldX = targetContentX - originX
    local targetWorldY = targetContentY - originY

    local layerIndex = li
    local z    = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
    local scol = win.scrollCol or 0
    local srow = win.scrollRow or 0
    local centerX = targetContentX + spriteW * 0.5
    local centerY = targetContentY + spriteH * 0.5
    local cx = centerX - scol * cw
    local cy = centerY - srow * ch
    local mouseX = win.x + cx * z
    local mouseY = win.y + cy * z

    SpriteController.setSpriteSelection(layer, { spriteEntry.itemIndex })
    SpriteController.beginDrag(win, layerIndex, spriteEntry.itemIndex, 0, 0)
    SpriteController.updateDrag(mouseX, mouseY)
    SpriteController.endDrag()
  end

  local applied = 0
  local usedFrames = 0
  local skippedTransparent = 0
  local spriteIdx = 1
  local loggedMappings = 0
  for _, frame in ipairs(frames) do
    if spriteIdx > #sprites then break end
    if frameIsTransparent(imgData, frame.x, frame.y, spriteW, spriteH) then
      skippedTransparent = skippedTransparent + 1
      goto continue
    end
    local spriteEntry = sprites[spriteIdx]
    local sprite = spriteEntry.sprite
    local paletteRemap = getPaletteRemapForSprite(sprite)
    local ok, why = applyFrameToSprite(sprite, imgData, frame.x, frame.y, spriteW, spriteH, brightnessMap, paletteRemap, app.edits, undoRedo, app, syncChangedTargets)
    if not ok then
      DebugController.log(
        "warning",
        "PNG_DROP",
        "Sprite frame apply failed frame=(%d,%d) spriteIdx=%d itemIndex=%s reason=%s",
        frame.x,
        frame.y,
        spriteIdx,
        tostring(spriteEntry.itemIndex),
        tostring(why)
      )
      finalizeUndo()
      app:setStatus("Sprite import failed: " .. tostring(why))
      return true
    end
    if loggedMappings < 24 then
      DebugController.log(
        "info",
        "PNG_DROP",
        "Map frame#%d (%d,%d) -> sprite itemIndex=%d mode=%s",
        usedFrames + 1,
        frame.x,
        frame.y,
        tonumber(spriteEntry.itemIndex) or -1,
        useSelectedSprites and "selected" or "auto"
      )
      loggedMappings = loggedMappings + 1
    end
    if not useSelectedSprites then
      moveSpriteToFrame(spriteEntry, frame)
    end
    applied = applied + 1
    usedFrames = usedFrames + 1
    spriteIdx = spriteIdx + 1
    ::continue::
  end

  local unusedFrames = #frames - usedFrames
  local untouchedSprites = #sprites - applied
  local msg = string.format("Imported %d frame(s) into %d sprite(s) (%dx%d)", applied, #sprites, spriteW, spriteH)
  if unusedFrames > 0 then
    msg = msg .. string.format(" (%d frame(s) unused)", unusedFrames)
  end
  if untouchedSprites > 0 then
    msg = msg .. string.format(" (%d sprite(s) untouched)", untouchedSprites)
  end
  if skippedTransparent > 0 then
    msg = msg .. string.format(" (%d transparent frame(s) skipped)", skippedTransparent)
  end

  DebugController.log(
    "info",
    "PNG_DROP",
    "Import completed layer=%d applied=%d targetSprites=%d frames=%d used=%d transparentSkipped=%d msg='%s'",
    tonumber(li) or -1,
    applied,
    #sprites,
    #frames,
    usedFrames,
    skippedTransparent,
    msg
  )
  finalizeUndo()
  if app and app.appEditState and #syncChangedTargets.list > 0 then
    ChrDuplicateSync.updateTiles(app.appEditState, syncChangedTargets.list)
  end
  app:setStatus(msg)
  return true
end

return M
