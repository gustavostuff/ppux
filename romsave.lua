local chr = require("chr")

local RomSave = {}

local function splitPath(p)
  local dir, base = p:match("^(.*)[/\\]([^/\\]+)$")
  if not dir then return "", p end
  return dir, base
end

local function stripExt(name)
  return (name:gsub("%.[^%.]+$", ""))
end

local function baseRomStem(path)
  local _, base = splitPath(path or "rom.nes")
  local stem = stripExt(base)
  stem = stem:gsub("_edited$", "")
  return stem
end

function RomSave.saveEditedROM(originalPath, romRaw, meta, banksBytes)
  local newROM = chr.replaceCHR(romRaw, meta, banksBytes)

  local dir, base = splitPath(originalPath or "rom.nes")
  local stem = baseRomStem(originalPath)
  local outName = stem .. "_edited.nes"
  local sep = (dir ~= "" and (dir:sub(-1) == "/" or dir:sub(-1) == "\\")) and ""
              or (dir ~= "" and (package.config:sub(1,1) == "\\" and "\\" or "/") or "")
  local outPath = (dir ~= "" and (dir .. sep .. outName) or outName)

  local fh, err = io.open(outPath, "wb")
  if not fh then
    return false, ("Failed to open for write: %s"):format(err or "unknown error")
  end
  local okWrite, errWrite = fh:write(newROM)
  fh:close()
  if not okWrite then
    return false, errWrite or "write failed"
  end
  return true, outPath
end

function RomSave.saveRawROM(originalPath, romRaw)
  local dir, base = splitPath(originalPath or "rom.nes")
  local stem = baseRomStem(originalPath)
  local outName = stem .. "_edited.nes"
  local sep = (dir ~= "" and (dir:sub(-1) == "/" or dir:sub(-1) == "\\")) and ""
              or (dir ~= "" and (package.config:sub(1,1) == "\\" and "\\" or "/") or "")
  local outPath = (dir ~= "" and (dir .. sep .. outName) or outName)

  local fh, err = io.open(outPath, "wb")
  if not fh then
    return false, ("Failed to open for write: %s"):format(err or "unknown error")
  end
  local okWrite, errWrite = fh:write(romRaw or "")
  fh:close()
  if not okWrite then
    return false, errWrite or "write failed"
  end
  return true, outPath
end

function RomSave.readByteFromAddress(romRaw, addr)
  return chr.readByteFromAddress(romRaw, addr)
end

function RomSave.writeByteToAddress(romRaw, addr, value)
  return chr.writeByteToAddress(romRaw, addr, value)
end

return RomSave
