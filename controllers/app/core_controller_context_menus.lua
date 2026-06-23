local TableUtils = require("utils.table_utils")
local BankViewController = require("controllers.chr.bank_view_controller")
local images = require("images")
local PaletteLinkController = require("controllers.palette.palette_link_controller")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local PatternTableDisplayController = require("controllers.game_art.pattern_table_display_controller")
local PpuRange = require("controllers.app.ppu_frame_range_helpers")

return function(AppCoreController)

function AppCoreController:_buildWindowHeaderContextMenuItems(win, opts)
  opts = opts or {}
  local forMinimizedTaskbar = (opts.forMinimizedTaskbarButton == true)
  local collapseLabel = (win and win._collapsed == true) and "Expand" or "Collapse"

  local wm = self.wm
  local function hasAnotherMinimizableWindow()
    if not (wm and wm.getWindows and win and win._closed ~= true) then
      return false
    end
    for _, w in ipairs(wm:getWindows()) do
      if w ~= win and w and w._closed ~= true and w._minimized ~= true and w._groupHidden ~= true then
        return true
      end
    end
    return false
  end

  local function hasAnotherMinimizableUnlinkedWindow()
    if not (wm and wm.getWindows and win and win._closed ~= true) then
      return false
    end
    local keepSet = (wm.collectLinkedMinimizeKeepSet and wm:collectLinkedMinimizeKeepSet(win)) or { [win] = true }
    for _, w in ipairs(wm:getWindows()) do
      if w and not keepSet[w] and w._closed ~= true and w._minimized ~= true and w._groupHidden ~= true then
        return true
      end
    end
    return false
  end

  local items = {
    {
      text = "Rename",
      menuGroup = "hdr_identity",
      enabled = win ~= nil and win._closed ~= true and win.titleLocked ~= true,
      callback = function()
        self:hideAppContextMenus()
        self:showRenameWindowModal(win)
      end,
    },
    {
      text = "Close",
      menuGroup = "hdr_identity",
      enabled = win ~= nil and win._closed ~= true,
      callback = function()
        self:hideAppContextMenus()
        local toolbar = win and win.headerToolbar or nil
        if toolbar and toolbar._onClose then
          toolbar:_onClose()
          return
        end
        if self.wm and self.wm.closeWindow and self.wm:closeWindow(win) then
        end
      end,
    },
    {
      text = collapseLabel,
      menuGroup = "hdr_window_state",
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
        end
      end,
    },
  }

  if forMinimizedTaskbar and win and win._minimized == true then
    items[#items + 1] = {
      text = "Maximize",
      menuGroup = "hdr_window_state",
      enabled = win._closed ~= true,
      callback = function()
        self:hideAppContextMenus()
        if self.wm and self.wm.restoreMinimizedWindow and self.wm:restoreMinimizedWindow(win) then
        end
      end,
    }
  else
    items[#items + 1] = {
      text = "Minimize",
      menuGroup = "hdr_window_state",
      enabled = win ~= nil and win._closed ~= true and win._minimized ~= true,
      callback = function()
        self:hideAppContextMenus()
        local toolbar = win and win.headerToolbar or nil
        if toolbar and toolbar._onMinimize then
          toolbar:_onMinimize()
          return
        end
        if self.wm and self.wm.minimizeWindow and self.wm:minimizeWindow(win) then
        end
      end,
    }
  end

  items[#items + 1] = {
    text = "Minimize others",
    menuGroup = "hdr_workspace",
    enabled = hasAnotherMinimizableWindow(),
    callback = function()
      self:hideAppContextMenus()
      if wm and wm.minimizeAllExcept then
        wm:minimizeAllExcept(win)
      end
    end,
  }

  items[#items + 1] = {
    text = "Minimize other (not linked)",
    menuGroup = "hdr_workspace",
    enabled = hasAnotherMinimizableUnlinkedWindow(),
    callback = function()
      self:hideAppContextMenus()
      if wm and wm.minimizeAllExceptLinked then
        wm:minimizeAllExceptLinked(win)
      end
    end,
  }

  items[#items + 1] = {
    text = (win and win._alwaysOnTop) and "Don't keep always on top" or "Keep always on top",
    menuGroup = "hdr_always_on_top",
    enabled = win ~= nil and win._closed ~= true,
    callback = function()
      self:hideAppContextMenus()
      if not win then
        return
      end
      win._alwaysOnTop = not (win._alwaysOnTop == true)
      local wm = self.wm
      if wm and wm.bringToFront then
        wm:bringToFront(win)
      end
    end,
  }

  return items
