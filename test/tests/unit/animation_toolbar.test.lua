local AnimationWindow = require("user_interface.windows_system.animation_window")
local AnimationToolbar = require("user_interface.toolbars.animation_toolbar")

describe("animation_window.lua - copyTilesFromPreviousLayer", function()
  it("copies tile items and metadata from previous layer into active layer", function()
    local win = AnimationWindow.new(0, 0, 8, 8, 2, 2, 1, { title = "anim" })
    win.layers = {}
    win:addLayer({ kind = "tile" })
    win:addLayer({ kind = "tile" })
    win.activeLayer = 2

    local prev = win.layers[1]
    prev.items = { [1] = "A", [3] = "B" }
    prev.paletteNumbers = { [0] = 1, [5] = 2 }
    prev.removedCells = { [4] = true }

    local curr = win.layers[2]
    curr.items = { [5] = "old" }
    curr.paletteNumbers = { [0] = 9 }
    curr.removedCells = { [1] = true }

    local ok = win:copyTilesFromPreviousLayer()
    expect(ok).toBe(true)

    expect(curr.items).toNotBe(prev.items)
    expect(curr.items[1]).toBe("A")
    expect(curr.items[3]).toBe("B")
    expect(curr.items[5]).toBeNil() -- old entry cleared

    expect(curr.paletteNumbers).toNotBe(prev.paletteNumbers)
    expect(curr.paletteNumbers[0]).toBe(1)
    expect(curr.paletteNumbers[5]).toBe(2)

    expect(curr.removedCells).toNotBe(prev.removedCells)
    expect(curr.removedCells[4]).toBe(true)
    expect(curr.removedCells[1]).toBeNil()
  end)

  it("copies sprite items from previous layer into active layer", function()
    local win = AnimationWindow.new(0, 0, 8, 8, 2, 2, 1, { title = "sprites" })
    win.layers = {}
    win:addLayer({ kind = "sprite", mode = "8x16" })
    win:addLayer({ kind = "sprite", mode = "8x16" })
    win.activeLayer = 2

    local prev = win.layers[1]
    prev.items = {
      { bank = 0, tile = 1, x = 4, y = 8, paletteNumber = 3, mirrorX = true },
      { bank = 1, tile = 2, x = 12, y = 16, tileBelow = 3, dx = 2, dy = -1, removed = true },
    }

    local curr = win.layers[2]
    curr.items = { { bank = 9, tile = 9 } }
    curr.hoverSpriteIndex = 1
    curr.selectedSpriteIndex = 1
    curr.multiSpriteSelection = { [1] = true }

    local ok = win:copyTilesFromPreviousLayer()
    expect(ok).toBe(true)

    expect(curr.items).toNotBe(prev.items)
    expect(#curr.items).toBe(2)
    expect(curr.items[1]).toNotBe(prev.items[1])
    expect(curr.items[1].bank).toBe(0)
    expect(curr.items[1].mirrorX).toBe(true)
    expect(curr.items[2].tileBelow).toBe(3)
    expect(curr.hoverSpriteIndex).toBeNil()
    expect(curr.multiSpriteSelection).toBeNil()
  end)

  it("returns false when no previous layer exists", function()
    local win = AnimationWindow.new(0, 0, 8, 8, 1, 1, 1, { title = "single" })
    win.layers = {}
    win:addLayer({ kind = "tile" })
    win.activeLayer = 1
    expect(win:copyTilesFromPreviousLayer()).toBe(false)
  end)
end)

describe("animation_toolbar.lua - copy button", function()
  it("invokes copy on the window and reports status", function()
    local copyCalled = false
    local status
    local win = {
      kind = "animation",
      getHeaderRect = function() return 0, 0, 20, 10 end,
      getActiveLayerIndex = function() return 2 end,
      getLayerCount = function() return 3 end,
      copyTilesFromPreviousLayer = function()
        copyCalled = true
        return true
      end,
    }
    local ctx = { setStatus = function(txt) status = txt end }
    local toolbar = AnimationToolbar.new(win, ctx, { getFocus = function() return win end })

    local copyButton
    for _, b in ipairs(toolbar.buttons) do
      if b.tooltip == "Copy previous layer" then
        copyButton = b
        break
      end
    end

    expect(copyButton).toBeTruthy()
    copyButton.action()
    expect(copyCalled).toBe(true)
    expect(status).toBe(nil)
  end)
end)

describe("animation_toolbar.lua - layer navigation", function()
  it("wraps next/previous layer navigation", function()
    local win = AnimationWindow.new(0, 0, 8, 8, 2, 2, 1, { title = "wrap-toolbar" })
    win.layers = {}
    win:addLayer({ kind = "tile" })
    win:addLayer({ kind = "tile" })
    win:addLayer({ kind = "tile" })
    win.activeLayer = 3

    local status
    local ctx = { setStatus = function(txt) status = txt end }
    local toolbar = AnimationToolbar.new(win, ctx, { getFocus = function() return win end })

    toolbar:_onNextLayer()
    expect(win:getActiveLayerIndex()).toBe(1)
    expect(status).toBe(nil)

    toolbar:_onPrevLayer()
    expect(win:getActiveLayerIndex()).toBe(3)
    expect(status).toBe(nil)
  end)
end)

describe("animation_toolbar.lua - OAM add sprite", function()
  it("adds an OAM-only add-sprite button and opens the shared add sprite modal", function()
    local addCalls = 0
    local win = {
      kind = "oam_animation",
      getHeaderRect = function() return 0, 0, 20, 10 end,
      getActiveLayerIndex = function() return 1 end,
      getLayerCount = function() return 2 end,
      layers = {
        { kind = "sprite", items = {} },
        { kind = "sprite", items = {} },
      },
    }
    local ctx = {
      app = {
        showPpuFrameAddSpriteModal = function(_, targetWindow)
          addCalls = addCalls + 1
          expect(targetWindow).toBe(win)
          return true
        end,
      },
      setStatus = function() end,
    }

    local toolbar = AnimationToolbar.new(win, ctx, { getFocus = function() return win end })
    expect(toolbar.addSpriteButton).toBeTruthy()

    toolbar.addSpriteButton.action()
    expect(addCalls).toBe(1)
  end)
end)

describe("window selection persistence per layer", function()
  it("remembers tile selections independently for each layer", function()
    local win = AnimationWindow.new(0, 0, 8, 8, 4, 4, 1, { title = "sel" })
    win.layers = {}
    win:addLayer({ kind = "tile" })
    win:addLayer({ kind = "tile" })

    win:setActiveLayerIndex(1)
    win:setSelected(1, 1, 1)
    win:setActiveLayerIndex(2)
    win:setSelected(3, 2, 2)

    win:setActiveLayerIndex(1)
    local c1, r1, l1 = win:getSelected()
    expect(c1).toBe(1)
    expect(r1).toBe(1)
    expect(l1).toBe(1)

    win:setActiveLayerIndex(2)
    local c2, r2, l2 = win:getSelected()
    expect(c2).toBe(3)
    expect(r2).toBe(2)
    expect(l2).toBe(2)
  end)

  it("keeps selections aligned after inserting and removing layers", function()
    local win = AnimationWindow.new(0, 0, 8, 8, 4, 4, 1, { title = "sel-shift" })
    win.layers = {}
    win:addLayer({ kind = "tile" })
    win:addLayer({ kind = "tile" })
    win:addLayer({ kind = "tile" })

    win:setSelected(0, 0, 1)
    win:setSelected(1, 1, 2)
    win:setSelected(2, 2, 3)

    win:setActiveLayerIndex(1)
    local inserted = win:addLayerAfterActive({ kind = "tile" })
    expect(inserted).toBe(2)

    win:setActiveLayerIndex(3)
    local cAfterInsert, rAfterInsert = win:getSelected()
    expect(cAfterInsert).toBe(1)
    expect(rAfterInsert).toBe(1)

    win:setActiveLayerIndex(4)
    local cLayer4, rLayer4 = win:getSelected()
    expect(cLayer4).toBe(2)
    expect(rLayer4).toBe(2)

    win:setActiveLayerIndex(2)
    local removed = win:removeActiveLayer()
    expect(removed).toBe(true)

    win:setActiveLayerIndex(2)
    local cAfterRemove, rAfterRemove = win:getSelected()
    expect(cAfterRemove).toBe(1)
    expect(rAfterRemove).toBe(1)
  end)
end)
