-- sprite_rom_persistence_controller.lua
-- Writes sprite OAM-backed displacements/attributes back into ROM bytes.
-- For ROM-backed sprites with no overlay `bank`, the persisted tile byte is the pattern-table logical
-- index (matching the linked pattern_table window ordering), consistent with hydrate + resolveTile.
local chr = require("chr")
local OamDisplacement = require("controllers.sprite.oam_displacement")

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

local function buildSpriteBytes(s)
  local dx = OamDisplacement.normalizeAxisDelta(s.dx)
  local dy = OamDisplacement.normalizeAxisDelta(s.dy)

  local baseX = tonumber(s.baseX) or 0
  local baseY = tonumber(s.baseY) or 0

  local newX = wrapByte(baseX + dx)
  local newY = wrapByte(baseY + dy)

  local tileByte = tonumber(s.oamTile) or tonumber(s.tile) or 0
  local attr = tonumber(s.attr) or 0

  tileByte = clamp(tileByte, 0, 255)
  attr = mergePaletteIntoAttr(attr, s.paletteNumber)
  attr = applyMirrorToAttr(attr, s.mirrorX, s.mirrorY)

  return { newY, tileByte, attr, newX }, attr
end

--- Desired wrapped OAM X/Y for a sprite (editor displacement vs ROM base).
local function desiredWrappedPosition(s)
  local bytes = buildSpriteBytes(s)
  return bytes[4], bytes[1]
end

local function spriteHasEditorDisplacement(s)
  if not s then
    return false
  end
  local dx = OamDisplacement.normalizeAxisDelta(s.dx)
  local dy = OamDisplacement.normalizeAxisDelta(s.dy)
  return s.hasMoved == true or dx ~= 0 or dy ~= 0
end

--- True when every *moved* candidate wants the same wrapped X/Y.
--- Unmoved peers (dx/dy = 0) must not veto baking an agreed editor move:
--- shared startAddr across PPU frames / OAM windows is common, and stale
--- unmoved copies would otherwise leave displacements out of `_edited.nes`.
local function movedCandidatesAgreeOnPosition(candidates)
  local firstX, firstY = nil, nil
  for _, s in ipairs(candidates or {}) do
    if type(s.startAddr) == "number" and spriteHasEditorDisplacement(s) then
      local x, y = desiredWrappedPosition(s)
      if firstX == nil then
        firstX, firstY = x, y
      elseif x ~= firstX or y ~= firstY then
        return false
      end
    end
  end
  return true
end

local function writeSpriteToROM(s, romRaw, opts)
  if type(s.startAddr) ~= "number" then
    return romRaw, nil
  end

  opts = opts or {}
  local bytes, attr = buildSpriteBytes(s)
  s.attr = attr

  -- Shared startAddr across windows (e.g. two cutscene frames) can disagree on
  -- editor dx/dy. Never bake a contested position into ROM; keep existing X/Y.
  if opts.preservePosition == true then
    local existing, readErr = chr.readBytesFromRange(romRaw, s.startAddr, s.startAddr + 3)
    if not existing then
      return nil, "[SpriteController] readBytesFromRange failed: " .. tostring(readErr)
    end
    bytes[1] = existing[1]
    bytes[4] = existing[4]
  end

  local written, err = chr.writeBytesToRange(romRaw, s.startAddr, 4, bytes)
  if not written then
    return nil, "[SpriteController] writeBytesToRange failed: " .. tostring(err)
  end

  return written, nil
end

local function mirrorExplicitnessCount(s)
  local count = 0
  if s and s.mirrorX ~= nil then count = count + 1 end
  if s and s.mirrorY ~= nil then count = count + 1 end
  return count
end

local function scoreSpriteCandidate(s)
  if not s then return -math.huge end
  local score = 0

  if s._mirrorXOverrideSet == true then score = score + 16 end
  if s._mirrorYOverrideSet == true then score = score + 16 end

  if s.mirrorX ~= nil then score = score + 8 end
  if s.mirrorY ~= nil then score = score + 8 end

  if s.paletteNumber ~= nil then score = score + 4 end

  local dx = OamDisplacement.normalizeAxisDelta(s.dx)
  local dy = OamDisplacement.normalizeAxisDelta(s.dy)
  if s.hasMoved or dx ~= 0 or dy ~= 0 then
    score = score + 2
  end

  if s.attr ~= nil then score = score + 1 end

  return score
end

local function chooseBestSpriteCandidate(candidates)
  local best = nil
  local bestScore = -math.huge
  local bestMirrorCount = -1

  for _, s in ipairs(candidates or {}) do
    local score = scoreSpriteCandidate(s)
    local mirrorCount = mirrorExplicitnessCount(s)
    if score > bestScore or (score == bestScore and mirrorCount >= bestMirrorCount) then
      best = s
      bestScore = score
      bestMirrorCount = mirrorCount
    end
  end

  return best
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
    if type(s.startAddr) == "number" and s._addModalPreview ~= true then
      local written, err = writeSpriteToROM(s, newRom)
      if not written then
        return nil, err
      end
      newRom = written
    end
  end

  return newRom
end

function M.applyDisplacementsToROMForWindows(windows, romRaw)
  local newRom = romRaw

  local byAddr = {}
  local orderedAddrs = {}

  local function addCandidate(sprite)
    if type(sprite.startAddr) ~= "number" then
      return
    end
    if sprite._addModalPreview == true then
      return
    end
    local addr = sprite.startAddr
    if not byAddr[addr] then
      byAddr[addr] = {}
      orderedAddrs[#orderedAddrs + 1] = addr
    end
    byAddr[addr][#byAddr[addr] + 1] = sprite
  end

  for _, win in ipairs(windows or {}) do
    if win.layers and win.getSpriteLayers then
      for _, info in ipairs(win:getSpriteLayers() or {}) do
        for _, s in ipairs((info.layer and info.layer.items) or {}) do
          addCandidate(s)
        end
      end
    end
  end

  for _, addr in ipairs(orderedAddrs) do
    local candidates = byAddr[addr]
    local sprite = chooseBestSpriteCandidate(candidates)
    if sprite then
      -- Only truly conflicting *moves* preserve ROM X/Y. Unmoved peers do not veto.
      local preservePosition = not movedCandidatesAgreeOnPosition(candidates)
      local updated, err = writeSpriteToROM(sprite, newRom, {
        preservePosition = preservePosition,
      })
      if not updated then
        return nil, err
      end
      newRom = updated
    end
  end

  return newRom
end

return M
