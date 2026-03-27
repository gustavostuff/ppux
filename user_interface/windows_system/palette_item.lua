-- palette_item.lua
-- Simple item to represent a palette swatch cell.
local BaseItem       = require("user_interface.windows_system.generic_window_item")
local Palettes       = require("palettes")
local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local colors = require("app_colors")

local PaletteItem = setmetatable({}, { __index = BaseItem })
PaletteItem.__index = PaletteItem

function PaletteItem.new(code)
  local self = BaseItem.new()
  setmetatable(self, PaletteItem)
  self.code = code or "0F"
  return self
end

function PaletteItem:setCode(code)
  self.code = code or self.code
end

function PaletteItem:getCode()
  return self.code
end

-- Draw as a filled swatch; Window will have set the scissor/checkerboard already.
function PaletteItem:draw(x, y, scale)
  local pal  = Palettes[ShaderPaletteController.paletteName] or Palettes.smooth_fbx
  local rgb  = pal[self.code] or colors.black
  local s    = scale or 1
  love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
  love.graphics.rectangle("fill", x, y, 8 * s, 8 * s)
  love.graphics.setColor(colors.white)
end

return PaletteItem
