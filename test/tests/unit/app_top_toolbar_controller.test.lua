local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")

describe("app_top_toolbar_controller.lua", function()
  it("routes Open quick button to open-project modal without ROM gating", function()
    local openCalls = 0
    local warningStatus = nil
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return false end,
      showOpenProjectModal = function()
        openCalls = openCalls + 1
      end,
      setStatus = function(_, text)
        warningStatus = text
      end,
      showToast = function()
      end,
    }

    AppTopToolbarController.syncLayout(app)
    local newButton = app._appTopQuickButtons.newWindow
    local openButton = app._appTopQuickButtons.open
    local saveButton = app._appTopQuickButtons.save
    local galleryButton = app._appTopQuickButtons.galleryRom
    expect(openButton).toBeTruthy()
    expect(newButton).toBeTruthy()
    expect(saveButton).toBeTruthy()
    expect(app._appTopQuickButtons.crtLens).toBe(nil)
    expect(app._appTopQuickButtons.nametableBreakpointCalc).toBe(nil)

    -- Full strip is visible without a ROM; project-only actions are disabled.
    expect(newButton.x).toBe(0)
    expect(openButton.x > newButton.x).toBe(true)
    expect(saveButton.x > openButton.x).toBe(true)
    expect(newButton.enabled).toBe(true)
    expect(openButton.enabled ~= false).toBe(true)
    expect(saveButton.enabled).toBe(false)
    expect(galleryButton.enabled).toBe(false)
    expect(galleryButton.tooltip:find("linked pattern table", 1, true)).toBeTruthy()
    expect(app._appTopQuickButtons.relocationPointerCalc).toBeTruthy()
    expect(app._appTopQuickButtons.relocationPointerCalc.x > galleryButton.x).toBe(true)

    local clickX = openButton.x + math.floor(openButton.w * 0.5)
    local clickY = openButton.y + math.floor(openButton.h * 0.5)
    expect(AppTopToolbarController.mousepressed(app, clickX, clickY, 1)).toBe(true)
    expect(openCalls).toBe(1)
    expect(warningStatus).toBe(nil)
  end)

  it("enables Save when a sketch window exists without a ROM", function()
    local saveCalls = 0
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return false end,
      wm = {
        getWindows = function()
          return { { kind = "sketch_canvas", _closed = false } }
        end,
      },
      showSaveOptionsModal = function()
        saveCalls = saveCalls + 1
      end,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    local saveButton = app._appTopQuickButtons.save
    expect(saveButton.enabled).toBe(true)

    local clickX = saveButton.x + math.floor(saveButton.w * 0.5)
    local clickY = saveButton.y + math.floor(saveButton.h * 0.5)
    expect(AppTopToolbarController.mousepressed(app, clickX, clickY, 1)).toBe(true)
    expect(saveCalls).toBe(1)
  end)

  it("enables Gallery ROM only when a packed sketch has a linked pattern table", function()
    local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
    local WM = require("controllers.window.window_controller")
    local wm = WM.new()
    local sketch = wm:createSketchCanvasWindow({ title = "Sketch" })
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return false end,
      wm = wm,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    expect(app._appTopQuickButtons.galleryRom.enabled).toBe(false)

    local canvas = sketch:getActiveCanvas()
    for y = 0, 7 do
      for x = 0, 7 do
        canvas:edit(x, y, 1)
      end
    end
    expect(SketchCanvasPackController.generate(sketch)).toBe(true)
    AppTopToolbarController.syncLayout(app)
    expect(app._appTopQuickButtons.galleryRom.enabled).toBe(false)

    local pt = wm:createPatternTableWindow({ title = "PT" })
    expect(SketchCanvasPackController.linkSketchToPatternTable(sketch, pt, wm)).toBe(true)
    expect(SketchCanvasPackController.generateAndApply(sketch, wm)).toBe(true)
    AppTopToolbarController.syncLayout(app)
    expect(app._appTopQuickButtons.galleryRom.enabled).toBe(true)
    expect(app._appTopQuickButtons.galleryRom.tooltip:find("from packed sketch", 1, true)).toBeTruthy()
  end)

  it("enables Mirror X for a focused sketch window without a ROM", function()
    local toggleCalls = 0
    local sketch = {
      kind = "sketch_canvas",
      _closed = false,
      _minimized = false,
      _collapsed = false,
      _mirrorXPreview = false,
    }
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return false end,
      wm = {
        getFocus = function()
          return sketch
        end,
        getWindows = function()
          return { sketch }
        end,
      },
      togglePreviewMirrorX = function(self)
        toggleCalls = toggleCalls + 1
        sketch._mirrorXPreview = not (sketch._mirrorXPreview == true)
        return true, sketch._mirrorXPreview == true
      end,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    local mirrorButton = app._appTopQuickButtons.mirrorXPreview
    expect(mirrorButton.enabled).toBe(true)
    expect(mirrorButton.bgColor).toBe(nil)

    local clickX = mirrorButton.x + math.floor(mirrorButton.w * 0.5)
    local clickY = mirrorButton.y + math.floor(mirrorButton.h * 0.5)
    expect(AppTopToolbarController.mousepressed(app, clickX, clickY, 1)).toBe(true)
    expect(toggleCalls).toBe(1)
    expect(sketch._mirrorXPreview).toBe(true)

    AppTopToolbarController.syncLayout(app)
    expect(app._appTopQuickButtons.mirrorXPreview.bgColor).toBeTruthy()
  end)

  it("keeps New first and orders Open / Save / ... when project is loaded", function()
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return true end,
      showOpenProjectModal = function() end,
      showNewWindowModal = function() end,
      showSaveOptionsModal = function() end,
      cloneFocusedWindow = function() end,
      resizeFocusedWindowGrid = function() end,
      getClipboardToolbarActionState = function()
        return { allowed = true }
      end,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    local newButton = app._appTopQuickButtons.newWindow
    local openButton = app._appTopQuickButtons.open
    local saveButton = app._appTopQuickButtons.save
    local cloneButton = app._appTopQuickButtons.cloneWindow
    local zoomOutButton = app._appTopQuickButtons.zoomOut
    local zoomInButton = app._appTopQuickButtons.zoomIn
    local addGridColumnButton = app._appTopQuickButtons.addGridColumn
    local addGridRowButton = app._appTopQuickButtons.addGridRow
    local copyButton = app._appTopQuickButtons.copy
    local cutButton = app._appTopQuickButtons.cut
    local pasteButton = app._appTopQuickButtons.paste
    local mirrorXButton = app._appTopQuickButtons.mirrorXPreview
    local alwaysOnTopButton = app._appTopQuickButtons.alwaysOnTop
    local relocationCalcButton = app._appTopQuickButtons.relocationPointerCalc

    expect(app._appTopQuickButtons.crtLens).toBe(nil)
    expect(app._appTopQuickButtons.nametableBreakpointCalc).toBe(nil)
    expect(newButton.x).toBe(0)
    expect(openButton.x > newButton.x).toBe(true)
    expect(saveButton.x > openButton.x).toBe(true)
    expect(copyButton.x > saveButton.x).toBe(true)
    expect(cutButton.x > copyButton.x).toBe(true)
    expect(pasteButton.x > cutButton.x).toBe(true)
    expect(zoomOutButton.x > pasteButton.x).toBe(true)
    expect(zoomInButton.x > zoomOutButton.x).toBe(true)
    expect(mirrorXButton.x > zoomInButton.x).toBe(true)
    expect(alwaysOnTopButton.x > mirrorXButton.x).toBe(true)
    expect(addGridColumnButton.x > alwaysOnTopButton.x).toBe(true)
    expect(addGridRowButton.x > addGridColumnButton.x).toBe(true)
    expect(cloneButton.x > addGridRowButton.x).toBe(true)
    expect(relocationCalcButton.x > cloneButton.x).toBe(true)

    local inferredGap = openButton.x - (newButton.x + newButton.w)
    expect(openButton.x).toBe(newButton.x + newButton.w + inferredGap)
    expect(saveButton.x).toBe(openButton.x + openButton.w + inferredGap)
    expect(copyButton.x).toBe(saveButton.x + saveButton.w + inferredGap)
    expect(cutButton.x).toBe(copyButton.x + copyButton.w + inferredGap)
    expect(pasteButton.x).toBe(cutButton.x + cutButton.w + inferredGap)
    expect(zoomOutButton.x).toBe(pasteButton.x + pasteButton.w + inferredGap)
    expect(zoomInButton.x).toBe(zoomOutButton.x + zoomOutButton.w + inferredGap)
    expect(mirrorXButton.x).toBe(zoomInButton.x + zoomInButton.w + inferredGap)
    expect(alwaysOnTopButton.x).toBe(mirrorXButton.x + mirrorXButton.w + inferredGap)
    expect(addGridColumnButton.x).toBe(alwaysOnTopButton.x + alwaysOnTopButton.w + inferredGap)
    expect(addGridRowButton.x).toBe(addGridColumnButton.x + addGridColumnButton.w + inferredGap)
    expect(cloneButton.x).toBe(addGridRowButton.x + addGridRowButton.w + inferredGap)
    local referenceButton = app._appTopQuickButtons.referenceBackground
    local galleryRomButton = app._appTopQuickButtons.galleryRom
    expect(referenceButton.x).toBe(cloneButton.x + cloneButton.w + inferredGap)
    expect(galleryRomButton).toBeTruthy()
    expect(galleryRomButton.x).toBe(referenceButton.x + referenceButton.w + inferredGap)
    expect(relocationCalcButton.x).toBe(galleryRomButton.x + galleryRomButton.w + inferredGap)
  end)

  it("routes copy/cut/paste buttons through shared app clipboard actions", function()
    local actions = {}
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return true end,
      showOpenProjectModal = function() end,
      showNewWindowModal = function() end,
      showSaveOptionsModal = function() end,
      performClipboardToolbarAction = function(_, action)
        actions[#actions + 1] = action
      end,
      getClipboardToolbarActionState = function()
        return { allowed = true }
      end,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    local copyButton = app._appTopQuickButtons.copy
    local cutButton = app._appTopQuickButtons.cut
    local pasteButton = app._appTopQuickButtons.paste

    local function click(button)
      local x = button.x + math.floor(button.w * 0.5)
      local y = button.y + math.floor(button.h * 0.5)
      expect(AppTopToolbarController.mousepressed(app, x, y, 1)).toBe(true)
      AppTopToolbarController.mousereleasedQuickButtons(app, x, y, 1)
    end

    click(copyButton)
    click(cutButton)
    click(pasteButton)

    expect(actions[1]).toBe("copy")
    expect(actions[2]).toBe("cut")
    expect(actions[3]).toBe("paste")
  end)

  it("updates clipboard button enabled state from capability checks", function()
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return true end,
      showOpenProjectModal = function() end,
      showNewWindowModal = function() end,
      showSaveOptionsModal = function() end,
      getClipboardToolbarActionState = function(_, action)
        if action == "paste" then
          return { allowed = false, reason = "Clipboard is empty" }
        end
        return { allowed = true }
      end,
      setStatus = function() end,
      showToast = function() end,
    }

    AppTopToolbarController.syncLayout(app)
    expect(app._appTopQuickButtons.copy.enabled).toBe(true)
    expect(app._appTopQuickButtons.cut.enabled).toBe(true)
    expect(app._appTopQuickButtons.paste.enabled).toBe(false)
  end)

  it("disables zoom quick buttons when focus is any palette window", function()
    local function makeApp(focus)
      return {
        canvas = {
          getWidth = function() return 640 end,
          getHeight = function() return 360 end,
        },
        separateToolbar = false,
        hasLoadedROM = function() return true end,
        showOpenProjectModal = function() end,
        showNewWindowModal = function() end,
        showSaveOptionsModal = function() end,
        wm = { getFocus = function() return focus end },
        getClipboardToolbarActionState = function()
          return { allowed = true }
        end,
        setStatus = function() end,
        showToast = function() end,
      }
    end

    local paletteCases = {
      { kind = "rom_palette", addZoomLevel = function() end },
      { kind = "palette", addZoomLevel = function() end },
      { isPalette = true, addZoomLevel = function() end },
    }
    for _, focus in ipairs(paletteCases) do
      focus._closed = false
      focus._minimized = false
      local app = makeApp(focus)
      AppTopToolbarController.syncLayout(app)
      expect(app._appTopQuickButtons.zoomOut.enabled).toBe(false)
      expect(app._appTopQuickButtons.zoomIn.enabled).toBe(false)
    end

    local chrFocus = {
      kind = "chr",
      _closed = false,
      _minimized = false,
      addZoomLevel = function() end,
    }
    local appChr = makeApp(chrFocus)
    AppTopToolbarController.syncLayout(appChr)
    expect(appChr._appTopQuickButtons.zoomOut.enabled).toBe(true)
    expect(appChr._appTopQuickButtons.zoomIn.enabled).toBe(true)
  end)

  it("disables zoom quick buttons when focus window is collapsed", function()
    local focus = {
      kind = "chr",
      _closed = false,
      _minimized = false,
      _collapsed = true,
      addZoomLevel = function() end,
    }
    local app = {
      canvas = {
        getWidth = function() return 640 end,
        getHeight = function() return 360 end,
      },
      separateToolbar = false,
      hasLoadedROM = function() return true end,
      showOpenProjectModal = function() end,
      showNewWindowModal = function() end,
      showSaveOptionsModal = function() end,
      wm = { getFocus = function() return focus end },
      getClipboardToolbarActionState = function()
        return { allowed = true }
      end,
      setStatus = function() end,
      showToast = function() end,
    }
    AppTopToolbarController.syncLayout(app)
    expect(app._appTopQuickButtons.zoomOut.enabled).toBe(false)
    expect(app._appTopQuickButtons.zoomIn.enabled).toBe(false)
  end)
end)
