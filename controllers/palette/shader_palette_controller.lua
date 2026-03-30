local Palettes = require("palettes")
local colors   = require("app_colors")
local chr      = require("chr")
local DebugController = require("controllers.dev.debug_controller")
local WindowCaps = require("controllers.window.window_capabilities")

local M = {
  paletteName = "smooth_fbx",
  -- indices 1..4 map to tile palette indices 0..3
  codes       = { "0F", "30", "36", "26" },
  shader      = nil,
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

-- Look up an RGB triplet (0..1) from palettes by NES hex code (e.g., "0F")
local function hex2rgb(paletteName, code)
  local p = Palettes[paletteName] or Palettes.smooth_fbx
  return (p and p[code]) or colors.black
end

-- Read a byte from romRaw at the given address and convert it to a hex string "HH".
-- romRaw: ROM string data
-- addr: 0-based ROM address (number)
-- Returns: 2-digit hex string like "0F", or "0F" as fallback if read fails
function M.resolveHexFromRomAddress(romRaw, addr)
  if type(romRaw) ~= "string" or #romRaw == 0 then
    DebugController.log("warning", "PALETTE", "resolveHexFromRomAddress: romRaw is not a valid string")
    return "0F"
  end
  
  if type(addr) ~= "number" then
    DebugController.log("warning", "PALETTE", "resolveHexFromRomAddress: addr must be a number, got %s", type(addr))
    return "0F"
  end
  
  local byte, err = chr.readByteFromAddress(romRaw, addr)
  if not byte or err then
    DebugController.log("warning", "PALETTE", "resolveHexFromRomAddress: failed to read byte at address 0x%X: %s", addr, err or "unknown error")
    return "0F"
  end
  
  -- Convert byte (0-255) to 2-digit hex string
  return string.format("%02X", byte)
end

----------------------------------------------------------------
-- Shader (index 0 transparent)
----------------------------------------------------------------
local PALETTE_SHADER_SRC = [[
extern vec4 pal[4];   // RGBA colors, already normalized 0..1

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
    vec4 px  = Texel(tex, tc);

    // Decode palette index from red channel (expected 0, 1/3, 2/3, 1)
    float f = floor(px.r * 3.0 + 0.5);  // ~0,1,2,3
    int i = int(f);

    vec4 outc = pal[i];

    // Force full transparency for index 0 (first color)
    if (i == 0) {
        outc.a = 0.0;
    }

    // Keep source alpha for cutout/sprite edges if you use it; otherwise outc.a drives it.
    // Multiplying by 'color' preserves tinting workflows.
    return outc * color;
}
]]

local function ensureShader()
  if M.shader then return M.shader end
  M.shader = love.graphics.newShader(PALETTE_SHADER_SRC)
  return M.shader
end

-- codes: array of 4 NES hex strings "HH" (optional; defaults to M.codes)
local function updateShaderUniforms(drawingActiveLayer, codes, layerOpacityOverride)
  if not M.shader then return end

  local useCodes = codes or M.codes

  local c0 = hex2rgb(M.paletteName, useCodes[1] or M.codes[1])
  local c1 = hex2rgb(M.paletteName, useCodes[2] or M.codes[2])
  local c2 = hex2rgb(M.paletteName, useCodes[3] or M.codes[3])
  local c3 = hex2rgb(M.paletteName, useCodes[4] or M.codes[4])

  -- Use provided opacity override if available, otherwise use default behavior
  -- Default: active layer = 1.0, inactive = 0.25 (for backwards compatibility)
  local layerOpacity
  if layerOpacityOverride ~= nil then
    layerOpacity = layerOpacityOverride
  else
    layerOpacity = drawingActiveLayer and 1.0 or 0.25
  end

  -- Send as varargs of vec4 tables (flat), first entry alpha = 0
  M.shader:send(
    "pal",
    { (c0[1] or 0), (c0[2] or 0), (c0[3] or 0), 0.0 },
    { (c1[1] or 0), (c1[2] or 0), (c1[3] or 0), layerOpacity },
    { (c2[1] or 0), (c2[2] or 0), (c2[3] or 0), layerOpacity },
    { (c3[1] or 0), (c3[2] or 0), (c3[3] or 0), layerOpacity }
  )
