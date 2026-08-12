-- scanners/init.lua
-- Nametable stream scanners keyed by layer codec. Add a module under scanners/
-- and register it here when a new codec gains Selection-mode support.

local KonamiNtScanner = require("scanners.konami_nt_scanner")

local M = {}

local byCodec = {
  konami = KonamiNtScanner,
}

--- @param codec string|nil
--- @return boolean
function M.supports(codec)
  local key = tostring(codec or ""):lower()
  return byCodec[key] ~= nil
end

--- @param codec string|nil
--- @return table|nil scanner module for that codec
function M.get(codec)
  local key = tostring(codec or ""):lower()
  return byCodec[key]
end

--- Dispatch scan to the codec's scanner (empty hits when unsupported).
function M.scan(romRaw, opts)
  opts = opts or {}
  local scanner = M.get(opts.codec or "konami")
  if not scanner or type(scanner.scan) ~= "function" then
    if opts.returnTiming then
      return {}, nil
    end
    return {}
  end
  return scanner.scan(romRaw, opts)
end

--- Hit helpers are shared across scanners (range geometry, not codec-specific).
function M.hitAt(hits, addr)
  return KonamiNtScanner.hitAt(hits, addr)
end

function M.dedupeOverlapping(hits)
  return KonamiNtScanner.dedupeOverlapping(hits)
end

return M
