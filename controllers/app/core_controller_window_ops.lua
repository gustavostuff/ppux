local Shared = require("controllers.app.core_controller_shared")
local TableUtils = require("utils.table_utils")
local BankViewController = require("controllers.chr.bank_view_controller")
local images = require("images")
local katsudo = require("lib.katsudo")
local UiScale = require("user_interface.ui_scale")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")

return function(AppCoreController)

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
  local fallback = images.icons and images.icons.icon_circle or nil
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
        self:setStatus(string.format("Created %s", win.title))
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
        self:setStatus(string.format("Created %s", win.title))
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
        self:setStatus(string.format("Created %s", win.title))
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
        self:setStatus(string.format("Created %s", win.title))
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
        self:setStatus(string.format("Created %s", win.title))
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
        self:setStatus(string.format("Created %s", win.title))
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
        self:setStatus(string.format("Created %s", win.title))
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
        self:setStatus(string.format("Created %s", win.title))
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
            initialName = "New Window",
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
    local msg = "Grid updated."
    if opts.addColumn then
      msg = "Added column."
    elseif opts.addRow then
      msg = "Added row."
    elseif opts.removeColumn then
      msg = "Removed last column."
    elseif opts.removeRow then
      msg = "Removed last row."
    end
    self:setStatus(msg)
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
  self:setStatus(string.format("Cloned window: %s", tostring(newWin.title or newWin._id)))
  if self.showToast then
    self:showToast("info", self.statusText)
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
  self:setStatus("Windows collapsed and stacked")
  return true
end

function AppCoreController:_buildWindowHeaderContextMenuItems(win)
  local collapseLabel = (win and win._collapsed == true) and "Expand" or "Collapse"
  return {
    {
      text = "Rename",
      enabled = win ~= nil and win._closed ~= true,
      callback = function()
        self:hideAppContextMenus()
        self:showRenameWindowModal(win)
      end,
    },
    {
      text = "Close",
      enabled = win ~= nil and win._closed ~= true,
      callback = function()
        self:hideAppContextMenus()
        local toolbar = win and win.headerToolbar or nil
        if toolbar and toolbar._onClose then
          toolbar:_onClose()
          return
        end
        if self.wm and self.wm.closeWindow and self.wm:closeWindow(win) then
          self:setStatus("Window closed")
        end
      end,
    },
    {
      text = collapseLabel,
      enabled = win ~= nil and win._closed ~= true and win._minimized ~= true,
      callback = function()
        self:hideAppContextMenus()
        local toolbar = win and win.headerToolbar or nil
        if toolbar and toolbar._onCollapse then
          toolbar:_onCollapse()
          return
        end
        if win then
          win._collapsed = not (win._collapsed == true)
          self:setStatus(win._collapsed and "Window collapsed" or "Window expanded")
        end
      end,
    },
    {
      text = "Minimize",
      enabled = win ~= nil and win._closed ~= true and win._minimized ~= true,
      callback = function()
        self:hideAppContextMenus()
        local toolbar = win and win.headerToolbar or nil
        if toolbar and toolbar._onMinimize then
          toolbar:_onMinimize()
          return
        end
        if self.wm and self.wm.minimizeWindow and self.wm:minimizeWindow(win) then
          self:setStatus("Window minimized")
        end
      end,
    },
  }
end

function AppCoreController:_buildEmptySpaceContextMenuItems()
  local hasRom = self:hasLoadedROM()
  local hasWindows = self.wm and self.wm.getWindows and #(self.wm:getWindows() or {}) > 0

  return {
    {
      text = "New Window",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        self:showNewWindowModal()
      end,
    },
    {
      text = "Minimize all",
      enabled = hasWindows,
      callback = function()
        self:hideAppContextMenus()
        if self.wm and self.wm.minimizeAll and self.wm:minimizeAll() then
          self:setStatus("Windows minimized")
        end
      end,
    },
    {
      text = "Collapse all",
      enabled = hasWindows,
      callback = function()
        self:hideAppContextMenus()
        self:_collapseAllWindowsFromMenu()
      end,
    },
  }
end

