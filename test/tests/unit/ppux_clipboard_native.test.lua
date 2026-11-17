local ClipboardNative = require("utils.ppux_clipboard_native")

describe("ppux_clipboard DIB decoder", function()
  local function writeU16(bytes, offset, value)
    bytes[offset] = string.char(value % 256)
    bytes[offset + 1] = string.char(math.floor(value / 256) % 256)
  end

  local function writeU32(bytes, offset, value)
    bytes[offset] = string.char(value % 256)
    bytes[offset + 1] = string.char(math.floor(value / 256) % 256)
    bytes[offset + 2] = string.char(math.floor(value / 65536) % 256)
    bytes[offset + 3] = string.char(math.floor(value / 16777216) % 256)
  end

  local function blank(n)
    local bytes = {}
    for i = 1, n do
      bytes[i] = "\0"
    end
    return bytes
  end

  local function join(bytes)
    return table.concat(bytes)
  end

  it("decodes a bottom-up 24-bit BI_RGB DIB when the library is available", function()
    if not ClipboardNative.isAvailable() then
      expect(true).toBe(true)
      return
    end

    local dib = blank(56)
    writeU32(dib, 1, 40)
    writeU32(dib, 5, 2)
    writeU32(dib, 9, 2)
    writeU16(dib, 13, 1)
    writeU16(dib, 15, 24)
    -- bottom row: blue, white. top row: red, green. BGR, stride 8.
    dib[41], dib[42], dib[43] = string.char(255), string.char(0), string.char(0)
    dib[44], dib[45], dib[46] = string.char(255), string.char(255), string.char(255)
    dib[49], dib[50], dib[51] = string.char(0), string.char(0), string.char(255)
    dib[52], dib[53], dib[54] = string.char(0), string.char(255), string.char(0)

    local rgba, w, h = ClipboardNative.dibToRgba(join(dib))
    expect(w).toBe(2)
    expect(h).toBe(2)
    expect(rgba:sub(1, 4)).toBe(string.char(255, 0, 0, 255))
    expect(rgba:sub(5, 8)).toBe(string.char(0, 255, 0, 255))
    expect(rgba:sub(9, 12)).toBe(string.char(0, 0, 255, 255))
    expect(rgba:sub(13, 16)).toBe(string.char(255, 255, 255, 255))
  end)

  it("decodes a bottom-up 32-bit BI_BITFIELDS DIB when the library is available", function()
    if not ClipboardNative.isAvailable() then
      expect(true).toBe(true)
      return
    end

    local dib = blank(60)
    writeU32(dib, 1, 40)
    writeU32(dib, 5, 1)
    writeU32(dib, 9, 2)
    writeU16(dib, 13, 1)
    writeU16(dib, 15, 32)
    writeU32(dib, 17, 3)
    writeU32(dib, 41, 0x00FF0000)
    writeU32(dib, 45, 0x0000FF00)
    writeU32(dib, 49, 0x000000FF)
    -- bottom pixel RGB 1,2,3 then top pixel RGB 4,5,6, stored B,G,R,0
    dib[53], dib[54], dib[55], dib[56] = string.char(3), string.char(2), string.char(1), string.char(0)
    dib[57], dib[58], dib[59], dib[60] = string.char(6), string.char(5), string.char(4), string.char(0)

    local rgba, w, h = ClipboardNative.dibToRgba(join(dib))
    expect(w).toBe(1)
    expect(h).toBe(2)
    expect(rgba:sub(1, 4)).toBe(string.char(4, 5, 6, 255))
    expect(rgba:sub(5, 8)).toBe(string.char(1, 2, 3, 255))
  end)
end)
