-- sprite_rom_persistence_controller.lua
-- Writes sprite OAM-backed displacements/attributes back into ROM bytes.

local chr = require("chr")

local M = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function wrapByte(v)
  if v == nil then return 0 end
  v = math.floor(v)
  v = v % 256
  if v < 0 then v = v + 256 end
  return v
end

local function mergePaletteIntoAttr(attr, paletteNumber)
  attr = clamp(attr or 0, 0, 255)
  if not paletteNumber then return attr end
  local palBits = (math.floor(paletteNumber) - 1) % 4
  return (attr - (attr % 4)) + palBits
end

local function applyMirrorToAttr(attr, mirrorX, mirrorY)
  attr = clamp(attr or 0, 0, 255)
  local function setBit(byte, bitIndex, on)
    local pow = 2 ^ bitIndex
    local cur = math.floor(byte / pow) % 2
    if on and cur == 0 then
      byte = byte + pow
    elseif (not on) and cur == 1 then
      byte = byte - pow
    end
    return byte
  end
  if mirrorX ~= nil then
    attr = setBit(attr, 6, mirrorX and true or false)
  end
  if mirrorY ~= nil then
    attr = setBit(attr, 7, mirrorY and true or false)
  end
  return attr
end

function M.applyDisplacementsToROMForLayer(layer, romRaw)
  if type(romRaw) ~= "string" then
    return nil, "romRaw must be a string"
  end
  if not (layer and layer.kind == "sprite") then
    return romRaw
  end

  local newRom = romRaw

  for _, s in ipairs(layer.items or {}) do
    local dx = s.dx or 0
    local dy = s.dy or 0
    if type(s.startAddr) == "number" then
      local baseX = s.baseX or 0
      local baseY = s.baseY or 0

      local newX = wrapByte(baseX + dx)
      local newY = wrapByte(baseY + dy)

      local tileByte = s.oamTile or s.tile or 0
      local attr = s.attr or 0

      tileByte = clamp(tileByte, 0, 255)
      attr = mergePaletteIntoAttr(attr, s.paletteNumber)
      attr = applyMirrorToAttr(attr, s.mirrorX, s.mirrorY)
      s.attr = attr

      local bytes = { newY, tileByte, attr, newX }
      local written, err = chr.writeBytesToRange(newRom, s.startAddr, 4, bytes)
      if not written then
        return nil, "[SpriteController] writeBytesToRange failed: " .. tostring(err)
      end
      newRom = written
    end
  end

  return newRom
end

function M.applyDisplacementsToROMForWindows(windows, romRaw)
  local newRom = romRaw
  for _, win in ipairs(windows or {}) do
    if win.layers and win.getSpriteLayers then
      for _, info in ipairs(win:getSpriteLayers() or {}) do
        local updated, err = M.applyDisplacementsToROMForLayer(info.layer, newRom)
        if not updated then
          return nil, err
        end
        newRom = updated
      end
    end
  end
  return newRom
end

return M
