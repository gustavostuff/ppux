local KeyboardClipboardController = require("controllers.input.keyboard_clipboard_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local ClipboardNative = require("utils.ppux_clipboard_native")

describe("OAM animation OS clipboard image paste", function()
  local originalGetImageData
  local originalImport

  local function makeOamWindow()
    return {
      kind = "oam_animation",
      layers = {
        {
          kind = "sprite",
          items = {
            { id = "sprite-a" },
          },
        },
      },
      getActiveLayerIndex = function()
        return 1
      end,
    }
  end

  local function makeCtx(win)
    local ctx = {
      statusText = nil,
      app = {
        showToast = function() end,
      },
    }
    function ctx.getMode()
      return "tile"
    end
    function ctx.getFocus()
      return win
    end
    function ctx.setStatus(text)
      ctx.statusText = text
    end
    return ctx
  end

  beforeEach(function()
    KeyboardClipboardController.reset()
    originalGetImageData = ClipboardNative.getImageData
    originalImport = SpriteController.importSpriteImageData
  end)

  afterEach(function()
    ClipboardNative.getImageData = originalGetImageData
    SpriteController.importSpriteImageData = originalImport
  end)

  it("enables OAM paste without reading the OS clipboard", function()
    local reads = 0
    ClipboardNative.getImageData = function()
      reads = reads + 1
      return nil, "no_image"
    end
    local win = makeOamWindow()
    local paste = KeyboardClipboardController.getActionAvailability(makeCtx(win), win, "paste")
    local copy = KeyboardClipboardController.getActionAvailability(makeCtx(win), win, "copy")

    expect(paste.allowed).toBe(true)
    expect(paste.oamOsImage).toBe(true)
    expect(copy.allowed).toBe(false)
    expect(copy.reason).toBe("Cannot copy sprites in OAM animation windows")
    expect(reads).toBe(0)
  end)

  it("pastes a clipboard image through the sprite importer", function()
    local image = { id = "clipboard-image" }
    local calls = {}
    ClipboardNative.getImageData = function()
      return image
    end
    SpriteController.importSpriteImageData = function(app, img, win)
      calls[#calls + 1] = { app = app, img = img, win = win }
      return true
    end
    local win = makeOamWindow()
    local ctx = makeCtx(win)

    expect(KeyboardClipboardController.performClipboardAction(ctx, win, "paste")).toBe(true)
    expect(#calls).toBe(1)
    expect(calls[1].img).toBe(image)
    expect(calls[1].win).toBe(win)
    expect(calls[1].app).toBe(ctx.app)
    expect(win.layers[1].items[1].id).toBe("sprite-a")
  end)

  it("leaves sprites unchanged when the clipboard has no image", function()
    local calls = 0
    ClipboardNative.getImageData = function()
      return nil, "no_image"
    end
    SpriteController.importSpriteImageData = function()
      calls = calls + 1
      return true
    end
    local win = makeOamWindow()
    local ctx = makeCtx(win)

    expect(KeyboardClipboardController.performClipboardAction(ctx, win, "paste")).toBe(true)
    expect(calls).toBe(0)
    expect(ctx.statusText).toBe("No image on the clipboard")
    expect(win.layers[1].items[1].id).toBe("sprite-a")
  end)

  it("reports a missing clipboard library and a decode failure", function()
    local win = makeOamWindow()
    ClipboardNative.getImageData = function()
      return nil, "unavailable"
    end
    local ctx = makeCtx(win)
    KeyboardClipboardController.performClipboardAction(ctx, win, "paste")
    expect(ctx.statusText).toBe("Image clipboard is unavailable")

    ClipboardNative.getImageData = function()
      return nil, "bad png"
    end
    KeyboardClipboardController.performClipboardAction(ctx, win, "paste")
    expect(ctx.statusText).toBe("Failed to read clipboard image: bad png")
  end)

  it("does not ask for an OS image from a non-OAM window", function()
    local reads = 0
    ClipboardNative.getImageData = function()
      reads = reads + 1
      return { id = "should-not-be-read" }
    end
    local win = {
      kind = "static_art",
      layers = {
        { kind = "tile", items = {} },
      },
      getActiveLayerIndex = function()
        return 1
      end,
    }
    local ctx = makeCtx(win)
    KeyboardClipboardController.performClipboardAction(ctx, win, "paste")
    expect(reads).toBe(0)
    expect(ctx.statusText).toBe("Clipboard is empty")
  end)

  it("keeps PPU frame sprite paste blocked", function()
    local reads = 0
    local toast = nil
    ClipboardNative.getImageData = function()
      reads = reads + 1
      return { id = "image" }
    end
    local win = {
      kind = "ppu_frame",
      layers = {
        {
          kind = "sprite",
          items = { { id = "ppu-sprite" } },
        },
      },
      getActiveLayerIndex = function()
        return 1
      end,
    }
    local ctx = makeCtx(win)
    ctx.app.showToast = function(_, kind, text)
      toast = kind .. ":" .. text
    end

    KeyboardClipboardController.performClipboardAction(ctx, win, "paste")
    expect(reads).toBe(0)
    expect(ctx.statusText).toBe("Cannot paste sprites in PPU frame windows")
    expect(toast).toBe("warning:Cannot paste sprites in PPU frame windows")
  end)

  it("accepts Ctrl+V on an OAM window in edit mode", function()
    local reads = 0
    ClipboardNative.getImageData = function()
      reads = reads + 1
      return nil, "no_image"
    end
    local win = makeOamWindow()
    local ctx = makeCtx(win)
    ctx.getMode = function()
      return "edit"
    end
    local utils = {
      ctrlDown = function() return true end,
      shiftDown = function() return false end,
      altDown = function() return false end,
    }

    expect(KeyboardClipboardController.handlePasteSelection(ctx, utils, "v", win)).toBe(true)
    expect(reads).toBe(1)
    expect(ctx.statusText).toBe("No image on the clipboard")
  end)
end)
