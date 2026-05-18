local StaticArtWindow = require("user_interface.windows_system.static_art_window")
local AnimationWindow = require("user_interface.windows_system.animation_window")
local OAMAnimationWindow = require("user_interface.windows_system.oam_animation_window")
local ChrBankWindow = require("user_interface.windows_system.chr_bank_window")
local RomWindow = require("user_interface.windows_system.rom_window")
local PaletteWindow = require("user_interface.windows_system.palette_window")
local RomPaletteWindow = require("user_interface.windows_system.rom_palette_window")
local PPUFrameWindow = require("user_interface.windows_system.ppu_frame_window")
local PixelSketchCanvasWindow = require("user_interface.windows_system.pixel_sketch_canvas_window")
local PatternTableWindow = require("user_interface.windows_system.pattern_table_window")

local SpriteController = require("controllers.sprite.sprite_controller")
local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local DebugController = require("controllers.dev.debug_controller")
local GridModeUtils = require("controllers.grid_mode_utils")
local WindowCaps = require("controllers.window.window_capabilities")
local PatternTableMapping = require("utils.pattern_table_mapping")

local TableUtils = require("utils.table_utils")
local ReferenceBackgroundController = require("controllers.window.reference_background_controller")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")

local M = {}

--- Layout disk format for ROM OAM slots (mirrors must match `hydration_controller.snapshotSpriteLayer`).
local function spriteOamSlotItemFromLayout(it)
  return {
    startAddr = it.startAddr,
    paletteNumber = it.paletteNumber,
    dx = it.dx,
    dy = it.dy,
    mirrorX = it.mirrorX,
    mirrorY = it.mirrorY,
    _mirrorXOverrideSet = (it.mirrorX ~= nil),
    _mirrorYOverrideSet = (it.mirrorY ~= nil),
  }
end

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

--- Layout may store visibleCols/visibleRows as 0; in Lua `0 or cols` keeps 0, yielding 0px viewport (invisible window).
local function positiveIntOrFallback(value, fallback)
  local n = tonumber(value)
  if n == nil or n < 1 then
    n = tonumber(fallback)
  end
  if n == nil or n < 1 then
    return 1
  end
  return math.max(1, math.floor(n))
end

--- Same issue as visibleCols: `w.cellW or 8` keeps 0 (0 is truthy), so the window has 0×N px content.
local function layoutCellDim(value, default)
  local n = tonumber(value)
  local d = tonumber(default) or 8
  if n == nil or n < 1 then
    return math.max(1, math.floor(d))
  end
  return math.max(1, math.floor(n))
end

--- `Window.new` uses `zoom or 1.0`; zoom=0 is truthy in Lua and yields invisible geometry and bad mouse math.
local function layoutZoomOrDefault(z, default)
  local n = tonumber(z)
  local d = tonumber(default) or 2
  if n == nil or n < 0.01 then
    n = d
  end
  return n
end

local function setScrollAndVisibleArea(targetWin, source)
  if not (targetWin and source) then
    return
  end
  targetWin.visibleCols = positiveIntOrFallback(source.visibleCols, source.cols)
  targetWin.visibleRows = positiveIntOrFallback(source.visibleRows, source.rows)
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
      title = w.title,
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

