local AppCoreController = require("controllers.app.core_controller")
local WM = require("controllers.window.window_controller")
local ToolbarController = require("controllers.window.toolbar_controller")
local WindowCaps = require("controllers.window.window_capabilities")
local TaskbarHelpers = require("user_interface.taskbar.helpers")

describe("sketch canvas - New Window + toolbar shell", function()
  it("includes Sketch canvas in New Window options and creates a sketch_canvas window", function()
    local created = nil
    local prevFocused = { title = "prev" }
    local app = setmetatable({
      hasLoadedROM = function()
        return true
      end,
      wm = {
        getFocus = function()
          return prevFocused
        end,
        createSketchCanvasWindow = function(_, opts)
          created = {
            kind = "sketch_canvas",
            title = opts and opts.title or "Sketch canvas",
            layers = {
              {
                kind = "canvas",
                canvas = { width = 256, height = 240 },
              },
            },
          }
          return created
        end,
      },
      undoRedo = {
        addWindowCreateEvent = function()
          return true
        end,
      },
    }, AppCoreController)

    local options = app:_buildNewWindowOptions()
    local sketchOpt = nil
    for _, opt in ipairs(options) do
      if opt.text == "Sketch canvas window" then
        sketchOpt = opt
        break
      end
    end

    expect(sketchOpt).toBeTruthy()
    expect(sketchOpt.skipSettingsModal).toBe(true)
    expect(sketchOpt.buttonText).toBe("Sketch canvas")
    expect(type(sketchOpt.callback)).toBe("function")

    sketchOpt.callback(nil, nil, nil, "My sketch")
    expect(created).toBeTruthy()
    expect(created.kind).toBe("sketch_canvas")
    expect(created.title).toBe("My sketch")
  end)

  it("creates a real Sketch canvas window at 256x240 via the window manager", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow({ title = "Sketch canvas" })
    expect(win).toBeTruthy()
    expect(win.kind).toBe("sketch_canvas")
    expect(WindowCaps.isSketchCanvas(win)).toBe(true)
    expect(win.title).toBe("Sketch canvas")
    local w, h = win:getContentSize()
    expect(w).toBe(256)
    expect(h).toBe(240)
  end)

  it("builds a sketch toolbar shell with Link, Tolerance, Generate controls (no Reflect button)", function()
    local wm = WM.new()
    local win = wm:createSketchCanvasWindow()
    local ctx = { app = { setStatus = function() end } }
    local toolbar = ToolbarController.createSpecializedToolbar(win, ctx, wm)
    local colors = require("app_colors")

    expect(toolbar).toBeTruthy()
    expect(toolbar.linkButton).toBeTruthy()
    expect(toolbar.toleranceDownButton).toBeTruthy()
    expect(toolbar.toleranceUpButton).toBeTruthy()
    expect(toolbar.generateButton).toBeTruthy()
    expect(toolbar.reflectButton).toBeNil()

    expect(toolbar.linkButton.enabled).toBe(true)
    expect(toolbar.linkButton.bgColor).toBe(colors.gray20)
    expect(toolbar.toleranceDownButton.enabled).toBe(false) -- tolerance starts at 0
    expect(toolbar.toleranceUpButton.enabled).toBe(true)
    expect(toolbar.generateButton.enabled).toBe(false) -- needs linked pattern table

    expect(toolbar.linkButton.tooltip:find("Link", 1, true)).toBeTruthy()
    expect(toolbar.generateButton.tooltip:find("linked pattern table", 1, true)).toBeTruthy()

    local pt = wm:createPatternTableWindow()
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    assert(SketchCanvasPackController.linkSketchToPatternTable(win, pt, wm))
    toolbar:updateIcons()
    expect(toolbar.linkButton.bgColor).toBe(colors.green)
    expect(toolbar.linkButton.tooltip:find("Manage", 1, true)).toBeTruthy()
    expect(toolbar.generateButton.enabled).toBe(true)
  end)

  it("maps sketch_canvas windows to the sketch taskbar icon key", function()
    expect(TaskbarHelpers.getTaskbarIconKeyForWindow({ kind = "sketch_canvas" })).toBe("sketch_canvas")
  end)
end)
