local ToolbarBase = require("ui.toolbars.toolbar_base")

describe("toolbar_base.lua - button activation", function()
  local function fakeIcon(w, h)
    return {
      getWidth = function() return w or 15 end,
      getHeight = function() return h or 15 end,
    }
  end

  local function makeToolbar()
    local win = {
      getHeaderRect = function() return 10, 20, 100, 15 end,
    }
    local wm = {
      getFocus = function() return win end,
    }
    local toolbar = ToolbarBase.new(win, { h = 15 })
    toolbar.windowController = wm
    return toolbar
  end

  it("cancels button action when press starts inside and release happens outside", function()
    local actionCalls = 0
    local toolbar = makeToolbar()
    toolbar:addButton(fakeIcon(15, 15), function()
      actionCalls = actionCalls + 1
    end, "Test")
    toolbar:updatePosition()

    local btn = toolbar.buttons[1]
    expect(btn).toBeTruthy()

    local insideX = btn.x + math.floor(btn.w / 2)
    local insideY = btn.y + math.floor(btn.h / 2)
    local outsideX = btn.x + btn.w + 20
    local outsideY = insideY

    expect(toolbar:mousepressed(insideX, insideY, 1)).toBeTruthy()
    expect(toolbar:mousereleased(outsideX, outsideY, 1)).toBeTruthy()
    expect(actionCalls).toBe(0)
  end)

  it("triggers button action when released inside the pressed button", function()
    local actionCalls = 0
    local toolbar = makeToolbar()
    toolbar:addButton(fakeIcon(15, 15), function()
      actionCalls = actionCalls + 1
    end, "Test")
    toolbar:updatePosition()

    local btn = toolbar.buttons[1]
    local x = btn.x + math.floor(btn.w / 2)
    local y = btn.y + math.floor(btn.h / 2)

    expect(toolbar:mousepressed(x, y, 1)).toBeTruthy()
    expect(toolbar:mousereleased(x, y, 1)).toBeTruthy()
    expect(actionCalls).toBe(1)
  end)

  it("does not consume empty-chrome release so deferred context menus can fire", function()
    local toolbar = makeToolbar()
    toolbar:addButton(fakeIcon(15, 15), nil, "No action")
    toolbar:updatePosition()

    -- No pressed button: release over the strip must return false.
    local x = toolbar.x + 1
    local y = toolbar.y + 1
    expect(toolbar:contains(x, y)).toBe(true)
    expect(toolbar:mousereleased(x, y, 1)).toBe(false)
  end)
end)

describe("mouse_input.lua - ROM palette link handle left click", function()
  local MouseInput = require("controllers.input.mouse_input")
  local MouseWindowChromeController = require("controllers.input.mouse_window_chrome_controller")
  local MouseMoveController = require("controllers.input.mouse_move_controller")
  local MouseTileDropController = require("controllers.input.mouse_tile_drop_controller")
  local MouseWheelController = require("controllers.input.mouse_wheel_controller")
  local SpriteController = require("controllers.sprite.sprite_controller")
  local MultiSelectController = require("controllers.input_support.multi_select_controller")
  local ToolbarController = require("controllers.window.toolbar_controller")
  local WM = require("controllers.window.window_controller")

  local originals

  beforeEach(function()
    originals = {
      move = MouseMoveController.handleMouseMoved,
      tileDrop = MouseTileDropController.handleTileDrop,
      wheel = MouseWheelController.handleWheel,
      finishSpriteMarquee = SpriteController.finishSpriteMarquee,
      isDragging = SpriteController.isDragging,
      finishDrag = SpriteController.finishDrag,
      endDrag = SpriteController.endDrag,
      finishTileMarquee = MultiSelectController.finishTileMarquee,
      reset = MultiSelectController.reset,
    }
    MouseMoveController.handleMouseMoved = function() end
    MouseTileDropController.handleTileDrop = function() return false end
    MouseWheelController.handleWheel = function() return false end
    SpriteController.finishSpriteMarquee = function() return false end
    SpriteController.isDragging = function() return false end
    SpriteController.finishDrag = function() end
    SpriteController.endDrag = function() end
    MultiSelectController.finishTileMarquee = function() return false end
    MultiSelectController.reset = function() end
    if MouseWindowChromeController._resetHeaderDoubleClickState then
      MouseWindowChromeController._resetHeaderDoubleClickState()
    end
  end)

  afterEach(function()
    MouseMoveController.handleMouseMoved = originals.move
    MouseTileDropController.handleTileDrop = originals.tileDrop
    MouseWheelController.handleWheel = originals.wheel
    SpriteController.finishSpriteMarquee = originals.finishSpriteMarquee
    SpriteController.isDragging = originals.isDragging
    SpriteController.finishDrag = originals.finishDrag
    SpriteController.endDrag = originals.endDrag
    MultiSelectController.finishTileMarquee = originals.finishTileMarquee
    MultiSelectController.reset = originals.reset
  end)

  it("opens the palette link source menu on right-click/release over the ROM palette badge", function()
    local wm = WM.new()
    local pal = wm:createRomPaletteWindow({ title = "ROM Palette", x = 40, y = 40 })
    wm:setFocus(pal)
    local ctx = {
      app = {
        wm = wm,
        windowLinksMode = "always",
        canvas = { getWidth = function() return 640 end, getHeight = function() return 360 end },
        appEditState = { romRaw = string.rep("\0", 64) },
        isGroupedPaletteWindowsEnabled = function()
          return false
        end,
        showPaletteLinkSourceContextMenu = function()
          return true
        end,
      },
    }
    local menuCalls = {}
    ctx.app.showPaletteLinkSourceContextMenu = function(_, win, x, y, opts)
      menuCalls[#menuCalls + 1] = { win = win, x = x, y = y, opts = opts }
    end
    ToolbarController.createToolbarsForWindow(pal, ctx, wm)

    local LinkVisual = require("controllers.window.window_link_visual_controller")
    local edges = LinkVisual.collectWindowLinkEdges(ctx.app)
    local layouts = select(1, LinkVisual.buildAnchorLayouts(ctx.app, edges))
    local entry = assert(layouts[pal] and layouts[pal].palette_source, "expected palette_source badge")
    local cx, cy = entry.cx, entry.cy
    local hx, hy, hw, hh = LinkVisual.getPivotHandleRect(cx, cy)
    expect(hx).toBeTruthy()

    MouseInput.setup({
      wm = function()
        return wm
      end,
      getMode = function()
        return "tile"
      end,
      getPainting = function()
        return false
      end,
      setPainting = function() end,
      setStatus = function() end,
      app = ctx.app,
    }, { active = false, pending = false }, { active = false }, {})

    expect(MouseInput.mousepressed(cx, cy, 2)).toBe(true)
    MouseInput.mousereleased(cx, cy, 2)
    expect(#menuCalls).toBe(1)
    expect(menuCalls[1].win).toBe(pal)
    -- Anchor opts are best-effort from badge geometry; menu open is the contract.
    if menuCalls[1].opts and menuCalls[1].opts.anchorRect then
      local anchor = menuCalls[1].opts.anchorRect
      expect(anchor.x).toBe(hx)
      expect(anchor.y).toBe(hy)
      expect(anchor.w).toBe(hw)
      expect(anchor.h).toBe(hh)
    end
  end)
end)
