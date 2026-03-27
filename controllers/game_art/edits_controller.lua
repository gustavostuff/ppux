local chr = require("chr")

local M = {}

local function decompressTileEdits(tileEdit)
  if not tileEdit or type(tileEdit) ~= "table" then return {} end

  local decompressed = {}
  for key, color in pairs(tileEdit) do
    local startStr, endStr = key:match("^(.+)-(.+)$")
    if startStr and endStr then
      local x1, y1 = startStr:match("^(%d+)_(%d+)$")
      local x2, y2 = endStr:match("^(%d+)_(%d+)$")
      x1, y1, x2, y2 = tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)

      if x1 and y1 and x2 and y2 then
        if x1 == x2 and y1 == y2 then
          decompressed[string.format("%d_%d", x1, y1)] = color
        elseif x1 == x2 then
          for y = y1, y2 do
            decompressed[string.format("%d_%d", x1, y)] = color
          end
        elseif y1 == y2 then
          for x = x1, x2 do
            decompressed[string.format("%d_%d", x, y1)] = color
          end
        else
          for y = y1, y2 do
            for x = x1, x2 do
              decompressed[string.format("%d_%d", x, y)] = color
            end
          end
        end
      end
    else
      local x, y = key:match("^(%d+)_(%d+)$")
      if x and y then
        decompressed[key] = color
      end
    end
  end

  return decompressed
end

