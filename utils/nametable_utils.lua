local DebugController = require("controllers.dev.debug_controller")
local codecsCache = {}

local function hex_to_bytes(s)
  local bytes = {}
  s = (s or ""):gsub("[^%x]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  for h in s:gmatch("%x%x") do bytes[#bytes+1] = tonumber(h, 16) end
  return bytes
end

local function bytes_to_hex(bytes)
  local hex = ""
  for i = 1, #bytes do
    hex = hex .. string.format("%02X", bytes[i])
  end
  return hex
end

-- Encode nametable using the specified codec (defaults to "konami")
local function resolve_codec(codec)
  local codecName = codec or "konami"
  if codecsCache[codecName] then
    return codecsCache[codecName]
  end

  local ok, codecModule = pcall(require, "codecs." .. codecName)
  if ok
    and type(codecModule) == "table"
    and type(codecModule.encode_nametable) == "function"
    and type(codecModule.decode_nametable) == "function"
  then
    codecsCache[codecName] = codecModule
    return codecModule
  end

  if codecName ~= "konami" then
    DebugController.log("warning", "CODEC", "Unknown codec '%s', defaulting to 'konami'", codecName)
  end

  local okKonami, konamiCodec = pcall(require, "codecs.konami")
  if not okKonami
    or type(konamiCodec) ~= "table"
    or type(konamiCodec.encode_nametable) ~= "function"
    or type(konamiCodec.decode_nametable) ~= "function"
  then
    error("[nametable_utils] failed to load default codec 'konami'")
  end

  codecsCache[codecName] = konamiCodec
  return konamiCodec
end

local function encode_decompressed_nametable(nametable, attributes, codec)
  local codecModule = resolve_codec(codec)
  return codecModule.encode_nametable(nametable, attributes)
end

-- Decode nametable using the specified codec (defaults to "konami")
local function decode_compressed_nametable(data, debug, codec)
  local codecModule = resolve_codec(codec)
  return codecModule.decode_nametable(data, debug)
end

local function decode_compressed_hex_nametable(hex_string, debug, codec)
  local data = hex_to_bytes(hex_string)
  return decode_compressed_nametable(data, debug, codec)
end

return {
  decode_compressed_nametable = decode_compressed_nametable,
  decode_compressed_hex_nametable = decode_compressed_hex_nametable,
  encode_decompressed_nametable = encode_decompressed_nametable,
  hex_to_bytes = hex_to_bytes,
  bytes_to_hex = bytes_to_hex
}