end

----------------------------------------------------------------
-- Public API (existing global behavior)
----------------------------------------------------------------

function M.getCodes()
  return M.codes
end

function M.setCodes(codes)  -- { "HH","HH","HH","HH" }
  for i = 1, 4 do
    if codes[i] then M.codes[i] = codes[i] end
  end
  ensureShader()
  updateShaderUniforms(true)
end

function M.setCodeAt(index, code) -- index 1..4
  if index < 1 or index > 4 then return end
  M.codes[index] = code
  ensureShader()
  updateShaderUniforms(true)
end

function M.setPaletteName(name)
  if name and Palettes[name] then
    M.paletteName = name
    ensureShader()
    updateShaderUniforms(true)
  end
end

function M.getColorAt(index) -- index 1..4
  return hex2rgb(M.paletteName, M.codes[index])
end

-- Global apply: uses M.codes (current global palette).
-- layer: optional layer to check shaderEnabled state
-- codes: optional custom palette codes (if nil, uses M.codes)
-- layerOpacityOverride: optional opacity override
function M.applyShader(drawingActiveLayer, layer, codes, layerOpacityOverride)
  -- Check if shader is disabled for this layer
  if layer and layer.shaderEnabled == false then
    -- Don't apply shader, just ensure it's cleared
    love.graphics.setShader()
    return
  end
  
  ensureShader()
  updateShaderUniforms(drawingActiveLayer, codes, layerOpacityOverride)
  -- This is the ONLY place setShader should be called
  love.graphics.setShader(M.shader)
end

function M.releaseShader()
  love.graphics.setShader()
end

function M.getShader()
  ensureShader()
  return M.shader
end

-- For UI swatches or non-shader uses: returns {r,g,b} 0..1
function M.colorOfIndex(idx01) -- idx01: 1..4 -> rgb
  return hex2rgb(M.paletteName, M.codes[idx01])
end

----------------------------------------------------------------
-- NEW: per-layer / per-item palette support
----------------------------------------------------------------
-- layer.paletteData = {
--   items = {
--     {"0F","30","28","16"}, -- palette #1
--     {"0F","30","06","16"}, -- palette #2
--     {"0F","10","27","16"}, -- palette #3
--     {"0F","30","36","26"}, -- palette #4
--   }
-- }
--
-- Each entry may be:
--   - string "HH" -> NES color code (used directly)
--   - number N    -> ROM address (0-based) where we read the color byte at runtime
--
-- item.paletteNumber = 1..4 selects which of those 4 palettes to use.

local function resolvePaletteEntryToHex(entry, romRaw)
  local t = type(entry)
  if t == "string" then
    -- Already a NES color code like "0F", "30", etc.
    return entry
  elseif t == "number" then
    -- ROM-backed color slot; read the byte at this address and convert to hex string
    return M.resolveHexFromRomAddress(romRaw, entry)
  else
    -- Fallback; caller may override with global palette.
    return nil
  end
end

