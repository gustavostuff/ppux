local Shared = require("controllers.app.core_controller_shared")
local TableUtils = require("utils.table_utils")
local BankViewController = require("controllers.chr.bank_view_controller")
local images = require("images")
local katsudo = require("lib.katsudo")
local UiScale = require("user_interface.ui_scale")
local WindowCaps = require("controllers.window.window_capabilities")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local AppSettingsController = require("controllers.app.settings_controller")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")

--- When false, the CRT layer visualizer window is not created, toggled, or restored from settings.
local CRT_LAYER_VIZ_WINDOW_ENABLED = false

return function(AppCoreController)

local function clampCrtVizActiveLayerIndex(crtWin)
  if not crtWin then
    return
  end
  local n = #(crtWin.crtRefLayers or {})
  if n == 0 then
    crtWin.activeLayer = 1
    return
  end
  local cur = crtWin.activeLayer or 1
  crtWin.activeLayer = math.max(1, math.min(math.floor(cur), n))
end

function AppCoreController:hideAppContextMenus()
  if self.windowHeaderContextMenu then
    self.windowHeaderContextMenu:hide()
  end
  if self.emptySpaceContextMenu then
    self.emptySpaceContextMenu:hide()
  end
  if self.ppuTileContextMenu then
    self.ppuTileContextMenu:hide()
  end
  if self.paletteLinkContextMenu then
    self.paletteLinkContextMenu:hide()
  end
end

function AppCoreController:_hideAllContextMenus()
  self:hideAppContextMenus()
  if self.taskbar and self.taskbar.menuController then
    self.taskbar.menuController:hide()
  end
end

local _newWindowOptionIcons = {}
local NEW_WINDOW_ICON_SHEETS_BY_KEY = {
  static_tile = "icon_static_tile_window",
  static_sprite = "icon_static_sprite_window",
  animated_tile = "icon_animated_tile_window",
  animated_sprite = "icon_animated_sprite_window",
  oam_animated = "icon_oam_animated_window",
  ppu_frame = "icon_ppu_frame_window",
  pattern_table = "icon_pattern_table_window",
  palette = "icon_palette_window",
  rom_palette = "icon_rom_palette_window",
  generic = "icon_generic_window",
}

local function getNewWindowOptionIcon(iconKey)
  local key = tostring(iconKey or "generic")
  if _newWindowOptionIcons[key] ~= nil then
    return _newWindowOptionIcons[key]
  end

  local windowIcons = images.windows_icons or images.animated_icons or {}
  local sheet = windowIcons[NEW_WINDOW_ICON_SHEETS_BY_KEY[key] or NEW_WINDOW_ICON_SHEETS_BY_KEY.generic]
  local fallback = images.icons and images.icons.chrome.icon_circle or nil
  local icon = fallback

  if sheet and katsudo and type(katsudo.new) == "function"
    and type(sheet.getWidth) == "function"
    and type(sheet.getHeight) == "function"
  then
    local frameSize = UiScale.normalButtonSize()
    local iw = sheet:getWidth()
    local ih = sheet:getHeight()
    if ih == frameSize and iw >= frameSize and (iw % frameSize == 0) then
      local frames = math.max(1, math.floor(iw / frameSize))
      icon = katsudo.new(sheet, frameSize, frameSize, frames, 0.1) or icon
    end
  end

  _newWindowOptionIcons[key] = icon
  return icon
end

