-- rom_window.lua
-- ROM-backed tile browser for CHR-RAM games.
-- Reuses CHR bank window behavior/keybindings, but the backing bytes are
-- pseudo CHR banks generated from the whole ROM file.

local ChrBankWindow = require("user_interface.windows_system.chr_bank_window")

local RomWindow = setmetatable({}, { __index = ChrBankWindow })
RomWindow.__index = RomWindow

function RomWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  data = data or {}
  data.title = data.title or "ROM Banks"

  local self = ChrBankWindow.new(x, y, cellW, cellH, cols, rows, zoom, data)
  setmetatable(self, RomWindow)

  -- Keep kind="chr" for compatibility with existing controllers and input paths.
  self.kind = "chr"
  self.isRomWindow = true

  return self
end

return RomWindow
