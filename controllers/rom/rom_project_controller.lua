-- managers/rom_project_controller.lua
-- Handles ROM load, project/layout load, and project save.

local chr             = require("chr")
local WindowController   = require("controllers.window.window_controller")
local GameArtController  = require("controllers.game_art.game_art_controller")
local PaletteWindow   = require("user_interface.windows_system.palette_window")
local RomWindow       = require("user_interface.windows_system.rom_window")
local StaticArtWindow = require("user_interface.windows_system.static_art_window")
local AnimationWindow = require("user_interface.windows_system.animation_window")
local BankViewController = require("controllers.chr.bank_view_controller")
local ChrDuplicateSync = require("controllers.chr.duplicate_sync_controller")
local ChrBackingController = require("controllers.rom.chr_backing_controller")
local ResolutionController = require("controllers.app.resolution_controller")
local SpriteController = require("controllers.sprite.sprite_controller")
local UserInput = require("controllers.input")
local DebugController    = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")

------------------------------------------------------------
-- Helpers: sha1 + path + edits merge
------------------------------------------------------------

local function sha1_hex(bytes)
  local digest = love.data.hash("sha1", bytes)
  return love.data.encode("string", "hex", digest)
end

local function sha1_file(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local bytes = f:read("*a"); f:close()
  if not bytes then return nil, "read failed" end
  return sha1_hex(bytes)
end

local function splitPath(p)
  local d,b = p:match("^(.*)[/\\]([^/\\]+)$")
  if not d then return "", p end
  return d, b
end

local function stripExt(name)
  return (name:gsub("%.[^%.]+$", ""))
end

local function canonicalProjectStem(name)
  local stem = stripExt(name or "project")
  stem = stem:gsub("_edited$", "")
  stem = stem:gsub("_project$", "")
  return stem
end

local function fileExt(path)
  if type(path) ~= "string" then return nil end
  local ext = path:match("%.([^%.\\/]+)$")
  return ext and ext:lower() or nil
end

local function isEditedRomPath(path)
  if type(path) ~= "string" then return false end
  return path:lower():match("_edited%.nes$") ~= nil
end

local function fileExists(path)
  if type(path) ~= "string" or path == "" then return false end
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function baseName(path)
  if type(path) ~= "string" or path == "" then return nil end
  return path:match("([^/\\]+)$") or path
end

local function joinPath(dir, name)
  local sep = (package.config:sub(1,1) == "\\" and "\\") or "/"
  if dir == "" then return name end
  if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then return dir .. name end
  return dir .. sep .. name
end

local function nowSeconds()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function logPerf(label, startedAt, extra)
  local elapsed = nowSeconds() - (startedAt or nowSeconds())
  if extra and extra ~= "" then
    DebugController.log("info", "LOAD_PERF", "%s duration=%.3fs %s", tostring(label), elapsed, tostring(extra))
  else
    DebugController.log("info", "LOAD_PERF", "%s duration=%.3fs", tostring(label), elapsed)
  end
end

local function pulseLoading(app, message)
  if app and app.pulseSimpleLoading then
    app:pulseSimpleLoading(message)
  end
end

local function formatLoadToast(seconds)
  seconds = math.max(0, tonumber(seconds) or 0)
  return string.format("Loaded in %.1f seconds", seconds)
end

local function projectPathForRom(romPath, ext)
  local dir, base = splitPath(romPath or "")
  local stem = canonicalProjectStem(base or "project")
  return joinPath(dir, stem .. "." .. tostring(ext))
end

local function normalizeRecentProjectBasePath(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local dir, base = splitPath(path)
  local stem = canonicalProjectStem(base or "")
  if stem == "" then
    return nil
  end
  return joinPath(dir, stem)
end

local function resolveRecentProjectLoadPath(basePath)
  local normalized = normalizeRecentProjectBasePath(basePath)
  if not normalized then
    return nil
  end

  local candidates = {
    normalized .. ".nes",
    normalized .. ".lua",
    normalized .. ".ppux",
    normalized .. "_edited.nes",
  }

  for _, candidate in ipairs(candidates) do
    if fileExists(candidate) then
      return candidate
    end
  end

  return nil
end

local function pushUniquePath(list, seen, path)
  if type(path) ~= "string" or path == "" then return end
  if seen[path] then return end
  seen[path] = true
  list[#list + 1] = path
end

local function projectPathCandidatesForRom(romPath, ext)
  local candidates = {}
  local seen = {}
  local dir, base = splitPath(romPath or "")
  local stem = canonicalProjectStem(base or "project")
  local normalizedExt = tostring(ext or "")

  pushUniquePath(candidates, seen, projectPathForRom(romPath, normalizedExt))
  if stem ~= "" then
    pushUniquePath(candidates, seen, joinPath(dir, stem .. "." .. normalizedExt))
  end

  return candidates
end

local function setDefaultProjectPaths(app, romPath)
  app.projectPath = projectPathForRom(romPath, "lua")
  app.encodedProjectPath = projectPathForRom(romPath, "ppux")
  _G.projectPath = app.projectPath
end

local function normalizeArtifactPath(path, romPath, ext)
  local currentExt = fileExt(path)
  if type(path) == "string" and path ~= "" and currentExt == ext then
    return path
  end

  if type(romPath) == "string" and romPath ~= "" then
    return projectPathForRom(romPath, ext)
  end

  if type(path) == "string" and path ~= "" then
    local dir, base = splitPath(path)
    local stem = canonicalProjectStem(base or ("project." .. ext))
    return joinPath(dir, stem .. "." .. tostring(ext))
  end

  return nil
end

local function ensureProjectSavePaths(app, state)
  if not app then return end
  state = state or app.appEditState or {}
  local romPath = state.romOriginalPath

  app.projectPath = normalizeArtifactPath(app.projectPath, romPath, "lua")
  app.encodedProjectPath = normalizeArtifactPath(app.encodedProjectPath, romPath, "ppux")
  _G.projectPath = app.projectPath

  if app.projectPath and app.encodedProjectPath and app.projectPath == app.encodedProjectPath then
    app.projectPath = normalizeArtifactPath(nil, romPath, "lua") or normalizeArtifactPath(app.projectPath, nil, "lua")
    app.encodedProjectPath = normalizeArtifactPath(nil, romPath, "ppux") or normalizeArtifactPath(app.encodedProjectPath, nil, "ppux")
    _G.projectPath = app.projectPath
  end
end

local function chooseAdjacentProjectPath(app)
  local candidates = {}
  local seen = {}
  local romPath = app and app.appEditState and app.appEditState.romOriginalPath or nil

  pushUniquePath(candidates, seen, app and app.projectPath or nil)
  pushUniquePath(candidates, seen, app and app.encodedProjectPath or nil)

  for _, path in ipairs(projectPathCandidatesForRom(romPath, "lua")) do
    pushUniquePath(candidates, seen, path)
  end
  for _, path in ipairs(projectPathCandidatesForRom(romPath, "ppux")) do
    pushUniquePath(candidates, seen, path)
  end

  for _, candidate in ipairs(candidates) do
    if fileExists(candidate) then
      return candidate, fileExt(candidate)
    end
  end

  return nil, nil
end

------------------------------------------------------------
-- RomProjectController
------------------------------------------------------------

local M = {}
local function fmtWin(win)
  if not win then return "<nil>" end
  return string.format(
    "%s(kind=%s,id=%s,title=%s,layers=%s)",
    tostring(win),
    tostring(win.kind),
    tostring(win._id),
    tostring(win.title),
    tostring(win.layers and #win.layers or 0)
  )
end

local function bindWindowManager(app)
  if not app or not app.wm then return end
  if app.taskbar then
    app.wm.taskbar = app.taskbar
  end
end

local function appHasLoadedRom(app)
  if app and type(app.hasLoadedROM) == "function" then
    return app:hasLoadedROM()
  end

  local state = app and app.appEditState or nil
  if not state then
    return false
  end
  if type(state.romSha1) == "string" and state.romSha1 ~= "" then
    return true
  end
  return type(state.romRaw) == "string"
    and #state.romRaw > 0
    and type(state.romOriginalPath) == "string"
    and state.romOriginalPath ~= ""
end

local function resetStateForNewROM(app)
  if UserInput and UserInput.resetRuntimeState then
    UserInput.resetRuntimeState()
  elseif SpriteController and SpriteController.endDrag then
    SpriteController.endDrag()
  end

  app.wm                      = WindowController.new()
  bindWindowManager(app)
  if app and app.taskbar and app.taskbar.resetWindowButtons then
    app.taskbar:resetWindowButtons()
  end
  app.winBank                 = nil
  app.edits                   = { banks = {} }
  app.projectPath             = nil
  app.encodedProjectPath      = nil
  app.currentBank             = 1
  app.syncDuplicateTiles      = false
  if app.undoRedo and app.undoRedo.clear then
    app.undoRedo:clear()
  end
  if app.tooltipController then
    app.tooltipController.visible = false
    app.tooltipController.candidateText = nil
    app.tooltipController.candidateKey = nil
    app.tooltipController.candidateImmediate = false
    app.tooltipController.lastMouseX = nil
    app.tooltipController.lastMouseY = nil
    app.tooltipController.stillSeconds = 0
  end
  if app.toastController then
    app.toastController.toasts = {}
    app.toastController.pressedToast = nil
    app.toastController.layoutDirty = true
  end
  if app.genericActionsModal and app.genericActionsModal.hide then
    app.genericActionsModal:hide()
  end
  if app.quitConfirmModal and app.quitConfirmModal.hide then
    app.quitConfirmModal:hide()
  end
  if app.saveOptionsModal and app.saveOptionsModal.hide then
    app.saveOptionsModal:hide()
  end
  if app.settingsModal and app.settingsModal.hide then
    app.settingsModal:hide()
  end
  if app.newWindowModal and app.newWindowModal.hide then
    app.newWindowModal:hide()
  end
  if app.renameWindowModal and app.renameWindowModal.hide then
    app.renameWindowModal:hide()
  end
  app._windowSnapshot         = nil
  app._windowSnapshotTimer    = 0
  app.appEditState.romRaw     = nil
  app.appEditState.romOriginalPath = nil
  app.appEditState.meta       = nil
  app.appEditState.chrBanksBytes = nil
  app.appEditState.originalChrBanksBytes = nil
  app.appEditState.currentBank = 1
  app.appEditState.romSha1    = nil
  app.appEditState.tilesPool  = {}
  app.appEditState.romTileViewMode = nil
  app.appEditState.romPatches = nil
  app.appEditState.tileSignatureIndex = nil
  app.appEditState.tileSignatureByTile = nil
  app.appEditState.tileSignatureIndexReady = false
  ChrBackingController.resetState(app.appEditState)
  if app.clearUnsavedChanges then
    app:clearUnsavedChanges()
  end
end

local function closeProjectState(app)
  resetStateForNewROM(app)
  app.statusText = "Drop an .nes ROM with CHR data"
  app.lastEventText = app.statusText
  if app.taskbar and app.taskbar._refreshMenuItems then
    app.taskbar:_refreshMenuItems()
  end
end

local function readTextFromFileOrPath(fileOrPath)
  if type(fileOrPath) == "string" then
    local f, err = io.open(fileOrPath, "rb")
    if not f then return nil, err end
    local s = f:read("*a")
    f:close()
    return s
  end

  if not fileOrPath then
    return nil, "missing file"
  end

  if fileOrPath.open then
    fileOrPath:open("r")
  end
  local s = fileOrPath.read and fileOrPath:read() or nil
  if fileOrPath.close then
    fileOrPath:close()
  end
  if type(s) ~= "string" then
    return nil, "read failed"
  end
  return s
end

local function detectProjectFormat(path)
  local ext = fileExt(path)
  if ext == "ppux" then
    return "ppux"
  end
  if ext == "lua" then
    return "lua"
  end
  return nil
end

local function loadProjectFromString(projectPath, raw)
  local format = detectProjectFormat(projectPath)
  if format == "ppux" then
    return GameArtController.loadProjectPpuxString(raw, projectPath), format
  end
  return GameArtController.loadProjectLuaString(raw, projectPath), "lua"
end

local function loadProjectFromPath(projectPath)
  local format = detectProjectFormat(projectPath)
  if format == "ppux" then
    return GameArtController.loadProjectPpux(projectPath), format
  end
  if format == "lua" then
    return GameArtController.loadProjectLua(projectPath), format
  end
  return nil, "Unsupported project file type: " .. tostring(projectPath), nil
end

local function pushCandidate(candidates, seen, path)
  if type(path) ~= "string" or path == "" then return end
  if seen[path] then return end
  seen[path] = true
  candidates[#candidates + 1] = path
end

local function resolveRomPathForProject(projectPath, project)
  local dir, base = splitPath(projectPath or "")
  local stem = canonicalProjectStem(base or "")

  local candidates = {}
  local seen = {}
  local sourceRomPath = project and project.sourceRomPath or nil
  local sourceRomFilename = project and project.sourceRomFilename or nil

  pushCandidate(candidates, seen, sourceRomPath)
  pushCandidate(candidates, seen, sourceRomPath and joinPath(dir, baseName(sourceRomPath)))
  pushCandidate(candidates, seen, sourceRomFilename and joinPath(dir, sourceRomFilename))
  if stem ~= "" then
    pushCandidate(candidates, seen, joinPath(dir, stem .. ".nes"))
  end

  for _, candidate in ipairs(candidates) do
    if fileExists(candidate) then
      return candidate
    end
  end

  return nil, string.format("Could not locate base ROM for project: %s", tostring(projectPath))
end

-- Read ROM from either a LÖVE File object or a file path string
local function readROMFromFile(app, fileOrPath)
  local state = app.appEditState
  local romPath
  local romData

  if type(fileOrPath) == "string" then
    -- File path provided (command-line argument)
    romPath = fileOrPath
    DebugController.log("info", "ROM", "Loading ROM file from path: %s", romPath)
    
    -- Open and read the file
    local f, err = io.open(romPath, "rb")
    if not f then
      app:setStatus("Failed to open ROM file: " .. tostring(err) .. " (" .. romPath .. ")")
      DebugController.log("info", "ROM", "Failed to open file: %s - %s", romPath, tostring(err))
      return false
    end
    
    -- Read all data at once
    romData = f:read("*all")  -- Use "*all" which is equivalent to "*a" but more explicit
    
    -- Close file immediately
    -- Note: file:close() returns true on success, nil on failure
    local closeOk = f:close()
    if not closeOk then
      DebugController.log("info", "ROM", "Warning: error closing file")
    end
    
    -- Check if read was successful
    if romData == nil or type(romData) ~= "string" then
      app:setStatus("Failed to read ROM file: " .. romPath .. " (read returned " .. type(romData) .. ")")
      DebugController.log("info", "ROM", "Read failed for file: %s (type: %s)", romPath, type(romData))
      return false
    end
    
    if #romData == 0 then
      app:setStatus("ROM file is empty: " .. romPath)
      DebugController.log("info", "ROM", "File is empty: %s", romPath)
      return false
    end
    
    DebugController.log("info", "ROM", "Successfully read %d bytes from file: %s", #romData, romPath)
  else
    -- LÖVE File object provided (filedropped)
    if fileOrPath.getFilename then
      romPath = fileOrPath:getFilename()
      DebugController.log("info", "ROM", "Loading ROM file: %s", romPath)
    end
    
    fileOrPath:open("r")
    romData = fileOrPath:read()
    fileOrPath:close()
  end
  
  state.romOriginalPath = romPath
  state.romRaw = romData
  
  DebugController.log("info", "ROM", "ROM loaded, size: %d bytes", #state.romRaw)
  return true
end

local function syncDuplicateIndexesForLoad(app, state)
  if app and app.syncDuplicateTiles == true then
    ChrDuplicateSync.buildSyncGroups(state)
  else
    ChrDuplicateSync.clearSyncGroups(state)
  end
end

local function cloneChrBanksBytes(banks)
  local out = {}
  if type(banks) ~= "table" then
    return out
  end

  for bankIdx, bankBytes in ipairs(banks) do
    local cloned = {}
    if type(bankBytes) == "table" then
      for i = 1, #bankBytes do
        cloned[i] = bankBytes[i]
      end
    end
    out[bankIdx] = cloned
  end

  return out
end

local function parseROM(app)
  local state = app.appEditState
  local parseStartedAt = nowSeconds()

  pulseLoading(app, "Hashing ROM...")
  local hashStartedAt = nowSeconds()
  local sha, err
  if type(state.romRaw) == "string" and #state.romRaw > 0 then
    sha = sha1_hex(state.romRaw)
  else
    sha, err = sha1_file(state.romOriginalPath)
  end
  state.romSha1 = sha
  if not sha then
    app:setStatus("SHA-1 failed: " .. tostring(err))
    return false
  end
  logPerf("parseROM.hash", hashStartedAt)

  pulseLoading(app, "Parsing iNES header...")
  local inesStartedAt = nowSeconds()
  local ok, result = pcall(chr.parseINES, state.romRaw)
  if not ok then
    app:setStatus("Error: " .. tostring(result))
    return false
  end
  logPerf("parseROM.ines", inesStartedAt)

  state.meta          = result.meta
  pulseLoading(app, "Preparing CHR banks...")
  local chrBackingStartedAt = nowSeconds()
  local banks, backingErr = ChrBackingController.configureFromParsedINES(state, result)
  if not banks then
    app:setStatus("Error: " .. tostring(backingErr or "CHR backing setup failed"))
    return false
  end
  state.originalChrBanksBytes = cloneChrBanksBytes(state.chrBanksBytes)
  logPerf("parseROM.prepare_chr_banks", chrBackingStartedAt, string.format("banks=%d", #(state.chrBanksBytes or {})))

  if ChrBackingController.isRomRawMode(state) then
    local backing = ChrBackingController.getDescriptor(state) or {}
    DebugController.log(
      "info",
      "ROM",
      "CHR-RAM ROM detected; using ROM window pseudo banks: %d bank(s) from %d bytes (offset=%d)",
      #state.chrBanksBytes,
      tonumber(backing.dataSize) or 0,
      tonumber(backing.dataOffset) or 0
    )
  end

  logPerf("parseROM.total", parseStartedAt)
  return true
end

local function makeProjectPath(app)
  local state = app.appEditState
  setDefaultProjectPaths(app, state.romOriginalPath)
end

local function ensureBankTilesInner(state, bankIdx)
  BankViewController.ensureBankTiles(state, bankIdx)
end

local function rebuildBankWindowLayers(app, winBank, state)
  if not winBank then
    return
  end

  state.currentBank = winBank.currentBank or state.currentBank or 1
  BankViewController.rebuildBankWindowItems(
    winBank,
    state,
    winBank.orderMode or "normal",
    function(txt)
      app:setStatus(txt)
    end
  )
  state.currentBank = winBank.currentBank or state.currentBank or 1
end

local function addPlannedBank(banksSet, bankIdx)
  local n = tonumber(bankIdx)
  if not n then return end
  n = math.floor(n)
  if n < 1 then return end
  banksSet[n] = true
end

M._projectPathCandidatesForRom = projectPathCandidatesForRom
M._chooseAdjacentProjectPath = chooseAdjacentProjectPath
M._isEditedRomPath = isEditedRomPath
M._normalizeRecentProjectBasePath = normalizeRecentProjectBasePath
M._resolveRecentProjectLoadPath = resolveRecentProjectLoadPath
M.resolveRecentProjectLoadPath = resolveRecentProjectLoadPath

local function collectPlannedBanksFromWindowData(value, banksSet)
  if type(value) ~= "table" then return end

  for k, v in pairs(value) do
    if k == "bank" or k == "currentBank" then
      addPlannedBank(banksSet, v)
    elseif type(v) == "table" then
      collectPlannedBanksFromWindowData(v, banksSet)
    end
  end
end

local function collectPlannedBanksFromEdits(edits, banksSet)
  local banks = edits and edits.banks
  if type(banks) ~= "table" then return end

  for bankIdx in pairs(banks) do
    addPlannedBank(banksSet, bankIdx)
  end
end

local function registerPlannedBanksForLayout(data, opts)
  opts = opts or {}
  local banksSet = {}
  addPlannedBank(banksSet, data and data.currentBank)

  for _, win in ipairs((data and data.windows) or {}) do
    collectPlannedBanksFromWindowData(win, banksSet)
  end

  if opts.includeEdits ~= false then
    collectPlannedBanksFromEdits(data and data.edits, banksSet)
  end

  if next(banksSet) == nil then
    addPlannedBank(banksSet, opts.defaultBank)
  end

  local ordered = {}
  for bankIdx in pairs(banksSet) do
    ordered[#ordered + 1] = bankIdx
  end
  table.sort(ordered)

end

local function dbLayoutHasWindows(layout)
  return type(layout) == "table"
    and type(layout.windows) == "table"
    and #layout.windows > 0
end

M._dbLayoutHasWindows = dbLayoutHasWindows

local function loadFromProject(app, project)
  local state = app.appEditState
  local loadStartedAt = nowSeconds()
  if project.syncDuplicateTiles ~= nil then
    app.syncDuplicateTiles = project.syncDuplicateTiles
  end
  state.romPatches = GameArtController.normalizeRomPatches(project.romPatches)

  pulseLoading(app, "Building project windows...")
  local registerStartedAt = nowSeconds()
  registerPlannedBanksForLayout(project, {
    defaultBank = state.currentBank or 1,
    includeEdits = true,
  })
  logPerf("project.register_planned_banks", registerStartedAt)

  app.wm = WindowController.new()
  bindWindowManager(app)
  local buildStartedAt = nowSeconds()
  local built, why = GameArtController.buildWindowsFromLayout(project, {
    wm          = app.wm,
    tilesPool   = state.tilesPool,
    ensureTiles = function(bankIdx) ensureBankTilesInner(state, bankIdx) end,
    romRaw      = state.romRaw,
    chrBackingMode = ChrBackingController.getMode(state),
  })

  if not built then
    app:setStatus("Project load error: " .. tostring(why or "unknown"))
    return false
  end
  logPerf("project.build_windows", buildStartedAt, string.format("windows=%d", #(project.windows or {})))

  app.winBank             = built.bankWindow
  if app.winBank then
    pulseLoading(app, "Building bank pages...")
    -- Update app state to match CHR window's state
    state.currentBank = app.winBank.currentBank or built.currentBank or project.currentBank or 1
    app.winBank.currentBank = state.currentBank
    local bankWindowStartedAt = nowSeconds()
    rebuildBankWindowLayers(app, app.winBank, state)
    logPerf("project.rebuild_bank_window", bankWindowStartedAt, string.format("bank=%d", state.currentBank or -1))
  end

  -- Load edits (may be in compressed format from saved projects)
  local edits = project.edits or GameArtController.newEdits()
  pulseLoading(app, "Applying project edits...")
  local editsStartedAt = nowSeconds()
  -- Apply edits first (applyEdits handles decompression internally)
  GameArtController.applyEdits(edits, state.tilesPool, state.chrBanksBytes,
    function(bankIdx) ensureBankTilesInner(state, bankIdx) end)
  -- Store edits in decompressed format for runtime use (easier to add new edits)
  app.edits = GameArtController.decompressEdits(edits)
  logPerf("project.apply_edits", editsStartedAt)

  pulseLoading(app, "Indexing duplicate tiles...")
  local dupesStartedAt = nowSeconds()
  syncDuplicateIndexesForLoad(app, state)
  logPerf("project.sync_duplicate_indexes", dupesStartedAt, string.format("enabled=%s", tostring(app.syncDuplicateTiles == true)))
  
  -- Restore selected pixel brush color
  if project.currentColor ~= nil then
    app.currentColor = project.currentColor
  end
  
  -- Sync active palette windows to global palette manager
  for _, win in ipairs(app.wm:getWindows()) do
    if win.isPalette and win.activePalette then
      win:syncToGlobalPalette()
    end
  end

  app:setStatus("Loaded project")
  
  -- Create toolbars for all windows
  pulseLoading(app, "Creating toolbars...")
  local ToolbarController = require("controllers.window.toolbar_controller")
  local toolbarsStartedAt = nowSeconds()
  ToolbarController.createToolbarsForWindows(app)
  logPerf("project.create_toolbars", toolbarsStartedAt)
  logPerf("project.total", loadStartedAt)
  
  return true
end

local function loadFromDBLayout(app, sha)
  local state = app.appEditState
  local loadStartedAt = nowSeconds()

  local layout = GameArtController.getLayout(sha)
  if not layout then return false end
  if not dbLayoutHasWindows(layout) then
    DebugController.log("info", "ROM", "DB layout is empty for SHA-1 %s; falling back to default layout", tostring(sha))
    return false
  end

  pulseLoading(app, "Building default windows...")
  local registerStartedAt = nowSeconds()
  registerPlannedBanksForLayout(layout, {
    defaultBank = state.currentBank or 1,
    includeEdits = false,
  })
  logPerf("db_layout.register_planned_banks", registerStartedAt)

  app.wm = WindowController.new()
  bindWindowManager(app)
  local buildStartedAt = nowSeconds()
  local built, why = GameArtController.buildWindowsFromLayout(layout, {
    wm          = app.wm,
    tilesPool   = state.tilesPool,
    ensureTiles = function(bankIdx) ensureBankTilesInner(state, bankIdx) end,
    romRaw      = state.romRaw,
    chrBackingMode = ChrBackingController.getMode(state),
  })

  if not built then
    app:setStatus("Layout load error: " .. tostring(why or "unknown"))
    return true -- layout existed, but failed
  end
  logPerf("db_layout.build_windows", buildStartedAt, string.format("windows=%d", #(layout.windows or {})))

  app.winBank       = built.bankWindow
  if app.winBank then
    pulseLoading(app, "Building bank pages...")
    state.currentBank = app.winBank.currentBank or built.currentBank or 1
    app.winBank.currentBank = state.currentBank
    local bankWindowStartedAt = nowSeconds()
    rebuildBankWindowLayers(app, app.winBank, state)
    logPerf("db_layout.rebuild_bank_window", bankWindowStartedAt, string.format("bank=%d", state.currentBank or -1))
  end

  pulseLoading(app, "Indexing duplicate tiles...")
  local dupesStartedAt = nowSeconds()
  syncDuplicateIndexesForLoad(app, state)
  logPerf("db_layout.sync_duplicate_indexes", dupesStartedAt, string.format("enabled=%s", tostring(app.syncDuplicateTiles == true)))

  app:setStatus("Loaded DB layout")
  
  -- Create toolbars for all windows
  pulseLoading(app, "Creating toolbars...")
  local ToolbarController = require("controllers.window.toolbar_controller")
  local toolbarsStartedAt = nowSeconds()
  ToolbarController.createToolbarsForWindows(app)
  logPerf("db_layout.create_toolbars", toolbarsStartedAt)

  DebugController.log("info", "ROM", "Loaded DB layout: %s", sha)
  DebugController.log("info", "ROM", "  #windows = %d", #(layout.windows or {}))
  logPerf("db_layout.total", loadStartedAt)
  
  return true
end

local function createDefaultWindows(app)
  local state = app.appEditState
  state.currentBank = 1
  local createStartedAt = nowSeconds()

  pulseLoading(app, "Building default windows...")
  local useRomWindow = ChrBackingController.isRomRawMode(state)
  local winCtor = useRomWindow and RomWindow or require("user_interface.windows_system.chr_bank_window")
  local winTitle = useRomWindow and "ROM Banks" or "CHR Banks"
  local winBank = winCtor.new(30, 30, 8, 8, 16, 32, 2, {
    visibleRows = 16,
    visibleCols = 16,
    title       = winTitle,
  })

  app.winBank = winBank
  app.wm:add(winBank)

  -- Unknown ROM fallback should still provide one global palette window so
  -- palette-aware rendering/import paths have an explicit UI source.
  local paletteWin = PaletteWindow.new(
    500, 30, 1,
    "smooth_fbx",
    1, 4,
    {
      activePalette = true,
      title = "Global palette",
    }
  )
  paletteWin._id = "palette_01"
  app.wm:add(paletteWin)

  local staticWin = StaticArtWindow.new(300, 30, 8, 8, 8, 8, 3, {
    visibleRows = 8,
    visibleCols = 8,
    title = "Static Art (tiles)",
    nonActiveLayerOpacity = 1.0,
  })
  staticWin._id = "default_static_tiles"
  staticWin:addLayer({
    opacity = 1.0,
    name = "Layer 1",
    kind = "tile",
  })
  app.wm:add(staticWin)

  local animationWin = AnimationWindow.new(500, 84, 8, 8, 8, 8, 2, {
    visibleRows = 8,
    visibleCols = 8,
    title = "Animation (sprites)",
    nonActiveLayerOpacity = 0.0,
  })
  animationWin._id = "default_animation_sprites"
  animationWin:addLayer({
    opacity = 1.0,
    name = "Frame 1",
    kind = "sprite",
    mode = "8x8",
    originX = 0,
    originY = 0,
  })
  if animationWin.updateLayerOpacities then
    animationWin:updateLayerOpacities()
  end
  app.wm:add(animationWin)

  app.wm:setFocus(winBank)

  if winBank.setCurrentBank then
    winBank:setCurrentBank(1)
  else
    winBank.currentBank = 1
    winBank.activeLayer = 1
  end
  winBank.orderMode = "normal"
  state.currentBank = 1
  pulseLoading(app, "Building bank pages...")
  local bankWindowStartedAt = nowSeconds()
  rebuildBankWindowLayers(app, winBank, state)
  logPerf("default_layout.rebuild_bank_window", bankWindowStartedAt, "bank=1")

  pulseLoading(app, "Indexing duplicate tiles...")
  local dupesStartedAt = nowSeconds()
  syncDuplicateIndexesForLoad(app, state)
  logPerf("default_layout.sync_duplicate_indexes", dupesStartedAt, string.format("enabled=%s", tostring(app.syncDuplicateTiles == true)))

  app:setStatus("Default layout")
  
  -- Create toolbars for all windows
  pulseLoading(app, "Creating toolbars...")
  local ToolbarController = require("controllers.window.toolbar_controller")
  local toolbarsStartedAt = nowSeconds()
  ToolbarController.createToolbarsForWindows(app)
  logPerf("default_layout.create_toolbars", toolbarsStartedAt)
  logPerf("default_layout.total", createStartedAt)
end

-- Unified ROM loading function that works for both file drops and command-line arguments
function M.loadROM(app, fileOrPath)
  if not fileOrPath then
    return false
  end
  local sourcePath = type(fileOrPath) == "string" and fileOrPath or (fileOrPath.getFilename and fileOrPath:getFilename())
  local sourceExt = detectProjectFormat(sourcePath)
  if sourceExt == "lua" or sourceExt == "ppux" then
    return M.loadProjectFile(app, fileOrPath)
  end
  local loadStartedAt = nowSeconds()
  if app and app.beginSimpleLoading then
    app:beginSimpleLoading("Opening workspace...")
  end

  local function finish(ok)
    if app and app.endSimpleLoading then
      app:endSimpleLoading()
    end
    if ok and app and app.showToast then
      --app:showToast("info", formatLoadToast(nowSeconds() - loadStartedAt))
    end
    return ok
  end

  -- Reset state for new ROM
  resetStateForNewROM(app)
  pulseLoading(app, "Reading ROM...")
  
  -- Read ROM file (handles both File objects and file paths)
  local readStartedAt = nowSeconds()
  if not readROMFromFile(app, fileOrPath) then
    return finish(false)
  end
  logPerf("loadROM.read_file", readStartedAt)
  
  -- Make project path
  makeProjectPath(app)
  
  -- Try to load project file
  local state = app.appEditState
  local detectedProjectPath = chooseAdjacentProjectPath(app)
  local project, loadErr
  local loadedProjectFormat = nil
  if detectedProjectPath then
    project, loadErr, loadedProjectFormat = loadProjectFromPath(detectedProjectPath)
    if loadedProjectFormat == "lua" then
      app.projectPath = detectedProjectPath
      _G.projectPath = app.projectPath
    elseif loadedProjectFormat == "ppux" then
      app.encodedProjectPath = detectedProjectPath
    end
  end

  if project and isEditedRomPath(sourcePath) then
    local baseRomPath = resolveRomPathForProject(detectedProjectPath, project)
    if type(baseRomPath) == "string" and baseRomPath ~= "" and baseRomPath ~= state.romOriginalPath then
      pulseLoading(app, "Switching to base ROM...")
      local rereadStartedAt = nowSeconds()
      if not readROMFromFile(app, baseRomPath) then
        return finish(false)
      end
      makeProjectPath(app)
      if loadedProjectFormat == "lua" then
        app.projectPath = detectedProjectPath
        _G.projectPath = app.projectPath
      elseif loadedProjectFormat == "ppux" then
        app.encodedProjectPath = detectedProjectPath
      end
      logPerf("loadROM.swap_to_base_rom", rereadStartedAt, string.format("from=%s", tostring(sourcePath)))
    end
  end

  -- Apply optional project ROM patches before parsing the ROM into banks/windows.
  if project and project.syncDuplicateTiles ~= nil then
    app.syncDuplicateTiles = project.syncDuplicateTiles
  end
  if project then
    pulseLoading(app, "Applying ROM patches...")
    local patchStartedAt = nowSeconds()
    state.romPatches = GameArtController.normalizeRomPatches(project.romPatches)
    if state.romPatches then
      local patched, patchErr, applied = GameArtController.applyRomPatches(state.romRaw, state.romPatches)
      if not patched then
        app:setStatus("ROM patch apply error: " .. tostring(patchErr or "unknown"))
        return finish(false)
      end
      state.romRaw = patched
      DebugController.log("info", "ROM_PATCH", "Applied %d project ROM patch(es)", applied or 0)
    end
    logPerf("loadROM.apply_rom_patches", patchStartedAt, string.format("hasPatches=%s", tostring(state.romPatches ~= nil)))
  else
    state.romPatches = nil
  end

  -- Parse ROM after optional project patches have been applied.
  if not parseROM(app) then
    return finish(false)
  end

  if project then
    if not loadFromProject(app, project) then
      return finish(false)
    end
  else
    -- Log why project loading failed (file doesn't exist, parse error, etc.)
    if loadErr then
      local errorMsg = string.format("Project file error: %s", tostring(loadErr))
      DebugController.log("error", "ROM", errorMsg)
      -- Show error to user but continue loading (fall back to DB layout or default)
      app:setStatus(errorMsg)
    else
      DebugController.log("info", "ROM", "Project file not found near ROM: %s", tostring(state.romOriginalPath or "unknown"))
    end
    
    -- Fall back to DB layout or default windows
    local sha = state.romSha1
    local okLayout = loadFromDBLayout(app, sha)
    if not okLayout then
      createDefaultWindows(app)
    end
  end

  logPerf("loadROM.total", loadStartedAt)
  if app and app.recordRecentProject then
    app:recordRecentProject(state.romOriginalPath or sourcePath)
  end
  return finish(true)
end

function M.loadProjectFile(app, fileOrPath)
  if not fileOrPath then
    return false
  end

  local projectPath = type(fileOrPath) == "string" and fileOrPath or (fileOrPath.getFilename and fileOrPath:getFilename())
  local projectFormat = detectProjectFormat(projectPath)
  if not projectFormat then
    app:setStatus("Unsupported project file type")
    return false
  end

  local loadStartedAt = nowSeconds()
  if app and app.beginSimpleLoading then
    app:beginSimpleLoading("Opening workspace...")
  end
  local function finish(ok)
    if app and app.endSimpleLoading then
      app:endSimpleLoading()
    end
    if ok and app and app.showToast then
      app:showToast("info", formatLoadToast(nowSeconds() - loadStartedAt))
    end
    return ok
  end

  pulseLoading(app, "Reading project...")
  local rawProject, rawErr = readTextFromFileOrPath(fileOrPath)
  if not rawProject then
    app:setStatus("Failed to read project file: " .. tostring(rawErr))
    return finish(false)
  end

  pulseLoading(app, "Parsing project...")
  local project, loadErr
  project, loadErr, projectFormat = loadProjectFromString(projectPath, rawProject)
  if not project then
    app:setStatus(loadErr or "Project load failed")
    return finish(false)
  end

  pulseLoading(app, "Resolving base ROM...")
  local romPath, romErr = resolveRomPathForProject(projectPath, project)
  if not romPath then
    app:setStatus(romErr or "Could not locate base ROM for project")
    return finish(false)
  end

  resetStateForNewROM(app)

  pulseLoading(app, "Reading ROM...")
  if not readROMFromFile(app, romPath) then
    return finish(false)
  end

  setDefaultProjectPaths(app, romPath)
  if projectFormat == "lua" then
    app.projectPath = projectPath
    _G.projectPath = app.projectPath
  else
    app.encodedProjectPath = projectPath
  end

  local state = app.appEditState
  if project.syncDuplicateTiles ~= nil then
    app.syncDuplicateTiles = project.syncDuplicateTiles
  end
  pulseLoading(app, "Applying ROM patches...")
  state.romPatches = GameArtController.normalizeRomPatches(project.romPatches)
  if state.romPatches then
    local patched, patchErr, applied = GameArtController.applyRomPatches(state.romRaw, state.romPatches)
    if not patched then
      app:setStatus("ROM patch apply error: " .. tostring(patchErr or "unknown"))
      return finish(false)
    end
    state.romRaw = patched
    DebugController.log("info", "ROM_PATCH", "Applied %d project ROM patch(es)", applied or 0)
  end

  if not parseROM(app) then
    return finish(false)
  end

  if not loadFromProject(app, project) then
    return finish(false)
  end

  logPerf("loadProjectFile.total", loadStartedAt, string.format("format=%s", tostring(projectFormat)))
  if app and app.recordRecentProject then
    app:recordRecentProject(romPath or projectPath)
  end
  return finish(true)
end

function M.requestLoad(app, fileOrPath)
  if not fileOrPath then
    return false
  end

  local hasUnsaved = app and app.hasUnsavedChanges and app:hasUnsavedChanges()
  if not hasUnsaved then
    return M.loadROM(app, fileOrPath)
  end

  local modal = app and app.genericActionsModal
  if not (modal and modal.show) then
    return M.loadROM(app, fileOrPath)
  end

  local function proceed()
    return M.loadROM(app, fileOrPath)
  end

  modal:show("Unsaved Changes", {
    {
      text = "Save current and open",
      callback = function()
        local ok = true
        if app and app.saveAllArtifacts then
          ok = app:saveAllArtifacts({ toast = false })
        elseif app and app.saveBeforeQuit then
          ok = app:saveBeforeQuit()
        end
        if ok then
          proceed()
        end
      end,
    },
    {
      text = "Open without saving",
      callback = function()
        proceed()
      end,
    },
    {
      text = "Cancel",
      callback = function()
      end,
    },
  })
  return true
end

function M.closeProject(app)
  if not app then
    return false
  end
  closeProjectState(app)
  return true
end

function M.handleFileDropped(app, file)
  -- Check if this is a PNG file for image import
  local filename = file:getFilename()
  local isPNG = filename:match("%.png$") or filename:match("%.PNG$")
  
  if isPNG then
    if not appHasLoadedRom(app) then
      app:setStatus("Open a ROM before importing PNGs.")
      return
    end
    local ImageImportController = require("controllers.rom.image_import_controller")
    local NametableUnscrambleController = require("controllers.ppu.nametable_unscramble_controller")
    local wm = app.wm
    local focusedWin = wm and wm:getFocus()
    local mouse = ResolutionController:getScaledMouse(true)
    local winBelowMouse = wm and wm:windowAt(mouse.x, mouse.y)
    local targetWin = winBelowMouse or focusedWin
    DebugController.log(
      "info",
      "PNG_DROP",
      "Dropped PNG '%s' mouse=(%.1f,%.1f) focused=%s underMouse=%s target=%s",
      tostring(filename),
      tonumber(mouse and mouse.x or -1) or -1,
      tonumber(mouse and mouse.y or -1) or -1,
      fmtWin(focusedWin),
      fmtWin(winBelowMouse),
      fmtWin(targetWin)
    )

    local function windowHasSpriteLayer(win)
      if not (win and win.layers) then return false end
      for _, L in ipairs(win.layers) do
        if L and L.kind == "sprite" then
          DebugController.log("info", "PNG_DROP", "windowHasSpriteLayer(%s)=true", fmtWin(win))
          return true
        end
      end
      DebugController.log("info", "PNG_DROP", "windowHasSpriteLayer(%s)=false", fmtWin(win))
      return false
    end

    local function windowHasSelectedSprite(win)
      if not (win and win.layers) then return false end
      for i, L in ipairs(win.layers) do
        if L and L.kind == "sprite" then
          local selected = SpriteController.getSelectedSpriteIndicesInOrder(L)
          if #selected > 0 then
            DebugController.log(
              "info",
              "PNG_DROP",
              "windowHasSelectedSprite(%s)=true on layer %d selectedCount=%d",
              fmtWin(win),
              tonumber(i) or -1,
              #selected
            )
            return true
          end
          local idx = L.selectedSpriteIndex
          if type(idx) == "number" then
            local s = L.items and L.items[idx]
            if s and s.removed ~= true then
              DebugController.log(
                "info",
                "PNG_DROP",
                "windowHasSelectedSprite(%s)=true via selectedSpriteIndex=%d on layer %d",
                fmtWin(win),
                idx,
                tonumber(i) or -1
              )
              return true
            end
          end
        end
      end
      DebugController.log("info", "PNG_DROP", "windowHasSelectedSprite(%s)=false", fmtWin(win))
      return false
    end

    local spriteTargetWin = nil
    if windowHasSelectedSprite(focusedWin) then
      spriteTargetWin = focusedWin
    elseif windowHasSpriteLayer(targetWin) then
      spriteTargetWin = targetWin
    elseif windowHasSpriteLayer(focusedWin) then
      spriteTargetWin = focusedWin
    end
    DebugController.log("info", "PNG_DROP", "spriteTargetWin=%s", fmtWin(spriteTargetWin))
    
    -- Handle PNG drop on sprite window (any window with active sprite layer)
    if spriteTargetWin and SpriteController.handleSpritePngDrop(app, file, spriteTargetWin) then
      DebugController.log("info", "PNG_DROP", "Sprite PNG drop handled by SpriteController for %s", fmtWin(spriteTargetWin))
      return
    end
    DebugController.log("info", "PNG_DROP", "SpriteController did not handle PNG for %s", fmtWin(spriteTargetWin))

    -- Handle PNG drop on PPU frame window (unscramble)
    if WindowCaps.isPpuFrame(targetWin) then
      DebugController.log("info", "PNG_DROP", "Routing PNG to PPU unscramble for %s", fmtWin(targetWin))
      -- Get tiles pool from app state
      local tilesPool = app.appEditState and app.appEditState.tilesPool
      
      if not tilesPool then
        app:setStatus("No tiles pool available")
        return
      end
      
      -- Perform unscrambling
      local success, message = NametableUnscrambleController.unscrambleFromPNG(
        focusedWin,
        file,
        tilesPool,
        0  -- threshold = 0 for zero-error margin by default
      )
      
      if success then
        app:setStatus(message or "Nametable unscrambled successfully")
        
        -- Trigger a refresh if needed
        if app.winBank then
          local BankViewController = require("controllers.chr.bank_view_controller")
          -- Refresh bank window to show any changes
        end
      else
        app:setStatus("Unscramble failed: " .. (message or "unknown error"))
      end
      
      return  -- Don't process as ROM file
    end

    -- Handle PNG image import into CHR window
    if WindowCaps.isChrLike(targetWin) then
      DebugController.log("info", "PNG_DROP", "Routing PNG to CHR import for %s", fmtWin(targetWin))
      -- Get selected tile position, or default to (0,0)
      local col, row = 0, 0
      if targetWin.getSelected then
        local selectedCol, selectedRow = targetWin:getSelected()
        if selectedCol and selectedRow then
          col, row = selectedCol, selectedRow
        end
      end
      
      -- Import image
      local success, message = ImageImportController.importImageToCHRWindow(
        file,
        targetWin,
        col,
        row,
        app.appEditState,
        app.edits,
        targetWin.orderMode or "normal",
        app.undoRedo,
        app
      )
      
      if success then
        app:setStatus(message or "Image imported successfully")
        
        -- Refresh the CHR bank window if needed
        if app.winBank == targetWin then
          local BankViewController = require("controllers.chr.bank_view_controller")
          BankViewController.rebuildBankWindowItems(targetWin, app.appEditState, targetWin.orderMode or "normal", function(txt)
            app:setStatus(txt)
          end)
        end
      else
        app:setStatus("Import failed: " .. (message or "unknown error"))
      end
      
      return  -- Don't process as ROM file
    else
      DebugController.log("warning", "PNG_DROP", "No compatible PNG drop target. targetWin=%s", fmtWin(targetWin))
      app:setStatus("Please select a CHR bank window or PPU frame window")
      return  -- Don't process as ROM file
    end
  end
  
  -- Default behavior: handle as ROM/project file using the guarded loader
  local filename = file and file.getFilename and file:getFilename() or file
  M.requestLoad(app, filename or file)
end

function M.saveProject(app)
  if not appHasLoadedRom(app) then
    app:setStatus("Open a ROM before saving.")
    return false
  end

  local state = app.appEditState

  ensureProjectSavePaths(app, state)

  if not app.edits then
    app.edits = GameArtController.newEdits()
  end

  local project = GameArtController.snapshotProject(
    app.wm,
    app.winBank,
    state.currentBank,
    app.edits,
    app
  )
  local ok, err = GameArtController.saveProjectLua(app.projectPath, project)
  app:setStatus(
    ok and ("Saved project: " .. app.projectPath)
      or ("Project save failed: " .. tostring(err))
  )
  return ok
end

function M.saveEncodedProject(app)
  if not appHasLoadedRom(app) then
    app:setStatus("Open a ROM before saving.")
    return false
  end

  local state = app.appEditState

  ensureProjectSavePaths(app, state)

  if not app.edits then
    app.edits = GameArtController.newEdits()
  end

  local project = GameArtController.snapshotProject(
    app.wm,
    app.winBank,
    state.currentBank,
    app.edits,
    app
  )
  local ok, err = GameArtController.saveProjectPpux(app.encodedProjectPath, project)
  app:setStatus(
    ok and ("Saved encoded project: " .. app.encodedProjectPath)
      or ("Encoded project save failed: " .. tostring(err))
  )
  return ok
end

return M