end

function AppCoreController:_buildEmptySpaceContextMenuItems()
  local hasRom = self:hasLoadedROM()
  local tb = self.taskbar
  local sortTitleIcon = (tb and tb.sortAlphaButton and tb.sortAlphaButton.icon) or images.icons.chrome.sort_a_z
  local sortKindIcon = (tb and tb.sortKindButton and tb.sortKindButton.icon) or images.icons.chrome.sort_kind_asc

  -- Same entries and enable rules as taskbar main menu → Windows (see user_interface/taskbar/menu.lua).
  return {
    {
      icon = images.icons.chrome.icon_new_window,
      text = "New Window",
      menuGroup = "empty_wm_new_window",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        self:showNewWindowModal()
      end,
    },
    {
      icon = images.icons.chrome.icon_cascade_all,
      text = "Expand all",
      menuGroup = "empty_wm_expand_all",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        local wm = self.wm
        if wm and wm.expandAll then
          wm:expandAll()
        end
      end,
    },
    {
      icon = images.icons.chrome.icon_collapse_all,
      text = "Collapse all",
      menuGroup = "empty_wm_collapse_all",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        self:_collapseAllWindowsFromMenu()
      end,
    },
    --[[ Mosaic all: deactivated in UI for now (implementation remains in WM:mosaicAll / _mosaicAllWindowsFromMenu).
    {
      icon = images.icons.actions.icon_mosaic,
      text = "Mosaic all",
      menuGroup = "empty_wm_mosaic_all",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        self:_mosaicAllWindowsFromMenu()
      end,
    },
    --]]
    {
      icon = sortTitleIcon,
      text = "Sort by title",
      menuGroup = "empty_wm_sort_by_title",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        if tb and tb.sortAlphaButton and tb.sortAlphaButton.action then
          tb.sortAlphaButton.action()
        end
      end,
    },
    {
      icon = sortKindIcon,
      text = "Sort by kind",
      menuGroup = "empty_wm_sort_by_kind",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        if tb and tb.sortKindButton and tb.sortKindButton.action then
          tb.sortKindButton.action()
        end
      end,
    },
    {
      icon = images.icons.chrome.min_all,
      text = "Minimize all",
      menuGroup = "empty_wm_minimize_all",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        local wm = self.wm
        if wm and wm.minimizeAll and wm:minimizeAll() then
        end
      end,
    },
    {
      icon = images.icons.chrome.max_all,
      text = "Maximize all",
      menuGroup = "empty_wm_maximize_all",
      enabled = hasRom,
      callback = function()
        self:hideAppContextMenus()
        local wm = self.wm
        if wm and wm.maximizeAll and wm:maximizeAll() then
        end
      end,
    },
  }
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
  return true
end

function AppCoreController:_buildPaletteLinkSourceContextMenuItems(paletteWin)
  local targets = PaletteLinkController.getLinkedTargetsForPalette(self.wm, paletteWin)
  local items = {}

  items[#items + 1] = {
    text = "Jump to linked layer",
    menuGroup = "palette_src_navigate",
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
    menuGroup = "palette_src_remove",
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
      menuGroup = "palette_dest_link",
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
      menuGroup = "palette_dest_linked_ops",
      callback = function()
        if self.focusPaletteWindowWithGrouping then
          self:focusPaletteWindowWithGrouping(linkedPalette)
        elseif self.wm and self.wm.setFocus then
          self.wm:setFocus(linkedPalette)
        end
      end,
    }
    items[#items + 1] = {
      text = "Remove ROM palette link",
      menuGroup = "palette_dest_linked_ops",
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
    menuGroup = "layer_palette_linked",
    callback = function()
      if self.focusPaletteWindowWithGrouping then
        self:focusPaletteWindowWithGrouping(paletteWin)
      elseif self.wm and self.wm.setFocus then
        self.wm:setFocus(paletteWin)
      end
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
    menuGroup = "layer_palette_linked",
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
    menuGroup = "layer_clipboard",
    callback = function()
      if self.performClipboardToolbarAction then
        self:performClipboardToolbarAction("paste", context.win, context.layerIndex, pasteOpts)
      end
    end,
  }
  return items
