local DebugController = require("controllers.dev.debug_controller")
local chr = require("chr")

local M = {}

local function normalizePatchAddress(address)
  address = tonumber(address)
  if not address then return nil end
  address = math.floor(address)
  if address < 0 then return nil end
  return address
end

local function normalizePatchValue(value)
  value = tonumber(value)
  if not value then return nil end
  value = math.floor(value)
  if value < 0 or value > 0xFF then return nil end
  return value
end

local function normalizeSingleRomPatchEntry(entry, reason)
  local address = normalizePatchAddress(entry.address)
  local value = normalizePatchValue(entry.value)
  if not address or value == nil then
    return nil
  end

  return {
    address = address,
    value = value,
    reason = reason,
  }
end

local function normalizePatchValues(values, count)
  if type(values) ~= "table" then
    return nil
  end

  count = count or #values
  if count == 0 or count ~= #values then
    return nil
  end

  local out = {}
  for i = 1, count do
    local value = normalizePatchValue(values[i])
    if value == nil then
      return nil
    end
    out[i] = value
  end

  return out
end

local function normalizeRangeSequenceRomPatchEntry(entry, reason)
  local toSpecifiedOnEntry = entry.to ~= nil
  local toSpecifiedOnAddresses = type(entry.addresses) == "table" and entry.addresses.to ~= nil
  local persistTo = toSpecifiedOnEntry or toSpecifiedOnAddresses

  local from = normalizePatchAddress(entry.from)
  local to = normalizePatchAddress(entry.to)

  if type(entry.addresses) == "table" then
    if from == nil then
      from = normalizePatchAddress(entry.addresses.from)
    end
    if to == nil then
      to = normalizePatchAddress(entry.addresses.to)
    end
  end

  if not from then
    return nil
  end

  local values
  local addressesOut = { from = from }

  if persistTo then
    if to == nil or to < from then
      return nil
    end
    local count = to - from + 1
    values = normalizePatchValues(entry.values, count)
    if not values then
      return nil
    end
    addressesOut.to = to
  else
    values = normalizePatchValues(entry.values)
    if not values then
      return nil
    end
    if #values == 0 then
      return nil
    end
  end

  return {
    addresses = addressesOut,
    values = values,
    reason = reason,
  }
end

local function normalizeAddressListSequenceRomPatchEntry(entry, reason)
  if type(entry.addresses) ~= "table" then
    return nil
  end

  local count = #entry.addresses
  local values = normalizePatchValues(entry.values, count)
  if not values then
    return nil
  end

  local addresses = {}
  for i = 1, count do
    local address = normalizePatchAddress(entry.addresses[i])
    if not address then
      return nil
    end
    addresses[i] = address
  end

  return {
    addresses = addresses,
    values = values,
    reason = reason,
  }
end

local function normalizeSequenceRomPatchEntry(entry, reason)
  if type(entry.values) ~= "table" then
    return nil
  end

  local hasRangeFromTo = (entry.from ~= nil or entry.to ~= nil)
  if type(entry.addresses) == "table" then
    hasRangeFromTo = hasRangeFromTo or entry.addresses.from ~= nil or entry.addresses.to ~= nil
  end

  if hasRangeFromTo then
    return normalizeRangeSequenceRomPatchEntry(entry, reason)
  end

  return normalizeAddressListSequenceRomPatchEntry(entry, reason)
end

local function normalizeRomPatchEntry(entry)
  if type(entry) ~= "table" then return nil end

  local reason = entry.reason
  if type(reason) ~= "string" then
    return nil
  end

  local hasSingleFields = (entry.address ~= nil or entry.value ~= nil)
  local hasSequenceFields = (entry.from ~= nil or entry.to ~= nil or entry.addresses ~= nil or entry.values ~= nil)
  if hasSingleFields and hasSequenceFields then
    return nil
  end

  if hasSequenceFields then
    return normalizeSequenceRomPatchEntry(entry, reason)
  end

  return normalizeSingleRomPatchEntry(entry, reason)
end

function M.normalizeRomPatches(romPatches)
  if type(romPatches) ~= "table" then return nil end

  local out = {}
  for _, patch in ipairs(romPatches) do
    local normalized = normalizeRomPatchEntry(patch)
    if normalized then
      out[#out + 1] = normalized
    end
  end

  if #out == 0 then return nil end
  return out
end

function M.applyRomPatches(romRaw, romPatches)
  if type(romRaw) ~= "string" then
    return nil, "romRaw must be string", 0
  end

  local normalized = M.normalizeRomPatches(romPatches)
  if not normalized then
    return romRaw, nil, 0
  end

  local patched = romRaw
  local applied = 0
  for _, patch in ipairs(normalized) do
    if patch.address ~= nil then
      local nextRom, err = chr.writeByteToAddress(patched, patch.address, patch.value)
      if nextRom then
        patched = nextRom
        applied = applied + 1
      else
        DebugController.log(
          "warning", "ROM_PATCH",
          "Skipping patch at 0x%06X => 0x%02X (%s): %s",
          patch.address, patch.value, patch.reason or "", tostring(err)
        )
      end
    elseif patch.addresses and patch.addresses.from ~= nil then
      for i, value in ipairs(patch.values) do
        local address = patch.addresses.from + (i - 1)
        local nextRom, err = chr.writeByteToAddress(patched, address, value)
        if nextRom then
          patched = nextRom
          applied = applied + 1
        else
          DebugController.log(
            "warning", "ROM_PATCH",
            "Skipping sequence patch[%d] at 0x%06X => 0x%02X (%s): %s",
            i, address, value, patch.reason or "", tostring(err)
          )
        end
      end
    else
      for i, address in ipairs(patch.addresses) do
        local value = patch.values[i]
        local nextRom, err = chr.writeByteToAddress(patched, address, value)
        if nextRom then
          patched = nextRom
          applied = applied + 1
        else
          DebugController.log(
            "warning", "ROM_PATCH",
            "Skipping address-list patch[%d] at 0x%06X => 0x%02X (%s): %s",
            i, address, value, patch.reason or "", tostring(err)
          )
        end
      end
    end
  end

  return patched, nil, applied
end

return M
