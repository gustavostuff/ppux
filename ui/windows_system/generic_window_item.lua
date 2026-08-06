-- generic_window_item.lua
-- Base class for things that live in Window cells.
local Item = {}
Item.__index = Item

function Item.new()
  return setmetatable({}, Item)
end

-- Intentionally no-op; subclasses override.
function Item:draw(x, y, scale) end

return Item