function M.createPatternTableWindow(w, tilesPool, ensureTiles)
  local cols = math.max(1, math.floor(tonumber(w.cols) or 16))
  local rows = math.max(1, math.floor(tonumber(w.rows) or 16))
  local cellW = layoutCellDim(w.cellW, 8)
  local cellH = layoutCellDim(w.cellH, 8)
  local zoom = layoutZoomOrDefault(w.zoom, 2)
  local win = PatternTableWindow.new(
    w.x or 0,
    w.y or 0,
    cellW,
    cellH,
    cols,
    rows,
    zoom,
    {
      title = w.title,
      visibleRows = w.visibleRows or rows,
      visibleCols = w.visibleCols or cols,
      nonActiveLayerOpacity = w.nonActiveLayerOpacity,
    }
  )

  win.layers = {}
  local Lsrc = ((w.layers or {})[1] or {})
  win:addLayer({
    opacity = 1.0,
    name = Lsrc.name or "Pattern table",
    kind = "tile",
    mode = Lsrc.mode or "8x8",
  })

  win._id = w.id
  win.kind = "pattern_table"
  win.activeLayer = w.activeLayer or 1
  win.nonActiveLayerOpacity = w.nonActiveLayerOpacity or 1.0

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
        if type(Lsrc.linkedPatternTableWindowId) == "string" and Lsrc.linkedPatternTableWindowId ~= "" then
          spriteLayer.linkedPatternTableWindowId = Lsrc.linkedPatternTableWindowId
        elseif type(Lsrc.patternTable) == "table" then
          spriteLayer.patternTable = TableUtils.deepcopy(Lsrc.patternTable)
        end
        spriteLayer.items = spriteLayer.items or {}
        for _, it in ipairs(Lsrc.items or {}) do
          local oamSlot = type(it.startAddr) == "number"
          local chrPair = it.bank ~= nil and type(it.tile) == "number"
          if oamSlot then
            table.insert(spriteLayer.items, spriteOamSlotItemFromLayout(it))
          elseif chrPair then
            if it.bank ~= nil then
              ensureTiles(it.bank)
            end
            table.insert(spriteLayer.items, {
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

      if type(Lsrc.linkedPatternTableWindowId) == "string" and Lsrc.linkedPatternTableWindowId ~= "" then
        spriteLayer.linkedPatternTableWindowId = Lsrc.linkedPatternTableWindowId
      elseif type(Lsrc.patternTable) == "table" then
        spriteLayer.patternTable = TableUtils.deepcopy(Lsrc.patternTable)
      end

      for _, it in ipairs(Lsrc.items or {}) do
        local oamSlot = type(it.startAddr) == "number"
        local chrPair = it.bank ~= nil and type(it.tile) == "number"
        if oamSlot then
          table.insert(spriteLayer.items, spriteOamSlotItemFromLayout(it))
        elseif chrPair then
          if it.bank ~= nil then
            ensureTiles(it.bank)
          end
          table.insert(spriteLayer.items, {
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
  local patternTable = ntLayer and ntLayer.patternTable or nil
  local mapOk, mapErr = PatternTableMapping.validate(patternTable)
  local linkedPatternTableWindowId =
    ntLayer and type(ntLayer.linkedPatternTableWindowId) == "string" and ntLayer.linkedPatternTableWindowId ~= ""
  local deferNametableHydrate = linkedPatternTableWindowId and not mapOk

  local win = PPUFrameWindow.new(w.x, w.y, w.zoom, {
    romRaw = romRaw,
    nametableStart = nametableStart,
    title = w.title,
    nonActiveLayerOpacity = w.nonActiveLayerOpacity,
    showSpriteOriginGuides = (w.showSpriteOriginGuides == true),
  })

  win._id = w.id
  win.kind = "ppu_frame"

  local ntRuntimeLayer = win.layers and win.layers[1]
  if ntRuntimeLayer then
    local hydrateStartedAt = nowSeconds()
    if deferNametableHydrate then
      win._ppuxDeferNametableHydrate = {
        layerIndex = 1,
        nametableStartAddr = nametableStart,
        nametableEndAddr = nametableEnd,
        codec = (ntLayer and ntLayer.codec) or "konami",
        noOverflowSupported = ntLayer and ntLayer.noOverflowSupported == true,
        tileSwaps = ntLayer and ntLayer.tileSwaps,
        userDefinedAttrs = ntLayer and ntLayer.userDefinedAttrs,
      }
      DebugController.log(
        "info",
        "GAM",
        "Defer nametable hydrate for '%s' until linked pattern table window is resolved",
        tostring(w.title or "")
      )
    elseif not mapOk then
      DebugController.log(
        "warning",
        "GAM",
        "Skipping PPU nametable hydrate for '%s': patternTable is missing/invalid (%s)",
        tostring(w.title or ""),
        tostring(mapErr)
      )
    else
      local ok, err = NametableTilesController.hydrateWindowNametable(win, ntRuntimeLayer, {
        romRaw = romRaw,
        tilesPool = tilesPool,
        ensureTiles = ensureTiles,
        nametableStartAddr = nametableStart,
        nametableEndAddr = nametableEnd,
        codec = (ntLayer and ntLayer.codec) or "konami",
        noOverflowSupported = ntLayer and ntLayer.noOverflowSupported == true,
        patternTable = patternTable,
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
    end
    logPerf("ppu_frame.hydrate_nametable", hydrateStartedAt, string.format("title=%s", tostring(w.title or "")))
  end

  local overlayStartedAt = nowSeconds()
  addPpuSpriteOverlayLayers(win, w, ensureTiles)
  logPerf("ppu_frame.add_sprite_overlays", overlayStartedAt, string.format("title=%s", tostring(w.title or "")))
  win.activeLayer = w.activeLayer or 1
  return win
end

function M.createPatternSketchCanvasWindow(w, decodePatternCanvasSnapshot, onPatternCanvasRestoreError)
  local win = PixelSketchCanvasWindow.new(
    w.x, w.y, w.cellW, w.cellH, w.cols, w.rows, w.zoom, {
      title = w.title,
      visibleRows = w.visibleRows or w.rows,
      visibleCols = w.visibleCols or w.cols,
    }
  )

  win._id = w.id
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

  return win
end

--- PPU frames may have runtime-only tile layers (e.g. pattern-table previews) that are not in the
--- saved layout. Index-wise metadata then mis-assigns sprite fields onto the wrong layer; match
--- sprite layers by order among `kind == "sprite"` entries instead.
local function mergePpuSpriteLayerMetadataFromLayoutByOrdinal(win, layoutLayers)
  if not (WindowCaps.isPpuFrame(win) and layoutLayers and win.layers) then
    return
  end

  local srcSprites = {}
  for _, L in ipairs(layoutLayers) do
    if L and L.kind == "sprite" then
      srcSprites[#srcSprites + 1] = L
    end
  end

  local dstSprites = {}
  for _, L in ipairs(win.layers) do
    if L and L.kind == "sprite" then
      dstSprites[#dstSprites + 1] = L
    end
  end

  for i = 1, math.min(#srcSprites, #dstSprites) do
    local Lsrc, Ldst = srcSprites[i], dstSprites[i]
    if type(Lsrc.linkedPatternTableWindowId) == "string" and Lsrc.linkedPatternTableWindowId ~= "" then
      Ldst.linkedPatternTableWindowId = Lsrc.linkedPatternTableWindowId
    end
    if type(Lsrc.patternTable) == "table"
      and not (type(Lsrc.linkedPatternTableWindowId) == "string" and Lsrc.linkedPatternTableWindowId ~= "")
    then
      Ldst.patternTable = TableUtils.deepcopy(Lsrc.patternTable)
    end
    if Lsrc.paletteData ~= nil then
      Ldst.paletteData = TableUtils.deepcopy(Lsrc.paletteData)
    end
    if type(Lsrc.userDefinedAttrs) == "string" then
      Ldst.userDefinedAttrs = Lsrc.userDefinedAttrs
    end
  end
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
      if Lsrc.nametableStartAddr ~= nil then Ldst.nametableStartAddr = Lsrc.nametableStartAddr end
      if Lsrc.nametableEndAddr ~= nil then Ldst.nametableEndAddr = Lsrc.nametableEndAddr end
      if Lsrc.noOverflowSupported ~= nil then
        Ldst.noOverflowSupported = (Lsrc.noOverflowSupported == true)
      end
      if type(Lsrc.linkedPatternTableWindowId) == "string" and Lsrc.linkedPatternTableWindowId ~= "" then
        Ldst.linkedPatternTableWindowId = Lsrc.linkedPatternTableWindowId
      end
      if type(Lsrc.patternTable) == "table"
        and not (type(Lsrc.linkedPatternTableWindowId) == "string" and Lsrc.linkedPatternTableWindowId ~= "")
      then
        Ldst.patternTable = TableUtils.deepcopy(Lsrc.patternTable)
      end
      if Lsrc.tileSwaps ~= nil then
        Ldst.tileSwaps = TableUtils.deepcopy(Lsrc.tileSwaps)
      end
      if type(Lsrc.userDefinedAttrs) == "string" then
        Ldst.userDefinedAttrs = Lsrc.userDefinedAttrs
      end
      if Lsrc.paletteData ~= nil then
        Ldst.paletteData = TableUtils.deepcopy(Lsrc.paletteData)
      end
    end
  end

  mergePpuSpriteLayerMetadataFromLayoutByOrdinal(win, layoutLayers)
end

function M.finalizeWindow(win, w, windowsById, wm, romRaw, tilesPool, layoutCurrentBank)
  if not win then return end

  local metadataStartedAt = nowSeconds()
  applyLayerMetadataFromLayout(win, w.layers)
  logPerf("window_finalize.apply_layer_metadata", metadataStartedAt, string.format("title=%s", tostring(w.title or "")))

  local spriteHydrationStartedAt = nowSeconds()
  SpriteController.hydrateWindowSpriteLayers(win, {
    romRaw = romRaw,
    tilesPool = tilesPool,
    defaultChrBank = w.currentBank or layoutCurrentBank,
  })
  logPerf("window_finalize.hydrate_sprite_layers", spriteHydrationStartedAt, string.format("title=%s", tostring(w.title or "")))

  local layoutStartedAt = nowSeconds()
  setScrollAndVisibleArea(win, w)
  win.title = w.title
  if win.updateBankTitle then
    win:updateBankTitle()
  end
  win.showGrid = GridModeUtils.normalize(w.showGrid)
  win._z = w.z or 0

  if type(w.referenceBackgroundPath) == "string" and w.referenceBackgroundPath ~= "" then
    local ctx = rawget(_G, "ctx")
    local app = ctx and ctx.app
    ReferenceBackgroundController.applyStoredPath(win, app, w.referenceBackgroundPath, {
      toastWarnOversized = true,
    })
  end

  if w.collapsed ~= nil then
    win._collapsed = w.collapsed
  end
  win._alwaysOnTop = (w.alwaysOnTop == true)
  win._mirrorXPreview = (w.mirrorXPreview == true)
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
  if wm then
    if wm.ensureStableWindowId then
      wm:ensureStableWindowId(win)
    end
  end
  windowsById[win._id or ("win" .. tostring((w.z or 0)))] = win
  if wm then
    wm:add(win)
    if shouldMinimize and wm.minimizeWindow then
      wm:minimizeWindow(win, { recordUndo = false })
    end
  end
  logPerf("window_finalize.register_window", registerStartedAt, string.format("title=%s", tostring(w.title or "")))

  if WindowCaps.isPatternTable(win) then
    local _, _, sw, sh = win:getScreenRect()
    local layer1 = win.layers and win.layers[1]
    local hasPt = layer1 and type(layer1.patternTable) == "table"
    DebugController.log(
      "info",
      "PATTERN_TABLE",
      "finalizeWindow kind=pattern_table id=%s title=%q pos=(%.1f,%.1f) screenRect=%.1fx%.1f cell=%dx%d zoom=%s visible=%dx%d colsxrows=%dx%d minimized=%s collapsed=%s layer1.patternTable=%s",
      tostring(win._id or "?"),
      tostring(win.title or ""),
      tonumber(win.x) or 0,
      tonumber(win.y) or 0,
      tonumber(sw) or 0,
      tonumber(sh) or 0,
      tonumber(win.cellW) or 0,
      tonumber(win.cellH) or 0,
      tostring(win.zoom),
      tonumber(win.visibleCols) or 0,
      tonumber(win.visibleRows) or 0,
      tonumber(win.cols) or 0,
      tonumber(win.rows) or 0,
      tostring(win._minimized == true),
      tostring(win._collapsed == true),
      tostring(hasPt)
    )
  end
end

function M.finalizeDeferredPpuNametableHydrates(wm, romRaw, tilesPool, ensureTiles)
  if not wm or not wm.getWindows then
    return
  end
  romRaw = romRaw or ""
  for _, win in ipairs(wm:getWindows()) do
    local pend = win and win._ppuxDeferNametableHydrate
    if WindowCaps.isPpuFrame(win) and type(pend) == "table" then
      win._ppuxDeferNametableHydrate = nil
      local layerIndex = math.max(1, math.floor(tonumber(pend.layerIndex) or 1))
      local layer = win.layers and win.layers[layerIndex]
      local patternTable = layer and layer.patternTable
      local mapOk, mapErr = PatternTableMapping.validate(patternTable)
      if not mapOk then
        DebugController.log(
          "warning",
          "GAM",
          "Deferred nametable hydrate for '%s': patternTable still unusable (%s)",
          tostring(win.title or win._id or ""),
          tostring(mapErr or "?")
        )
      else
        local ok, err = NametableTilesController.hydrateWindowNametable(win, layer, {
          romRaw = romRaw,
          tilesPool = tilesPool,
          ensureTiles = ensureTiles,
          nametableStartAddr = pend.nametableStartAddr,
          nametableEndAddr = pend.nametableEndAddr,
          codec = pend.codec or "konami",
          noOverflowSupported = pend.noOverflowSupported == true,
          tileSwaps = pend.tileSwaps,
          userDefinedAttrs = pend.userDefinedAttrs,
        })
        if not ok then
          DebugController.log(
            "info",
            "GAM",
            "Deferred hydrateWindowNametable failed for '%s': %s",
            tostring(win.title or win._id or ""),
            tostring(err)
          )
        end
      end
    end
  end
end

function M.afterLayoutPatternTablesHydrate(wm, tilesPool, ensureTiles, opts)
  opts = type(opts) == "table" and opts or {}
  PatternTableDisplayController.resolveLinkedPatternTableLayers(wm)

  -- Copy linked pattern tables onto consuming layers (`patternTable`), then rebuild sprite CHR refs.
  -- OAM tile bytes are logical indices into the linked pattern-table window ordering (same 0–255 path
  -- as populateTileLayerItemsFromPatternTable: row-major 16-wide grid).
  local romRawLinked = opts.romRaw or ""
  if wm and wm.getWindows then
    for _, win in ipairs(wm:getWindows()) do
      SpriteController.hydrateWindowSpriteLayers(win, {
        romRaw = romRawLinked,
        tilesPool = tilesPool,
        appEditState = opts.appEditState,
      })
    end
  end

  PatternTableDisplayController.refreshAllPatternTableWindows(wm, {
    tilesPool = tilesPool,
    ensureTiles = ensureTiles,
    appEditState = opts.appEditState,
  })
  M.finalizeDeferredPpuNametableHydrates(wm, opts.romRaw, tilesPool, ensureTiles)

  -- hydrateWindowNametable / early layout can populate nametable visuals before tilesPool CHR keys
  -- exist or before pattern linkage is finalized, leaving sparse layer.items until something
  -- (e.g. switching tabs) retriggers rebuild. Refresh every real nametable tile layer once CHR is ready.
  if wm and wm.getWindows and type(tilesPool) == "table" then
    for _, win in ipairs(wm:getWindows()) do
      if WindowCaps.isPpuFrame(win)
        and type(win.refreshNametableVisuals) == "function"
        and #(win.nametableBytes or {}) > 0
      then
        for li, L in ipairs(win.layers or {}) do
          if L
            and L.kind == "tile"
            and L._runtimePatternTableRefLayer ~= true
            and PatternTableMapping.validate(L.patternTable)
          then
            win:refreshNametableVisuals(tilesPool, li)
          end
        end
      end
    end
  end

  if wm and wm.getWindows then
    for _, win in ipairs(wm:getWindows()) do
      if WindowCaps.isPpuFrame(win) and win.setActiveLayerIndex and win.getActiveLayerIndex then
        win:setActiveLayerIndex(win:getActiveLayerIndex())
      end
    end
  end

  if wm and wm.getWindows then
    local n = 0
    for _, w in ipairs(wm:getWindows()) do
      if WindowCaps.isPatternTable(w) and not w._closed then
        n = n + 1
      end
    end
    DebugController.log(
      "info",
      "PATTERN_TABLE",
      "afterLayoutPatternTablesHydrate: open pattern_table windows in WM count=%d",
      n
    )
  end
end

return M
