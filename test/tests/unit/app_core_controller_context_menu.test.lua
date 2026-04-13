local AppCoreController = require("controllers.app.core_controller")
local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")

describe("core_controller.lua - contextual menu helpers", function()
  it("shows the shared new window modal when a ROM is loaded", function()
    local shownTitle = nil
    local shownOptions = nil
    local app = setmetatable({
      hasLoadedROM = function() return true end,
      newWindowModal = {
        show = function(_, title, options)
          shownTitle = title
          shownOptions = options
        end,
      },
    }, AppCoreController)

    local ok = app:showNewWindowModal()

    expect(ok).toBe(true)
    expect(shownTitle).toBe("New Window")
    expect(type(shownOptions)).toBe("table")
    expect(#shownOptions).toBe(7)
    expect(shownOptions[1].text).toBe("Static Art window (tiles)")
    expect(shownOptions[4].text).toBe("Animation window  (sprites)")
    expect(shownOptions[5].text).toBe("Palette window")
    expect(shownOptions[6].text).toBe("ROM Palette window")
    expect(shownOptions[7].text).toBe("Pattern Table Builder")
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
    local app = setmetatable({}, AppCoreController)
    local items = app:_buildWindowHeaderContextMenuItems({
      _closed = false,
      _minimized = false,
    })

    expect(#items).toBe(3)
    expect(items[1].text).toBe("Close")
    expect(items[2].text).toBe("Collapse")
    expect(items[3].text).toBe("Minimize")
    expect(items[1].enabled).toBe(true)
    expect(items[2].enabled).toBe(true)
    expect(items[3].enabled).toBe(true)
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

    expect(#items).toBe(3)
    expect(items[1].text).toBe("New Window")
    expect(items[2].text).toBe("Minimize all")
    expect(items[3].text).toBe("Collapse all")
    expect(items[1].enabled).toBe(true)
    expect(items[2].enabled).toBe(true)
    expect(items[3].enabled).toBe(true)
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
end)
