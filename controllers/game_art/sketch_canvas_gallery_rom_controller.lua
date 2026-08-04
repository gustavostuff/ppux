-- sketch_canvas_gallery_rom_controller.lua
-- Assemble a gallery .nes from packed sketch windows via asm/gallery (ca65/ld65).
--
-- Pipeline:
--   1. prepareWritableGalleryDir (copy template to a writable cache; needed for
--      fused EXE / AppImage where asm/ lives inside the package)
--   2. encodeHardwareSlideFromSketch -> data/chr|nam|pal
--   3. write slide_meta.s
--   4. run ca65 + ld65 (no GNU make / bash required) -> gallery.nes
--   5. copy beside project/ROM as {stem}_gallery.nes

local WindowCaps = require("controllers.window.window_capabilities")
local SketchCanvasPackController = require("controllers.game_art.sketch_canvas_pack_controller")
local SketchCanvasExportController = require("controllers.game_art.sketch_canvas_export_controller")
local FilesystemPath = require("utils.filesystem_path")

local M = {}

M.MAX_SLIDES = 16

-- Must match asm/gallery/Makefile SRCS order (ld65 object list).
local GALLERY_SOURCES = {
  "header",
  "vars",
  "cnrom",
  "controller",
  "palette",
  "gallery",
  "nmi",
  "reset",
  "main",
  "nam_slots",
  "chr_slots",
  "slide_meta",
  "vectors",
}

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

local function pathSep()
  return FilesystemPath.separator()
end

local function joinPath(...)
  return FilesystemPath.join(...)
end

local function fileExists(path)
  return FilesystemPath.pathExists(path)
end

local function ensureDir(path)
  return FilesystemPath.ensureDir(path)
end

local function shellQuote(path)
  path = tostring(path or "")
  if IS_WINDOWS then
    return '"' .. path:gsub('"', "") .. '"'
  end
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function runShell(cmd)
  local result = os.execute(cmd)
  if result == true or result == 0 then
    return true
  end
  return false, result
end