-- Resolve a palette# (1..4) on a given layer into 4 hex codes "HH".
-- Supports:
--   layer.paletteData = { winId = "rom_palette_01" }  -- link to ROM/global palette window
--   layer.paletteData = { items = { ... } }           -- old inline palettes (back-compat)
function M.resolveLayerPaletteCodes(layer, paletteNumber, romRaw)
  if not layer or not layer.paletteData then
    return nil
  end

  local palIdx = paletteNumber
  if not palIdx or palIdx < 1 or palIdx > 4 then
    return nil
  end

  local pd = layer.paletteData

  ------------------------------------------------------------------
  -- 1) Linked palette via window id (runtime lookup)
  ------------------------------------------------------------------
  if pd.winId then
    local ctx = rawget(_G, "ctx")
    local wm  = ctx and ctx.wm and ctx.wm()
    if wm and wm.findWindowById then
      local win = wm:findWindowById(pd.winId)
      if WindowCaps.isAnyPaletteWindow(win) and win.codes2D then
        local rowIdx = palIdx - 1
        if WindowCaps.isGlobalPaletteWindow(win) then
          if type(win.codes2D[rowIdx]) ~= "table" then
            rowIdx = 0
          end
        end
        local rowTbl = win.codes2D[rowIdx]
        if type(rowTbl) == "table" then
          local out = {}
          for col = 0, 3 do
            local code = rowTbl[col]
            if type(code) ~= "string" then
              return nil
            end
            out[#out + 1] = code
          end
          return out
        end
      end
    end
  end

  ------------------------------------------------------------------
  -- 2) Legacy inline paletteData.items (backwards compatible)
  ------------------------------------------------------------------
  if not pd.items then
    return nil
  end

  local palRow = pd.items[palIdx]
  if type(palRow) ~= "table" then
    return nil
  end

  local out = {}
  for i = 1, 4 do
    local entry = palRow[i]
    local hex   = resolvePaletteEntryToHex(entry, romRaw)
    if not hex then
      return nil
    end
    out[i] = hex
  end

  return out
end

----------------------------------------------------------------
-- ROM-backed palette entries + per-layer / per-item palettes
----------------------------------------------------------------

-- Apply shader for a specific (layer, item) combo:
-- - If paletteNumberOverride is provided, use that (tiles per cell).
-- - Else, if item.paletteNumber exists (e.g., sprites), use that.
-- - Else fall back to global M.codes.
-- - layerOpacityOverride: optional opacity value (0.0-1.0) to use instead of default behavior
function M.applyLayerItemPalette(layer, item, drawingActiveLayer, romRaw, paletteNumberOverride, layerOpacityOverride)
  local palNum = paletteNumberOverride or (item and item.paletteNumber)
  local codes  = nil

  if layer and palNum then
    codes = M.resolveLayerPaletteCodes(layer, palNum, romRaw)
  end

  -- Use applyShader to centralize setShader call (all setShader calls go through applyShader)
  -- Pass the resolved codes and opacity override
  M.applyShader(drawingActiveLayer, layer, codes or M.codes, layerOpacityOverride)
end

--- Get RGB color for a palette number (1-4) on a layer
-- Returns {r, g, b} 0..1 for the 2nd color of the palette (most visible)
-- Falls back to global palette if layer paletteData is not available
function M.getPaletteColor(layer, paletteNumber, romRaw)
  if not paletteNumber or paletteNumber < 1 or paletteNumber > 4 then
    -- Fall back to global palette, 2nd color
    return hex2rgb(M.paletteName, M.codes[2] or "30")
  end
  
  local codes = M.resolveLayerPaletteCodes(layer, paletteNumber, romRaw)
  local useCodes = codes or M.codes
  
  -- Use the 2nd color (index 2) as it's typically the most visible
  local hexCode = useCodes[2] or M.codes[2] or "30"
  return hex2rgb(M.paletteName, hexCode)
end

--- Get all 4 RGB colors for a palette number (1-4) on a layer
-- Returns array of 4 {r, g, b} tables, or nil if palette not available
function M.getPaletteColors(layer, paletteNumber, romRaw)
  local codes = M.resolveLayerPaletteCodes(layer, paletteNumber, romRaw)
  local useCodes = codes or M.codes
  
  if not useCodes then return nil end
  
  local colors = {}
  for i = 1, 4 do
    local hexCode = useCodes[i] or M.codes[i] or "0F"
    colors[i] = hex2rgb(M.paletteName, hexCode)
  end
  
  return colors
end

return M
