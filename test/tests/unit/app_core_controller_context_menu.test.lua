local AppCoreController = require("controllers.app.core_controller")
local ChrBankUiHelpers = require("controllers.chr.chr_bank_ui_helpers")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")

describe("core_controller.lua - contextual menu helpers", function()
  it("shows the shared new window modal when a ROM is loaded", function()
    local typeTitle = nil
    local typeOptions = nil
    local app = setmetatable({
      hasLoadedROM = function() return true end,
      newWindowTypeModal = {
        show = function(_, title, options)
          typeTitle = title
          typeOptions = options
        end,
      },
      newWindowModal = {
        show = function()
          error("newWindowModal should open only after a window type is chosen")
        end,
      },
    }, AppCoreController)

    local ok = app:showNewWindowModal()

    expect(ok).toBe(true)
    expect(typeTitle).toBe("New Window")
    expect(type(typeOptions)).toBe("table")
    expect(#typeOptions).toBe(9)
    expect(typeOptions[1].text).toBe("Static Art window (tiles)")
    expect(typeOptions[4].text).toBe("Animation window  (sprites)")
    expect(typeOptions[5].text).toBe("Palette window")
    expect(typeOptions[6].text).toBe("ROM Palette window")
    expect(typeOptions[7].text).toBe("PPU Frame window")
    expect(typeOptions[8].text).toBe("Pattern table window")
    expect(typeOptions[9].text).toBe("OAM animation")
    expect(type(typeOptions[1].callback)).toBe("function")
  end)

  it("refuses to show the new window modal when no ROM is loaded", function()
    local status = nil
    local shown = 0
    local app = setmetatable({
      hasLoadedROM = function() return false end,
      setStatus = function(_, text)
        status = text
      end,
      newWindowModal = {
        show = function()
          shown = shown + 1
        end,
      },
    }, AppCoreController)

    local ok = app:showNewWindowModal()

    expect(ok).toBe(false)
    expect(status).toBe("Open a ROM before creating windows.")
    expect(shown).toBe(0)
  end)

  it("builds the window header context menu entries in the expected order", function()
    local renameCalls = 0
    local app = setmetatable({
      hideAppContextMenus = function() end,
      showRenameWindowModal = function(_, w)
        renameCalls = renameCalls + 1
        expect(w.title).toBe("My window")
      end,
    }, AppCoreController)
    local win = {
      _closed = false,
      _minimized = false,
      title = "My window",
    }
    local items = app:_buildWindowHeaderContextMenuItems(win)

    expect(#items).toBe(6)
    expect(items[1].text).toBe("Rename")
    expect(items[2].text).toBe("Close")
    expect(items[3].text).toBe("Collapse")
    expect(items[4].text).toBe("Minimize")
    expect(items[5].text).toBe("Minimize others")
    expect(items[6].text).toBe("Keep always on top")
    expect(items[1].enabled).toBe(true)
    expect(items[2].enabled).toBe(true)
    expect(items[3].enabled).toBe(true)
    expect(items[4].enabled).toBe(true)
    expect(items[5].enabled).toBe(false)
    expect(items[6].enabled).toBe(true)

    items[1].callback()
    expect(renameCalls).toBe(1)
  end)

  it("enables Minimize others when another window can be minimized", function()
    local app = setmetatable({
      hideAppContextMenus = function() end,
    }, AppCoreController)
    local winA = { _closed = false, _minimized = false, title = "A" }
    local winB = { _closed = false, _minimized = false, title = "B" }
    app.wm = {
      getWindows = function()
        return { winA, winB }
      end,
    }
    local items = app:_buildWindowHeaderContextMenuItems(winA)
    expect(items[5].text).toBe("Minimize others")
    expect(items[5].enabled).toBe(true)
  end)

  it("labels always-on-top menu item when window is already pinned", function()
    local app = setmetatable({}, AppCoreController)
    local win = {
      _closed = false,
      _minimized = false,
      _alwaysOnTop = true,
      title = "Pinned",
    }
    local items = app:_buildWindowHeaderContextMenuItems(win)
    expect(items[6].text).toBe("Don't keep always on top")
  end)

  it("disables Rename in header menu when window title is locked", function()
    local app = setmetatable({}, AppCoreController)
    local win = {
      _closed = false,
      _minimized = false,
      titleLocked = true,
      title = "Bank 1/2",
    }
    local items = app:_buildWindowHeaderContextMenuItems(win)
    expect(items[1].text).toBe("Rename")
    expect(items[1].enabled).toBe(false)
  end)

  it("does not open rename modal for title-locked windows", function()
    local modalShown = 0
    local app = setmetatable({
      renameWindowModal = {
        show = function()
          modalShown = modalShown + 1
        end,
      },
    }, AppCoreController)
    local win = { titleLocked = true, title = "Bank 1/1" }
    expect(app:showRenameWindowModal(win)).toBe(false)
    expect(modalShown).toBe(0)
  end)

  it("builds taskbar minimized header menu with Maximize replacing Minimize", function()
    local app = setmetatable({}, AppCoreController)
    local win = { kind = "static_art", title = "T", _minimized = true, _closed = false }
    local items = app:_buildWindowHeaderContextMenuItems(win, { forMinimizedTaskbarButton = true })
    expect(#items).toBe(6)
    expect(items[3].text).toBe("Collapse")
    expect(items[3].enabled).toBe(false)
    expect(items[4].text).toBe("Maximize")
    expect(items[4].enabled).toBe(true)
    expect(items[5].text).toBe("Minimize others")
    expect(items[6].text).toBe("Keep always on top")
  end)

  it("builds the empty-space context menu entries in the expected order", function()
    local app = setmetatable({
      hasLoadedROM = function() return true end,
      wm = {
        getWindows = function()
          return {
            { title = "A" },
          }
        end,
      },
    }, AppCoreController)

    local items = app:_buildEmptySpaceContextMenuItems()

    expect(#items).toBe(7)
    expect(items[1].text).toBe("New Window")
    expect(items[2].text).toBe("Expand all")
    expect(items[3].text).toBe("Collapse all")
    expect(items[4].text).toBe("Sort by title")
    expect(items[5].text).toBe("Sort by kind")
    expect(items[6].text).toBe("Minimize all")
    expect(items[7].text).toBe("Maximize all")
    for i = 1, 7 do
      expect(items[i].enabled).toBe(true)
      expect(items[i].icon).toBeTruthy()
    end
  end)

  it("builds OAM empty-space sprite context menu with add action", function()
    local addCalls = 0
    local app = setmetatable({
      showPpuFrameAddSpriteModal = function(_, win)
        addCalls = addCalls + 1
        expect(win.kind).toBe("oam_animation")
        return true
      end,
    }, AppCoreController)

    local context = app:_buildOamSpriteEmptySpaceContext({
      kind = "oam_animation",
      layers = {
        { kind = "sprite", items = {} },
      },
    }, 1)

    local items = app:_buildOamSpriteEmptySpaceContextMenuItems(context)
    expect(#items).toBe(1)
    expect(items[1].text).toBe("Add new sprite")
    expect(items[1].enabled).toBe(true)

    local ok = items[1].callback()
    expect(ok).toBe(true)
    expect(addCalls).toBe(1)
  end)

  it("adds Remove selected sprites to OAM empty-space menu when sprites are selected", function()
    local app = setmetatable({
      showPpuFrameAddSpriteModal = function()
        return true
      end,
      undoRedo = {
        addRemovalEvent = function() end,
      },
      setStatus = function() end,
    }, AppCoreController)

    local layer = {
      kind = "sprite",
      items = {
        { bank = 0, tile = 1 },
      },
      selectedSpriteIndex = 1,
    }
    local context = app:_buildOamSpriteEmptySpaceContext({
      kind = "oam_animation",
      layers = { layer },
    }, 1)

    local items = app:_buildOamSpriteEmptySpaceContextMenuItems(context)
    expect(#items).toBeGreaterThanOrEqual(2)
    expect(items[1].text).toBe("Add new sprite")
    expect(items[2].text).toBe("Remove selected sprites")
    expect(items[2].enabled).toBe(true)
    items[2].callback()
    expect(layer.items[1].removed).toBe(true)
  end)

  it("puts Edit sprite first on OAM sprite select-in-CHR context menu", function()
    local editCalls = 0
    local app = setmetatable({
      showPpuFrameAddSpriteModal = function(_, targetWin, opts)
        editCalls = editCalls + 1
        expect(targetWin.kind).toBe("oam_animation")
        expect(opts and opts.editSprite).toBeTruthy()
        expect(opts.editSprite.layerIndex).toBe(1)
        expect(opts.editSprite.itemIndex).toBe(2)
        return true
      end,
    }, AppCoreController)

    local win = { kind = "oam_animation", layers = {} }
    local layer = {
      kind = "sprite",
      items = {
        { bank = 1, tile = 0, startAddr = 0x200 },
        { bank = 1, tile = 3, startAddr = 0x204 },
      },
    }
    local context = {
      win = win,
      layerIndex = 1,
      layer = layer,
      itemIndex = 2,
      item = layer.items[2],
      tileIndex = 3,
    }

    local items = app:_buildSelectInChrContextMenuItems(context)
    expect(items[1].text).toBe("Edit sprite")
    expect(items[1].enabled).toBe(true)
    expect(items[2].text).toBe("Reset position")
    expect(items[2].enabled).toBe(false)
    items[1].callback()
    expect(editCalls).toBe(1)
  end)

  it("enables Reset position on OAM select-in-CHR menu when sprite is offset from ROM base", function()
    local undoAdded = false
    local marked = nil
    local app = setmetatable({
      undoRedo = {
        addDragEvent = function(_, ev)
          undoAdded = true
          expect(ev.type).toBe("sprite_drag")
          expect(ev.mode).toBe("move")
        end,
      },
      markUnsaved = function(_, t)
        marked = t
      end,
      setStatus = function() end,
    }, AppCoreController)

    local layer = {
      kind = "sprite",
      selectedSpriteIndex = 1,
      items = {
        {
          bank = 1,
          tile = 0,
          startAddr = 0x200,
          baseX = 10,
          baseY = 20,
          worldX = 50,
          worldY = 60,
          x = 50,
          y = 60,
          dx = 40,
          dy = 40,
          hasMoved = true,
        },
      },
    }
    local win = { kind = "oam_animation", layers = { layer } }
    local context = {
      win = win,
      layerIndex = 1,
      layer = layer,
      itemIndex = 1,
      item = layer.items[1],
      tileIndex = 0,
    }

    local items = app:_buildSelectInChrContextMenuItems(context)
    local resetItem
    for _, it in ipairs(items) do
      if it.text == "Reset position" then
        resetItem = it
        break
      end
    end
    expect(resetItem ~= nil).toBe(true)
    expect(resetItem.enabled).toBe(true)
    resetItem.callback()
    expect(layer.items[1].worldX).toBe(10)
    expect(layer.items[1].worldY).toBe(20)
    expect(layer.items[1].dx).toBe(0)
    expect(layer.items[1].hasMoved).toBe(false)
    expect(undoAdded).toBe(true)
    expect(marked).toBe("sprite_move")
  end)

  it("puts Edit sprite first on PPU frame sprite select-in-CHR context menu", function()
    local editCalls = 0
    local app = setmetatable({
      showPpuFrameAddSpriteModal = function(_, targetWin, opts)
        editCalls = editCalls + 1
        expect(targetWin.kind).toBe("ppu_frame")
        expect(opts and opts.editSprite).toBeTruthy()
        expect(opts.editSprite.layerIndex).toBe(2)
        expect(opts.editSprite.itemIndex).toBe(1)
        return true
      end,
    }, AppCoreController)

    local win = { kind = "ppu_frame", layers = {} }
    local layer = {
      kind = "sprite",
      items = {
        { bank = 1, tile = 5, startAddr = 0x300 },
      },
    }
    local context = {
      win = win,
      layerIndex = 2,
      layer = layer,
      itemIndex = 1,
      item = layer.items[1],
      tileIndex = 5,
    }

    local items = app:_buildSelectInChrContextMenuItems(context)
    expect(items[1].text).toBe("Edit sprite")
    items[1].callback()
    expect(editCalls).toBe(1)
    expect(items[2].text).toBe("Reset position")
    expect(items[2].enabled).toBe(false)
  end)

  it("builds tile-layer empty-space context menu with palette link actions when linked", function()
    local paletteWin = { kind = "rom_palette", _id = 42, title = "P" }
    local app = setmetatable({
      wm = {
        findWindowById = function(_, id)
          if id == 42 then
            return paletteWin
          end
          return nil
        end,
      },
    }, AppCoreController)

    local win = {
      kind = "static_art",
      _id = "w1",
      layers = {
        { kind = "tile", paletteData = { winId = 42 } },
      },
    }
    local context = app:_buildTileLayerEmptySpaceContext(win, 1, 2, 3)
    expect(context).toBeTruthy()
    expect(context.layerIndex).toBe(1)
    local items = app:_buildTileLayerEmptySpaceContextMenuItems(context)
    expect(#items).toBeGreaterThanOrEqual(2)
    expect(items[1].text).toBe("Jump to linked palette")
    expect(items[2].text).toBe("Remove ROM palette link")
  end)

  it("adds Paste to PPU/select/CHR context menus only when clipboard paste is allowed", function()
    local oldHasClipboardData = KeyboardClipboardController.hasClipboardData
    local oldGetActionAvailability = KeyboardClipboardController.getActionAvailability
    KeyboardClipboardController.hasClipboardData = function()
      return true
    end
    KeyboardClipboardController.getActionAvailability = function()
      return { allowed = true }
    end

    local pasteCall = nil
    local app = setmetatable({
      performClipboardToolbarAction = function(_, action, win, layerIndex, opts)
        pasteCall = {
          action = action,
          win = win,
          layerIndex = layerIndex,
          opts = opts,
        }
      end,
    }, AppCoreController)

    local win = {
      kind = "chr",
      title = "ROM Banks",
      layers = {
        [1] = { kind = "tile" },
      },
    }
    local context = {
      win = win,
      layerIndex = 1,
      layer = win.layers[1],
      col = 3,
      row = 4,
      item = { _bankIndex = 1, index = 7 },
      tileIndex = 7,
    }

    local ppuItems = app:_buildPpuTileContextMenuItems(context)
    local chrItems = app:_buildChrBankTileContextMenuItems(context)
    local selectItems = app:_buildSelectInChrContextMenuItems(context)

    local function findPaste(items)
      for _, item in ipairs(items or {}) do
        if item.text == "Paste" then
          return item
        end
      end
      return nil
    end

    local ppuPaste = findPaste(ppuItems)
    local chrPaste = findPaste(chrItems)
    local selectPaste = findPaste(selectItems)
    expect(ppuPaste ~= nil).toBe(true)
    expect(chrPaste ~= nil).toBe(true)
    expect(selectPaste ~= nil).toBe(true)

    chrPaste.callback()
    expect(pasteCall.action).toBe("paste")
    expect(pasteCall.win).toBe(win)
    expect(pasteCall.layerIndex).toBe(1)
    expect(pasteCall.opts.anchorCol).toBe(3)
    expect(pasteCall.opts.anchorRow).toBe(4)

    KeyboardClipboardController.hasClipboardData = oldHasClipboardData
    KeyboardClipboardController.getActionAvailability = oldGetActionAvailability
  end)

  it("CHR bank tile menu includes Copy tile bytes (hex) when bank bytes exist", function()
    local bank = {}
    for i = 1, 112 do
      bank[i] = 0
    end
    bank[97] = 0xAB

    local statuses = {}
    local win = {
      kind = "chr",
      layers = {
        [1] = { kind = "tile" },
      },
    }
    local app = setmetatable({
      appEditState = { chrBanksBytes = { bank } },
      performClipboardToolbarAction = function() end,
      setStatus = function(_, t)
        statuses[#statuses + 1] = t
      end,
    }, AppCoreController)

    local context = {
      win = win,
      layerIndex = 1,
      layer = win.layers[1],
      col = 0,
      row = 0,
      item = { _bankIndex = 1, index = 6 },
      sourceBank = 1,
      tileIndex = 6,
    }

    local oldLove = rawget(_G, "love")
    local captured = nil
    rawset(_G, "love", {
      system = {
        setClipboardText = function(t)
          captured = t
        end,
      },
    })

    local chrItems = app:_buildChrBankTileContextMenuItems(context)
    local hexItem
    for _, item in ipairs(chrItems or {}) do
      if item.text == "Copy tile bytes (hex)" then
        hexItem = item
        break
      end
    end
    expect(hexItem ~= nil).toBe(true)
    expect(hexItem.enabled).toBe(true)
    hexItem.callback()

    rawset(_G, "love", oldLove)

    expect(captured).toBe(
      ChrBankUiHelpers.formatTileChrBytesHexSpaceSeparated(bank, 6)
    )
    expect(statuses[#statuses] ~= nil).toBe(true)
  end)

  it("keeps Paste hidden when clipboard is empty", function()
    local oldHasClipboardData = KeyboardClipboardController.hasClipboardData
    local oldGetActionAvailability = KeyboardClipboardController.getActionAvailability
    KeyboardClipboardController.hasClipboardData = function()
      return false
    end
    KeyboardClipboardController.getActionAvailability = function()
      return { allowed = true }
    end

    local app = setmetatable({}, AppCoreController)
    local context = {
      win = {
        kind = "ppu_frame",
        layers = {
          [1] = { kind = "tile" },
        },
      },
      layerIndex = 1,
      layer = { kind = "tile" },
      col = 1,
      row = 2,
      tileIndex = 5,
    }
    local items = app:_buildPpuTileContextMenuItems(context)
    local hasPaste = false
    for _, item in ipairs(items) do
      if item.text == "Paste" then
        hasPaste = true
      end
    end
    expect(hasPaste).toBe(false)

    KeyboardClipboardController.hasClipboardData = oldHasClipboardData
    KeyboardClipboardController.getActionAvailability = oldGetActionAvailability
  end)

  it("resolves clipboard action focus from winBank fallback when WM focus is nil", function()
    local oldGetActionAvailability = KeyboardClipboardController.getActionAvailability
    local capturedFocus = nil
    KeyboardClipboardController.getActionAvailability = function(_, focus, action)
      capturedFocus = focus
      return { allowed = true, action = action }
    end

    local winBank = {
      kind = "chr",
      layers = {
        [1] = { kind = "tile" },
      },
      getActiveLayerIndex = function() return 1 end,
    }
    local app = setmetatable({
      wm = {
        getFocus = function() return nil end,
      },
      winBank = winBank,
      appEditState = {},
    }, AppCoreController)

    local state = app:getClipboardToolbarActionState("paste")
    expect(state.allowed).toBe(true)
    expect(capturedFocus).toBe(winBank)

    KeyboardClipboardController.getActionAvailability = oldGetActionAvailability
  end)

  it("detects PPU range changes when pattern-table ranges are updated", function()
    local didChange = AppCoreController.didPpuFrameRangeSettingsChange
    expect(type(didChange)).toBe("function")

    local beforeState = {
      layerState = {
        nametableStartAddr = 0x2000,
        nametableEndAddr = 0x23BF,
        patternTable = {
          ranges = {
            { bank = 1, page = 1, from = 0, to = 31 },
          },
        },
      },
    }
    local afterState = {
      layerState = {
        nametableStartAddr = 0x2000,
        nametableEndAddr = 0x23BF,
        patternTable = {
          ranges = {
            { bank = 1, page = 1, from = 0, to = 31 },
            { bank = 1, page = 2, from = 64, to = 79 },
          },
        },
      },
    }

    local changed = didChange(beforeState, afterState)
    expect(changed).toBe(true)
  end)

  it("PPU nametable and OAM use pattern-table jump menu; standalone pattern_table keeps CHR jump", function()
    local fullPattern256 = {
      ranges = {
        { bank = 1, page = 1, from = 0, to = 255 },
      },
    }

    local ptWin = {
      kind = "pattern_table",
      _id = "pt_unit",
      _closed = nil,
      cols = 16,
      rows = 16,
      activeLayer = 1,
      layers = {
        { kind = "tile", mode = "8x8", patternTable = fullPattern256 },
      },
      getActiveLayerIndex = function() return 1 end,
    }

    local app = setmetatable({
      wm = {
        getWindows = function()
          return { ptWin }
        end,
      },
    }, AppCoreController)

    local function findNavigateLabel(items)
      for _, it in ipairs(items or {}) do
        if it.menuGroup == "sel_chr_navigate" and type(it.text) == "string" and it.text:find("^[Ss]elect in ") then
          return it.text
        end
      end
      return nil
    end

    local ptTileItems = app:_buildSelectInChrContextMenuItems({
      win = { kind = "pattern_table", layers = {} },
      layerIndex = 1,
      layer = { kind = "tile" },
      col = 1,
      row = 2,
      item = { index = 5, _bankIndex = 1 },
      tileIndex = 5,
    })
    expect(findNavigateLabel(ptTileItems)).toBe("Select in CHR/ROM window")

    local oamItems = app:_buildSelectInChrContextMenuItems({
      win = { kind = "oam_animation", layers = {} },
      layerIndex = 1,
      layer = {
        kind = "sprite",
        linkedPatternTableWindowId = "pt_unit",
        patternTable = fullPattern256,
      },
      itemIndex = 1,
      item = { tile = 9 },
      tileIndex = 40,
    })
    expect(findNavigateLabel(oamItems)).toBe("Select in pattern table window")

    local ppuNtItems = app:_buildPpuTileContextMenuItems({
      win = { kind = "ppu_frame" },
      layer = {
        kind = "tile",
        linkedPatternTableWindowId = "pt_unit",
        patternTable = fullPattern256,
      },
      byteVal = 9,
      tileIndex = 12,
      col = 0,
      row = 0,
    })
    local function findPpuNav(items)
      for _, it in ipairs(items or {}) do
        if it.menuGroup == "ppt_selection" and type(it.text) == "string" and it.text:find("^[Ss]elect in ") then
          return it.text
        end
      end
      return nil
    end
    expect(findPpuNav(ppuNtItems)).toBe("Select in pattern table window")
  end)
end)