--- Resolve read-only template asm/gallery on a real disk (dev / unzipped trees).
function M.resolveGalleryAsmSourceDir()
  local candidates = {}
  local source = nil
  if love and love.filesystem and love.filesystem.getSource then
    source = love.filesystem.getSource()
  end
  if type(source) == "string" and source ~= "" then
    -- Fused EXE / .love file: source is a file, not a directory with asm/.
    local isFile = false
    if love.filesystem.isFused and love.filesystem.isFused() then
      isFile = true
    elseif source:lower():match("%.love$") or source:lower():match("%.exe$") then
      isFile = true
    end
    if not isFile then
      candidates[#candidates + 1] = joinPath(source, "asm", "gallery")
      candidates[#candidates + 1] = joinPath(source, "..", "asm", "gallery")
    end
  end
  local cwd = FilesystemPath.getWorkingDirectory()
  if type(cwd) == "string" and cwd ~= "" then
    candidates[#candidates + 1] = joinPath(cwd, "asm", "gallery")
    candidates[#candidates + 1] = joinPath(cwd, "..", "asm", "gallery")
  end
  candidates[#candidates + 1] = "asm/gallery"
  candidates[#candidates + 1] = "../asm/gallery"

  for _, dir in ipairs(candidates) do
    if fileExists(joinPath(dir, "nes.cfg")) and fileExists(joinPath(dir, "s", "main.s")) then
      return dir
    end
  end
  return nil, "asm/gallery source not found on disk"
end

-- Back-compat alias used by older tests / callers.
function M.resolveGalleryAsmDir()
  return M.resolveGalleryAsmSourceDir()
end

local function getWritableGalleryRoot()
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local saveDir = love.filesystem.getSaveDirectory()
    if type(saveDir) == "string" and saveDir ~= "" then
      return joinPath(saveDir, "gallery_build")
    end
  end
  local SettingsPath = require("utils.settings_path")
  if SettingsPath.getConfigDir then
    local cfg = SettingsPath.getConfigDir()
    if type(cfg) == "string" and cfg ~= "" then
      return joinPath(cfg, "gallery_build")
    end
  end
  return joinPath(FilesystemPath.getTempDir(), "ppux_gallery_build")
end

local function copyBytesToPath(data, destPath)
  local parent = destPath:match("^(.*)[/\\][^/\\]+$")
  if parent and parent ~= "" then
    ensureDir(parent)
  end
  return SketchCanvasExportController.writeBinaryFile(destPath, data)
end

local function copyOsFile(src, dst)
  local inFh, inErr = io.open(src, "rb")
  if not inFh then
    return false, inErr or "open source failed"
  end
  local data = inFh:read("*a")
  inFh:close()
  return copyBytesToPath(data, dst)
end

local function loveInfo(virtPath)
  if not (love and love.filesystem and love.filesystem.getInfo) then
    return nil
  end
  return love.filesystem.getInfo(virtPath)
end

local function copyLoveTreeFiles(virtDir, destRoot, relPrefix)
  relPrefix = relPrefix or ""
  if not (love and love.filesystem and love.filesystem.getDirectoryItems) then
    return false, "love.filesystem unavailable"
  end
  local items = love.filesystem.getDirectoryItems(virtDir)
  if type(items) ~= "table" then
    return false, "missing " .. virtDir
  end
  local copied = 0
  for _, name in ipairs(items) do
    local virtPath = virtDir .. "/" .. name
    local info = loveInfo(virtPath)
    local rel = relPrefix == "" and name or (relPrefix .. "/" .. name)
    if info and info.type == "directory" then
      -- Skip generated / bulky trees; PPUX writes data/ itself.
      if name ~= "data" and name ~= "o" then
        local ok, err = copyLoveTreeFiles(virtPath, destRoot, rel)
        if not ok then
          return false, err
        end
        copied = copied + 1
      end
    elseif info and info.type == "file" then
      -- Skip docs and build outputs; keep Makefile for optional manual builds.
      local lower = name:lower()
      if lower ~= "readme.md"
        and lower ~= ".gitignore"
        and lower ~= "gallery.nes"
        and not lower:match("%.o$")
      then
        local data = love.filesystem.read(virtPath)
        if type(data) ~= "string" then
          return false, "failed to read " .. virtPath
        end
        local dest = joinPath(destRoot, (rel:gsub("/", pathSep())))
        local ok, err = copyBytesToPath(data, dest)
        if not ok then
          return false, err or ("write failed: " .. dest)
        end
        copied = copied + 1
      end
    end
  end
  return true, copied
end

local function copyOsTreeTemplate(srcRoot, destRoot)
  local files = {
    "nes.cfg",
    "Makefile",
  }
  for _, name in ipairs(GALLERY_SOURCES) do
    files[#files + 1] = joinPath("s", name .. ".s")
  end
  for _, rel in ipairs(files) do
    local src = joinPath(srcRoot, rel)
    if fileExists(src) then
      local dst = joinPath(destRoot, rel)
      local ok, err = copyOsFile(src, dst)
      if not ok then
        return false, err or ("copy failed: " .. rel)
      end
    end
  end
  return true
end

--- Ensure a writable gallery work tree (template sources + empty data/o dirs).
--  Always uses a cache under the save/config/temp dir so fused packages can build.
function M.prepareWritableGalleryDir(opts)
  opts = opts or {}
  local dest = opts.destDir or getWritableGalleryRoot()
  if not ensureDir(dest) then
    return nil, "cannot create gallery build dir: " .. tostring(dest)
  end

  local okLove = false
  if loveInfo("asm/gallery/nes.cfg") or loveInfo("asm/gallery/Makefile") then
    local ok, err = copyLoveTreeFiles("asm/gallery", dest, "")
    if not ok then
      return nil, err
    end
    okLove = true
  end

  if not okLove then
    local src, srcErr = M.resolveGalleryAsmSourceDir()
    if not src then
      return nil, srcErr or "asm/gallery template not found (package missing asm/gallery?)"
    end
    -- If dest is already the source tree, use it in place (dev convenience).
    local srcAbs = FilesystemPath.toAbsolutePath(src) or src
    local destAbs = FilesystemPath.toAbsolutePath(dest) or dest
    if srcAbs == destAbs then
      -- fall through to ensure data dirs
    else
      local ok, err = copyOsTreeTemplate(src, dest)
      if not ok then
        return nil, err
      end
    end
  end

  if not fileExists(joinPath(dest, "nes.cfg")) then
    return nil, "gallery template missing nes.cfg after prepare"
  end
  if not fileExists(joinPath(dest, "s", "main.s")) then
    return nil, "gallery template missing s/main.s after prepare"
  end

  ensureDir(joinPath(dest, "s"))
  ensureDir(joinPath(dest, "o"))
  ensureDir(joinPath(dest, "data", "chr"))
  ensureDir(joinPath(dest, "data", "nam"))
  for i = 0, M.MAX_SLIDES - 1 do
    ensureDir(joinPath(dest, "data", "pal", string.format("slide%02d", i)))
  end

  return dest
end

function M.collectPackedSketches(wm, sketchWindows)
  local list = {}
  if type(sketchWindows) == "table" and #sketchWindows > 0 then
    for _, win in ipairs(sketchWindows) do
      if WindowCaps.isSketchCanvas(win)
        and not win._closed
        and SketchCanvasPackController.hasPackData(win)
      then
        list[#list + 1] = win
      end
    end
    return list
  end

  if not wm then
    return list
  end
  local windows = wm.windows or wm._windows
  if type(windows) ~= "table" then
    return list
  end
  for _, win in ipairs(windows) do
    if WindowCaps.isSketchCanvas(win)
      and not win._closed
      and SketchCanvasPackController.hasPackData(win)
    then
      list[#list + 1] = win
    end
  end
  return list
end

function M.writeSlideMeta(path, slideCount)
  local n = math.floor(tonumber(slideCount) or 0)
  if n < 1 then
    n = 1
  elseif n > M.MAX_SLIDES then
    n = M.MAX_SLIDES
  end
  local body = table.concat({
    "; Generated by PPUX gallery export - do not edit by hand.",
    ".export slide_count",
    "",
    '.segment "RODATA"',
    "slide_count:",
    string.format("  .byte %d", n),
    "",
  }, "\n")
  return SketchCanvasExportController.writeBinaryFile(path, body)
end

function M.writeSlideAssets(asmDir, sketches, wm)
  if type(asmDir) ~= "string" or asmDir == "" then
    return false, "missing asm dir"
  end
  if type(sketches) ~= "table" or #sketches < 1 then
    return false, "no packed sketch canvases"
  end
  if #sketches > M.MAX_SLIDES then
    return false, string.format("at most %d sketch canvases (got %d)", M.MAX_SLIDES, #sketches)
  end

  local chrDir = joinPath(asmDir, "data", "chr")
  local namDir = joinPath(asmDir, "data", "nam")
  local palRoot = joinPath(asmDir, "data", "pal")
  if not ensureDir(chrDir) or not ensureDir(namDir) or not ensureDir(palRoot) then
    return false, "cannot create gallery data directories"
  end

  for i, win in ipairs(sketches) do
    -- Hardware bake: NES BG index 0 always uses $3F00, so per-attr color 0 from
    -- sketch mode is remapped into visible CHR indices when needed.
    local chr4k, nam, palBlob, slideErr =
      SketchCanvasExportController.encodeHardwareSlideFromSketch(win, wm)
    if not chr4k then
      return false, string.format("slide %d: %s", i - 1, tostring(slideErr or nam or palBlob))
    end
    local chr8k, padErr = SketchCanvasExportController.padChrBankTo8KiB(chr4k)
    if not chr8k then
      return false, string.format("slide %d pad: %s", i - 1, tostring(padErr))
    end
    if type(nam) ~= "string" or #nam ~= SketchCanvasExportController.NAMETABLE_FULL then
      return false, string.format(
        "slide %d nametable: expected %d bytes",
        i - 1,
        SketchCanvasExportController.NAMETABLE_FULL
      )
    end
    if type(palBlob) ~= "string" or #palBlob ~= 32 then
      return false, string.format("slide %d palette: expected 32 bytes", i - 1)
    end

    local stem = string.format("slide%02d", i - 1)
    local palDir = joinPath(palRoot, stem)
    if not ensureDir(palDir) then
      return false, "cannot create " .. palDir
    end
    local okChr, errChr = SketchCanvasExportController.writeBinaryFile(
      joinPath(chrDir, stem .. ".chr"),
      chr8k
    )
    if not okChr then
      return false, errChr
    end
    local okNam, errNam = SketchCanvasExportController.writeBinaryFile(
      joinPath(namDir, stem .. ".nam"),
      nam
    )
    if not okNam then
      return false, errNam
    end
    local okPal, errPal = SketchCanvasExportController.writeBinaryFile(
      joinPath(palDir, "main.pal"),
      palBlob
    )
    if not okPal then
      return false, errPal
    end
  end

  -- Keep unused slots as zeros so CHR/NT/PAL segments stay valid.
  local emptyChr = string.rep("\0", SketchCanvasExportController.CHR_BANK_8K)
  local emptyNam = string.rep("\0", SketchCanvasExportController.NAMETABLE_FULL)
  local emptyPal = SketchCanvasExportController.encodePaletteFromSketch(nil)
  for i = #sketches, M.MAX_SLIDES - 1 do
    local stem = string.format("slide%02d", i)
    local okChr, errChr = SketchCanvasExportController.writeBinaryFile(
      joinPath(chrDir, stem .. ".chr"),
      emptyChr
    )
    if not okChr then
      return false, errChr
    end
    local okNam, errNam = SketchCanvasExportController.writeBinaryFile(
      joinPath(namDir, stem .. ".nam"),
      emptyNam
    )
    if not okNam then
      return false, errNam
    end
    local palDir = joinPath(palRoot, stem)
    if not ensureDir(palDir) then
      return false, "cannot create " .. palDir
    end
    local okPal, errPal = SketchCanvasExportController.writeBinaryFile(
      joinPath(palDir, "main.pal"),
      emptyPal
    )
    if not okPal then
      return false, errPal
    end
  end

  return true, #sketches
end

local function readCommandOutput(cmd)
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end
  local out = handle:read("*a")
  handle:close()
  if type(out) ~= "string" then
    return nil
  end
  out = out:gsub("\r", "")
  local line = out:match("([^\n]+)")
  if type(line) == "string" then
    line = line:match("^%s*(.-)%s*$")
  end
  if line and line ~= "" then
    return line
  end
  return nil
end

local function findTool(name)
  local envHome = os.getenv("CC65_HOME")
  if type(envHome) == "string" and envHome ~= "" then
    local binName = IS_WINDOWS and (name .. ".exe") or name
    local candidate = joinPath(envHome, "bin", binName)
    if fileExists(candidate) then
      return candidate
    end
  end

  local whichCmd
  if IS_WINDOWS then
    whichCmd = "where " .. name .. " 2>NUL"
  else
    whichCmd = "command -v " .. name .. " 2>/dev/null"
  end
  local found = readCommandOutput(whichCmd)
  if found and found ~= "" then
    return found
  end
  return nil
end

local function withWorkingDirCommand(dir, innerCmd)
  if IS_WINDOWS then
    return "cd /d " .. shellQuote(dir) .. " && " .. innerCmd
  end
  return "cd " .. shellQuote(dir) .. " && " .. innerCmd
end

local CC65_MISSING_MESSAGE = "Gallery ROM needs cc65 tools on PATH (ca65 and ld65). "
  .. "Install from https://cc65.github.io/ and reopen PPUX. "
  .. "Optional: set CC65_HOME to your cc65 install root."

--- Returns true when ca65 and ld65 are available; otherwise false, user message.
function M.checkCc65Tools()
  local ca65 = findTool("ca65")
  local ld65 = findTool("ld65")
  if ca65 and ld65 then
    return true, ca65, ld65
  end
  local missing = {}
  if not ca65 then
    missing[#missing + 1] = "ca65"
  end
  if not ld65 then
    missing[#missing + 1] = "ld65"
  end
  return false, CC65_MISSING_MESSAGE .. " Missing: " .. table.concat(missing, ", ") .. "."
end

--- Assemble gallery.nes with ca65/ld65 (no make/bash). cwd = asmDir.
function M.assembleGalleryRom(asmDir)
  if type(asmDir) ~= "string" or asmDir == "" then
    return false, "missing asm dir"
  end
  if not fileExists(joinPath(asmDir, "nes.cfg")) then
    return false, "nes.cfg missing in " .. asmDir
  end

  local toolsOk, ca65OrErr, ld65 = M.checkCc65Tools()
  if not toolsOk then
    return false, ca65OrErr
  end
  local ca65 = ca65OrErr

  if not ensureDir(joinPath(asmDir, "o")) then
    return false, "cannot create object dir"
  end

  os.remove(joinPath(asmDir, "gallery.nes"))

  local objRel = {}
  for _, name in ipairs(GALLERY_SOURCES) do
    local srcRel = "s/" .. name .. ".s"
    local objName = "o/" .. name .. ".o"
    if not fileExists(joinPath(asmDir, "s", name .. ".s")) then
      return false, "missing source " .. srcRel
    end
    local cmd = withWorkingDirCommand(
      asmDir,
      shellQuote(ca65) .. " -o " .. shellQuote(objName) .. " " .. shellQuote(srcRel)
    )
    local ok, status = runShell(cmd)
    if not ok then
      return false, string.format("ca65 failed for %s (status %s)", name, tostring(status))
    end
    objRel[#objRel + 1] = objName
  end

  local ldParts = {
    shellQuote(ld65),
    "-C",
    shellQuote("nes.cfg"),
    "-o",
    shellQuote("gallery.nes"),
  }
  for _, obj in ipairs(objRel) do
    ldParts[#ldParts + 1] = shellQuote(obj)
  end
  local ldCmd = withWorkingDirCommand(asmDir, table.concat(ldParts, " "))
  local okLd, ldStatus = runShell(ldCmd)
  if not okLd then
    return false, "ld65 failed (status " .. tostring(ldStatus) .. ")"
  end

  if not fileExists(joinPath(asmDir, "gallery.nes")) then
    return false, "assemble succeeded but gallery.nes missing"
  end
  return true
end

function M.defaultOutPath(app)
  local dir = SketchCanvasExportController.defaultExportDir(app)
  local stem = "gallery"
  local projectPath = app and (app.projectPath or app.encodedProjectPath)
  if type(projectPath) == "string" and projectPath ~= "" then
    local base = projectPath:match("([^/\\]+)$") or "project"
    stem = (base:gsub("%.[^%.]+$", "")):gsub("_project$", "") .. "_gallery"
  else
    local romPath = app and app.appEditState and app.appEditState.romOriginalPath
    if type(romPath) == "string" and romPath ~= "" then
      local base = romPath:match("([^/\\]+)$") or "rom.nes"
      stem = (base:gsub("%.[^%.]+$", "")):gsub("_edited$", "") .. "_gallery"
    end
  end
  return joinPath(dir, stem .. ".nes")
end

--- Build gallery ROM from packed sketch windows.
--  opts.asmDir - override writable work dir (skips prepare; tests)
--  opts.outPath - override output .nes path
--  opts.skipMake / opts.skipAssemble - write assets only
--  @return ok, pathOrErr
function M.buildGalleryRom(app, sketchWindows, opts)
  opts = opts or {}
  local wm = app and app.wm
  if type(wm) == "function" then
    wm = wm()
  end

  local sketches = M.collectPackedSketches(wm, sketchWindows)
  if #sketches < 1 then
    return false, "no packed sketch canvases to export"
  end
  if #sketches > M.MAX_SLIDES then
    return false, string.format("at most %d sketch canvases (got %d)", M.MAX_SLIDES, #sketches)
  end

  local asmDir, asmErr = opts.asmDir, nil
  if not asmDir then
    asmDir, asmErr = M.prepareWritableGalleryDir()
  end
  if not asmDir then
    return false, asmErr or "gallery build dir unavailable"
  end

  local okAssets, countOrErr = M.writeSlideAssets(asmDir, sketches, wm)
  if not okAssets then
    return false, countOrErr
  end

  local metaPath = joinPath(asmDir, "s", "slide_meta.s")
  local okMeta, metaErr = M.writeSlideMeta(metaPath, countOrErr)
  if not okMeta then
    return false, metaErr
  end

  if opts.skipMake or opts.skipAssemble then
    return true, asmDir
  end

  local okAsm, asmFail = M.assembleGalleryRom(asmDir)
  if not okAsm then
    return false, asmFail
  end

  local built = joinPath(asmDir, "gallery.nes")
  local outPath = opts.outPath or M.defaultOutPath(app)
  local outParent = outPath:match("^(.*)[/\\][^/\\]+$")
  if outParent and outParent ~= "" then
    ensureDir(outParent)
  end
  local okCopy, copyErr = copyOsFile(built, outPath)
  if not okCopy then
    return false, copyErr
  end
  return true, outPath
end

return M