end
local function resolvePatternTableLinkLayerIndex(win)
  if not win then
    return 1
  end
  local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
  li = math.floor(tonumber(li) or 1)
  local layer = win.layers and win.layers[li]
  if WindowCaps.isPpuFrame(win)
    and layer
    and layer._runtimePatternTableRefLayer == true
    and type(layer._runtimePatternTableRefTargetLayerIndex) == "number"
  then
    return math.floor(layer._runtimePatternTableRefTargetLayerIndex)
  end
  return li
end

--- Restore minimized / hidden / collapsed state so WM:setFocus actually runs; then bring to front
--- (setFocus is a no-op for minimized windows; it also skips bringToFront when focus is unchanged).
local function activateWindowForJump(wm, win)
  if not (wm and win) or win._closed then
    return
  end
  if win._collapsed == true then
    win._collapsed = false
  end
  if win._groupHidden == true then
    win._groupHidden = false
  end
  if win._minimized == true and wm.restoreMinimizedWindow then
    wm:restoreMinimizedWindow(win, { recordUndo = false })
  elseif wm.setFocus then
    wm:setFocus(win)
  end
  if wm.bringToFront and win._closed ~= true and win._minimized ~= true and win._groupHidden ~= true then
    wm:bringToFront(win)
  end
end

local function normalizeLinkedPatternTableWindowId(id)
  if type(id) ~= "string" or id == "" then
    return nil
  end
  return id
end

local function snapshotPatternTableLayerBeforeMutation(win, layerIndex)
  local layer = win.layers and win.layers[layerIndex]
  if not layer then
    return nil
  end
  local pt = layer.patternTable
  return {
    linkedId = normalizeLinkedPatternTableWindowId(layer.linkedPatternTableWindowId),
    patternTableDeep = type(pt) == "table" and TableUtils.deepcopy(pt) or { ranges = {} },
    patternTableRef = pt,
  }
end

local function snapshotPatternTableLayerAfterMutation(win, layerIndex)
  local layer = win.layers and win.layers[layerIndex]
  if not layer then
    return nil
  end
  local pt = layer.patternTable
  return {
    linkedId = normalizeLinkedPatternTableWindowId(layer.linkedPatternTableWindowId),
    patternTableDeep = type(pt) == "table" and TableUtils.deepcopy(pt) or { ranges = {} },
  }
end

local function patternTableLayerMutationWasNoOp(beforeSnap, layerAfter)
  if not (beforeSnap and layerAfter) then
    return false
  end
  return beforeSnap.linkedId == normalizeLinkedPatternTableWindowId(layerAfter.linkedPatternTableWindowId)
    and beforeSnap.patternTableRef == layerAfter.patternTable
end

local function pushPatternTableLinkUndoIfNeeded(self, win, layerIndex, beforeSnap)
  if not (self and self.undoRedo and win and beforeSnap) then
    return
  end
  local layer = win.layers and win.layers[layerIndex]
  if not layer then
    return
  end
  if patternTableLayerMutationWasNoOp(beforeSnap, layer) then
    return
  end
  local afterSnap = snapshotPatternTableLayerAfterMutation(win, layerIndex)
  if not afterSnap then
    return
  end
  self.undoRedo:addPatternTableLinkEvent({
    type = "pattern_table_link",
    actions = {
      {
        win = win,
        layerIndex = layerIndex,
        beforeLinkedId = beforeSnap.linkedId,
        afterLinkedId = afterSnap.linkedId,
        beforePatternTable = beforeSnap.patternTableDeep,
        afterPatternTable = afterSnap.patternTableDeep,
      },
    },
  })
end

--- @param entries { { win = w, layerIndex = i, beforeSnap = snap } ... } captured before a batch mutation.
local function pushPatternTableLinkUndoBatchAfterMutations(self, entries)
  if not (self and self.undoRedo and type(entries) == "table") then
    return
  end
  local actions = {}
  for _, e in ipairs(entries) do
    local win = e.win
    local li = e.layerIndex
    local beforeSnap = e.beforeSnap
    local layer = win and win.layers and li and win.layers[li]
    if layer and beforeSnap and not patternTableLayerMutationWasNoOp(beforeSnap, layer) then
      local afterSnap = snapshotPatternTableLayerAfterMutation(win, li)
      if afterSnap then
        actions[#actions + 1] = {
          win = win,
          layerIndex = li,
          beforeLinkedId = beforeSnap.linkedId,
          afterLinkedId = afterSnap.linkedId,
          beforePatternTable = beforeSnap.patternTableDeep,
          afterPatternTable = afterSnap.patternTableDeep,
        }
      end
    end
  end
  if #actions > 0 then
    self.undoRedo:addPatternTableLinkEvent({
      type = "pattern_table_link",
      actions = actions,
    })
  end
