local GameArtLayoutIOController = require("controllers.game_art.layout_io_controller")
local GameArtWindowBuilderController = require("controllers.game_art.window_builder_controller")
local DebugController = require("controllers.dev.debug_controller")

describe("game_art_layout_io_controller.lua", function()
  local originalPrint
  local originalDebugIsEnabled
  local originalDebugLog
  local tmpCounter = 0
  local createdPaths

  local function nextTmpPath(tag)
    tmpCounter = tmpCounter + 1
    return string.format("/tmp/ppux_%s_%d.lua", tag, tmpCounter)
  end

  beforeEach(function()
    createdPaths = {}
    originalPrint = _G.print
    originalDebugIsEnabled = DebugController.isEnabled
    originalDebugLog = DebugController.log
    _G.print = function() end
    DebugController.isEnabled = function() return true end
    DebugController.log = function() end
  end)

  afterEach(function()
    _G.print = originalPrint
    DebugController.isEnabled = originalDebugIsEnabled
    DebugController.log = originalDebugLog
    for _, path in ipairs(createdPaths or {}) do
      os.remove(path)
    end
  end)

  it("decodes and sorts userDefinedCode entries while normalizing invalid black codes", function()
    local decoded = GameArtLayoutIOController.decodeUserDefinedCodes("30,2,1;0e,1,3;1f,0,1;BAD;16,1,1")
    expect(decoded).toBeTruthy()
    expect(#decoded).toBe(4)
    expect(decoded[1]).toEqual({ code = "0F", col = 0, row = 1 })
    expect(decoded[2]).toEqual({ code = "16", col = 1, row = 1 })
    expect(decoded[3]).toEqual({ code = "30", col = 2, row = 1 })
    expect(decoded[4]).toEqual({ code = "0F", col = 1, row = 3 })
  end)

  it("round-trips layouts through saveLayoutLua/loadLayoutLua", function()
    local path = nextTmpPath("layout_io")
    table.insert(createdPaths, path)

    local layout = {
      currentBank = 2,
      windows = {
        { id = "bank", kind = "chr", title = "CHR banks", currentBank = 2, layers = { { items = {} } } },
        { id = "pal", kind = "palette", title = "Global", items = { { col = 0, row = 0, code = "0F" } } },
      },
    }

    local ok, err = GameArtLayoutIOController.saveLayoutLua(path, layout)
    expect(ok).toBeTruthy()
    expect(err).toBeNil()

    local loaded, loadErr = GameArtLayoutIOController.loadLayoutLua(path)
    expect(loadErr).toBeNil()
    expect(loaded).toEqual(layout)
  end)

  it("loads project files without a leading return and defaults kind to project", function()
    local path = nextTmpPath("project_io")
    table.insert(createdPaths, path)

    local wrote, writeErr = GameArtLayoutIOController.writeFile(path, "{ windows = {}, currentBank = 1 }")
    expect(wrote).toBeTruthy()
    expect(writeErr).toBeNil()

    local project, err = GameArtLayoutIOController.loadProjectLua(path)
    expect(err).toBeNil()
    expect(project).toBeTruthy()
    expect(project.kind).toBe("project")
    expect(project.projectVersion).toBe(GameArtLayoutIOController.PROJECT_FORMAT_VERSION)
    expect(type(project.windows)).toBe("table")
    expect(#project.windows).toBe(0)
  end)

  it("round-trips projects through saveProjectLua/loadProjectLua", function()
    local path = nextTmpPath("project_roundtrip")
    table.insert(createdPaths, path)

    local project = {
      kind = "project",
      projectVersion = 999, -- save path should normalize to current version
      currentBank = 3,
      windows = {
        { id = "bank", kind = "chr", currentBank = 3, layers = { { items = {} } } },
      },
      edits = { banks = {} },
      syncDuplicateTiles = true,
      currentColor = 4,
      paletteGroupState = {
        version = 1,
        enabled = true,
        global = {
          activeSourceWindowId = "palette_01",
          activeIndex = 1,
          logicalWindow = { x = 11, y = 22 },
        },
        rom = {
          activeSourceWindowId = "rom_palette_01",
          activeIndex = 1,
          logicalWindow = { x = 33, y = 44 },
        },
      },
    }

    local ok, err = GameArtLayoutIOController.saveProjectLua(path, project)
    expect(ok).toBeTruthy()
    expect(err).toBeNil()

    local loaded, loadErr = GameArtLayoutIOController.loadProjectLua(path)
    expect(loadErr).toBeNil()
    project.projectVersion = GameArtLayoutIOController.PROJECT_FORMAT_VERSION
    expect(loaded).toEqual(project)
  end)

  it("round-trips projects through saveProjectPpux/loadProjectPpux", function()
    local path = string.format("/tmp/ppux_project_roundtrip_%d.ppux", tmpCounter + 1)
    tmpCounter = tmpCounter + 1
    table.insert(createdPaths, path)

    local project = {
      kind = "project",
      currentBank = 2,
      windows = {
        { id = "bank", kind = "chr", currentBank = 2, layers = { { items = {} } } },
      },
      edits = { banks = {} },
    }

    local ok, err = GameArtLayoutIOController.saveProjectPpux(path, project)
    expect(ok).toBeTruthy()
    expect(err).toBeNil()

    local loaded, loadErr = GameArtLayoutIOController.loadProjectPpux(path)
    expect(loadErr).toBeNil()
    project.projectVersion = GameArtLayoutIOController.PROJECT_FORMAT_VERSION
    expect(loaded).toEqual(project)
  end)

  it("writes distinct lua text and ppux binary project files side by side", function()
    local luaPath = nextTmpPath("project_dual_artifacts")
    local ppuxPath = luaPath:gsub("%.lua$", ".ppux")
    table.insert(createdPaths, luaPath)
    table.insert(createdPaths, ppuxPath)

    local project = {
      kind = "project",
      currentBank = 2,
      windows = {
        { id = "bank", kind = "chr", currentBank = 2, layers = { { items = {} } } },
      },
      edits = { banks = {} },
    }

    local okLua, errLua = GameArtLayoutIOController.saveProjectLua(luaPath, project)
    local okPpux, errPpux = GameArtLayoutIOController.saveProjectPpux(ppuxPath, project)

    expect(okLua).toBeTruthy()
    expect(errLua).toBeNil()
    expect(okPpux).toBeTruthy()
    expect(errPpux).toBeNil()

    local luaFile = assert(io.open(luaPath, "rb"))
    local luaBytes = assert(luaFile:read("*a"))
    luaFile:close()

    local ppuxFile = assert(io.open(ppuxPath, "rb"))
    local ppuxBytes = assert(ppuxFile:read("*a"))
    ppuxFile:close()

    expect(type(luaBytes)).toBe("string")
    expect(type(ppuxBytes)).toBe("string")
    expect(#luaBytes).toBeGreaterThan(0)
    expect(#ppuxBytes).toBeGreaterThan(0)
    expect(luaBytes:match("^%s*{") or luaBytes:match("^%s*return%s")).toNotBe(nil)
    expect(ppuxBytes).toNotBe(luaBytes)
  end)

  it("migrates legacy project tables without projectVersion", function()
    local migrated, err = GameArtLayoutIOController.migrateProjectTable({
      kind = "project",
      windows = {},
      currentBank = 1,
    })

    expect(err).toBeNil()
    expect(migrated).toBeTruthy()
    expect(migrated.projectVersion).toBe(GameArtLayoutIOController.PROJECT_FORMAT_VERSION)
  end)

  it("rejects unsupported future project versions", function()
    local path = nextTmpPath("project_future_version")
    table.insert(createdPaths, path)

    local wrote, writeErr = GameArtLayoutIOController.writeFile(
      path,
      "return { kind = 'project', projectVersion = 999, windows = {} }"
    )
    expect(wrote).toBeTruthy()
    expect(writeErr).toBeNil()

    local project, err = GameArtLayoutIOController.loadProjectLua(path)
    expect(project).toBeNil()
    expect(type(err)).toBe("string")
    expect(string.find(err, "Unsupported project version", 1, true)).toNotBe(nil)
  end)

  it("stores pattern sketch canvas snapshots in the layer edits field and restores them", function()
    local wm = require("controllers.window.window_controller").new()
    local win = wm:createPatternSketchCanvasWindow({ title = "PTB" })
    win._id = "ptb_01"
    win.layers[1].canvas:edit(0, 0, 1)
    win.layers[1].canvas:edit(9, 0, 2)
    win.layers[1].canvas:edit(5, 7, 3)

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    local entry = snapshot.windows[1]
    expect(entry.kind).toBe("pattern_sketch_canvas")
    expect(#entry.layers).toBe(1)
    expect(entry.layers[1].edits).toBeTruthy()
    expect(entry.layers[1].edits.kind).toBe("canvas_snapshot")
    expect(entry.layers[1].edits.encoding).toBe("2bpp_v1")
    expect(type(entry.layers[1].edits.data)).toBe("string")

    local built = GameArtWindowBuilderController.buildWindowsFromLayout(snapshot, {
      wm = require("controllers.window.window_controller").new(),
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
      decodePatternCanvasSnapshot = GameArtLayoutIOController.decodePatternCanvasSnapshot,
    })

    local restored = built.windowsById["ptb_01"]
    expect(restored).toBeTruthy()
    expect(restored.kind).toBe("pattern_sketch_canvas")
    expect(restored.layers[1].canvas:getPixel(0, 0)).toBe(1)
    expect(restored.layers[1].canvas:getPixel(9, 0)).toBe(2)
    expect(restored.layers[1].canvas:getPixel(5, 7)).toBe(3)
  end)

  it("snapshots pattern_table windows with compact from/to ranges, not per-tile items", function()
    local wm = require("controllers.window.window_controller").new()
    local win = wm:createPatternTableWindow({ title = "PT" })
    win._id = "pt_compact_save"
    local layer = win.layers[1]
    layer.patternTable = {
      ranges = {
        {
          tiles = {
            { bank = 1, tileIndex = 0 },
            { bank = 1, tileIndex = 1 },
            { bank = 1, tileIndex = 2 },
          },
        },
      },
    }

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    local entry = snapshot.windows[1]
    expect(entry.kind).toBe("pattern_table")
    expect(#entry.layers).toBe(1)
    expect(entry.layers[1].items).toEqual({})
    expect(entry.layers[1].patternTable.ranges[1]).toEqual({ bank = 1, from = 0, to = 2 })
    expect(entry.layers[1].patternTable.ranges[1].tiles).toBeNil()
  end)

  it("reports pattern sketch canvas snapshot restore failures", function()
    local wm = require("controllers.window.window_controller").new()
    local win = wm:createPatternSketchCanvasWindow({ title = "PTB Hash" })
    win._id = "ptb_hash"
    win.layers[1].canvas:edit(0, 0, 1)

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    snapshot.windows[1].layers[1].edits.hash = "invalid_hash_value"

    local restoreError = nil
    local built = GameArtWindowBuilderController.buildWindowsFromLayout(snapshot, {
      wm = require("controllers.window.window_controller").new(),
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
      decodePatternCanvasSnapshot = GameArtLayoutIOController.decodePatternCanvasSnapshot,
      onPatternCanvasRestoreError = function(info)
        restoreError = info
      end,
    })

    expect(built).toBeTruthy()
    expect(restoreError).toBeTruthy()
    expect(restoreError.layerIndex).toBe(1)
    expect(restoreError.reason).toBe("snapshot_hash_mismatch")
    expect(restoreError.windowSpec.title).toBe("PTB Hash")
  end)

  it("persists ROM palette compact mode through layout snapshot and rebuild", function()
    local wm = require("controllers.window.window_controller").new()
    local win = wm:createRomPaletteWindow({ title = "ROM Palette Compact", compactView = true })
    win._id = "rom_palette_compact"

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    local entry = snapshot.windows[1]
    expect(entry.kind).toBe("rom_palette")
    expect(entry.compactView).toBe(true)

    local built = GameArtWindowBuilderController.buildWindowsFromLayout(snapshot, {
      wm = require("controllers.window.window_controller").new(),
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = string.rep(string.char(0x0F), 64),
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
    })

    local restored = built.windowsById["rom_palette_compact"]
    expect(restored).toBeTruthy()
    expect(restored.compactView).toBe(true)
    expect(restored.cellW).toBe(20)
    expect(restored.cellH).toBe(14)
  end)

  it("persists mirror X preview through layout snapshot and rebuild", function()
    local WM = require("controllers.window.window_controller")
    local wm = WM.new()
    local win = wm:createTileWindow({
      title = "Mirror persistence",
      cols = 8,
      rows = 8,
      numLayers = 1,
    })
    win._id = "mirror_persist_win"
    win._mirrorXPreview = true

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    expect(snapshot.windows[1].mirrorXPreview).toBe(true)

    local built = GameArtWindowBuilderController.buildWindowsFromLayout(snapshot, {
      wm = WM.new(),
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
    })

    local restored = built.windowsById["mirror_persist_win"]
    expect(restored).toBeTruthy()
    expect(restored._mirrorXPreview).toBe(true)
  end)

  it("persists OAM animation sprite origin guides through layout snapshot and rebuild", function()
    local WM = require("controllers.window.window_controller")
    local wm = WM.new()
    local win = wm:createSpriteWindow({
      animated = true,
      oamBacked = true,
      numFrames = 1,
      cols = 16,
      rows = 14,
      spriteMode = "8x8",
      title = "OAM Guides",
    })
    win._id = "oam_guides"
    win.showSpriteOriginGuides = true

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1)
    local entry = snapshot.windows[1]
    expect(entry.kind).toBe("oam_animation")
    expect(entry.showSpriteOriginGuides).toBe(true)

    local built = GameArtWindowBuilderController.buildWindowsFromLayout(snapshot, {
      wm = WM.new(),
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
    })

    local restored = built.windowsById["oam_guides"]
    expect(restored).toBeTruthy()
    expect(restored.showSpriteOriginGuides).toBe(true)
  end)

  it("includes paletteGroupState in layout snapshots when app exposes it", function()
    local oldCtx = rawget(_G, "ctx")
    _G.ctx = {
      app = {
        groupedPaletteWindows = true,
        getPaletteGroupStateForSave = function()
          return {
            version = 1,
            enabled = true,
            global = {
              activeSourceWindowId = "palette_02",
              activeIndex = 2,
              logicalWindow = { x = 10, y = 20 },
            },
            rom = {
              activeSourceWindowId = "rom_palette_01",
              activeIndex = 1,
              logicalWindow = { x = 30, y = 40 },
            },
          }
        end,
      },
    }

    local wm = require("controllers.window.window_controller").new()
    local win = wm:createPaletteWindow({ title = "Palette A" })
    win._id = "palette_01"

    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1, _G.ctx.app)
    _G.ctx = oldCtx

    expect(snapshot.paletteGroupState).toBeTruthy()
    expect(snapshot.paletteGroupState.enabled).toBe(true)
    expect(snapshot.paletteGroupState.global.activeSourceWindowId).toBe("palette_02")
    expect(snapshot.paletteGroupState.rom.activeSourceWindowId).toBe("rom_palette_01")
  end)

  it("uses app argument for paletteGroupState when ctx.app is unavailable", function()
    local oldCtx = rawget(_G, "ctx")
    _G.ctx = nil

    local mockApp = {
      groupedPaletteWindows = true,
      getPaletteGroupStateForSave = function()
        return {
          version = 1,
          enabled = true,
          global = { activeSourceWindowId = "palette_01", activeIndex = 1, logicalWindow = {} },
          rom = {},
        }
      end,
    }

    local wm = require("controllers.window.window_controller").new()
    local snapshot = GameArtLayoutIOController.snapshotLayout(wm, nil, 1, mockApp)
    _G.ctx = oldCtx

    expect(snapshot.paletteGroupState).toBeTruthy()
    expect(snapshot.paletteGroupState.enabled).toBe(true)
    expect(snapshot.paletteGroupState.global.activeSourceWindowId).toBe("palette_01")
  end)

  it("snapshotLayout onlyWindow omits paletteGroupState and captures one window", function()
    local oldCtx = rawget(_G, "ctx")
    _G.ctx = {
      app = {
        groupedPaletteWindows = true,
        getPaletteGroupStateForSave = function()
          return { version = 1, enabled = true, global = {}, rom = {} }
        end,
      },
    }

    local wm = require("controllers.window.window_controller").new()
    local pal = wm:createPaletteWindow({ title = "P" })
    pal._id = "palette_01"
    local other = wm:createPaletteWindow({ title = "Q" })
    other._id = "palette_02"
    wm:setFocus(pal)

    local snap = GameArtLayoutIOController.snapshotLayout(wm, nil, 1, _G.ctx.app, { onlyWindow = pal })
    _G.ctx = oldCtx

    expect(snap.paletteGroupState).toBeNil()
    expect(#snap.windows).toBe(1)
    expect(snap.windows[1].id).toBe("palette_01")
    expect(snap.focusedWindowId).toBeNil()
    expect(snap.windowOrderIds).toBeNil()
  end)

  it("snapshotLayout persists windowOrderIds from taskbar minimized strip order", function()
    local WM = require("controllers.window.window_controller")
    local Taskbar = require("user_interface.taskbar")
    local wm = WM.new()
    local app = { wm = wm }
    local tb = Taskbar.new(app, { h = 15 })
    wm.taskbar = tb

    local winA = wm:createPaletteWindow({ title = "A", activePalette = false })
    winA._id = "win_order_a"
    local winB = wm:createPaletteWindow({ title = "B", activePalette = false })
    winB._id = "win_order_b"

    tb.minimizedWindows = { winB, winA }

    local snap = GameArtLayoutIOController.snapshotLayout(wm, nil, 1, app)
    expect(snap.windowOrderIds).toBeTruthy()
    expect(#snap.windowOrderIds).toBe(2)
    expect(snap.windowOrderIds[1]).toBe("win_order_b")
    expect(snap.windowOrderIds[2]).toBe("win_order_a")
  end)

  it("buildWindowsFromLayout restores wm stack from layout.windows and taskbar strip from windowOrderIds", function()
    local WM = require("controllers.window.window_controller")
    local Taskbar = require("user_interface.taskbar")
    local GameArtWindowBuilderController = require("controllers.game_art.window_builder_controller")

    local wm1 = WM.new()
    local app1 = { wm = wm1 }
    wm1.taskbar = Taskbar.new(app1, { h = 15 })

    local winA = wm1:createPaletteWindow({ title = "A", activePalette = false })
    winA._id = "persist_a"
    local winB = wm1:createPaletteWindow({ title = "B", activePalette = false })
    winB._id = "persist_b"
    wm1.taskbar.minimizedWindows = { winB, winA }

    local snap = GameArtLayoutIOController.snapshotLayout(wm1, nil, 1, app1)
    expect(snap.windowOrderIds[1]).toBe("persist_b")

    expect(snap.windows[1].id).toBe("persist_a")
    expect(snap.windows[2].id).toBe("persist_b")

    local wm2 = WM.new()
    local app2 = { wm = wm2 }
    wm2.taskbar = Taskbar.new(app2, { h = 15 })

    GameArtWindowBuilderController.buildWindowsFromLayout(snap, {
      wm = wm2,
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
    })

    local orderIds = {}
    for _, w in ipairs(wm2.windows) do
      if not w._closed and not w._alwaysOnTop then
        orderIds[#orderIds + 1] = w._id
      end
    end
    expect(#orderIds).toBe(2)
    expect(orderIds[1]).toBe("persist_a")
    expect(orderIds[2]).toBe("persist_b")

    expect(wm2.taskbar.minimizedWindows[1]._id).toBe("persist_b")
    expect(wm2.taskbar.minimizedWindows[2]._id).toBe("persist_a")
  end)

  it("buildWindowsFromLayout uses layout.windows z-order when windowOrderIds misses a window id", function()
    local WM = require("controllers.window.window_controller")
    local Taskbar = require("user_interface.taskbar")
    local GameArtWindowBuilderController = require("controllers.game_art.window_builder_controller")

    local snap = {
      windows = {
        {
          kind = "palette",
          id = "pal_back",
          title = "Back",
          x = 10,
          y = 10,
          rows = 4,
          cols = 4,
          items = {},
        },
        {
          kind = "palette",
          id = "pal_was_omitted",
          title = "OmittedOrder",
          x = 20,
          y = 10,
          rows = 4,
          cols = 4,
          items = {},
        },
      },
      windowOrderIds = { "pal_back" },
      currentBank = 1,
    }

    local wm = WM.new()
    local app = { wm = wm }
    wm.taskbar = Taskbar.new(app, { h = 15 })

    GameArtWindowBuilderController.buildWindowsFromLayout(snap, {
      wm = wm,
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
    })

    local orderIds = {}
    for _, w in ipairs(wm.windows) do
      if not w._closed and not w._alwaysOnTop then
        orderIds[#orderIds + 1] = w._id
      end
    end
    expect(#orderIds).toBe(2)
    expect(orderIds[1]).toBe("pal_back")
    expect(orderIds[2]).toBe("pal_was_omitted")
  end)

  it("buildWindowsFromLayout uses construction order when layout entries have blank ids", function()
    local WM = require("controllers.window.window_controller")
    local Taskbar = require("user_interface.taskbar")
    local GameArtWindowBuilderController = require("controllers.game_art.window_builder_controller")

    local snap = {
      windows = {
        {
          kind = "palette",
          id = "",
          title = "First",
          x = 0,
          y = 0,
          rows = 4,
          cols = 4,
          items = {},
        },
        {
          kind = "palette",
          id = "",
          title = "Second",
          x = 10,
          y = 0,
          rows = 4,
          cols = 4,
          items = {},
        },
      },
      windowOrderIds = {},
      currentBank = 1,
    }

    local wm = WM.new()
    local app = { wm = wm }
    wm.taskbar = Taskbar.new(app, { h = 15 })

    GameArtWindowBuilderController.buildWindowsFromLayout(snap, {
      wm = wm,
      tilesPool = {},
      ensureTiles = function() end,
      romRaw = "",
      decodeUserDefinedCodes = GameArtLayoutIOController.decodeUserDefinedCodes,
    })

    local orderIds = {}
    for _, w in ipairs(wm.windows) do
      if not w._closed and not w._alwaysOnTop then
        orderIds[#orderIds + 1] = w._id
      end
    end
    expect(#orderIds).toBe(2)
    expect(orderIds[1]).toBe("palette_1")
    expect(orderIds[2]).toBe("palette_2")
  end)
end)