local function encodeTileEditRLE(tileEdit)
  if not tileEdit or type(tileEdit) ~= "table" then return nil end
  local expanded = decompressTileEdits(tileEdit)
  local cells = {}
  for y = 0, 7 do
    for x = 0, 7 do
      local key = string.format("%d_%d", x, y)
      local v = expanded[key]
      cells[#cells + 1] = v == nil and -1 or v
    end
  end

  local parts = {}
  local current = cells[1]
  local count = 1
  for i = 2, #cells do
    local v = cells[i]
    if v == current then
      count = count + 1
    else
      parts[#parts + 1] = string.format("%d:%d", current, count)
      current = v
      count = 1
    end
  end
  parts[#parts + 1] = string.format("%d:%d", current, count)

  return table.concat(parts, ";")
end

local function decodeTileEditRLE(rle)
  if type(rle) ~= "string" or rle == "" then return {} end
  local cells = {}
  for token in rle:gmatch("([^;]+)") do
    local v, len = token:match("^(-?%d+):(%d+)$")
    v = tonumber(v)
    len = tonumber(len)
    if v and len then
      for _ = 1, len do cells[#cells + 1] = v end
    end
  end
  while #cells < 64 do cells[#cells + 1] = -1 end

  local out = {}
  local idx = 1
  for y = 0, 7 do
    for x = 0, 7 do
      local v = cells[idx]
      if v and v >= 0 then
        out[string.format("%d_%d", x, y)] = v
      end
      idx = idx + 1
    end
  end
  return out
end

local function ensureBankTile(edits, bank, tile)
  local b = edits.banks[bank]
  if not b then b = {}; edits.banks[bank] = b end
  local t = b[tile]
  if not t then t = {}; b[tile] = t end
  return t
end

local function cloneTileEdit(tileEdit)
  local out = {}
  if type(tileEdit) ~= "table" then
    return out
  end
  for k, v in pairs(tileEdit) do
    out[k] = v
  end
  return out
end

function M.newEdits()
  return { banks = {} }
end

function M.recordEdit(edits, bankIdx, tileIdx, x, y, color)
  edits.banks = edits.banks or {}
  local tileTbl = ensureBankTile(edits, bankIdx, tileIdx)
  tileTbl[x .. "_" .. y] = color
end

function M.compressEdits(edits)
  if not edits or type(edits) ~= "table" or type(edits.banks) ~= "table" then
    return { banks = {} }
  end

  local out = { banks = {} }
  for bankIdx, tiles in pairs(edits.banks) do
    local bankOut = {}
    for tileIdx, tileEdit in pairs(tiles) do
      local tileNum = tonumber(tileIdx)
      if tileNum then
        local rle
        if type(tileEdit) == "string" then
          rle = tileEdit
        else
          rle = encodeTileEditRLE(tileEdit)
        end
        if rle and rle ~= "" then
          bankOut[tostring(tileNum)] = rle
        end
      end
    end
    if next(bankOut) then
      out.banks[bankIdx] = bankOut
    end
  end

  return out
end

function M.decompressEdits(edits)
  if not edits or type(edits) ~= "table" or type(edits.banks) ~= "table" then
    return { banks = {} }
  end

  local out = { banks = {} }
  for bankIdx, tiles in pairs(edits.banks) do
    out.banks[bankIdx] = {}
    for tileKey, tileEdit in pairs(tiles) do
      local startStr, endStr = tostring(tileKey):match("^(%d+)-(%d+)$")
      local decoded
      if type(tileEdit) == "string" then
        decoded = decodeTileEditRLE(tileEdit)
      else
        decoded = decompressTileEdits(tileEdit)
      end

      if startStr and endStr then
        local startIdx, endIdx = tonumber(startStr), tonumber(endStr)
        if startIdx and endIdx then
          for idx = startIdx, endIdx do
            out.banks[bankIdx][idx] = cloneTileEdit(decoded)
          end
        end
      else
        local tileNum = tonumber(tileKey)
        if tileNum then
          out.banks[bankIdx][tileNum] = decoded
        end
      end
    end
    if not next(out.banks[bankIdx]) then
      out.banks[bankIdx] = nil
    end
  end

  return out
end

function M.compressEditsRLE(edits)
  return M.compressEdits(edits)
end

function M.decompressEditsRLE(editsRLE)
  return M.decompressEdits(editsRLE)
end

function M.applyEdits(edits, tilesPool, chrBanksBytes, ensureTiles)
  if not (edits and edits.banks) then return end
  for bankIdx, tiles in pairs(edits.banks) do
    bankIdx = tonumber(bankIdx)
    local bankBytes = chrBanksBytes and chrBanksBytes[bankIdx]
    local pool = tilesPool and tilesPool[bankIdx]
    if bankBytes then
      for tileKey, pixels in pairs(tiles) do
        local startStr, endStr = tostring(tileKey):match("^(%d+)-(%d+)$")
        local tileIndices = {}
        if startStr and endStr then
          local startIdx, endIdx = tonumber(startStr), tonumber(endStr)
          for tileIdx = startIdx, endIdx do
            table.insert(tileIndices, tileIdx)
          end
        else
          local tileIdx = tonumber(tileKey)
          if tileIdx then
            table.insert(tileIndices, tileIdx)
          end
        end

        local expanded
        if type(pixels) == "string" then
          expanded = decodeTileEditRLE(pixels)
        else
          expanded = decompressTileEdits(pixels)
        end

        for _, tileIdx in ipairs(tileIndices) do
          local tileRef = pool and pool[tileIdx] or nil
          for key, color in pairs(expanded) do
            local x, y = key:match("^(%d+)_(%d+)$")
            x, y = tonumber(x), tonumber(y)
            if x and y then
              chr.setTilePixel(bankBytes, tileIdx, x, y, color)
              if tileRef then
                tileRef:edit(x, y, color)
              end
            end
          end
        end
      end
    end
  end
end

function M.buildEditsFromChrDiff(originalChrBanksBytes, currentChrBanksBytes)
  local out = M.newEdits()
  if type(currentChrBanksBytes) ~= "table" then
    return out
  end

  local maxBanks = math.max(
    #(originalChrBanksBytes or {}),
    #currentChrBanksBytes
  )

  for bankIdx = 1, maxBanks do
    local originalBank = originalChrBanksBytes and originalChrBanksBytes[bankIdx] or nil
    local currentBank = currentChrBanksBytes[bankIdx]
    if currentBank then
      local originalLen = originalBank and #originalBank or 0
      local currentLen = #currentBank
      local tileCount = math.max(originalLen, currentLen) / 16
      tileCount = math.floor(tileCount)

      for tileIdx = 0, tileCount - 1 do
        local base = tileIdx * 16
        local changed = false
        for offset = 1, 16 do
          local before = originalBank and originalBank[base + offset] or 0
          local after = currentBank[base + offset] or 0
          if before ~= after then
            changed = true
            break
          end
        end

        if changed then
          local beforePixels = chr.decodeTile(originalBank or {}, tileIdx) or {}
          local afterPixels = chr.decodeTile(currentBank, tileIdx) or {}
          for y = 0, 7 do
            for x = 0, 7 do
              local idx = (y * 8) + x + 1
              local before = beforePixels[idx] or 0
              local after = afterPixels[idx] or 0
              if before ~= after then
                M.recordEdit(out, bankIdx, tileIdx, x, y, after)
              end
            end
          end
        end
      end
    end
  end

  return out
end

return M