function AppCoreController:showWindowHeaderContextMenu(win, x, y)
  if not (self.windowHeaderContextMenu and win and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.windowHeaderContextMenu:showAt(cx, cy, self:_buildWindowHeaderContextMenuItems(win))
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

local function setWindowActiveLayer(win, layerIndex)
  if not (win and type(layerIndex) == "number") then
    return
  end
  if win.setActiveLayerIndex then
    win:setActiveLayerIndex(layerIndex)
  else
    win.activeLayer = layerIndex
  end
end

function AppCoreController:_focusLinkedLayerTarget(win, layerIndex)
  if not win then
    return false
  end
  setWindowActiveLayer(win, layerIndex)
  if self.wm and self.wm.setFocus then
    self.wm:setFocus(win)
  end
  self:setStatus(string.format(
    "Focused %s layer %d",
    tostring(win.title or "window"),
    tonumber(layerIndex) or 1
  ))
  return true
end

function AppCoreController:_buildPaletteLinkSourceContextMenuItems(paletteWin)
  local targets = PaletteLinkController.getLinkedTargetsForPalette(self.wm, paletteWin)
  local items = {}

  items[#items + 1] = {
    text = "Jump to linked layer",
    children = function()
      if #targets == 0 then
        return {
          {
            text = "No linked layers",
            callback = function() end,
          },
        }
      end
      local childItems = {}
      for _, target in ipairs(targets) do
        childItems[#childItems + 1] = {
          text = string.format("%s / layer %d", tostring(target.win.title or "window"), target.layerIndex),
          callback = function()
            self:_focusLinkedLayerTarget(target.win, target.layerIndex)
          end,
        }
      end
      return childItems
    end,
  }

  items[#items + 1] = {
    text = "Remove all links",
    callback = function()
      PaletteLinkController.removeAllLinksForPalette(self.wm, paletteWin)
    end,
  }

  return items
end

function AppCoreController:_buildPaletteLinkDestinationContextMenuItems(contentWin)
  local layerIndex = (contentWin and contentWin.getActiveLayerIndex and contentWin:getActiveLayerIndex())
    or (contentWin and contentWin.activeLayer)
    or 1
  local linkedPalette = PaletteLinkController.getActiveLayerLinkedPaletteWindow(contentWin, self.wm)
  local paletteWindows = PaletteLinkController.getRomPaletteWindows(self.wm)
  local items = {}

  items[#items + 1] = {
      text = "Link To Palette",
      children = function()
        local childItems = {}
        for _, paletteWin in ipairs(paletteWindows) do
          childItems[#childItems + 1] = {
            text = tostring(paletteWin.title or "Palette"),
            callback = function()
              PaletteLinkController.linkLayerToPalette(contentWin, layerIndex, paletteWin)
            end,
          }
        end
        if #childItems == 0 then
          childItems[1] = {
            text = "No ROM palettes available",
            callback = function() end,
          }
        end
        return childItems
      end,
    }

  if linkedPalette then
    items[#items + 1] = {
      text = "Jump to linked palette",
      callback = function()
        if self.focusPaletteWindowWithGrouping then
          self:focusPaletteWindowWithGrouping(linkedPalette)
        elseif self.wm and self.wm.setFocus then
          self.wm:setFocus(linkedPalette)
        end
        self:setStatus(string.format("Focused %s", tostring(linkedPalette.title or "palette")))
      end,
    }
    items[#items + 1] = {
      text = "Remove ROM palette link",
      callback = function()
        self:hideAppContextMenus()
        PaletteLinkController.removeLinkForLayer(contentWin, layerIndex)
      end,
    }
  end

  return items
end

function AppCoreController:_resolveLinkedPaletteForLayer(win, layerIndex)
  if not (win and layerIndex and self.wm and self.wm.findWindowById) then
    return nil
  end
  local layer = (win.getLayer and win:getLayer(layerIndex)) or (win.layers and win.layers[layerIndex]) or nil
  local pd = layer and layer.paletteData or nil
  local winId = pd and pd.winId or nil
  if not winId then
    return nil
  end
  local paletteWin = self.wm:findWindowById(winId)
  if paletteWin and paletteWin._closed ~= true and paletteWin._minimized ~= true and paletteWin.kind == "rom_palette" then
    return paletteWin
  end
  return nil
end

function AppCoreController:_appendJumpToLinkedPaletteMenuItem(items, win, layerIndex)
  if type(items) ~= "table" then
    return items
  end
  local paletteWin = self:_resolveLinkedPaletteForLayer(win, layerIndex)
  if not paletteWin then
    return items
  end
  items[#items + 1] = {
    text = "Jump to linked palette",
    callback = function()
      if self.focusPaletteWindowWithGrouping then
        self:focusPaletteWindowWithGrouping(paletteWin)
      elseif self.wm and self.wm.setFocus then
        self.wm:setFocus(paletteWin)
      end
      self:setStatus(string.format("Focused %s", tostring(paletteWin.title or "ROM Palette")))
    end,
  }
  return items
end

function AppCoreController:_appendRemoveRomPaletteLinkMenuItem(items, win, layerIndex)
  if type(items) ~= "table" then
    return items
  end
  if not (win and type(layerIndex) == "number") then
    return items
  end
  if not self:_resolveLinkedPaletteForLayer(win, layerIndex) then
    return items
  end
  local selfRef = self
  items[#items + 1] = {
    text = "Remove ROM palette link",
    callback = function()
      selfRef:hideAppContextMenus()
      PaletteLinkController.removeLinkForLayer(win, layerIndex)
    end,
  }
  return items
end

function AppCoreController:_appendPasteContextMenuItem(items, context)
  -- Paste is intentionally scoped to art/tile context menus (PPU/select-in-CHR/CHR bank).
  -- Palette-link and OAM-empty-space menus keep their existing specialized options only.
  if type(items) ~= "table" then
    return items
  end
  if not (context and context.win and type(context.layerIndex) == "number") then
    return items
  end

  local layer = context.layer
    or (context.win.getLayer and context.win:getLayer(context.layerIndex))
    or (context.win.layers and context.win.layers[context.layerIndex])
  if not layer then
    return items
  end

  local fakeCtx = {
    app = self,
  }
  local availability = KeyboardClipboardController.getActionAvailability(
    fakeCtx,
    context.win,
    "paste",
    { layerIndex = context.layerIndex }
  )
  if not (availability and availability.allowed and KeyboardClipboardController.hasClipboardData()) then
    return items
  end

  local pasteOpts = {}
  if layer.kind == "tile" then
    if type(context.col) == "number" and type(context.row) == "number" then
      pasteOpts.anchorCol = context.col
      pasteOpts.anchorRow = context.row
    end
  elseif layer.kind == "sprite" then
    local item = context.item
    if item then
      local sx = item.worldX or item.baseX or item.x
      local sy = item.worldY or item.baseY or item.y
      if type(sx) == "number" and type(sy) == "number" then
        pasteOpts.anchorX = sx
        pasteOpts.anchorY = sy
      end
    end
  end

  items[#items + 1] = {
    text = "Paste",
    callback = function()
      if self.performClipboardToolbarAction then
        self:performClipboardToolbarAction("paste", context.win, context.layerIndex, pasteOpts)
      end
    end,
  }
  return items
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

end