end
local function findPpuNametableTileLayerIndex(win)
  if not win or not win.layers then
    return nil
  end
  for i, layer in ipairs(win.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      if type(layer.nametableStartAddr) == "number" and type(layer.nametableEndAddr) == "number" then
        return i
      end
    end
  end
  for i, layer in ipairs(win.layers) do
    if layer and layer.kind == "tile" and layer._runtimePatternTableRefLayer ~= true then
      return i
    end
  end
  return nil
end

local function findPpuFirstSpriteLayerIndex(win)
  if not win or not win.layers then
    return nil
  end
  for i, layer in ipairs(win.layers) do
    if layer and layer.kind == "sprite" then
      return i
    end
  end
  return nil
end

local function findWindowByLinkedPatternTableId(wm, linkedId)
  if type(linkedId) ~= "string" or linkedId == "" or not wm or not wm.getWindows then
    return nil
  end
  for _, w in ipairs(wm:getWindows()) do
    if w._id == linkedId then
      return w
    end
  end
  return nil
end

--- Icon for picking a pattern table in link submenus (radio-style: filled circle = current link).
local function patternTablePickMenuIcon(ptWindow, linkedWindowId)
  local chrome = images.icons and images.icons.chrome or nil
  local circle = chrome and chrome.icon_circle or nil
  local empty = chrome and chrome.icon_empty or nil
  if linkedWindowId and ptWindow and ptWindow._id == linkedWindowId then
    return circle
  end
  return empty
end

local function oamAnimationLinkedPatternTableId(contentWin)
  for _, layer in ipairs(contentWin.layers or {}) do
    if layer and layer.kind == "sprite" and type(layer.linkedPatternTableWindowId) == "string" and layer.linkedPatternTableWindowId ~= "" then
      return layer.linkedPatternTableWindowId
    end
  end
  return nil
end

local function patternTableRootMenuIcons()
  local actions = images.icons and images.icons.actions or nil
  local chrome = images.icons and images.icons.chrome or nil
  return {
    link = actions and actions.icon_connect,
    unlink = chrome and chrome.icon_x,
    jump = chrome and chrome.icon_windows,
  }
end

function AppCoreController:_buildPatternTableLinkDestinationContextMenuItems(contentWin)
  local items = {}
  local ptWindows = PatternTableDisplayController.collectPatternTableWindows(self.wm)
  local hideMenus = function()
    if self.hideAppContextMenus then
      self:hideAppContextMenus()
    end
  end

  if WindowCaps.isOamAnimation(contentWin) then
    local spriteCount = 0
    for _, layer in ipairs(contentWin.layers or {}) do
      if layer and layer.kind == "sprite" then
        spriteCount = spriteCount + 1
      end
    end

    if spriteCount <= 0 then
      items[1] = {
        text = "No sprite layers",
        callback = function() end,
      }
      return items
    end

    local iconsOam = patternTableRootMenuIcons()
    items[#items + 1] = {
      text = "Link pattern table",
      icon = iconsOam.link,
      menuGroup = "pt_oam_link",
      children = function()
        local childItems = {}
        local linkedId = oamAnimationLinkedPatternTableId(contentWin)
        for _, pt in ipairs(ptWindows) do
          if pt ~= contentWin then
            childItems[#childItems + 1] = {
              text = tostring(pt.title or pt._id or "Pattern table"),
              icon = patternTablePickMenuIcon(pt, linkedId),
              callback = function()
                local batchBefore = {}
                for li, L in ipairs(contentWin.layers or {}) do
                  if L and L.kind == "sprite" then
                    batchBefore[#batchBefore + 1] = {
                      win = contentWin,
                      layerIndex = li,
                      beforeSnap = snapshotPatternTableLayerBeforeMutation(contentWin, li),
                    }
                  end
                end
                PatternTableDisplayController.linkAllOamSpriteLayersToPatternTableWindow(contentWin, pt)
                pushPatternTableLinkUndoBatchAfterMutations(self, batchBefore)
                for li, L in ipairs(contentWin.layers or {}) do
                  if L and L.kind == "sprite" then
                    self:_afterPatternTableLinkChange(contentWin, li)
                  end
                end
                hideMenus()
              end,
            }
          end
        end
        if #childItems == 0 then
          childItems[1] = {
            text = "No pattern table windows",
            callback = function() end,
          }
        end
        return childItems
      end,
    }

    local linkedIdFound = oamAnimationLinkedPatternTableId(contentWin)

    if linkedIdFound then
      local linkedWin = findWindowByLinkedPatternTableId(self.wm, linkedIdFound)
      if linkedWin then
        items[#items + 1] = {
          text = "Jump to pattern table",
          icon = iconsOam.jump,
          menuGroup = "pt_oam_follow",
          callback = function()
            activateWindowForJump(self.wm, linkedWin)
            hideMenus()
          end,
        }
      end
      items[#items + 1] = {
        text = "Unlink pattern table",
        icon = iconsOam.unlink,
        menuGroup = "pt_oam_follow",
        callback = function()
          local batchBefore = {}
          for li, L in ipairs(contentWin.layers or {}) do
            if L and L.kind == "sprite" then
              batchBefore[#batchBefore + 1] = {
                win = contentWin,
                layerIndex = li,
                beforeSnap = snapshotPatternTableLayerBeforeMutation(contentWin, li),
              }
            end
          end
          PatternTableDisplayController.unlinkAllOamSpriteLayersPatternTable(contentWin)
          pushPatternTableLinkUndoBatchAfterMutations(self, batchBefore)
          for li, L in ipairs(contentWin.layers or {}) do
            if L and L.kind == "sprite" then
              self:_afterPatternTableLinkChange(contentWin, li)
            end
          end
          hideMenus()
        end,
      }
    end

    return items
  end

  if WindowCaps.isPpuFrame(contentWin) then
    local iconsRoot = patternTableRootMenuIcons()
    local bgIdx = findPpuNametableTileLayerIndex(contentWin)
    local sprIdx = findPpuFirstSpriteLayerIndex(contentWin)

    items[#items + 1] = {
      text = "Link background pattern table",
      icon = iconsRoot.link,
      menuGroup = "pt_ppu_link_layers",
      children = function()
        if not bgIdx then
          return {
            {
              text = "No background layer",
              callback = function() end,
            },
          }
        end
        local childItems = {}
        local bgLinkedId = nil
        local bgL = contentWin.layers and contentWin.layers[bgIdx]
        if bgL and type(bgL.linkedPatternTableWindowId) == "string" and bgL.linkedPatternTableWindowId ~= "" then
          bgLinkedId = bgL.linkedPatternTableWindowId
        end
        for _, pt in ipairs(ptWindows) do
          if pt ~= contentWin then
            childItems[#childItems + 1] = {
              text = tostring(pt.title or pt._id or "Pattern table"),
              icon = patternTablePickMenuIcon(pt, bgLinkedId),
              callback = function()
                local beforeSnap = snapshotPatternTableLayerBeforeMutation(contentWin, bgIdx)
                PatternTableDisplayController.linkContentLayerToPatternTableWindow(contentWin, bgIdx, pt)
                pushPatternTableLinkUndoIfNeeded(self, contentWin, bgIdx, beforeSnap)
                self:_afterPatternTableLinkChange(contentWin, bgIdx)
                hideMenus()
              end,
            }
          end
        end
        if #childItems == 0 then
          childItems[1] = {
            text = "No pattern table windows",
            callback = function() end,
          }
        end
        return childItems
      end,
    }

    if sprIdx then
      items[#items + 1] = {
        text = "Link sprites pattern table",
        icon = iconsRoot.link,
        menuGroup = "pt_ppu_link_layers",
        children = function()
          local childItems = {}
          local sprLinkedId = nil
          local sprL = contentWin.layers and contentWin.layers[sprIdx]
          if sprL and type(sprL.linkedPatternTableWindowId) == "string" and sprL.linkedPatternTableWindowId ~= "" then
            sprLinkedId = sprL.linkedPatternTableWindowId
          end
          for _, pt in ipairs(ptWindows) do
            if pt ~= contentWin then
              childItems[#childItems + 1] = {
                text = tostring(pt.title or pt._id or "Pattern table"),
                icon = patternTablePickMenuIcon(pt, sprLinkedId),
                callback = function()
                  local beforeSnap = snapshotPatternTableLayerBeforeMutation(contentWin, sprIdx)
                  PatternTableDisplayController.linkContentLayerToPatternTableWindow(contentWin, sprIdx, pt)
                  pushPatternTableLinkUndoIfNeeded(self, contentWin, sprIdx, beforeSnap)
                  self:_afterPatternTableLinkChange(contentWin, sprIdx)
                  hideMenus()
                end,
              }
            end
          end
          if #childItems == 0 then
            childItems[1] = {
              text = "No pattern table windows",
              callback = function() end,
            }
          end
          return childItems
        end,
      }
    end

    local bgLayer = bgIdx and contentWin.layers and contentWin.layers[bgIdx]
    local sprLayer = sprIdx and contentWin.layers and contentWin.layers[sprIdx]

    if bgLayer and type(bgLayer.linkedPatternTableWindowId) == "string" and bgLayer.linkedPatternTableWindowId ~= "" then
      local lw = findWindowByLinkedPatternTableId(self.wm, bgLayer.linkedPatternTableWindowId)
      if lw then
        items[#items + 1] = {
          text = "Jump to background pattern table",
          icon = iconsRoot.jump,
          menuGroup = "pt_ppu_jump",
          callback = function()
            activateWindowForJump(self.wm, lw)
            hideMenus()
          end,
        }
      end
    end

    if sprLayer and type(sprLayer.linkedPatternTableWindowId) == "string" and sprLayer.linkedPatternTableWindowId ~= "" then
      local lw = findWindowByLinkedPatternTableId(self.wm, sprLayer.linkedPatternTableWindowId)
      if lw then
        items[#items + 1] = {
          text = "Jump to sprites pattern table",
          icon = iconsRoot.jump,
          menuGroup = "pt_ppu_jump",
          callback = function()
            activateWindowForJump(self.wm, lw)
            hideMenus()
          end,
        }
      end
    end

    if bgLayer and type(bgLayer.linkedPatternTableWindowId) == "string" and bgLayer.linkedPatternTableWindowId ~= "" then
      items[#items + 1] = {
        text = "Unlink background pattern table",
        icon = iconsRoot.unlink,
        menuGroup = "pt_ppu_unlink",
        callback = function()
          local beforeSnap = snapshotPatternTableLayerBeforeMutation(contentWin, bgIdx)
          PatternTableDisplayController.unlinkContentLayerPatternTable(contentWin, bgIdx)
          pushPatternTableLinkUndoIfNeeded(self, contentWin, bgIdx, beforeSnap)
          self:_afterPatternTableLinkChange(contentWin, bgIdx)
          hideMenus()
        end,
      }
    end

    if sprLayer and type(sprLayer.linkedPatternTableWindowId) == "string" and sprLayer.linkedPatternTableWindowId ~= "" then
      items[#items + 1] = {
        text = "Unlink sprites pattern table",
        icon = iconsRoot.unlink,
        menuGroup = "pt_ppu_unlink",
        callback = function()
          local beforeSnap = snapshotPatternTableLayerBeforeMutation(contentWin, sprIdx)
          PatternTableDisplayController.unlinkContentLayerPatternTable(contentWin, sprIdx)
          pushPatternTableLinkUndoIfNeeded(self, contentWin, sprIdx, beforeSnap)
          self:_afterPatternTableLinkChange(contentWin, sprIdx)
          hideMenus()
        end,
      }
    end

    return items
  end

  local layerIndex = resolvePatternTableLinkLayerIndex(contentWin)
  local layer = contentWin.layers and contentWin.layers[layerIndex]

  if not (layer and (layer.kind == "tile" or layer.kind == "sprite")) then
    items[1] = {
      text = "No linkable layer",
      callback = function() end,
    }
    return items
  end

  local iconsFb = patternTableRootMenuIcons()
  items[#items + 1] = {
    text = "Link pattern table",
    icon = iconsFb.link,
    menuGroup = "pt_layer_link",
    children = function()
      local childItems = {}
      local layerLinkedId = nil
      if type(layer.linkedPatternTableWindowId) == "string" and layer.linkedPatternTableWindowId ~= "" then
        layerLinkedId = layer.linkedPatternTableWindowId
      end
      for _, pt in ipairs(ptWindows) do
        if pt ~= contentWin then
          childItems[#childItems + 1] = {
            text = tostring(pt.title or pt._id or "Pattern table"),
            icon = patternTablePickMenuIcon(pt, layerLinkedId),
            callback = function()
              local beforeSnap = snapshotPatternTableLayerBeforeMutation(contentWin, layerIndex)
              PatternTableDisplayController.linkContentLayerToPatternTableWindow(contentWin, layerIndex, pt)
              pushPatternTableLinkUndoIfNeeded(self, contentWin, layerIndex, beforeSnap)
              self:_afterPatternTableLinkChange(contentWin, layerIndex)
              hideMenus()
            end,
          }
        end
      end
      if #childItems == 0 then
        childItems[1] = {
          text = "No pattern table windows",
          callback = function() end,
        }
      end
      return childItems
    end,
  }

  if type(layer.linkedPatternTableWindowId) == "string" and layer.linkedPatternTableWindowId ~= "" then
    local linkedWin = findWindowByLinkedPatternTableId(self.wm, layer.linkedPatternTableWindowId)
    if linkedWin then
      items[#items + 1] = {
        text = "Jump to pattern table",
        icon = iconsFb.jump,
        menuGroup = "pt_layer_linked",
        callback = function()
          activateWindowForJump(self.wm, linkedWin)
          hideMenus()
        end,
      }
    end
    items[#items + 1] = {
      text = "Unlink pattern table",
      icon = iconsFb.unlink,
      menuGroup = "pt_layer_linked",
      callback = function()
        local beforeSnap = snapshotPatternTableLayerBeforeMutation(contentWin, layerIndex)
        PatternTableDisplayController.unlinkContentLayerPatternTable(contentWin, layerIndex)
        pushPatternTableLinkUndoIfNeeded(self, contentWin, layerIndex, beforeSnap)
        self:_afterPatternTableLinkChange(contentWin, layerIndex)
        hideMenus()
      end,
    }
  end

  return items
end

function AppCoreController:showPatternTableLinkDestinationContextMenu(win, x, y)
  if not (self.paletteLinkContextMenu and win and type(x) == "number" and type(y) == "number") then
    return false
  end
  self:_hideAllContextMenus()
  local cx, cy = self:contentPointToCanvasPoint(x, y)
  self.paletteLinkContextMenu:showAt(cx, cy, self:_buildPatternTableLinkDestinationContextMenuItems(win))
  return self.paletteLinkContextMenu:isVisible()
end

function AppCoreController:_buildPatternTableLinkSourceContextMenuItems(patternTableWin)
  local targets = PatternTableDisplayController.getLinkedConsumersForPatternTable(self.wm, patternTableWin)
  local items = {}

  items[#items + 1] = {
    text = "Jump to linked layer",
    menuGroup = "pt_src_navigate",
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
    menuGroup = "pt_src_remove",
    callback = function()
      if #targets == 0 then
        return
      end
      self:hideAppContextMenus()
      local batchBefore = {}
      for _, entry in ipairs(targets) do
        batchBefore[#batchBefore + 1] = {
          win = entry.win,
          layerIndex = entry.layerIndex,
          beforeSnap = snapshotPatternTableLayerBeforeMutation(entry.win, entry.layerIndex),
        }
      end
      for _, entry in ipairs(targets) do
        PatternTableDisplayController.unlinkContentLayerPatternTable(entry.win, entry.layerIndex)
      end
      pushPatternTableLinkUndoBatchAfterMutations(self, batchBefore)
      for _, entry in ipairs(targets) do
        self:_afterPatternTableLinkChange(entry.win, entry.layerIndex)
      end
      if self.setStatus then
        self:setStatus(string.format(
          "Unlinked %d layer(s) from %s",
          #targets,
          tostring(patternTableWin.title or "pattern table")
        ))
      end
    end,
  }

  return items
end

function AppCoreController:_buildCrtLayerVizContextMenuItems(crtWin)
  local app = self
  local wm = self.wm

  local function isRefAlreadyInCrtViz(wid, layerIndex)
    local li = math.floor(tonumber(layerIndex) or 0)
    if li < 1 then
      return false
    end
    for _, r in ipairs(crtWin.crtRefLayers or {}) do
      if tostring(r.windowId) == tostring(wid) and math.floor(tonumber(r.layerIndex) or 0) == li then
        return true
      end
    end
    return false
  end

  local function hasAnyCrtVizLayoutWindow()
    if not wm then
      return false
    end
    for _, w in ipairs(wm:getWindows()) do
      if WindowCaps.isCrtVizLayoutWindow(w) then
        return true
      end
    end
    return false
  end

  local function buildAddWindowItems()
    local out = {}
    if not wm then
      return out
    end
    local list = {}
    for _, w in ipairs(wm:getWindows()) do
      if WindowCaps.isCrtVizLayoutWindow(w) then
        list[#list + 1] = w
      end
    end
    table.sort(list, function(a, b)
      return (a.title or ""):lower() < (b.title or ""):lower()
    end)
    for _, w in ipairs(list) do
      local wref = w
      local layerItems = {}
      local layers = wref.layers or {}
      for li = 1, #layers do
        if not isRefAlreadyInCrtViz(wref._id, li) then
          local L = layers[li]
          local liSnap = li
          layerItems[#layerItems + 1] = {
            text = (L and L.name) or ("Layer " .. li),
            action = function()
              app:crtVizAddReference(crtWin, wref._id, liSnap)
            end,
          }
        end
      end
      if #layerItems > 0 then
        out[#out + 1] = {
          text = wref.title or ("Window " .. tostring(wref._id)),
          children = function()
            return layerItems
          end,
        }
      end
    end
    return out
  end

  local function buildRemoveWindowItems()
    local refs = crtWin.crtRefLayers or {}
    if #refs == 0 then
      return {}
    end

    local groups = {}
    for idx, ref in ipairs(refs) do
      local wid = ref.windowId
      if not groups[wid] then
        groups[wid] = {}
      end
      table.insert(groups[wid], { refIndex = idx, layerIndex = ref.layerIndex })
    end

    local winIds = {}
    for wid in pairs(groups) do
      winIds[#winIds + 1] = wid
    end
    table.sort(winIds, function(a, b)
      local wa, wb = wm and wm:findWindowById(a), wm and wm:findWindowById(b)
      local ta = (wa and wa.title) or ""
      local tb = (wb and wb.title) or ""
      return ta:lower() < tb:lower()
    end)

    local items = {}
    for _, wid in ipairs(winIds) do
      local wSnap = wm and wm:findWindowById(wid)
      local title = (wSnap and wSnap.title) or ("#" .. tostring(wid))
      local entries = groups[wid]
      items[#items + 1] = {
        text = title,
        children = function()
          local layerItems = {}
          local countForLayer = {}
          for _, entry in ipairs(entries) do
            local li = entry.layerIndex
            countForLayer[li] = (countForLayer[li] or 0) + 1
            local n = countForLayer[li]
            local L = wSnap and wSnap.layers and wSnap.layers[li]
            local base = (L and L.name) or ("Layer " .. li)
            local label = base
            if n > 1 then
              label = base .. " [" .. n .. "]"
            end
            local snapIdx = entry.refIndex
            layerItems[#layerItems + 1] = {
              text = label,
              action = function()
                app:crtVizRemoveReferenceAt(crtWin, snapIdx)
              end,
            }
          end
          return layerItems
        end,
      }
    end
    return items
  end

  local addWinItems = buildAddWindowItems()
  local removeWinItems = buildRemoveWindowItems()

  return {
    {
      text = "Add window layer",
      menuGroup = "crt_viz_add",
      children = function()
        if #addWinItems == 0 then
          if not hasAnyCrtVizLayoutWindow() then
            return {
              {
                text = "(No layout windows)",
                action = function()
                  app:setStatus("Open a layout window (not palette or CHR) to reference a layer")
                end,
              },
            }
          end
          return {
            {
              text = "(All layers are already in this list)",
              action = function() end,
            },
          }
        end
        return addWinItems
      end,
    },
    {
      text = "Remove window layer",
      menuGroup = "crt_viz_remove_tree",
      enabled = #removeWinItems > 0,
      children = function()
        return removeWinItems
      end,
    },
    {
      text = "Remove current layer",
      menuGroup = "crt_viz_remove_active",
      enabled = #(crtWin.crtRefLayers or {}) > 0,
      action = function()
        local idx = crtWin.getActiveLayerIndex and crtWin:getActiveLayerIndex() or 1
        app:crtVizRemoveReferenceAt(crtWin, idx)
      end,
    },
  }
end

end
