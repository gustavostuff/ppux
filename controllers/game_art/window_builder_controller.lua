local GameArtWindowFactoryController = require("controllers.game_art.window_factory_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local DebugController = require("controllers.dev.debug_controller")

local M = {}

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function describeWindowSpec(w)
  if not w then
    return "kind=? id=? title=?"
  end
  return string.format(
    "kind=%s id=%s title=%s",
    tostring(w.kind or "normal"),
    tostring(w.id or ""),
    tostring(w.title or "")
  )
end

function M.buildWindowsFromLayout(layout, opts)
  if not layout or type(layout) ~= "table" then return nil, "invalid-layout" end

  local wm = opts.wm
  local tilesPool = opts.tilesPool
  local ensureTiles = opts.ensureTiles
  local romRaw = opts.romRaw or ""
  local chrBackingMode = opts.chrBackingMode
  local romTileViewMode = (chrBackingMode == "rom_raw") or (opts.romTileViewMode == true)
  local decodeUserDefinedCodes = opts.decodeUserDefinedCodes
  local lastPaletteWindow = nil
  local builders = {
    palette = function(w)
      local win = GameArtWindowFactoryController.createPaletteWindow(w)
      lastPaletteWindow = win
      return win
    end,
    rom_palette = function(w)
      local win = GameArtWindowFactoryController.createRomPaletteWindow(w, romRaw, decodeUserDefinedCodes)
      lastPaletteWindow = win
      return win
    end,
    chr = function(w)
      if romTileViewMode and w.isRomWindow == nil then
        w.isRomWindow = true
      end
      return GameArtWindowFactoryController.createChrBankWindow(w)
    end,
    static_art = function(w)
      return GameArtWindowFactoryController.createStaticArtWindow(w, tilesPool, ensureTiles)
    end,
    ppu_frame = function(w)
      return GameArtWindowFactoryController.createPPUFrameWindow(w, tilesPool, ensureTiles, romRaw)
    end,
    animation = function(w)
      return GameArtWindowFactoryController.createAnimationWindow(w, tilesPool, ensureTiles)
    end,
    oam_animation = function(w)
      return GameArtWindowFactoryController.createOamAnimationWindow(w, tilesPool, ensureTiles)
    end,
  }

  local windowsById = {}

  for _, w in ipairs(layout.windows or {}) do
    local kind = w.kind or "normal"
    local builder = builders[kind]
    local buildStartedAt = nowSeconds()
    local win = builder and builder(w) or nil
    local buildElapsed = nowSeconds() - buildStartedAt

    local finalizeStartedAt = nowSeconds()
    GameArtWindowFactoryController.finalizeWindow(win, w, windowsById, wm, romRaw, tilesPool)
    local finalizeElapsed = nowSeconds() - finalizeStartedAt

    DebugController.log(
      "info",
      "LOAD_PERF",
      "window_builder window %s create=%.3fs finalize=%.3fs",
      describeWindowSpec(w),
      buildElapsed,
      finalizeElapsed
    )
  end

  local paletteSyncStartedAt = nowSeconds()
  local activePaletteFound = false
  local allWindows = wm:getWindows()
  for _, win in ipairs(allWindows) do
    if win.isPalette then
      if activePaletteFound and win.activePalette then
        win.activePalette = false
      elseif win.activePalette then
        activePaletteFound = true
        if win.syncToGlobalPalette then
          win:syncToGlobalPalette()
        end
      end
    end
  end

  if not activePaletteFound and lastPaletteWindow then
    lastPaletteWindow.activePalette = true
    if lastPaletteWindow.syncToGlobalPalette then
      lastPaletteWindow:syncToGlobalPalette()
    end
  end
  DebugController.log("info", "LOAD_PERF", "window_builder palette_activation duration=%.3fs", nowSeconds() - paletteSyncStartedAt)

  local bankWin = windowsById["bank"]
  if WindowCaps.isChrLike(bankWin) then
    layout.currentBank = bankWin.currentBank or layout.currentBank or 1
  end

  local focusRestoreStartedAt = nowSeconds()
  local focusWin = nil
  if layout.focusedWindowId and wm then
    focusWin = windowsById[layout.focusedWindowId]
    if focusWin and not focusWin._closed then
      wm:setFocus(focusWin)
    end
  end
  DebugController.log("info", "LOAD_PERF", "window_builder restore_focus duration=%.3fs focused=%s", nowSeconds() - focusRestoreStartedAt, tostring(layout.focusedWindowId))

  return {
    windowsById = windowsById,
    bankWindow = bankWin,
    currentBank = layout.currentBank or 1,
    focusedWindow = focusWin,
  }
end

return M