function AppCoreController:_buildNewWindowOptions()
  return {
    {
      text = "Static Art window (tiles)",
      icon = getNewWindowOptionIcon("static_tile"),
      buttonText = "Static Tiles window",
      callback = function(cols, rows, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createTileWindow({
          animated = false,
          title    = windowTitle or "Static Art (tiles)",
          cols     = cols,
          rows     = rows,
        })
        Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
      end
    },
    {
      text = "Static Art window (sprites)",
      icon = getNewWindowOptionIcon("static_sprite"),
      buttonText = "Static Sprites window",
      requiresSpriteMode = true,
      callback = function(cols, rows, spriteMode, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createSpriteWindow({
          animated = false,
          title = windowTitle or "Static Art (sprites)",
          spriteMode = spriteMode,
          cols = cols,
          rows = rows,
        })
        Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
      end
    },
    {
      text = "Animation window  (tiles)",
      icon = getNewWindowOptionIcon("animated_tile"),
      buttonText = "Animation Tiles window",
      callback = function(cols, rows, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createTileWindow({
          animated = true,
          title = windowTitle or "Animation (tiles)",
          numFrames = 3,
          cols = cols,
          rows = rows,
        })
        Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
      end
    },
    {
      text = "Animation window  (sprites)",
      icon = getNewWindowOptionIcon("animated_sprite"),
      buttonText = "Animation Sprites window",
      requiresSpriteMode = true,
      callback = function(cols, rows, spriteMode, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createSpriteWindow({
          animated = true,
          title = windowTitle or "Animation (sprites)",
          numFrames = 3,
          spriteMode = spriteMode,
          cols = cols,
          rows = rows,
        })
        Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
      end
    },
    {
      text = "Palette window",
      icon = getNewWindowOptionIcon("palette"),
      buttonText = "Palette window",
      skipSettingsModal = true,
      callback = function(_, _, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createPaletteWindow({
          title = windowTitle or "Palette",
        })
        Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
      end
    },
    {
      text = "ROM Palette window",
      icon = getNewWindowOptionIcon("rom_palette"),
      buttonText = "ROM Palette window",
      skipSettingsModal = true,
      callback = function(_, _, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createRomPaletteWindow({
          title = windowTitle or "ROM Palette",
        })
        Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
      end
    },
    {
      text = "PPU Frame window",
      icon = getNewWindowOptionIcon("ppu_frame"),
      buttonText = "PPU Frame window",
      skipSettingsModal = true,
      callback = function(_, _, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local currentBank = self.appEditState and self.appEditState.currentBank or 1
        local win = self.wm:createPPUFrameWindow({
          title = windowTitle or "PPU Frame",
          romRaw = self.appEditState and self.appEditState.romRaw or nil,
          bankIndex = currentBank,
          pageIndex = 1,
          codec = "konami",
        })
        Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
      end
    },
    {
      text = "Pattern table window",
      icon = getNewWindowOptionIcon("pattern_table"),
      buttonText = "Pattern table",
      fixedGrid = true,
      fixedCols = 16,
      fixedRows = 16,
      fixedSpriteMode = "8x8",
      suggestedWindowName = "Pattern table",
      callback = function(cols, rows, _, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createPatternTableWindow({
          title = windowTitle or "Pattern table",
          cols = cols or 16,
          rows = rows or 16,
        })
        Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
      end
    },
    {
      text = "OAM animation",
      icon = getNewWindowOptionIcon("oam_animated"),
      buttonText = "OAM animation",
      requiresSpriteMode = true,
      callback = function(cols, rows, spriteMode, windowTitle)
        local prevFocusedWin = self.wm and self.wm.getFocus and self.wm:getFocus() or nil
        local win = self.wm:createSpriteWindow({
          animated = true,
          oamBacked = true,
          numFrames = 1,
          title = windowTitle or "OAM Animation",
          spriteMode = spriteMode,
          cols = cols,
          rows = rows,
        })
        Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
      end
    },
  }
end

function AppCoreController:showNewWindowModal()
  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before creating windows.")
    return false
  end

  local options = self:_buildNewWindowOptions()
  local configTitle = "Window Settings"
  self.newWindowTypeModal:show("New Window", (function()
    local mapped = {}
    for _, option in ipairs(options) do
      mapped[#mapped + 1] = {
        text = option.text,
        buttonText = option.buttonText,
        icon = option.icon,
        callback = function()
          if option.skipSettingsModal == true then
            option.callback(nil, nil, nil, nil)
            return
          end

          self.newWindowModal:show({
            title = configTitle,
            option = option,
            initialName = option.suggestedWindowName or "New Window",
            onConfirm = function(cols, rows, spriteMode, windowName, selectedOption)
              local targetOption = selectedOption or option
              if not (targetOption and targetOption.callback) then
                return false
              end
              targetOption.callback(cols, rows, spriteMode, windowName)
              return true
            end,
          })
        end,
      }
    end
    return mapped
  end)())
  return true
end

function AppCoreController:resizeFocusedWindowGrid(opts)
  opts = opts or {}
  local WindowGridResizeController = require("controllers.window.window_grid_resize_controller")
  local GridLayoutUndo = require("controllers.input_support.grid_layout_undo")
  local wm = self.wm
  local win = wm and wm.getFocus and wm:getFocus() or nil
  local snapBefore = nil
  if win and not win._closed and not win._minimized and WindowGridResizeController.isGridResizeWindow(win) then
    snapBefore = GridLayoutUndo.snapshot(win)
  end

  local ok, err = WindowGridResizeController.applyFocusedResize(self, opts)
  if ok then
    if snapBefore and self.undoRedo and self.undoRedo.addGridLayoutEvent then
      local snapAfter = GridLayoutUndo.snapshot(win)
      self.undoRedo:addGridLayoutEvent({
        type = "grid_layout",
        win = win,
        beforeState = snapBefore,
        afterState = snapAfter,
      })
    end
  else
    self:setStatus(err or "Could not resize grid.")
    if self.showToast then
      self:showToast("warning", self.statusText or err or "")
    end
  end
  return ok
end

function AppCoreController:cloneFocusedWindow()
  if not self:hasLoadedROM() then
    self:setStatus("Open a ROM before cloning a window.")
    if self.showToast then
      self:showToast("warning", self.statusText or "Open a ROM first.")
    end
    return false
  end
  local wm = self.wm
  if not wm then
    return false
  end
  local src = wm:getFocus()
  if not src or src._closed == true then
    self:setStatus("No window focused to clone.")
    if self.showToast then
      self:showToast("warning", self.statusText or "Focus a window first.")
    end
    return false
  end
  if src._runtimeOnly == true then
    self:setStatus("This window cannot be cloned.")
    return false
  end

  local GameArtController = require("controllers.game_art.game_art_controller")
  local ToolbarController = require("controllers.window.toolbar_controller")
  local ChrBackingController = require("controllers.rom.chr_backing_controller")

  local state = self.appEditState
  local layout = GameArtController.snapshotLayout(
    wm,
    self.winBank,
    state and state.currentBank or 1,
    self,
    { onlyWindow = src }
  )
  if not layout or type(layout.windows) ~= "table" or #layout.windows ~= 1 then
    self:setStatus("Could not clone this window.")
    return false
  end

  local entry = TableUtils.deepcopy(layout.windows[1])
  local entryKind = entry.kind or src.kind or "window"
  entry.id = Shared.allocateCloneWindowId(wm, entryKind)
  entry.title = Shared.deriveCloneWindowTitle(entry.title or src.title)
  entry.x = (tonumber(entry.x) or 0) + 12
  entry.y = (tonumber(entry.y) or 0) + 12

  local partial = {
    currentBank = layout.currentBank or (state and state.currentBank) or 1,
    windows = { entry },
  }

  local prevFocus = src
  local built, why = GameArtController.buildWindowsFromLayout(partial, {
    wm = wm,
    tilesPool = state and state.tilesPool or {},
    ensureTiles = function(bankIdx)
      BankViewController.ensureBankTiles(state, bankIdx)
    end,
    romRaw = state and state.romRaw or "",
    appEditState = state,
    chrBackingMode = ChrBackingController.getMode(state),
  })

  if not built then
    self:setStatus("Clone failed: " .. tostring(why or "unknown"))
    return false
  end

  local newWin = built.windowsById[entry.id]
  if not newWin then
    self:setStatus("Clone failed: window was not registered.")
    return false
  end

  local ctx = rawget(_G, "ctx")
  ToolbarController.createToolbarsForWindow(newWin, ctx, wm)
  wm:setFocus(newWin)
  Shared.recordWindowCreateUndo(self, newWin, prevFocus)
  if self.showToast then
    self:showToast("info", string.format("Cloned window: %s", tostring(newWin.title or newWin._id)))
  end
  return true
end

function AppCoreController:_collapseAllWindowsFromMenu()
  local wm = self.wm
  local canvas = self.canvas
  if not (wm and wm.collapseAll and canvas) then
    return false
  end

  local taskbarTopY = (self.taskbar and self.taskbar.getTopY and self.taskbar:getTopY())
    or (self.taskbar and self.taskbar.y)
    or canvas:getHeight()

  wm:collapseAll({
    areaX = 30,
    areaY = 30,
    areaH = math.max(1, taskbarTopY - 38),
    gapX = 8,
    gapY = 2,
  })
  return true
end

function AppCoreController:_mosaicAllWindowsFromMenu()
  local wm = self.wm
  local canvas = self.canvas
  if not (wm and wm.mosaicAll and canvas) then
    return false
  end

  local taskbarTopY = (self.taskbar and self.taskbar.getTopY and self.taskbar:getTopY())
    or (self.taskbar and self.taskbar.y)
    or canvas:getHeight()

  local areaX = 30
  local topPad = AppTopToolbarController.getContentOffsetY(self)
  local areaY = math.max(30, topPad + 8)
  local areaH = math.max(1, taskbarTopY - areaY - 8)
  local areaW = math.max(1, canvas:getWidth() - areaX - 8)

  wm:mosaicAll({
    areaX = areaX,
    areaY = areaY,
    areaW = areaW,
    areaH = areaH,
    gapX = 4,
    gapY = 4,
    batchDispX = 20,
    batchDispY = 20,
  })
  return true
end

function AppCoreController:showWindowHeaderContextMenu(win, x, y, opts)
  if not (self.windowHeaderContextMenu and win and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.windowHeaderContextMenu:showAt(cx, cy, self:_buildWindowHeaderContextMenuItems(win, opts))
  return self.windowHeaderContextMenu:isVisible()
end

function AppCoreController:showEmptySpaceContextMenu(x, y)
  if not (self.emptySpaceContextMenu and type(x) == "number" and type(y) == "number") then
    return false
  end
  if not self:hasLoadedROM() then
    if self.emptySpaceContextMenu and self.emptySpaceContextMenu.hide then
      self.emptySpaceContextMenu:hide()
    end
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.emptySpaceContextMenu:showAt(cx, cy, self:_buildEmptySpaceContextMenuItems())
  return self.emptySpaceContextMenu:isVisible()
end

--- Mouse and window geometry use full canvas coordinates (including the top toolbar strip).
function AppCoreController:contentYToCanvasY(y)
  return y
end

function AppCoreController:contentPointToCanvasPoint(x, y)
  return x, y
end


function AppCoreController:showPaletteLinkSourceContextMenu(win, x, y)
  if not (self.paletteLinkContextMenu and win and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.paletteLinkContextMenu:showAt(cx, cy, self:_buildPaletteLinkSourceContextMenuItems(win))
  return self.paletteLinkContextMenu:isVisible()
end

function AppCoreController:showPaletteLinkDestinationContextMenu(win, x, y)
  if not (self.paletteLinkContextMenu and win and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.paletteLinkContextMenu:showAt(cx, cy, self:_buildPaletteLinkDestinationContextMenuItems(win))
  return self.paletteLinkContextMenu:isVisible()
end


function AppCoreController:_afterPatternTableLinkChange(contentWin, layerIndex)
  local layer = contentWin.layers and contentWin.layers[layerIndex]
  if not layer then
    return
  end
  local isPpuNametableTileLayer = WindowCaps.isPpuFrame(contentWin)
    and layer.kind == "tile"
    and layer._runtimePatternTableRefLayer ~= true

  -- Linking swaps `layer.patternTable` to the PT window snapshot, but nametable visuals are
  -- tile refs accumulated in layer.items via the *previous* mapping. Re-sync from nametableBytes.
  if isPpuNametableTileLayer then
    if contentWin.refreshNametableVisuals and self.appEditState then
      if type(layer.patternTable) == "table" and type(layer.patternTable.ranges) == "table" then
        local ensured = {}
        for _, r in ipairs(layer.patternTable.ranges) do
          PpuRange.foreachBankInPatternRange(r, function(bankIdx)
            local b = math.floor(tonumber(bankIdx) or -1)
            if b >= 1 and ensured[b] == nil and self.appEditState.chrBanksBytes[b] then
              ensured[b] = true
              BankViewController.ensureBankTiles(self.appEditState, b)
            end
          end)
        end
      end
      contentWin:refreshNametableVisuals(self.appEditState.tilesPool, layerIndex)
    end
  end

  if WindowCaps.isPpuFrame(contentWin)
    and layer.kind == "tile"
    and layer._runtimePatternTableRefLayer ~= true
    and self._ensurePpuPatternTableReferenceLayer
    and contentWin.patternLayerSoloMode == true
  then
    self:_ensurePpuPatternTableReferenceLayer({
      win = contentWin,
      layer = layer,
      layerIndex = layerIndex,
    }, { keepActiveLayer = true, allowReferenceLayer = true })
  elseif WindowCaps.isPpuFrame(contentWin) and contentWin.removePatternReferenceLayers then
    contentWin:removePatternReferenceLayers(layerIndex)
  end
  PatternTableDisplayController.invalidateConsumersUsingPatternTable(self, layer.patternTable)

  if layer.kind == "sprite" and self.appEditState then
    local SpriteController = require("controllers.sprite.sprite_controller")
    SpriteController.hydrateSpriteLayer(layer, {
      romRaw = self.appEditState.romRaw or "",
      tilesPool = self.appEditState.tilesPool,
      appEditState = self.appEditState,
    })
  end

  if contentWin.specializedToolbar and contentWin.specializedToolbar.updateIcons then
    contentWin.specializedToolbar:updateIcons()
  end
  if self.wm and self.wm.getWindows then
    for _, w in ipairs(self.wm:getWindows()) do
      if WindowCaps.isPatternTable(w) and w.specializedToolbar and w.specializedToolbar.updateIcons then
        w.specializedToolbar:updateIcons()
      end
    end
  end
end


function AppCoreController:showPatternTableLinkSourceContextMenu(win, x, y)
  if not (self.paletteLinkContextMenu and win and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.paletteLinkContextMenu:showAt(cx, cy, self:_buildPatternTableLinkSourceContextMenuItems(win))
  return self.paletteLinkContextMenu:isVisible()
end

function AppCoreController:_getCrtLensWindow()
  local wm = self.wm
  if not wm or not wm.getWindows then
    return nil
  end
  for _, w in ipairs(wm:getWindows()) do
    if w and w.kind == "crt_lens" then
      return w
    end
  end
  return nil
end

--- Snapshot CRT layer visualizer state for settings (single runtime window).
function AppCoreController:_serializeCrtLayerVizState(win)
  if not win or win.kind ~= "crt_lens" then
    return nil
  end
  local refs = {}
  for _, r in ipairs(win.crtRefLayers or {}) do
    refs[#refs + 1] = {
      windowId = r.windowId,
      layerIndex = r.layerIndex,
      panX = tonumber(r.panX) or 0,
      panY = tonumber(r.panY) or 0,
      opacity = tonumber(r.opacity) or 1,
    }
  end
  return {
    visible = win._crtLensVisible == true,
    distortion = tonumber(win.crtVizDistortion),
    activeLayer = win.getActiveLayerIndex and win:getActiveLayerIndex() or 1,
    refs = refs,
  }
end

function AppCoreController:_persistCrtLayerViz()
  local win = self:_getCrtLensWindow()
  if not win then
    return
  end
  local state = self:_serializeCrtLayerVizState(win)
  if state then
    AppSettingsController.save({ crtLayerViz = state })
  end
end

--- Restore CRT layer visualizer from normalized settings (refs skipped if target window/layer missing).
function AppCoreController:_applyCrtLayerVizFromSettings(settings)
  if not CRT_LAYER_VIZ_WINDOW_ENABLED then
    return
  end
  local win = self:_getCrtLensWindow()
  if not win or win.kind ~= "crt_lens" then
    return
  end
  local viz = settings and settings.crtLayerViz
  if type(viz) ~= "table" then
    return
  end
  win._crtLensVisible = (viz.visible == true)
  local dist = tonumber(viz.distortion)
  if dist then
    win.crtVizDistortion = dist
  else
    win.crtVizDistortion = nil
  end

  local wm = self.wm
  win.crtRefLayers = {}
  for _, r in ipairs(viz.refs or {}) do
    if type(r) == "table" and r.windowId ~= nil then
      local wid = r.windowId
      local li = math.max(1, math.floor(tonumber(r.layerIndex) or 1))
      local tw = wm and wm.findWindowById and wm:findWindowById(wid)
      if tw and tw.layers and tw.layers[li] then
        win.crtRefLayers[#win.crtRefLayers + 1] = {
          windowId = wid,
          layerIndex = li,
          panX = tonumber(r.panX) or 0,
          panY = tonumber(r.panY) or 0,
          opacity = math.max(0, math.min(1, tonumber(r.opacity) or 1)),
        }
      end
    end
  end
  clampCrtVizActiveLayerIndex(win)
  local n = #(win.crtRefLayers or {})
  if n > 0 then
    local want = math.max(1, math.floor(tonumber(viz.activeLayer) or 1))
    win.activeLayer = math.min(want, n)
  else
    win.activeLayer = 1
  end
end

function AppCoreController:ensureCrtLensWindow()
  if not CRT_LAYER_VIZ_WINDOW_ENABLED then
    return nil
  end
  local existing = self:_getCrtLensWindow()
  if existing then
    if not existing.specializedToolbar then
      local ToolbarController = require("controllers.window.toolbar_controller")
      ToolbarController.createToolbarsForWindow(existing, _G.ctx, self.wm)
    end
    return existing
  end
  if not (self.wm and self.wm.createCrtLensWindow) then
    return nil
  end
  return self.wm:createCrtLensWindow({})
end

function AppCoreController:toggleCrtLensWindow()
  if not CRT_LAYER_VIZ_WINDOW_ENABLED then
    return
  end
  local win = self:ensureCrtLensWindow()
  if not win then
    return
  end
  win._crtLensVisible = not win._crtLensVisible
  if win._crtLensVisible then
    if self.wm and self.wm.setFocus then
      self.wm:setFocus(win)
    end
    self:setStatus("CRT layer visualizer shown")
  else
    self:setStatus("CRT layer visualizer hidden")
  end
  self:_persistCrtLayerViz()
end

function AppCoreController:crtVizAddReference(crtWin, windowId, layerIndex)
  if not (crtWin and crtWin.kind == "crt_lens" and self.wm) then
    return
  end
  local targetWin = self.wm:findWindowById(windowId)
  if not targetWin then
    return
  end
  local li = tonumber(layerIndex)
  if not li or li < 1 or not (targetWin.layers and targetWin.layers[li]) then
    return
  end
  crtWin.crtRefLayers = crtWin.crtRefLayers or {}
  table.insert(crtWin.crtRefLayers, {
    windowId = windowId,
    layerIndex = li,
    panX = 0,
    panY = 0,
    opacity = 1.0,
  })
  if crtWin.setActiveLayerIndex then
    crtWin:setActiveLayerIndex(#crtWin.crtRefLayers)
  else
    crtWin.activeLayer = #crtWin.crtRefLayers
    clampCrtVizActiveLayerIndex(crtWin)
  end
  local L = targetWin.layers[li]
  self:setStatus(string.format(
    "CRT viz + %s  |  %s",
    targetWin.title or "(window)",
    (L and L.name) or ("layer " .. li)
  ))
  self:_persistCrtLayerViz()
end

function AppCoreController:crtVizRemoveReferenceAt(crtWin, refIndex)
  if not (crtWin and crtWin.crtRefLayers) then
    return
  end
  local i = tonumber(refIndex)
  if not i or i < 1 or i > #crtWin.crtRefLayers then
    return
  end
  local n = #crtWin.crtRefLayers
  table.remove(crtWin.crtRefLayers, i)
  local newN = #crtWin.crtRefLayers
  local nextIdx = 1
  if newN > 0 then
    -- Prefer the ref that was "below" the removed slot (next index); if we removed the last entry, take the one above.
    if i < n then
      nextIdx = i
    else
      nextIdx = i - 1
    end
  end
  if crtWin.setActiveLayerIndex then
    crtWin:setActiveLayerIndex(nextIdx)
  else
    crtWin.activeLayer = nextIdx
    clampCrtVizActiveLayerIndex(crtWin)
  end
  self:setStatus("CRT viz: removed reference")
  self:_persistCrtLayerViz()
end

function AppCoreController:showCrtLayerVizContextMenu(crtWin, x, y)
  if not (self.ppuTileContextMenu and crtWin and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.ppuTileContextMenu:showAt(cx, cy, self:_buildCrtLayerVizContextMenuItems(crtWin))
  return self.ppuTileContextMenu:isVisible()
end


end
