local StaticArtWindow = require("user_interface.windows_system.static_art_window")
local AnimationWindow = require("user_interface.windows_system.animation_window")
local OAMAnimationWindow = require("user_interface.windows_system.oam_animation_window")
local ChrBankWindow = require("user_interface.windows_system.chr_bank_window")
local RomWindow = require("user_interface.windows_system.rom_window")
local PaletteWindow = require("user_interface.windows_system.palette_window")
local RomPaletteWindow = require("user_interface.windows_system.rom_palette_window")
local PPUFrameWindow = require("user_interface.windows_system.ppu_frame_window")
local PatternTableBuilderWindow = require("user_interface.windows_system.pattern_table_builder_window")

local SpriteController = require("controllers.sprite.sprite_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local DebugController = require("controllers.dev.debug_controller")
local GridModeUtils = require("controllers.grid_mode_utils")
local WindowCaps = require("controllers.window.window_capabilities")

local TableUtils = require("utils.table_utils")

local M = {}

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function logPerf(label, startedAt, extra)
  local elapsed = nowSeconds() - (startedAt or nowSeconds())
  if extra and extra ~= "" then
    DebugController.log("info", "LOAD_PERF", "%s duration=%.3fs %s", tostring(label), elapsed, tostring(extra))
  else
    DebugController.log("info", "LOAD_PERF", "%s duration=%.3fs", tostring(label), elapsed)
  end
end

local function setScrollAndVisibleArea(targetWin, source)
  targetWin.visibleCols = source.visibleCols or source.cols
  targetWin.visibleRows = source.visibleRows or source.rows
  targetWin:setScroll(source.scrollCol or 0, source.scrollRow or 0)
end

local function applyNonActiveLayerOpacity(win)
  if not win or WindowCaps.isChrLike(win) or WindowCaps.isAnyPaletteWindow(win) then return end
  local opa = win.nonActiveLayerOpacity or 1.0
  if not win.layers then return end
  local active = win.activeLayer or 1
  for li, L in ipairs(win.layers) do
    if li == active then
      L.opacity = 1.0
    else
      L.opacity = opa
    end
  end
end

function M.createPaletteWindow(w)
  local rows, cols = w.rows or 1, w.cols or 4
  local initCodes

  if type(w.items) == "table" and #w.items > 0 then
    table.sort(w.items, function(a, b)
      if a.row == b.row then return a.col < b.col end
      return a.row < b.row
    end)

    initCodes = {}
    for i = 1, #w.items do
      initCodes[i] = w.items[i].code or "0F"
    end
  end

  local win = PaletteWindow.new(
    w.x, w.y, 1,
    w.paletteName or "smooth_fbx",
    rows, cols, {
      initCodes = initCodes,
      activePalette = (w.activePalette == true) or false,
      compactView = (w.compactView == true),
    }
  )

  win._id = w.id or "palette"

  if w.selectedCol ~= nil and w.selectedRow ~= nil then
    win:setSelected(w.selectedCol, w.selectedRow)
  end

  if win.activePalette then
    win:syncToGlobalPalette()
  end

  return win
end

function M.createRomPaletteWindow(w, romRaw, decodeUserDefinedCodes)
  local rows, cols = w.rows or 4, w.cols or 4
  if w.paletteData and type(w.paletteData.userDefinedCode) == "string" then
    w.paletteData = TableUtils.deepcopy(w.paletteData)
    w.paletteData.userDefinedCode = (decodeUserDefinedCodes and decodeUserDefinedCodes(w.paletteData.userDefinedCode)) or {}
  end

  local win = RomPaletteWindow.new(
    w.x, w.y, w.zoom or 1,
    w.paletteName or "smooth_fbx",
    rows, cols, {
      paletteData = w.paletteData or {},
      romRaw = romRaw,
      activePalette = false,
      compactView = (w.compactView == true),
    }
  )

  win._id = w.id or "rom_palette"

  if w.selectedCol ~= nil and w.selectedRow ~= nil then
    win:setSelected(w.selectedCol, w.selectedRow)
  end

  return win
end

function M.createChrBankWindow(w)
  local winCtor = (w and w.isRomWindow == true) and RomWindow or ChrBankWindow
  local win = winCtor.new(
    w.x, w.y, w.cellW, w.cellH, w.cols, w.rows, w.zoom, {
      title = w.title,
      orderMode = w.orderMode,
      currentBank = w.currentBank,
    }
  )

  win._id = w.id or "bank"
  win.kind = "chr"
  win.isRomWindow = (w and w.isRomWindow == true) or (win.isRomWindow == true)
  win.currentBank = w.currentBank or win.currentBank or 1
  win.activeLayer = 1

  return win
end

local function hydrateTileLayersFromLayout(win, w, tilesPool, ensureTiles)
  for li, Lsrc in ipairs(w.layers or {}) do
    local layerKind = Lsrc.kind or "tile"
    if layerKind ~= "sprite" and type(Lsrc.items) == "table" then
      local Ldst = win.layers and win.layers[li]
      if Ldst then
        Ldst.paletteNumbers = Ldst.paletteNumbers or {}
      end

      for _, it in ipairs(Lsrc.items) do
        if it.bank and it.tile then
          ensureTiles(it.bank)
          local tileRef = tilesPool[it.bank] and tilesPool[it.bank][it.tile]
          if tileRef then
            win:set(it.col, it.row, tileRef, li)
            if Ldst and it.paletteNumber then
              local col = it.col or 0
              local row = it.row or 0
              local idx = row * win.cols + col
              Ldst.paletteNumbers[idx] = it.paletteNumber
            end
          end
        end
      end
    end
  end
end

function M.createStaticArtWindow(w, tilesPool, ensureTiles)
  local win = StaticArtWindow.new(
    w.x, w.y, w.cellW, w.cellH, w.cols, w.rows, w.zoom, {
      title = w.title,
      nonActiveLayerOpacity = w.nonActiveLayerOpacity,
    }
  )

  win.layers = {}
  local layers = w.layers or {}
  for li, Lsrc in ipairs(layers) do
    local layerKind = Lsrc.kind or "tile"
    win:addLayer({
      opacity = 1.0,
      name = Lsrc.name or ("Layer " .. li),
      kind = layerKind,
      mode = Lsrc.mode,
      originX = Lsrc.originX,
      originY = Lsrc.originY,
    })
  end

  win._id = w.id
  win.kind = "static_art"
  win.activeLayer = w.activeLayer or 1

  for li, Lsrc in ipairs(layers) do
    if Lsrc.kind == "sprite" then
      local spriteLayer = win.layers[li]
      if spriteLayer then
        spriteLayer.items = spriteLayer.items or {}
        for _, it in ipairs(Lsrc.items or {}) do
          if it.bank and it.tile then
            ensureTiles(it.bank)
            table.insert(spriteLayer.items, {
              x = it.x or 0,
              y = it.y or 0,
              bank = it.bank,
              tile = it.tile,
              paletteNumber = it.paletteNumber,
              mirrorX = it.mirrorX,
              mirrorY = it.mirrorY,
              _mirrorXOverrideSet = (it.mirrorX ~= nil),
              _mirrorYOverrideSet = (it.mirrorY ~= nil),
            })
          end
        end
      end
    end
  end

  hydrateTileLayersFromLayout(win, w, tilesPool, ensureTiles)
  applyNonActiveLayerOpacity(win)

  return win
end

function M.createAnimationWindow(w, tilesPool, ensureTiles)
  local win = AnimationWindow.new(
    w.x, w.y, w.cellW, w.cellH, w.cols, w.rows, w.zoom, {
      title = w.title,
      nonActiveLayerOpacity = w.nonActiveLayerOpacity,
    }
  )

  win._id = w.id
  win.kind = "animation"
  win.activeLayer = w.activeLayer or 1

  if w.delaysPerLayer and type(w.delaysPerLayer) == "table" then
    for i, delay in ipairs(w.delaysPerLayer) do
      win.frameDelays[i] = delay
    end
  end

  win.layers = {}
  local layers = w.layers or {}
  if #layers == 0 then
    win:addLayer({ opacity = 1.0, name = "Layer 1", kind = "tile" })
  else
    for li, Lsrc in ipairs(layers) do
      local layerKind = Lsrc.kind or "tile"
      win:addLayer({
        opacity = 1.0,
        name = Lsrc.name or ("Layer " .. li),
        kind = layerKind,
        mode = Lsrc.mode,
        originX = Lsrc.originX,
        originY = Lsrc.originY,
      })
    end
  end

  for li, Lsrc in ipairs(layers or {}) do
    if Lsrc.kind == "sprite" then
      local spriteLayer = win.layers[li]
      if spriteLayer then
        spriteLayer.items = spriteLayer.items or {}
        for _, it in ipairs(Lsrc.items or {}) do
          if it.bank and it.tile then
            ensureTiles(it.bank)
            table.insert(spriteLayer.items, {
              x = it.x or 0,
              y = it.y or 0,
              bank = it.bank,
              tile = it.tile,
              paletteNumber = it.paletteNumber,
              mirrorX = it.mirrorX,
              mirrorY = it.mirrorY,
              _mirrorXOverrideSet = (it.mirrorX ~= nil),
              _mirrorYOverrideSet = (it.mirrorY ~= nil),
            })
          end
        end
        if SpriteController and SpriteController.hydrateSpriteLayer then
          SpriteController.hydrateSpriteLayer(spriteLayer, {
            romRaw = "",
            tilesPool = tilesPool,
          })
        end
      end
    end
  end

  hydrateTileLayersFromLayout(win, w, tilesPool, ensureTiles)

  local numLayers = #win.layers
  if numLayers > 0 then
    win.activeLayer = math.max(1, math.min(win.activeLayer or 1, numLayers))
  end

  applyNonActiveLayerOpacity(win)
  return win
end

function M.createOamAnimationWindow(w, tilesPool, ensureTiles)
  local win = OAMAnimationWindow.new(
    w.x, w.y, w.cellW, w.cellH, w.cols, w.rows, w.zoom, {
      title = w.title,
      nonActiveLayerOpacity = w.nonActiveLayerOpacity,
      multiRowToolbar = (w.multiRowToolbar == true),
      showSpriteOriginGuides = (w.showSpriteOriginGuides == true),
    }
  )

  win._id = w.id
  win.kind = "oam_animation"
  win.activeLayer = w.activeLayer or 1

  if w.delaysPerLayer and type(w.delaysPerLayer) == "table" then
    for i, delay in ipairs(w.delaysPerLayer) do
      win.frameDelays[i] = delay
    end
  end

  win.layers = {}
  local layers = w.layers or {}
  if #layers == 0 then
    win:addLayer({
      opacity = 1.0,
      name = "Frame 1",
      kind = "sprite",
      mode = "8x8",
      originX = 0,
      originY = 0,
    })
  else
    for li, Lsrc in ipairs(layers) do
      win:addLayer({
        opacity = 1.0,
        name = Lsrc.name or ("Frame " .. li),
        kind = "sprite",
        mode = Lsrc.mode or "8x8",
        originX = (Lsrc.originX ~= nil) and Lsrc.originX or 0,
        originY = (Lsrc.originY ~= nil) and Lsrc.originY or 0,
      })

      local spriteLayer = win.layers[li]
      if spriteLayer then
        spriteLayer.items = spriteLayer.items or {}
        for _, it in ipairs(Lsrc.items or {}) do
          if it.bank and (it.tile or it.startAddr) then
            ensureTiles(it.bank)
            table.insert(spriteLayer.items, {
              startAddr = it.startAddr,
              bank = it.bank,
              tile = it.tile,
              dx = it.dx,
              dy = it.dy,
              x = it.x,
              y = it.y,
              paletteNumber = it.paletteNumber,
              mirrorX = it.mirrorX,
              mirrorY = it.mirrorY,
              _mirrorXOverrideSet = (it.mirrorX ~= nil),
              _mirrorYOverrideSet = (it.mirrorY ~= nil),
            })
          end
        end
      end
    end
  end

  local numLayers = #win.layers
  if numLayers > 0 then
    win.activeLayer = math.max(1, math.min(win.activeLayer or 1, numLayers))
  end

  applyNonActiveLayerOpacity(win)
  return win
end

local function addPpuSpriteOverlayLayers(win, w, ensureTiles)
  win.layers = win.layers or {}

  for li, Lsrc in ipairs(w.layers or {}) do
    if Lsrc.kind == "sprite" then
      local spriteLayer = {
        items = {},
        opacity = 1.0,
        name = Lsrc.name or ("Layer " .. li),
        kind = "sprite",
        mode = Lsrc.mode,
        originX = Lsrc.originX,
        originY = Lsrc.originY,
      }

      for _, it in ipairs(Lsrc.items or {}) do
        if it.bank and it.tile then
          ensureTiles(it.bank)
          table.insert(spriteLayer.items, {
            startAddr = it.startAddr,
            bank = it.bank,
            tile = it.tile,
            dx = it.dx,
            dy = it.dy,
            paletteNumber = it.paletteNumber,
            mirrorX = it.mirrorX,
            mirrorY = it.mirrorY,
            _mirrorXOverrideSet = (it.mirrorX ~= nil),
            _mirrorYOverrideSet = (it.mirrorY ~= nil),
          })
        end
      end

      table.insert(win.layers, spriteLayer)
    end
  end
end

function M.createPPUFrameWindow(w, tilesPool, ensureTiles, romRaw)
  local ntLayer = nil
  for _, Lsrc in ipairs(w.layers or {}) do
    local layerKind = Lsrc.kind or "tile"
    if layerKind ~= "sprite" and Lsrc.nametableStartAddr then
      ntLayer = Lsrc
      break
    end
  end

  local nametableStart = ntLayer and ntLayer.nametableStartAddr or w.nametableStartAddr
  local nametableEnd = ntLayer and ntLayer.nametableEndAddr or w.nametableEndAddr
  if not (nametableStart and nametableEnd) then
    return nil
  end

  local bankIdx = (ntLayer and ntLayer.bank) or w.bank or w.bankIndex or 1
  local pageIdx = (ntLayer and ntLayer.page) or w.page or w.pageIndex or 1

  local win = PPUFrameWindow.new(w.x, w.y, w.zoom, {
    romRaw = romRaw,
    nametableStart = nametableStart,
    title = w.title,
    nonActiveLayerOpacity = w.nonActiveLayerOpacity,
    showSpriteOriginGuides = (w.showSpriteOriginGuides == true),
  })

  win._id = w.id
  win.kind = "ppu_frame"

  DebugController.log("info", "GAM", "Creating PPU frame window - bankIdx: %d, pageIdx: %d", bankIdx, pageIdx)

  local ntRuntimeLayer = win.layers and win.layers[1]
  if ntRuntimeLayer then
    local hydrateStartedAt = nowSeconds()
    local ok, err = NametableTilesController.hydrateWindowNametable(win, ntRuntimeLayer, {
      romRaw = romRaw,
      tilesPool = tilesPool,
      ensureTiles = ensureTiles,
      nametableStartAddr = nametableStart,
      nametableEndAddr = nametableEnd,
      codec = (ntLayer and ntLayer.codec) or "konami",
      noOverflowSupported = ntLayer and ntLayer.noOverflowSupported == true,
      bankIndex = bankIdx,
      pageIndex = pageIdx,
      patternTable = ntLayer and ntLayer.patternTable,
      tileSwaps = ntLayer and ntLayer.tileSwaps,
      userDefinedAttrs = ntLayer and ntLayer.userDefinedAttrs,
    })
    if not ok then
      DebugController.log("info", "GAM", "hydrateWindowNametable failed for PPU frame: %s", tostring(err))
    else
      DebugController.log("info", "GAM", "hydrateWindowNametable OK for %s", win._id or win.title)
      DebugController.log("info", "GAM", "  #nametableBytes = %d", #(win.nametableBytes or {}))
      DebugController.log("info", "GAM", "  #nametableAttrBytes = %d", #(win.nametableAttrBytes or {}))
      if ntRuntimeLayer.paletteNumbers then
        DebugController.log("info", "GAM", "  ntRuntimeLayer.paletteNumbers present (table)")
      else
        DebugController.log("info", "GAM", "  ntRuntimeLayer.paletteNumbers is NIL")
      end
    end
    logPerf("ppu_frame.hydrate_nametable", hydrateStartedAt, string.format("title=%s", tostring(w.title or "")))
  end

  local overlayStartedAt = nowSeconds()
  addPpuSpriteOverlayLayers(win, w, ensureTiles)
  logPerf("ppu_frame.add_sprite_overlays", overlayStartedAt, string.format("title=%s", tostring(w.title or "")))
  win.activeLayer = w.activeLayer or 1
  return win
end

function M.createPatternTableBuilderWindow(w, decodePatternCanvasSnapshot, onPatternCanvasRestoreError)
  local win = PatternTableBuilderWindow.new(
    w.x, w.y, w.cellW, w.cellH, w.cols, w.rows, w.zoom, {
      title = w.title,
      visibleRows = w.visibleRows or w.rows,
      visibleCols = w.visibleCols or w.cols,
      patternTolerance = w.patternTolerance or 0,
    }
  )

  win._id = w.id
  win.kind = "pattern_table_builder"
  win.activeLayer = w.activeLayer or 1

  for li, Lsrc in ipairs(w.layers or {}) do
    local Ldst = win.layers and win.layers[li] or nil
    if Ldst and Lsrc.edits and Ldst.canvas and decodePatternCanvasSnapshot then
      local ok, reason = decodePatternCanvasSnapshot(Ldst.canvas, Lsrc.edits)
      if not ok and onPatternCanvasRestoreError then
        onPatternCanvasRestoreError({
          window = win,
          windowSpec = w,
          layerIndex = li,
          reason = reason,
          edits = Lsrc.edits,
        })
      end
    end
  end

  if win.generatePackedPatternTable then
    win:generatePackedPatternTable()
  end

  return win
end

local function applyLayerMetadataFromLayout(win, layoutLayers)
  if not (win and layoutLayers and win.layers) then return end

  for li, Lsrc in ipairs(layoutLayers or {}) do
    local Ldst = win.layers[li]
    if Ldst then
      if Lsrc.originX ~= nil then Ldst.originX = Lsrc.originX end
      if Lsrc.originY ~= nil then Ldst.originY = Lsrc.originY end
      if Lsrc.mode ~= nil and Ldst.mode == nil then Ldst.mode = Lsrc.mode end
      if Lsrc.codec ~= nil then Ldst.codec = Lsrc.codec end
      if Lsrc.noOverflowSupported ~= nil then
        Ldst.noOverflowSupported = (Lsrc.noOverflowSupported == true)
      end
      if type(Lsrc.patternTable) == "table" then
        Ldst.patternTable = TableUtils.deepcopy(Lsrc.patternTable)
      end
      if Lsrc.paletteData ~= nil then
        Ldst.paletteData = TableUtils.deepcopy(Lsrc.paletteData)
      end
    end
  end
end

function M.finalizeWindow(win, w, windowsById, wm, romRaw, tilesPool)
  if not win then return end

  local metadataStartedAt = nowSeconds()
  applyLayerMetadataFromLayout(win, w.layers)
  logPerf("window_finalize.apply_layer_metadata", metadataStartedAt, string.format("title=%s", tostring(w.title or "")))

  local spriteHydrationStartedAt = nowSeconds()
  SpriteController.hydrateWindowSpriteLayers(win, {
    romRaw = romRaw,
    tilesPool = tilesPool,
  })
  logPerf("window_finalize.hydrate_sprite_layers", spriteHydrationStartedAt, string.format("title=%s", tostring(w.title or "")))

  local layoutStartedAt = nowSeconds()
  setScrollAndVisibleArea(win, w)
  win.title = w.title
  win.showGrid = GridModeUtils.normalize(w.showGrid)
  win._z = w.z or 0

  if w.collapsed ~= nil then
    win._collapsed = w.collapsed
  end
  local shouldMinimize = (w.minimized == true)
  if not wm and shouldMinimize then
    win._minimized = true
  end

  if win.nonActiveLayerOpacity and win.layers then
    local active = win.activeLayer or 1
    for li, L in ipairs(win.layers) do
      if li == active then
        L.opacity = 1.0
      else
        L.opacity = win.nonActiveLayerOpacity
      end
    end
  end
  logPerf("window_finalize.apply_layout_state", layoutStartedAt, string.format("title=%s", tostring(w.title or "")))

  local registerStartedAt = nowSeconds()
  windowsById[win._id or ("win" .. tostring((w.z or 0)))] = win
  if wm then
    wm:add(win)
    if shouldMinimize and wm.minimizeWindow then
      wm:minimizeWindow(win, { recordUndo = false })
    end
  end
  logPerf("window_finalize.register_window", registerStartedAt, string.format("title=%s", tostring(w.title or "")))
end

return M
